import XCTest
@testable import Belfer

final class LaunchActionTests: XCTestCase {
    func testXamppPresetsAndNoEmbeddedSudo() throws {
        for operation in ["start", "stop", "restart", "status"] {
            let action = LaunchAction.xampp(operation)
            try action.validate()
            XCTAssertEqual(action.arguments, [operation])
            XCTAssertEqual(action.administrator, operation != "status")
            XCTAssertFalse(action.privilegedScript.contains("sudo"))
            XCTAssertTrue(action.privilegedScript.hasSuffix("with administrator privileges"))
            XCTAssertFalse(action.withMaterials)
        }
    }
    func testArgumentsArePassedLiterallyAndOutputIsCaptured() throws {
        let literal = "O'Brien $(echo INJECTION); `echo INJECTION` \"projekt\""
        let action = LaunchAction(name: "Wypisz", kind: .command, executable: "/usr/bin/printf", arguments: ["%s", literal])
        let result = try ActionExecutor.run(action)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output, literal)
        // Ten sam sposób cytowania jest używany przy poleceniach administratora.
        let wrapper = LaunchAction(name: "Cytowanie", kind: .command, executable: "/bin/sh", arguments: ["-c", action.displayCommand])
        XCTAssertEqual(try ActionExecutor.run(wrapper).output, literal)
    }
    func testWorkingDirectoryAndNonzeroExit() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Belfer O'Brien \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let action = LaunchAction(name: "Katalog", kind: .command, executable: "/bin/sh", arguments: ["-c", "pwd; echo blad >&2; exit 7"], folder: folder.path)
        let result = try ActionExecutor.run(action)
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.output.contains(folder.lastPathComponent))
        XCTAssertTrue(result.output.contains("blad"))
        let wrapper = LaunchAction(name: "Katalog admin", kind: .command, executable: "/bin/sh", arguments: ["-c", action.displayCommand])
        let quoted = try ActionExecutor.run(wrapper)
        XCTAssertEqual(quoted.exitCode, 7)
        XCTAssertTrue(quoted.output.contains(folder.lastPathComponent))
    }
    func testLargeOutputDoesNotDeadlockAndTimeoutReturns() throws {
        let large = LaunchAction(name: "Duży wynik", kind: .command, executable: "/usr/bin/seq", arguments: ["1", "30000"])
        XCTAssertTrue(try ActionExecutor.run(large).output.contains("64 KB"))
        let sleep = LaunchAction(name: "Limit czasu", kind: .command, executable: "/bin/sleep", arguments: ["10"])
        let started = Date()
        let result = try ActionExecutor.run(sleep, timeout: 0.15)
        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }
    func testValidationAndMissingPaths() {
        XCTAssertThrowsError(try LaunchAction(name: "Brak ścieżki", executable: "code").validate())
        XCTAssertThrowsError(try LaunchAction(name: "Nie aplikacja", executable: "/bin/sh").validate())
        XCTAssertThrowsError(try LaunchAction(name: "NUL", kind: .command, executable: "/bin/echo", arguments: ["a\0b"]).validate())
        XCTAssertThrowsError(try ActionExecutor.resolved(LaunchAction(name: "Brak", kind: .command, executable: "/not-a-belfer-program")))
        XCTAssertThrowsError(try ActionExecutor.resolved(LaunchAction(name: "Katalog", kind: .command, executable: "/bin/pwd", folder: "/not-a-belfer-folder")))
    }
    func testMatchingAndWorkspaceCompatibility() throws {
        let group = SchoolClass(name: "4TI")
        let topic = Topic(title: "PHP")
        let lesson = Lesson(classID: group.id, topicID: topic.id)
        var data = Workspace(classes: [group], topics: [topic], lessons: [lesson])
        var scoped = LaunchAction.vscode(); scoped.topicID = topic.id
        var another = LaunchAction.xampp("stop"); another.lessonID = UUID()
        var global = LaunchAction.xampp("start"); global.withMaterials = true
        data.actions = [scoped, global]
        XCTAssertEqual(data.actions(for: lesson).map(\.id), [scoped.id, global.id])
        data.actions.append(LaunchAction.xampp("status"))
        XCTAssertEqual(data.actions(for: lesson).count, 2) // samo przypięcie na kokpicie nie dodaje do zestawu
        _ = try data.validated()
        data.actions.append(another)
        XCTAssertThrowsError(try data.validated())
    }
    @MainActor
    func testOldBackupAndActionRoundTrip() async throws {
        let original = Workspace.demo()
        let oldBytes = try WorkspaceStore.encode(original)
        XCTAssertFalse(String(decoding: oldBytes, as: UTF8.self).contains("launchActions"))
        XCTAssertTrue(try WorkspaceStore.decode(oldBytes).actions.isEmpty)
        var updated = original
        updated.actions = [.vscode(), .xampp("start"), .xampp("stop")]
        XCTAssertEqual(try WorkspaceStore.decode(WorkspaceStore.encode(updated)), updated)
    }
    @MainActor
    func testRunnerStopsBatchOnFailure() async throws {
        let runner = ActionRunner()
        let failure = LaunchAction(name: "Błąd", kind: .command, executable: "/bin/sh", arguments: ["-c", "exit 4"])
        let next = LaunchAction(name: "Pominięta", kind: .command, executable: "/usr/bin/printf", arguments: ["nigdy"])
        var callbackCalled = false
        runner.run([failure, next]) { callbackCalled = true }
        let deadline = Date().addingTimeInterval(10)
        while runner.busy && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(runner.busy)
        XCTAssertEqual(runner.results[failure.id]?.exitCode, 4)
        XCTAssertNil(runner.results[next.id])
        XCTAssertFalse(callbackCalled)
        XCTAssertTrue(runner.showingOutput)
    }
}
