# ICMP Validation Tool Design

## Goal

Build a CLI tool + wrapper script that validates our ICMPEngine's real-world behavior by comparing probe results against mtr. Designed for Claude to run after code changes to catch regressions.

## Architecture

### Tool 1: `icmp-probe` (Swift CLI, `tools/icmp-probe.swift`)

Compiles against the real `ICMPEngine.swift` — no code duplication. Runs N probe rounds against a target host and emits one JSON Lines object per round to stdout.

**Build:**
```bash
cd tools && swiftc -O -o icmp-probe icmp-probe.swift ../TraceBar/TraceBar/Services/ICMPEngine.swift
```

**Usage:**
```
./icmp-probe <host> [--rounds 3] [--max-hops 30] [--interval 1.0]
```

No sudo required (uses SOCK_DGRAM + IPPROTO_ICMP).

**Output format (JSON Lines, one object per round):**
```json
{
  "host": "8.8.8.8",
  "round": 1,
  "timestamp": "2026-03-09T12:00:00.000Z",
  "destination_hop": 9,
  "destination_reached": true,
  "hops": [
    {"hop": 1, "address": "192.168.1.1", "latency_ms": 1.2, "icmp_type": 11, "icmp_code": 0},
    {"hop": 2, "address": "", "latency_ms": -1, "icmp_type": null, "icmp_code": null},
    {"hop": 9, "address": "8.8.8.8", "latency_ms": 12.4, "icmp_type": 0, "icmp_code": 0}
  ]
}
```

- Timeouts: `latency_ms: -1`, null ICMP fields
- `destination_reached`: true if Echo Reply (type 0) or Dest Unreachable from target IP (type 3)
- `destination_hop`: hop number of destination, or 0 if not reached

### ICMPEngine change

Add `icmpType` and `icmpCode` fields to `HopResult` so the probe tool can report ICMP response types. This is a small additive change — `probeRound()` already has this info in `ParsedICMPResponse`, it just isn't propagated to the return value.

Timeouts get `icmpType: nil, icmpCode: nil` (these are optional fields).

### Tool 2: `validate-icmp.sh` (Bash wrapper, `tools/validate-icmp.sh`)

Orchestrates validation by running both `icmp-probe` and `mtr` against a set of targets, then comparing results.

**Default targets:**
- `8.8.8.8` — reliable, well-peered
- `1.1.1.1` — reliable, different path
- `cloudflare.com` — DNS resolution + trace
- A host known to firewall ICMP (TBD at implementation time)

**Comparison checks:**
1. **Hop count** — destination hop matches mtr within ±1
2. **Destination reached** — both agree on whether destination was reached
3. **Hop addresses** — IP addresses match for most hops (tolerance for ECMP load balancing)
4. **No duplicates** — no repeated hop entries in our output
5. **No post-destination hops** — no entries after destination hop
6. **Firewalled hosts** — correct termination behavior

**Output:** Pass/fail per target with details on mismatches.

## Known issues this catches

- Duplicate hop entries
- Empty hop entries past the destination
- Incorrect behavior with firewalled hosts
- Destination not properly identified
- Regressions in packet construction or parsing

## Files to create/modify

| File | Action |
|------|--------|
| `TraceBar/TraceBar/Services/ICMPEngine.swift` | Add `icmpType`/`icmpCode` to `HopResult` |
| `tools/icmp-probe.swift` | New: Swift CLI probe tool |
| `tools/validate-icmp.sh` | New: Bash comparison wrapper |
