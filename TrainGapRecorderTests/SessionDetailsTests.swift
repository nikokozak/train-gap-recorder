import Foundation
import Testing
@testable import TrainGapRecorder

/// The detail screen reads the end of the ride and the notes, which are appended after it.
struct SessionDetailsTests {
    private func writeRecording(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).ndjson")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func notesFollowTheNoteTypedAtFinish() throws {
        let trickyNote = #"says "type":"note" in the text"#
        let encodedNote = String(decoding: try JSONEncoder().encode(RecorderNote(addedAt: "2026-10-19T08:00:00Z", text: trickyNote)), as: UTF8.self)
        let url = try writeRecording([
            #"{"type":"session_start","v":1}"#,
            #"{"type":"sample","t_ms":0}"#,
            #"{"type":"session_end","t_ms":125400,"ended_at":"2026-10-19T07:40:00Z","note":"phone in a pocket"}"#,
            encodedNote,
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let details = SessionsStore.readDetails(url: url)
        #expect(details.hasEnd)
        #expect(details.durationSeconds == 125)
        #expect(details.endStationName == nil)  // "Not sure"
        #expect(details.notes == ["phone in a pocket", trickyNote])
    }

    @Test func aRideCutOffBeforeStopHasNoEnd() throws {
        let url = try writeRecording([#"{"type":"session_start","v":1}"#, #"{"type":"sample","t_ms":0}"#])
        defer { try? FileManager.default.removeItem(at: url) }

        let details = SessionsStore.readDetails(url: url)
        #expect(!details.hasEnd)
        #expect(details.notes.isEmpty)
    }
}
