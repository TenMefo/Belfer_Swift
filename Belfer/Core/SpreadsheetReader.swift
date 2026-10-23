import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct WorkbookSheet: Identifiable { var id: String; var name: String; var rows: [[String]] }
private final class XMLNode {
    var name: String; var attributes: [String: String]; var text = ""; var children: [XMLNode] = []
    init(_ name: String, _ attributes: [String: String] = [:]) { self.name = name; self.attributes = attributes }
    func nodes(_ name: String) -> [XMLNode] { children.filter { $0.name == name } }
    func descendants(_ name: String) -> [XMLNode] { children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) } }
}
private final class TreeParser: NSObject, XMLParserDelegate {
    let root = XMLNode("root"); var stack: [XMLNode] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let node = XMLNode(elementName.components(separatedBy: ":").last!, attributeDict)
        (stack.last ?? root).children.append(node); stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if !stack.isEmpty { stack.removeLast() } }
    static func read(_ data: Data) throws -> XMLNode {
        let delegate = TreeParser(); let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse() else { throw DataError.invalid("Nieprawidłowy plik XML w arkuszu.") }; return delegate.root
    }
}
enum SpreadsheetReader {
    static func read(_ url: URL) throws -> [WorkbookSheet] {
        if url.pathExtension.lowercased() != "xlsx" {
            return [WorkbookSheet(id: "csv", name: url.lastPathComponent, rows: try CSVImporter.rows(String(contentsOf: url, encoding: .utf8)))]
        }
        func entry(_ path: String) throws -> Data {
            guard path.hasPrefix("xl/"), !path.components(separatedBy: "/").contains("..") else { throw DataError.invalid("Nieprawidłowa ścieżka wewnątrz XLSX.") }
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); process.arguments = ["-p", url.path, path]
            process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            try process.run()
            var result = Data()
            while let chunk = try pipe.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
                result.append(chunk)
                if result.count > 16_000_000 { process.terminate(); process.waitUntilExit(); throw DataError.invalid("Arkusz jest zbyt duży (limit 16 MB XML na część).") }
            }
            process.waitUntilExit(); guard process.terminationStatus == 0 else { throw DataError.invalid("Nie odczytano części XLSX: \(path)") }
            return result
        }
        let book = try TreeParser.read(entry("xl/workbook.xml"))
        let relationships = try TreeParser.read(entry("xl/_rels/workbook.xml.rels"))
        let shared: [String]
        if let bytes = try? entry("xl/sharedStrings.xml"), let xml = try? TreeParser.read(bytes) { shared = xml.descendants("si").map { $0.descendants("t").map(\.text).joined() } }
        else { shared = [] }
        var sheets: [WorkbookSheet] = []
        for sheet in book.descendants("sheet") {
            guard let id = sheet.attributes["r:id"], let relation = relationships.descendants("Relationship").first(where: { $0.attributes["Id"] == id }), let target = relation.attributes["Target"], relation.attributes["TargetMode"] != "External" else { continue }
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            let xml = try TreeParser.read(entry(path))
            var rows: [[String]] = []
            for row in xml.descendants("row") {
                var cells: [Int: String] = [:]
                for cell in row.nodes("c") {
                    let reference = cell.attributes["r"] ?? "A1"
                    let index = reference.prefix(while: { $0.isLetter }).uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
                    guard (0..<1000).contains(index) else { throw DataError.invalid("Arkusz ma za dużo kolumn.") }
                    let raw = cell.nodes("v").first?.text ?? ""
                    let type = cell.attributes["t"] ?? ""
                    cells[index] = type == "s" ? (Int(raw).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? "") : (type == "inlineStr" ? cell.descendants("t").map(\.text).joined() : raw)
                }
                let rowNumber = Int(row.attributes["r"] ?? "") ?? (rows.count + 1)
                guard rowNumber <= 100_000 && rowNumber > 0 else { throw DataError.invalid("Arkusz ma za dużo wierszy.") }
                while rows.count < rowNumber - 1 { rows.append([]) }
                let count = (cells.keys.max() ?? -1) + 1
                rows.append((0..<max(count, 0)).map { cells[$0] ?? "" })
            }
            if !rows.isEmpty { sheets.append(WorkbookSheet(id: id, name: sheet.attributes["name"] ?? id, rows: rows)) }
        }
        guard !sheets.isEmpty else { throw DataError.invalid("Brak arkuszy z danymi.") }
        return sheets
    }
}
struct TopicImportChange: Identifiable {
    var id: UUID { topic.id }
    var topic: Topic
    var previous: Topic?
    var description: String { previous == nil ? "NOWY" : "ZMIANA \(previous!.hours) → \(topic.hours) h" }
}
enum TopicImport {
    static func changes(rows: [[String]], header: Int, titleColumn: Int, hoursColumn: Int?, subject: Subject, curriculum: Curriculum, existing: [Topic]) throws -> [TopicImportChange] {
        guard rows.indices.contains(header), titleColumn >= 0 else { throw DataError.invalid("Wybierz nagłówek i kolumnę tematu.") }
        var changes: [TopicImportChange] = []; var seen = Set<String>()
        for (offset, row) in rows.dropFirst(header + 1).enumerated() {
            guard row.indices.contains(titleColumn) else { continue }
            let title = row[titleColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { continue }
            let key = Workspace.key(title)
            guard seen.insert(key).inserted else { throw DataError.invalid("Powtórzony temat w imporcie: \(title)") }
            var hours = 1
            if let column = hoursColumn, row.indices.contains(column), !row[column].isEmpty {
                guard let number = Double(row[column].replacingOccurrences(of: ",", with: ".")), number.isFinite, number.rounded() == number, (1...1000).contains(number) else { throw DataError.invalid("Wiersz \(header + offset + 2): nieprawidłowa liczba godzin.") }
                hours = Int(number)
            }
            let previous = existing.first { $0.curriculumID == curriculum.id && Workspace.key($0.title) == key }
            var topic = previous ?? Topic()
            topic.title = title; topic.subject = subject.name; topic.subjectID = subject.id; topic.curriculumID = curriculum.id
            topic.hours = hours; topic.order = offset + 1
            if previous == nil || previous != topic { changes.append(TopicImportChange(topic: topic, previous: previous)) }
        }
        return changes
    }
}
