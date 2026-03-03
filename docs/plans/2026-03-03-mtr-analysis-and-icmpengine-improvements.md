# mtr Source Analysis & ICMPEngine Improvement Plan

**Date:** 2026-03-03
**Source:** Analysis of [traviscross/mtr](https://github.com/traviscross/mtr) source code
**Target file:** `MenubarTracert/TracertHelper/ICMPEngine.swift`

## Purpose

This document captures how mtr achieves higher hop visibility than standard traceroute, and provides actionable improvements for our `ICMPEngine`. A future agent session should be able to implement these changes using this document alone.

---

## Why mtr Sees Hops That Traceroute Misses

### 1. Continuous Probing (already handled at our ViewModel layer)

Standard traceroute sends 3 probes per hop and gives up. mtr sends probes continuously in rounds. If a hop drops 90% of probes, traceroute shows `* * *`, but mtr accumulates statistics and eventually gets a response. Our `TracerouteViewModel` already runs continuous rounds, so this advantage is already present in our architecture.

### 2. Multi-Protocol Probes (not implemented)

Many routers rate-limit or drop ICMP Echo Requests but still generate ICMP Time Exceeded for UDP or TCP packets transiting through them. mtr supports ICMP, UDP, TCP, and SCTP probe modes.

- **UDP mode:** Sends raw UDP packets to high destination ports (starting 33434) with low TTLs. Intermediate routers send TTL Exceeded. The destination sends ICMP Port Unreachable (type 3, code 3), which mtr treats as "destination reached."
- **TCP mode:** Opens a non-blocking `SOCK_STREAM` socket with a low TTL, calls `connect()`. Intermediate routers still send TTL Exceeded. Destination either completes the handshake or sends RST — both detected via `select()` writability.

### 3. Broader ICMP Response Handling (partially missing)

mtr handles three ICMP response types:

| ICMP Type | Code | Meaning | Our engine handles? |
|-----------|------|---------|-------------------|
| 0 (Echo Reply) | — | Destination reached | Yes |
| 11 (Time Exceeded) | 0 | TTL expired in transit | Yes |
| 3 (Dest Unreachable) | 3 (Port Unreachable) | Destination reached (UDP) | **No** |
| 3 (Dest Unreachable) | other | Network/host/admin unreachable | **No** |

### 4. Asynchronous I/O (not implemented)

mtr sends all probes for a round without waiting, then collects responses. It uses non-blocking sockets with `select()`. Our engine sends one probe, blocks waiting for a response, then sends the next. This makes us slower and more susceptible to timing issues.

### 5. Separate Send/Receive Sockets (not implemented)

mtr uses separate sockets for sending and receiving. The receive socket is `SOCK_RAW, IPPROTO_ICMP`, which catches all ICMP packets on the system. This allows receiving ICMP errors generated in response to UDP/TCP probes sent on different sockets.

---

## Current ICMPEngine Limitations

Referencing `MenubarTracert/TracertHelper/ICMPEngine.swift`:

1. **ICMP-only probes** — builds and sends only ICMP Echo Request (type 8). See `buildPacket()` at line 80.
2. **Blocking sequential I/O** — loops `for hop in 1...maxHops`, sends one probe, calls blocking `recvfrom()` with `SO_RCVTIMEO`, then moves to next hop. See `probeRound()` at line 36.
3. **Single socket** — one `SOCK_RAW, IPPROTO_ICMP` socket for both send and receive. See line 18.
4. **Sequence numbers are hop numbers** — `let seq = UInt16(hop)` at line 40. This means sequence 1 is reused every round, risking stale response matching.
5. **Only handles ICMP types 0 and 11** — `receiveResponse()` at lines 149-167 ignores type 3 (Destination Unreachable).
6. **Socket created and destroyed per round** — `probeRound()` opens/closes the socket each call. See lines 18-22.

---

## Recommended Improvements

### Priority 1: Handle ICMP Destination Unreachable (quick win)

**What:** In `receiveResponse()`, add handling for ICMP type 3. Port Unreachable (code 3) should be treated as "destination reached." Other codes (network unreachable, host unreachable, admin prohibited) should be reported as a reachable hop with an error indicator.

**Why:** Some destinations don't respond to ICMP Echo but do send Port Unreachable for UDP. Even in ICMP-only mode, some firewalls send Destination Unreachable instead of silently dropping.

**Where:** `ICMPEngine.swift`, `receiveResponse()`, after the `else if icmpType == 11` block (line 155). The inner packet parsing is identical to the Time Exceeded case — extract the inner IP header, find the inner ICMP header, match ID and sequence.

**Code sketch:**
```swift
} else if icmpType == 3 { // Destination Unreachable
    let icmpCode = data[ipHdrLen + 1]
    let innerIPOffset = ipHdrLen + 8
    guard data.count >= innerIPOffset + 20 else { continue }
    let innerIPHdrLen = Int(data[innerIPOffset] & 0x0F) * 4
    let innerICMPOff = innerIPOffset + innerIPHdrLen
    guard data.count >= innerICMPOff + 8 else { continue }

    let innerID = UInt16(data[innerICMPOff + 4]) << 8 | UInt16(data[innerICMPOff + 5])
    let innerSeq = UInt16(data[innerICMPOff + 6]) << 8 | UInt16(data[innerICMPOff + 7])
    if innerID == identifier && innerSeq == expectedSeq {
        return Response(address: senderIP, latencyMs: machDiffMs(sendTime, recvTime))
    }
}
```

**HopResult change:** Consider adding an optional error field to `HopResult` to distinguish "destination reached" from "destination unreachable (network prohibited)" etc. Not strictly required for the initial implementation.

---

### Priority 2: Rolling Sequence Numbers (quick win)

**What:** Replace `let seq = UInt16(hop)` with a rolling counter that increments across rounds. Range: 33434–65535 (matches traditional traceroute port range, ~32K unique values before wrap).

**Why:** Using hop number as sequence means every round reuses the same sequences. A stale response from round N can be mistaken for a response in round N+1. With continuous probing this is a real risk.

**Where:** Add a `private var nextSequence: UInt16 = 33434` instance property on `ICMPEngine`. Increment per probe. Wrap to 33434 when reaching 65535.

**Code sketch:**
```swift
private var nextSequence: UInt16 = 33434

private func allocateSequence() -> UInt16 {
    let seq = nextSequence
    nextSequence = nextSequence >= 65535 ? 33434 : nextSequence + 1
    return seq
}
```

In `probeRound()`, replace `let seq = UInt16(hop)` with `let seq = allocateSequence()`. The response matching already checks both ID and sequence, so no changes needed there. You'll need to pass the allocated sequence to the response matcher so it knows what to expect.

---

### Priority 3: Non-Blocking Async I/O (medium effort)

**What:** Send all probes for a round first (one per hop, all TTLs), then enter a receive loop collecting responses until timeout. Use non-blocking sockets with `select()` or `poll()`.

**Why:** Sequential blocking means a single slow/unresponsive hop delays the entire round. Async I/O lets all hops be probed in parallel, matching mtr's behavior.

**Where:** Restructure `probeRound()` into two phases:

**Phase 1 — Send all probes:**
```swift
var probes: [(hop: Int, seq: UInt16, sendTime: UInt64)] = []
for hop in 1...maxHops {
    var ttl = Int32(hop)
    setsockopt(sock, IPPROTO_IP, IP_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size))
    let seq = allocateSequence()
    let packet = buildPacket(sequence: seq)
    let sendTime = mach_absolute_time()
    // sendto(...)
    probes.append((hop: hop, seq: seq, sendTime: sendTime))
}
```

**Phase 2 — Collect responses:**
```swift
// Set socket non-blocking
var flags = fcntl(sock, F_GETFL)
fcntl(sock, F_SETFL, flags | O_NONBLOCK)

var results = [Int: HopResult]()  // keyed by hop
let deadline = mach_absolute_time() + timeoutInMachUnits

while results.count < probes.count && mach_absolute_time() < deadline {
    var readSet = fd_set()
    // fd_set setup, select() with remaining timeout
    // recvfrom(), match response to probe by sequence number
    // Store in results dict
}
```

**Considerations:**
- macOS `fd_set` manipulation requires using the `__darwin_fd_set` macros. The Swift wrappers are awkward; consider a small C helper or use `poll()` instead.
- The `TracertHelperProtocol` XPC interface returns `[ProbeResultXPC]` as an array per round, so the caller doesn't need to change — just the internal implementation.
- Socket lifecycle: consider keeping the socket open across rounds (see Priority 5).

---

### Priority 4: UDP Probe Mode (medium effort)

**What:** Add the ability to send UDP probes instead of ICMP Echo Requests. Send raw UDP packets to incrementing destination ports with low TTLs. Listen for ICMP Time Exceeded (intermediate hops) and ICMP Port Unreachable (destination).

**Why:** Networks that rate-limit ICMP often pass UDP freely. This is the single biggest improvement for hop visibility on restrictive networks.

**Where:** Requires a second raw socket (`SOCK_RAW, IPPROTO_UDP`) for sending UDP probes, while keeping the ICMP receive socket for collecting ICMP error responses.

**Implementation outline:**

1. Add a `ProbeProtocol` enum: `.icmp`, `.udp` (TCP can come later).
2. Add a `udpSendSocket` opened as `socket(AF_INET, SOCK_RAW, IPPROTO_UDP)`.
3. Construct UDP packets manually (IP header is handled by the kernel for `SOCK_RAW`):
   - Source port: arbitrary (e.g., 44000)
   - Destination port: `33434 + sequence` (traditional traceroute convention)
   - Payload: 8+ bytes (timestamp for RTT calculation)
4. The ICMP receive socket (`SOCK_RAW, IPPROTO_ICMP`) already receives all ICMP packets. When an ICMP Time Exceeded or Dest Unreachable arrives, the inner packet is UDP instead of ICMP. Parse the inner UDP header to match source/dest ports to the probe.
5. Expose the protocol choice through the XPC protocol. Add a `probeProtocol` parameter to `TracertHelperProtocol.runTraceroute()`.

**Inner packet matching for UDP (in ICMP error responses):**
```
ICMP Error Packet Layout:
  [IP Header][ICMP Header (8 bytes)][Original IP Header][Original UDP Header (8 bytes)]
                                     ^                    ^
                                     innerIPOffset        innerUDPOffset

Original UDP Header:
  [src port (2)][dst port (2)][length (2)][checksum (2)]
```

Match by destination port (which encodes the sequence number): `innerDstPort - 33434 == expectedSeq`.

---

### Priority 5: Persistent Socket Lifecycle (low effort, do with Priority 3)

**What:** Keep sockets open across multiple rounds instead of creating/destroying per `probeRound()` call.

**Why:** Socket creation has overhead and the kernel may reuse file descriptors that confuse response matching.

**Where:** Move socket creation to `init()` and socket closing to `deinit()`. Add an `open()` / `close()` method pair if lifecycle control is needed.

---

### Priority 6: Separate Send/Receive Sockets (do with Priority 4)

**What:** Use one socket for sending probes and a separate `SOCK_RAW, IPPROTO_ICMP` socket for receiving all ICMP responses.

**Why:** When adding UDP probe support, ICMP error responses arrive on the ICMP socket, not the UDP socket. Separate sockets make this clean. mtr uses 6 sockets (3 per address family: ICMP send, UDP send, ICMP receive).

**Where:** Create two sockets in `init()`:
- `icmpSendSocket`: `socket(AF_INET, SOCK_RAW, IPPROTO_ICMP)` — for sending ICMP Echo Requests
- `icmpRecvSocket`: `socket(AF_INET, SOCK_RAW, IPPROTO_ICMP)` — for receiving all ICMP responses
- `udpSendSocket`: `socket(AF_INET, SOCK_RAW, IPPROTO_UDP)` — for sending UDP probes (when UDP mode is added)

The receive socket is always the ICMP one regardless of probe protocol.

---

## Out of Scope (Future)

These are things mtr supports that we can defer:

- **TCP probe mode** — requires `SOCK_STREAM` with `connect()` and writability detection; more complex than UDP
- **SCTP probe mode** — niche
- **IPv6 support** — separate socket family, ICMPv6 types differ
- **MPLS label extraction** — parsing ICMP extension headers (RFC 4950)
- **Linux error queue (`IP_RECVERR`)** — Linux-only, not relevant for macOS
- **Unprivileged DGRAM ICMP sockets** — Linux-only; we have root via XPC helper

---

## Implementation Order

A reasonable sequence, where each step builds on the previous:

1. **Handle ICMP type 3** in `receiveResponse()` — standalone change, no dependencies
2. **Rolling sequence numbers** — standalone change, no dependencies
3. **Persistent sockets** — refactor socket lifecycle to `init()`/`deinit()`
4. **Non-blocking async I/O** — restructure `probeRound()` into send-all/receive-all phases
5. **Separate send/receive sockets** — split into dedicated sockets
6. **UDP probe mode** — add UDP send socket, update inner-packet matching, expose via XPC protocol

Steps 1–2 can be done independently. Steps 3–5 are best done together as a single refactor. Step 6 depends on step 5.
