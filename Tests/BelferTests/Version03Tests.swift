import XCTest
@testable import Belfer

final class Version03Tests: XCTestCase {
    @MainActor
    func testMigrationPreservesLegacyIDsAndCreatesSubjectCurriculum() async throws {
        var original = Workspace.demo()
        original.schemaVersion = 1; original.subjectCatalog = nil; original.curriculumCatalog = nil
        for i in original.classes.indices { original.classes[i].subjectID = nil }
        for i in original.topics.indices { original.topics[i].subjectID = nil; original.topics[i].curriculumID = nil }
        let bytes = try WorkspaceStore.encode(original)
        let updated = try WorkspaceStore.decode(bytes)
        XCTAssertEqual(updated.schemaVersion, 3)
        XCTAssertEqual(updated.subjects.count, 2)
        XCTAssertEqual(updated.curricula.count, 2)
        XCTAssertEqual(updated.lessons.map(\.id), original.lessons.map(\.id))
        XCTAssertEqual(updated.topics.map(\.id), original.topics.map(\.id))
        XCTAssertEqual(try WorkspaceStore.decode(WorkspaceStore.encode(updated)), updated)
    }
    func testSubjectRestrictionsAndProfileCannotLeakXampp() throws {
        var data = Workspace.demo()
        let php = data.classes[0].subjectID!, react = data.classes[1].subjectID!
        var xampp = LaunchAction.xampp("start"); xampp.subjectID = php; xampp.withMaterials = true
        data.actions = [xampp]
        XCTAssertEqual(data.actions(for: data.lessons[0]).count, 1)
        XCTAssertTrue(data.actions(for: data.lessons[1]).isEmpty)
        let profile = EnvironmentProfile(name: "Błędny", subjectID: react, actionIDs: [xampp.id])
        data.profiles = [profile]
        XCTAssertThrowsError(try data.validated())
        data.profiles = []
        data.lessons[1].topicID = data.lessons[0].topicID
        XCTAssertThrowsError(try data.validated())
    }
    func testContinuationAndShiftingPreserveHistory() throws {
        var data = Workspace.demo()
        data.lessons[0].nextSteps = "Zadanie 3"
        data.lessons[0].status = .completed
        let old = data.lessons[0]
        try data.continueLesson(old.id, at: old.start.addingTimeInterval(86400 * 7))
        XCTAssertEqual(data.lessons.last?.continuationOf, old.id)
        XCTAssertEqual(data.lessons.last?.notes, "Zadanie 3")
        XCTAssertEqual(data.lessons.last?.resources, old.resources)
        let future = data.lessons.last!.start
        data.shiftUpcoming(classID: old.classID, from: old.start, days: 1)
        XCTAssertEqual(data.lessons[0].start, old.start)
        XCTAssertGreaterThan(data.lessons.last!.start, future)
        XCTAssertThrowsError(try data.continueLesson(old.id, at: old.start))
    }
    func testImportDiffKeepsAttachmentsAndExistingIDs() throws {
        let subject = Subject(name: "PHP"), planID = UUID()
        let plan = Curriculum(id: planID, subjectID: subject.id)
        let file = Resource(name: "Prezentacja", kind: .website, location: "https://example.com")
        let old = Topic(title: "Formularze", subject: subject.name, subjectID: subject.id, curriculumID: planID, order: 1, hours: 1, resources: [file])
        let changes = try TopicImport.changes(rows: [["Temat", "h"], ["Formularze", "2"], ["Sesje", "1"]], header: 0, titleColumn: 0, hoursColumn: 1, subject: subject, curriculum: plan, existing: [old])
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[0].topic.id, old.id)
        XCTAssertEqual(changes[0].topic.resources, [file])
        XCTAssertEqual(changes[0].topic.hours, 2)
        XCTAssertThrowsError(try TopicImport.changes(rows: [["T"], ["A"], ["A"]], header: 0, titleColumn: 0, hoursColumn: nil, subject: subject, curriculum: plan, existing: []))
    }
    func testStudentCopySkipsSymlinksAndDependencies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("src"), target = root.appendingPathComponent("copy")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try Data("plik".utf8).write(to: source.appendingPathComponent("index.html"))
        try Data("haslo".utf8).write(to: source.appendingPathComponent(".env"))
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("link"), withDestinationURL: source.appendingPathComponent("index.html"))
        try StudentFiles.copy(source, to: target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("index.html").path))
        for name in ["node_modules", ".env", "link"] { XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent(name).path)) }
        let solution = Resource(name: "Rozwiązanie", role: .solution)
        XCTAssertTrue(solution.isPrivate)
    }
    func testXlsxSharedStringsInlineStringsAndSheets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("xl/_rels"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("xl/worksheets"), withIntermediateDirectories: true)
        let files = [
            "xl/workbook.xml": "<workbook xmlns:r='r'><sheets><sheet name='PHP' r:id='r1'/></sheets></workbook>",
            "xl/_rels/workbook.xml.rels": "<Relationships><Relationship Id='r1' Target='worksheets/sheet1.xml'/></Relationships>",
            "xl/sharedStrings.xml": "<sst><si><t>Temat</t></si><si><t>Formularze</t></si></sst>",
            "xl/worksheets/sheet1.xml": "<worksheet><sheetData><row><c r='A1' t='s'><v>0</v></c><c r='B1' t='inlineStr'><is><t>Godziny</t></is></c></row><row><c r='A2' t='s'><v>1</v></c><c r='B2'><v>2</v></c></row></sheetData></worksheet>"
        ]
        for (path, content) in files { try content.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8) }
        let archive = root.appendingPathComponent("test.xlsx")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); process.currentDirectoryURL = root; process.arguments = ["-qr", archive.path, "xl"]
        try process.run(); process.waitUntilExit()
        let sheets = try SpreadsheetReader.read(archive)
        XCTAssertEqual(sheets.count, 1)
        XCTAssertEqual(sheets[0].name, "PHP")
        XCTAssertEqual(sheets[0].rows, [["Temat", "Godziny"], ["Formularze", "2"]])
    }
    @MainActor
    func testManagedServerCanStartLogAndStop() async throws {
        let runner = ActionRunner()
        var action = LaunchAction(name: "Test serwera", kind: .command, executable: "/bin/sh", arguments: ["-c", "echo serwer; exec /bin/sleep 30"])
        action.managed = true
        try runner.startService(action)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(runner.running.contains(action.id))
        XCTAssertTrue(runner.serviceOutput(action.id).contains("serwer"))
        runner.stopService(action.id)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(runner.running.contains(action.id))
        XCTAssertFalse(runner.services[action.id]?.isRunning ?? true)
    }
}

extension Version03Tests {
    func testStudentArchiveExcludesTeacherSolutions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let visible = root.appendingPathComponent("zadanie.txt"), secret = root.appendingPathComponent("rozwiazanie.txt")
        try Data("zadanie".utf8).write(to: visible); try Data("tajne".utf8).write(to: secret)
        let output = root.appendingPathComponent("uczen.zip")
        try StudentFiles.archive(resources: [(Resource(name: "Zadanie"), visible), (Resource(name: "Rozwiązanie", role: .solution), secret)], exercise: "Polecenie", to: output)
        let process = Process(); let pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); process.arguments = ["-Z1", output.path]; process.standardOutput = pipe
        try process.run(); let listing = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); process.waitUntilExit()
        XCTAssertTrue(listing.contains("zadanie.txt")); XCTAssertTrue(listing.contains("Polecenie.txt")); XCTAssertFalse(listing.contains("rozwiazanie.txt"))
    }
    @MainActor
    func testAutomaticBackupRetentionDoesNotRemoveOtherFiles() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("inne".utf8).write(to: folder.appendingPathComponent("moje.json"))
        for _ in 0..<33 { try AutomaticBackup.write(Data("kopia".utf8), to: folder) }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(names.filter { $0.hasPrefix("Belfer-auto-") }.count, 30)
        XCTAssertTrue(names.contains("moje.json"))
    }
}
