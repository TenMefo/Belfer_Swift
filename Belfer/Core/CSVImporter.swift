import Foundation

/// CSV UTF-8 wyeksportowany z Excela. Obsługuje separator ; lub , i pola w cudzysłowach.
enum CSVImporter {
    static func rows(_ source: String) throws -> [[String]] {
        let source = source.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let header = String(source.prefix(while: { $0 != "\n" }))
        let delimiter: Character = header.filter { $0 == ";" }.count >= header.filter { $0 == "," }.count ? ";" : ","
        let chars = Array(source)
        var result: [[String]] = [], row: [String] = [], field = "", quoted = false, closed = false, i = 0
        while i < chars.count {
            let char = chars[i]
            if quoted {
                if char == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(char) }
            } else if char == delimiter || char == "\n" {
                row.append(field.trimmingCharacters(in: .whitespaces)); field = ""; closed = false
                if char == "\n" { if row.contains(where: { !$0.isEmpty }) { result.append(row) }; row = [] }
            } else if char == "\"" {
                guard field.isEmpty && !closed else { throw DataError.invalid("Nieprawidłowy cudzysłów w CSV.") }
                quoted = true
            } else {
                guard !closed || char.isWhitespace else { throw DataError.invalid("Nieprawidłowy zapis za cudzysłowem w CSV.") }
                if !closed { field.append(char) }
            }
            i += 1
        }
        guard !quoted else { throw DataError.invalid("Niedomknięty cudzysłów w CSV.") }
        row.append(field.trimmingCharacters(in: .whitespaces))
        if row.contains(where: { !$0.isEmpty }) { result.append(row) }
        return result
    }
    static func topics(_ source: String) throws -> [Topic] {
        let rows = try rows(source)
        guard let header = rows.first else { throw DataError.invalid("Plik CSV jest pusty.") }
        let columns = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        guard let titleColumn = columns.firstIndex(of: "temat") else { throw DataError.invalid("Brakuje kolumny temat. Użyj nagłówków: temat;przedmiot;godziny.") }
        let subjectColumn = columns.firstIndex(of: "przedmiot"), hoursColumn = columns.firstIndex(of: "godziny")
        var result: [Topic] = []
        for (offset, row) in rows.dropFirst().enumerated() {
            guard row.count == header.count else { throw DataError.invalid("Wiersz \(offset + 2): liczba kolumn nie zgadza się z nagłówkiem.") }
            let title = row[titleColumn]
            guard !title.isEmpty else { throw DataError.invalid("Wiersz \(offset + 2): pusty temat.") }
            let rawHours = hoursColumn.map { row[$0] } ?? "1"
            guard let hours = Int(rawHours), (1...1000).contains(hours) else { throw DataError.invalid("Wiersz \(offset + 2): godziny muszą być liczbą całkowitą od 1 do 1000.") }
            result.append(Topic(title: title, subject: subjectColumn.map { row[$0] } ?? "", hours: hours))
        }
        guard !result.isEmpty else { throw DataError.invalid("Brak tematów do importu.") }
        return result
    }
}
