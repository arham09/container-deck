import Foundation

/// Decodes UTF-8 text from a sequence of arbitrary byte chunks.
///
/// Pipe reads split output at arbitrary byte boundaries, including in the
/// middle of a multi-byte codepoint. This decoder holds back an incomplete
/// trailing sequence until the next chunk completes it. Invalid bytes decode
/// to U+FFFD rather than being dropped.
struct IncrementalUTF8Decoder {
    private var pending: [UInt8] = []

    /// Feeds a chunk and returns all text that is complete so far.
    mutating func decode(_ chunk: Data) -> String {
        pending.append(contentsOf: chunk)
        let holdCount = Self.incompleteSuffixLength(of: pending)
        let readyCount = pending.count - holdCount
        guard readyCount > 0 else { return "" }
        let ready = pending[0..<readyCount]
        pending = Array(pending[readyCount...])
        return String(decoding: ready, as: UTF8.self)
    }

    /// Flushes any held-back bytes (used at end of stream); incomplete
    /// sequences decode lossily.
    mutating func flush() -> String {
        guard !pending.isEmpty else { return "" }
        let text = String(decoding: pending, as: UTF8.self)
        pending = []
        return text
    }

    /// Number of trailing bytes that form an incomplete UTF-8 sequence.
    static func incompleteSuffixLength(of bytes: [UInt8]) -> Int {
        guard !bytes.isEmpty else { return 0 }
        let scanLimit = min(4, bytes.count)
        for offset in 1...scanLimit {
            let byte = bytes[bytes.count - offset]
            if byte & 0b1000_0000 == 0 {
                // ASCII byte: everything up to here is complete.
                return 0
            }
            if byte & 0b1100_0000 == 0b1100_0000 {
                // Leading byte of a multi-byte sequence.
                let needed: Int
                if byte >= 0xF0 {
                    needed = 4
                } else if byte >= 0xE0 {
                    needed = 3
                } else {
                    needed = 2
                }
                return offset < needed ? offset : 0
            }
            // Continuation byte: keep scanning backwards.
        }
        // Four trailing continuation bytes cannot be a valid suffix; let the
        // lossy decoder handle them.
        return 0
    }
}
