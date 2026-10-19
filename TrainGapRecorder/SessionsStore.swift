import Foundation

@MainActor
final class SessionsStore: ObservableObject {
    @Published private(set) var sessions: [SessionInfo] = []

    func refresh() {
        let dir = Recorder.sessionsDirectoryURL()
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []

        var out: [SessionInfo] = []
        for url in urls where url.pathExtension.lowercased() == "ndjson" {
            if let start = readSessionStart(url: url) {
                out.append(start)
                continue
            }

            // Fallback: best-effort parse from filename.
            let name = url.deletingPathExtension().lastPathComponent
            let parts = name.split(separator: "_")
            if parts.count >= 3 {
                let lineID = String(parts[1])
                let fromTo = parts[2].split(separator: "-")
                if fromTo.count == 2 {
                    out.append(SessionInfo(
                        id: name,
                        startedAt: Date.distantPast,
                        lineID: lineID,
                        startStationID: String(fromTo[0]),
                        startStationName: String(fromTo[0]),
                        directionTerminalStationID: String(fromTo[1]),
                        directionTerminalStationName: String(fromTo[1]),
                        fileURL: url
                    ))
                }
            }
        }

        sessions = out.sorted { $0.startedAt > $1.startedAt }
    }

    func delete(_ session: SessionInfo) {
        do {
            try FileManager.default.removeItem(at: session.fileURL)
        } catch {
            // Best-effort.
        }
        refresh()
    }

    /// Appends a note to a recording. The file stays append-only: what the ride recorded is never rewritten.
    func addNote(_ text: String, to session: SessionInfo) async throws {
        // NDJSONWriter would create a missing file, holding only the note.
        guard FileManager.default.fileExists(atPath: session.fileURL.path) else { throw CocoaError(.fileNoSuchFile) }
        let writer = try NDJSONWriter(fileURL: session.fileURL)
        do {
            try await writer.append(RecorderNote(addedAt: iso8601String(Date()), text: text))
        } catch {
            await writer.close()
            throw error
        }
        await writer.close()
    }

    /// Reads the end of the ride and the notes from the whole file. Lines are decoded only when
    /// they are one of those events: a ride file has thousands of samples and motion batches.
    nonisolated static func readDetails(url: URL) -> SessionDetails {
        var details = SessionDetails()
        guard let data = try? Data(contentsOf: url), let content = String(data: data, encoding: .utf8) else { return details }
        details.fileSizeBytes = data.count
        let decoder = JSONDecoder()
        // JSONEncoder writes no spaces, so the type appears exactly like this. Inside a string,
        // the quotes would be escaped, so a note's text cannot match.
        for line in content.split(separator: "\n") {
            if line.contains(#""type":"session_end""#), let end = try? decoder.decode(RecorderSessionEnd.self, from: Data(line.utf8)) {
                details.hasEnd = true
                details.durationSeconds = end.tMS / 1000
                details.endStationName = end.endStationName
                if let note = end.note, !note.isEmpty {
                    details.notes.insert(note, at: 0)  // Typed at Finish: before the ones added later.
                }
            } else if line.contains(#""type":"note""#), let note = try? decoder.decode(RecorderNote.self, from: Data(line.utf8)) {
                details.notes.append(note.text)
            }
        }
        return details
    }

    private func readSessionStart(url: URL) -> SessionInfo? {
        guard let firstLine = readFirstLine(url: url) else { return nil }
        guard let data = firstLine.data(using: .utf8) else { return nil }

        // Confirm the event type is session_start, then decode.
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = obj["type"] as? String,
            type == "session_start"
        else { return nil }

        let decoder = JSONDecoder()
        guard let event = try? decoder.decode(RecorderSessionStart.self, from: data) else { return nil }

        let startedAt = parseISO8601(event.startedAt) ?? Date.distantPast
        return SessionInfo(
            id: event.sessionID,
            startedAt: startedAt,
            lineID: event.lineID,
            startStationID: event.fromStationID,
            startStationName: event.fromStationName,
            directionTerminalStationID: event.toStationID,
            directionTerminalStationName: event.toStationName,
            fileURL: url
        )
    }

    private func readFirstLine(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: 8192)) ?? Data()
        guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return nil }
        if let nl = s.firstIndex(of: "\n") {
            return String(s[..<nl])
        }
        return s
    }

    private func parseISO8601(_ s: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
