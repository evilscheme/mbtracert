import Testing
@testable import TraceBar

@Suite("ICMP Parsing")
struct ICMPParsingTests {

    // MARK: - Helpers

    /// Synthetic Echo Reply (type 0) — IP_STRIPHDR means ICMP starts at byte 0.
    private func echoReply(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: 8)
        buf[0] = 0  // type: Echo Reply
        buf[1] = 0  // code
        buf[4] = UInt8(identifier >> 8)
        buf[5] = UInt8(identifier & 0xFF)
        buf[6] = UInt8(sequence >> 8)
        buf[7] = UInt8(sequence & 0xFF)
        return buf
    }

    /// Synthetic ICMP error response (Time Exceeded or Dest Unreachable) with
    /// an embedded inner IP + ICMP Echo Request header.
    private func icmpError(
        type: UInt8,
        code: UInt8,
        innerIdentifier: UInt16,
        innerSequence: UInt16,
        innerIHL: UInt8 = 5
    ) -> [UInt8] {
        let innerIPSize = Int(innerIHL) * 4
        let totalSize = 8 + innerIPSize + 8
        var buf = [UInt8](repeating: 0, count: totalSize)
        buf[0] = type
        buf[1] = code
        // Inner IP header at offset 8
        buf[8] = 0x40 | innerIHL
        // Inner ICMP at offset 8 + innerIPSize
        let off = 8 + innerIPSize
        buf[off]     = 8  // type: Echo Request
        buf[off + 1] = 0  // code
        buf[off + 4] = UInt8(innerIdentifier >> 8)
        buf[off + 5] = UInt8(innerIdentifier & 0xFF)
        buf[off + 6] = UInt8(innerSequence >> 8)
        buf[off + 7] = UInt8(innerSequence & 0xFF)
        return buf
    }

    // MARK: - Echo Reply

    @Test func echoReplyExtractsSequence() {
        let buf = echoReply(identifier: 0x1234, sequence: 0xABCD)
        let result = ICMPEngine.parseResponse(buf, count: buf.count, identifier: 0x1234)
        #expect(result != nil)
        #expect(result?.seq == 0xABCD)
    }

    @Test func echoReplyReportsTypeZero() {
        let buf = echoReply(identifier: 0x1234, sequence: 100)
        let result = ICMPEngine.parseResponse(buf, count: buf.count, identifier: 0x1234)
        #expect(result?.icmpType == 0)
        #expect(result?.icmpCode == 0)
    }

    // MARK: - Time Exceeded

    @Test func timeExceededExtractsInnerSequence() {
        let buf = icmpError(type: 11, code: 0, innerIdentifier: 0x1234, innerSequence: 0x5678)
        let result = ICMPEngine.parseResponse(buf, count: buf.count, identifier: 0x1234)
        #expect(result != nil)
        #expect(result?.seq == 0x5678)
        #expect(result?.icmpType == 11)
    }

    @Test func timeExceededWithNonStandardIHL() {
        let buf = icmpError(type: 11, code: 0, innerIdentifier: 0x1234, innerSequence: 42, innerIHL: 6)
        let result = ICMPEngine.parseResponse(buf, count: buf.count, identifier: 0x1234)
        #expect(result != nil)
        #expect(result?.seq == 42)
    }

    // MARK: - Dest Unreachable

    @Test func destUnreachableExtractsSequenceAndCode() {
        let buf = icmpError(type: 3, code: 3, innerIdentifier: 0x1234, innerSequence: 0x5678)
        let result = ICMPEngine.parseResponse(buf, count: buf.count, identifier: 0x1234)
        #expect(result != nil)
        #expect(result?.seq == 0x5678)
        #expect(result?.icmpType == 3)
        #expect(result?.icmpCode == 3)
    }

    @Test func destUnreachablePreservesAllCodes() {
        for code: UInt8 in [0, 1, 2, 3, 4, 13] {
            let buf = icmpError(type: 3, code: code, innerIdentifier: 0xAAAA, innerSequence: 100)
            let result = ICMPEngine.parseResponse(buf, count: buf.count, identifier: 0xAAAA)
            #expect(result?.icmpCode == code, "Code \(code) not preserved")
        }
    }

    // MARK: - Identifier validation (Finding #4)

    @Test func timeExceededRejectsWrongIdentifier() {
        let buf = icmpError(type: 11, code: 0, innerIdentifier: 0x9999, innerSequence: 100)
        let result = ICMPEngine.parseResponse(buf, count: buf.count, identifier: 0x1234)
        #expect(result == nil)
    }

    @Test func destUnreachableRejectsWrongIdentifier() {
        let buf = icmpError(type: 3, code: 3, innerIdentifier: 0x9999, innerSequence: 100)
        let result = ICMPEngine.parseResponse(buf, count: buf.count, identifier: 0x1234)
        #expect(result == nil)
    }

    // MARK: - Edge cases

    @Test func bufferTooShortReturnsNil() {
        let buf: [UInt8] = [0, 0, 0]
        let result = ICMPEngine.parseResponse(buf, count: buf.count, identifier: 0x1234)
        #expect(result == nil)
    }

    @Test func unknownTypeReturnsNil() {
        var buf = [UInt8](repeating: 0, count: 8)
        buf[0] = 5  // Redirect — not handled
        let result = ICMPEngine.parseResponse(buf, count: buf.count, identifier: 0x1234)
        #expect(result == nil)
    }

    @Test func errorResponseTooShortForInnerICMPReturnsNil() {
        // Has outer ICMP + start of inner IP but not enough for inner ICMP
        var buf = [UInt8](repeating: 0, count: 32)
        buf[0] = 11      // Time Exceeded
        buf[8] = 0x45    // IPv4, IHL=5 (20 bytes) → inner ICMP at 28, need 36
        let result = ICMPEngine.parseResponse(buf, count: buf.count, identifier: 0x1234)
        #expect(result == nil)
    }

    @Test func countSmallerThanBufferIsRespected() {
        let buf = echoReply(identifier: 0x1234, sequence: 100)
        let result = ICMPEngine.parseResponse(buf, count: 3, identifier: 0x1234)
        #expect(result == nil)
    }
}
