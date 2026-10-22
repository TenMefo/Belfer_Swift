import XCTest
@testable import Belfer

final class BelferTests: XCTestCase {
    func testCSVHandlesBOMQuotesMultilineAndEscapes() throws {
        let text = "\u{FEFF}temat;przedmiot;godziny\r\n\"JS; formularze\";INF.03;2\r\n\"Wiersz 1\nWiersz 2 i \"\"tekst\"\"\";Web;1"
        let items = try CSVImporter.topics(text)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "JS; formularze")
        XCTAssertEqual(items[0].hours, 2)
        XCTAssertEqual(items[1].title, "Wiersz 1\nWiersz 2 i \"tekst\"")
    }
    func testCSVCommaAndInvalidData() throws {
        XCTAssertEqual(try CSVImporter.topics("temat,przedmiot,godziny\nReact,Web,3").first?.hours, 3)
        XCTAssertThrowsError(try CSVImporter.topics("temat;godziny\nJS;abc"))
        XCTAssertThrowsError(try CSVImporter.topics("temat;godziny\nJS;0"))
        XCTAssertThrowsError(try CSVImporter.topics("temat;godziny\nJS;1;extra"))
        XCTAssertThrowsError(try CSVImporter.topics("temat\n\"bez końca"))
        XCTAssertThrowsError(try CSVImporter.topics("temat\n\"tekst\"x"))
        XCTAssertThrowsError(try CSVImporter.topics("inna\nJS"))
    }
    func testRecurringWeekIsIdempotentAndRespectsWeekBoundary() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let date = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))! // niedziela zmiany czasu
        let group = SchoolClass(name: "4TI")
        var data = Workspace(classes: [group], slots: [WeeklySlot(classID: group.id, weekday: 2, hour: 8), WeeklySlot(classID: group.id, weekday: 1, hour: 9)])
        data.generateWeek(containing: date, calendar: cal)
        data.generateWeek(containing: date, calendar: cal)
        XCTAssertEqual(data.lessons.count, 2)
        XCTAssertEqual(data.lessons.map { cal.component(.day, from: $0.start) }.sorted(), [19, 25])
        XCTAssertEqual(data.lessons.map { cal.component(.hour, from: $0.start) }.sorted(), [8, 9])
        _ = try data.validated()
    }
    func testConflictsAdjacentCancelledAndSameID() {
        let group = SchoolClass(name: "3TP")
        let first = Lesson(classID: group.id, start: Date(timeIntervalSince1970: 0))
        var data = Workspace(classes: [group], lessons: [first])
        XCTAssertFalse(data.conflicts(with: first))
        XCTAssertTrue(data.conflicts(with: Lesson(classID: group.id, start: first.start.addingTimeInterval(60))))
        XCTAssertFalse(data.conflicts(with: Lesson(classID: group.id, start: first.end)))
        data.lessons[0].status = .cancelled
        XCTAssertFalse(data.conflicts(with: Lesson(classID: group.id, start: first.start)))
    }
    func testPreviousLessonUsesSameClassAndCompletedOnly() {
        let group = SchoolClass(name: "3TP"), other = SchoolClass(name: "4TP")
        let first = Lesson(classID: group.id, start: Date(timeIntervalSince1970: 0), status: .completed, nextSteps: "Slajd 12")
        let planned = Lesson(classID: group.id, start: Date(timeIntervalSince1970: 1000))
        let foreign = Lesson(classID: other.id, start: Date(timeIntervalSince1970: 2000), status: .completed)
        let next = Lesson(classID: group.id, start: Date(timeIntervalSince1970: 5000))
        let data = Workspace(classes: [group, other], lessons: [first, planned, foreign, next])
        XCTAssertEqual(data.previousLesson(before: next)?.nextSteps, "Slajd 12")
    }
    func testValidationRejectsBrokenRelationsAndUnknownSchema() throws {
        var data = Workspace(lessons: [Lesson(classID: UUID())])
        XCTAssertThrowsError(try data.validated())
        data = Workspace(schemaVersion: 2)
        XCTAssertThrowsError(try data.validated())
        let group = SchoolClass(name: "4TI")
        data = Workspace(classes: [group, group])
        XCTAssertThrowsError(try data.validated())
        data = Workspace(classes: [group], slots: [WeeklySlot(classID: group.id, hour: 25)])
        XCTAssertThrowsError(try data.validated())
        _ = try Workspace.demo().validated()
    }
    @MainActor
    func testAtomicPersistenceRoundTripAndPreviousCopy() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WorkspaceStore(directory: dir)
        XCTAssertTrue(store.change { $0 = .demo() })
        XCTAssertTrue(store.change { $0.classes[0].notes = "Nowa notatka" })
        let loaded = WorkspaceStore(directory: dir)
        XCTAssertEqual(loaded.data, store.data)
        let previous = try WorkspaceStore.decode(Data(contentsOf: dir.appendingPathComponent("workspace.previous.json")))
        XCTAssertEqual(previous.classes[0].notes, "")
        let bytes = try WorkspaceStore.encode(store.data)
        XCTAssertEqual(try WorkspaceStore.decode(bytes), store.data)
    }
    @MainActor
    func testCorruptFileIsNeverOverwritten() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("workspace.json")
        let broken = Data("uszkodzone".utf8)
        try broken.write(to: file)
        let store = WorkspaceStore(directory: dir)
        XCTAssertTrue(store.locked)
        XCTAssertFalse(store.change { $0 = .demo() })
        XCTAssertEqual(try Data(contentsOf: file), broken)
    }
    @MainActor
    func testUnsafeLinksAreRejected() async throws {
        let store = WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertThrowsError(try store.resolvedURL(Resource(name: "Bad", kind: .website, location: "javascript:alert(1)")))
        XCTAssertThrowsError(try store.resolvedURL(Resource(name: "Bad", kind: .website, location: "https:")))
        XCTAssertNoThrow(try store.resolvedURL(Resource(name: "Chat", kind: .chat, location: "https://chatgpt.com/c/example")))
    }
}
