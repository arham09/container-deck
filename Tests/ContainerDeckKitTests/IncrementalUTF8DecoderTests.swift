import Foundation
import Testing
@testable import ContainerDeckKit

@Suite("IncrementalUTF8Decoder")
struct IncrementalUTF8DecoderTests {
    @Test("ASCII passes through unchanged")
    func ascii() {
        var decoder = IncrementalUTF8Decoder()
        #expect(decoder.decode(Data("hello".utf8)) == "hello")
        #expect(decoder.flush() == "")
    }

    @Test("Three-byte codepoint split across chunks reassembles")
    func splitEuroSign() {
        // € = E2 82 AC
        var decoder = IncrementalUTF8Decoder()
        #expect(decoder.decode(Data([0xE2])) == "")
        #expect(decoder.decode(Data([0x82])) == "")
        #expect(decoder.decode(Data([0xAC])) == "€")
    }

    @Test("Four-byte emoji split mid-sequence reassembles")
    func splitEmoji() {
        // 🚀 = F0 9F 9A 80
        var decoder = IncrementalUTF8Decoder()
        #expect(decoder.decode(Data([0x61, 0xF0, 0x9F])) == "a")
        #expect(decoder.decode(Data([0x9A, 0x80, 0x62])) == "🚀b")
    }

    @Test("Complete multibyte suffix is not held back")
    func completeSuffix() {
        var decoder = IncrementalUTF8Decoder()
        #expect(decoder.decode(Data("héllo".utf8)) == "héllo")
    }

    @Test("Flush decodes an incomplete trailing sequence lossily")
    func flushIncomplete() {
        var decoder = IncrementalUTF8Decoder()
        #expect(decoder.decode(Data([0x61, 0xE2])) == "a")
        #expect(decoder.flush() == "\u{FFFD}")
    }

    @Test("Invalid bytes decode to replacement characters, never dropped silently")
    func invalidBytes() {
        var decoder = IncrementalUTF8Decoder()
        let text = decoder.decode(Data([0x61, 0xFF, 0x62]))
        #expect(text.contains("a"))
        #expect(text.contains("b"))
        #expect(text.contains("\u{FFFD}"))
    }

    @Test("Suffix-length calculation covers boundary cases")
    func suffixLength() {
        #expect(IncrementalUTF8Decoder.incompleteSuffixLength(of: []) == 0)
        #expect(IncrementalUTF8Decoder.incompleteSuffixLength(of: [0x41]) == 0)
        #expect(IncrementalUTF8Decoder.incompleteSuffixLength(of: [0xE2]) == 1)
        #expect(IncrementalUTF8Decoder.incompleteSuffixLength(of: [0xE2, 0x82]) == 2)
        #expect(IncrementalUTF8Decoder.incompleteSuffixLength(of: [0xE2, 0x82, 0xAC]) == 0)
        #expect(IncrementalUTF8Decoder.incompleteSuffixLength(of: [0xF0, 0x9F, 0x9A]) == 3)
        #expect(IncrementalUTF8Decoder.incompleteSuffixLength(of: [0xF0, 0x9F, 0x9A, 0x80]) == 0)
    }
}
