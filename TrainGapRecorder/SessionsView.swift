import SwiftUI

struct SessionsView: View {
    @EnvironmentObject private var sessionsStore: SessionsStore

    /// A swipe asks before it deletes: a recording is a ride that cannot be repeated.
    @State private var sessionToDelete: SessionInfo?

    var body: some View {
        List {
            if sessionsStore.sessions.isEmpty {
                Text("No sessions yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessionsStore.sessions) { session in
                    NavigationLink(value: session) {
                        SessionRow(session: session)
                    }
                }
                .onDelete { offsets in
                    sessionToDelete = offsets.first.map { sessionsStore.sessions[$0] }
                }
            }
        }
        .navigationTitle("Sessions")
        .navigationDestination(for: SessionInfo.self) { session in
            SessionDetailView(session: session)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sessionsStore.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .deleteRecordingDialog(for: $sessionToDelete) { session in
            sessionsStore.delete(session)
        }
    }
}

private struct SessionRow: View {
    var session: SessionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(session.lineID) \(session.startStationName) → \(session.directionTerminalStationName)")
                .font(.headline)
            Text(session.startedAt == Date.distantPast ? session.fileURL.lastPathComponent : dateString(session.startedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// One recording: what it holds, its notes, and Share, Add note, and Delete.
private struct SessionDetailView: View {
    @EnvironmentObject private var sessionsStore: SessionsStore
    @Environment(\.dismiss) private var dismiss

    var session: SessionInfo

    @State private var details = SessionDetails()
    @State private var isAddingNote = false
    @State private var newNote = ""
    @State private var sessionToDelete: SessionInfo?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                DetailRow(name: "Started", value: session.startedAt == Date.distantPast ? "—" : dateString(session.startedAt))
                DetailRow(name: "Toward", value: session.directionTerminalStationName)
                DetailRow(name: "Got off", value: endStationText)
                DetailRow(name: "Length", value: details.durationSeconds.map { formatElapsed(seconds: $0) } ?? "—")
                DetailRow(name: "File", value: ByteCountFormatter.string(fromByteCount: Int64(details.fileSizeBytes), countStyle: .file))
            }

            Section("Notes") {
                ForEach(Array(details.notes.enumerated()), id: \.offset) { _, note in
                    Text(note)
                }
                Button("Add note", systemImage: "square.and.pencil") {
                    newNote = ""
                    isAddingNote = true
                }
            }

            Section {
                ShareLink(item: session.fileURL) {
                    Label("Share recording", systemImage: "square.and.arrow.up")
                }
                Button("Delete recording", systemImage: "trash", role: .destructive) {
                    sessionToDelete = session
                }
                .foregroundStyle(.red)  // The role colors the text only; the icon would stay blue.
            } footer: {
                Text(session.fileURL.lastPathComponent)
            }
        }
        .navigationTitle("\(session.lineID) from \(session.startStationName)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetails()
        }
        .alert("Add note", isPresented: $isAddingNote) {
            TextField("For example: phone in a pocket", text: $newNote)
                .autocorrectionDisabled()  // It turns station names like "Atlantic Av" into "Atlantic At".
            Button("Add") {
                Task { await addNote() }
            }
            .disabled(newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The note is added to the end of the recording file.")
        }
        .alert("Could not add the note", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .deleteRecordingDialog(for: $sessionToDelete) { session in
            sessionsStore.delete(session)
            dismiss()
        }
    }

    private var endStationText: String {
        guard details.hasEnd else { return "Not saved (the app ended before Stop)" }
        return details.endStationName ?? "Not sure"
    }

    /// Reads the file off the main thread: a long ride is a few megabytes.
    private func loadDetails() async {
        let url = session.fileURL
        details = await Task.detached { SessionsStore.readDetails(url: url) }.value
    }

    private func addNote() async {
        do {
            try await sessionsStore.addNote(newNote.trimmingCharacters(in: .whitespacesAndNewlines), to: session)
            await loadDetails()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DetailRow: View {
    var name: String
    var value: String

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private extension View {
    /// Asks before a recording is deleted, from a swipe or from the Delete button.
    func deleteRecordingDialog(for session: Binding<SessionInfo?>, delete: @escaping (SessionInfo) -> Void) -> some View {
        confirmationDialog(
            "Delete this recording?",
            isPresented: Binding(get: { session.wrappedValue != nil }, set: { if !$0 { session.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: session.wrappedValue
        ) { presentedSession in
            Button("Delete recording", role: .destructive) {
                delete(presentedSession)
            }
        } message: { _ in
            Text("This cannot be undone. Share it first to keep a copy.")
        }
    }
}

private func dateString(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
}
