import AppKit
import SwiftUI
import Observation

/// One received log line. Timestamps are arrival times (the CLI emits no
/// per-line timestamps for stdio logs), labeled as such in the UI.
struct LogLine: Identifiable, Equatable, Sendable {
    let id: Int
    let receivedAt: Date
    let text: String
    let isStderr: Bool
}

/// Owns one `container logs` stream: bounded buffer, follow, pause/resume,
/// and guaranteed child-process termination on stop (spec §21).
@MainActor
@Observable
final class LogSession {
    private(set) var lines: [LogLine] = []
    private(set) var isStreaming = false
    private(set) var didComplete = false
    var isPaused = false {
        didSet {
            if !isPaused { flushPending() }
        }
    }
    private(set) var failureMessage: String?

    /// Provides the log stream for (tail, follow, boot) — containers and
    /// machines share this session.
    typealias StreamProvider = @Sendable (Int?, Bool, Bool) async throws
        -> AsyncThrowingStream<CommandOutputEvent, Error>

    private let provider: StreamProvider
    private let bufferLimit: Int
    private var pending: [LogLine] = []
    private var partialLine = ""
    private var nextLineID = 0
    private var streamTask: Task<Void, Never>?

    init(provider: @escaping StreamProvider, bufferLimit: Int) {
        self.provider = provider
        self.bufferLimit = max(100, bufferLimit)
    }

    func start(tail: Int?, follow: Bool, boot: Bool) {
        stop()
        lines = []
        pending = []
        partialLine = ""
        failureMessage = nil
        didComplete = false
        isStreaming = true
        streamTask = Task {
            do {
                let stream = try await provider(tail, follow, boot)
                for try await event in stream {
                    switch event {
                    case .stdout(let text):
                        ingest(text, isStderr: false)
                    case .stderr(let text):
                        ingest(text, isStderr: true)
                    case .completed:
                        didComplete = true
                    }
                }
            } catch let error as ContainerEngineError where error == .commandCancelled {
                // Expected on stop().
            } catch {
                failureMessage = (error as? ContainerEngineError)
                    .map { UserFacingError.make(from: $0).explanation }
                    ?? error.localizedDescription
            }
            flushPartial()
            isStreaming = false
        }
    }

    /// Cancels the stream; cancellation terminates the child process.
    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func clear() {
        lines = []
        pending = []
    }

    var fullText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    private func ingest(_ chunk: String, isStderr: Bool) {
        // Chunks are not line-aligned: carry partial lines to the next chunk.
        let combined = partialLine + chunk
        var newLines = combined.components(separatedBy: "\n")
        partialLine = newLines.removeLast()
        guard !newLines.isEmpty else { return }
        let received = Date()
        let entries = newLines.map { text in
            nextLineID += 1
            return LogLine(id: nextLineID, receivedAt: received, text: text, isStderr: isStderr)
        }
        if isPaused {
            pending.append(contentsOf: entries)
            trim(&pending)
        } else {
            lines.append(contentsOf: entries)
            trim(&lines)
        }
    }

    private func flushPartial() {
        guard !partialLine.isEmpty else { return }
        nextLineID += 1
        let line = LogLine(id: nextLineID, receivedAt: Date(), text: partialLine, isStderr: false)
        partialLine = ""
        if isPaused {
            pending.append(line)
        } else {
            lines.append(line)
            trim(&lines)
        }
    }

    private func flushPending() {
        guard !pending.isEmpty else { return }
        lines.append(contentsOf: pending)
        pending = []
        trim(&lines)
    }

    private func trim(_ buffer: inout [LogLine]) {
        if buffer.count > bufferLimit {
            buffer.removeFirst(buffer.count - bufferLimit)
        }
    }
}

/// Log viewer (spec §21): monospaced, follow/pause, search, wrap and
/// timestamp toggles, auto-scroll, clear, copy, save. Closing the sheet
/// cancels the stream and the child process.
struct ContainerLogsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    enum LogSource { case container, machine }

    let container: ContainerSummary
    var logSource: LogSource = .container
    /// When embedded as a detail tab there is no sheet: drop the Done button,
    /// the redundant title, and the fixed sheet frame.
    var embedded = false
    @State private var session: LogSession?
    @State private var follow = true
    @State private var showBootLog = false
    @State private var search = ""
    @State private var wrapLines = true
    @State private var showTimestamps = false
    @State private var autoScroll = true

    private var visibleLines: [LogLine] {
        guard let session else { return [] }
        guard !search.isEmpty else { return session.lines }
        return session.lines.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            logBody
            Divider()
            statusBar
        }
        .frame(
            minWidth: embedded ? nil : 640,
            idealWidth: embedded ? nil : 760,
            minHeight: embedded ? nil : 420,
            idealHeight: embedded ? nil : 520
        )
        .frame(maxWidth: embedded ? .infinity : nil, maxHeight: embedded ? .infinity : nil)
        .task {
            let engine = env.engine
            let id = container.id
            let source = logSource
            let session = LogSession(
                provider: { tail, follow, boot in
                    switch source {
                    case .container:
                        try await engine.containerLogs(id: id, tail: tail, follow: follow, boot: boot)
                    case .machine:
                        try await engine.machineLogs(name: id, tail: tail, follow: follow, boot: boot)
                    }
                },
                bufferLimit: env.settings.logBufferLines
            )
            self.session = session
            session.start(tail: 500, follow: follow, boot: showBootLog)
        }
        .onDisappear {
            session?.stop()
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if !embedded {
                Text(container.name)
                    .font(.headline)
            }
            Picker("Source", selection: $showBootLog) {
                Text("Logs").tag(false)
                Text("Boot").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
            .labelsHidden()
            .onChange(of: showBootLog) { _, boot in
                session?.start(tail: boot ? nil : 500, follow: boot ? false : follow, boot: boot)
            }
            Toggle("Follow", isOn: $follow)
                .onChange(of: follow) { _, newValue in
                    guard !showBootLog else { return }
                    session?.start(tail: 500, follow: newValue, boot: false)
                }
                .disabled(showBootLog)
            if let session {
                Toggle("Pause", isOn: Binding(
                    get: { session.isPaused },
                    set: { session.isPaused = $0 }
                ))
                .disabled(!session.isStreaming)
            }
            Spacer()
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
            Menu {
                Toggle("Wrap Lines", isOn: $wrapLines)
                Toggle("Timestamps (received)", isOn: $showTimestamps)
                Toggle("Auto-scroll", isOn: $autoScroll)
                Divider()
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session?.fullText ?? "", forType: .string)
                }
                Button("Save…") { save() }
                Button("Clear View") { session?.clear() }
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 90)
            if !embedded {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
        .toggleStyle(.checkbox)
    }

    @ViewBuilder
    private var logBody: some View {
        if let session {
            if visibleLines.isEmpty && !session.isStreaming {
                ContentUnavailableView {
                    Label(
                        session.failureMessage == nil ? "No Log Output" : "Logs Unavailable",
                        systemImage: "text.alignleft"
                    )
                } description: {
                    Text(session.failureMessage ?? "The container has not produced any output.")
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(wrapLines ? .vertical : [.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(visibleLines) { line in
                                logRow(line)
                                    .id(line.id)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: visibleLines.last?.id) { _, lastID in
                        if autoScroll, let lastID {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
                .background(Color.deckTermBg)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func logRow(_ line: LogLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if showTimestamps {
                Text(line.receivedAt, format: .dateTime.hour().minute().second())
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.deckTextFaint)
            }
            Text(line.text)
                .font(.callout.monospaced())
                .foregroundStyle(line.isStderr ? Color.deckOrange : Color.deckTermText)
                .textSelection(.enabled)
                .lineLimit(wrapLines ? nil : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let session {
                if session.isStreaming {
                    ProgressView().controlSize(.mini)
                    Text(session.isPaused ? "Paused — output is buffered" : "Streaming")
                } else if session.didComplete {
                    Text("Log stream ended")
                }
                Spacer()
                Text("\(visibleLines.count) lines")
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(container.name)-logs.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Data((session?.fullText ?? "").utf8).write(to: url)
    }
}
