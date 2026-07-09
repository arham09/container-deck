import SwiftUI

/// Compact popover listing the operations currently running (system start/stop,
/// image/container/machine actions) with their live phase. Nothing is retained
/// once an operation finishes — see `OperationStore`.
struct OperationsPopoverView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Operations")
                .font(.headline)
                .foregroundStyle(Color.deckText)
            let running = env.operations.active
            if running.isEmpty {
                Text("No operations running.")
                    .foregroundStyle(Color.deckTextDim)
                    .font(.callout)
            } else {
                ForEach(running) { record in
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.mini)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(record.title)
                                .font(.callout)
                                .foregroundStyle(Color.deckText)
                                .lineLimit(1)
                            if let phase = record.phase {
                                Text(phase)
                                    .font(.caption)
                                    .foregroundStyle(Color.deckTextDim)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(record.startedAt, format: .dateTime.hour().minute())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.deckTextFaint)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}

struct OperationsPopoverView_Previews: PreviewProvider {
    static var previews: some View {
        OperationsPopoverView()
            .environment(makeEnvironment())
    }

    static func makeEnvironment() -> AppEnvironment {
        let environment = AppEnvironment.preview(running: true)
        environment.operations.begin(
            title: "Stopping Apple Container",
            kind: .stopSystem,
            redactedCommand: "container system stop",
            phase: "Waiting for the system to report stopped"
        )
        return environment
    }
}
