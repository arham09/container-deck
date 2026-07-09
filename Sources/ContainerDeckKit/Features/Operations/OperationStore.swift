import Foundation
import Observation

/// Tracks in-flight operations for the live operations popover and toolbar
/// badge. Records are kept in memory only — nothing is persisted or browsable
/// after an operation finishes.
@MainActor
@Observable
public final class OperationStore {
    /// Newest first.
    public private(set) var operations: [OperationRecord] = []

    /// Upper bound on retained records; finished ones are dropped oldest-first.
    private let capacity = 200
    /// Upper bound on the stored output excerpt per operation.
    private let outputCapacity = 16_384

    public init() {}

    public var active: [OperationRecord] {
        operations.filter { $0.status == .running }
    }

    public var hasActiveOperations: Bool {
        operations.contains { $0.status == .running }
    }

    @discardableResult
    public func begin(
        title: String,
        kind: OperationRecord.Kind,
        redactedCommand: String? = nil,
        phase: String? = nil
    ) -> UUID {
        let record = OperationRecord(
            title: title,
            kind: kind,
            redactedCommand: redactedCommand,
            phase: phase
        )
        operations.insert(record, at: 0)
        trim()
        return record.id
    }

    public func updatePhase(_ id: UUID, phase: String) {
        mutate(id) { $0.phase = phase }
    }

    /// Appends already-redacted output. Callers are responsible for redaction.
    public func appendOutput(_ id: UUID, text: String) {
        mutate(id) { record in
            record.outputExcerpt += text
            if record.outputExcerpt.count > outputCapacity {
                record.outputExcerpt = String(record.outputExcerpt.suffix(outputCapacity))
            }
        }
    }

    public func finish(_ id: UUID, status: OperationRecord.Status) {
        mutate(id) { record in
            record.status = status
            record.endedAt = Date()
            record.phase = nil
        }
    }

    private func mutate(_ id: UUID, _ transform: (inout OperationRecord) -> Void) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        transform(&operations[index])
    }

    private func trim() {
        guard operations.count > capacity else { return }
        // Never drop running operations; drop the oldest finished ones.
        var finishedIndices = operations.indices.filter { operations[$0].status.isFinished }
        while operations.count > capacity, let last = finishedIndices.popLast() {
            operations.remove(at: last)
        }
    }
}
