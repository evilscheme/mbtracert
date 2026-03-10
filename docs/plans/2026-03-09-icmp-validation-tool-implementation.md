# ICMP Validation Tool Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a machine-readable CLI probe tool and comparison script to validate ICMPEngine against mtr.

**Architecture:** Swift CLI (`icmp-probe`) compiles against real `ICMPEngine.swift`, emits JSON Lines. Bash wrapper (`validate-icmp.sh`) runs both tools and diffs results. `HopResult` gains optional ICMP type/code fields to expose response metadata.

**Tech Stack:** Swift (CLI, no SwiftUI), Bash, jq (for JSON comparison)

---

### Task 1: Add ICMP type/code to HopResult

**Files:**
- Modify: `TraceBar/TraceBar/Services/ICMPEngine.swift:4-8` (HopResult struct)
- Modify: `TraceBar/TraceBar/Services/ICMPEngine.swift:59-67` (ProbeState)
- Modify: `TraceBar/TraceBar/Services/ICMPEngine.swift:149-156` (receiver stores type/code)
- Modify: `TraceBar/TraceBar/Services/ICMPEngine.swift:210-217` (results builder)

**Step 1: Add optional fields to HopResult**

Change `HopResult` at line 4:
```swift
struct HopResult: Sendable {
    let hop: Int
    let address: String
    let latencyMs: Double
    let icmpType: UInt8?
    let icmpCode: UInt8?
}
```

**Step 2: Update ProbeState responses tuple to carry type/code**

Change the `responses` dict type in `ProbeState` (line 62):
```swift
var responses: [Int: (address: String, latencyMs: Double, icmpType: UInt8, icmpCode: UInt8)] = [:]
```

**Step 3: Store type/code in receiver thread**

At line 152, change:
```swift
state.responses[hop] = (senderIP, latencyMs)
```
to:
```swift
state.responses[hop] = (senderIP, latencyMs, parsed.icmpType, parsed.icmpCode)
```

**Step 4: Propagate in results builder**

At lines 210-216, change the map to:
```swift
let hops = (1...hopRange).map { hop in
    if let resp = finalResponses[hop] {
        return HopResult(hop: hop, address: resp.address, latencyMs: resp.latencyMs,
                         icmpType: resp.icmpType, icmpCode: resp.icmpCode)
    } else {
        return HopResult(hop: hop, address: "", latencyMs: -1,
                         icmpType: nil, icmpCode: nil)
    }
}
```

**Step 5: Build and run tests**

Run:
```bash
xcodebuild test -project TraceBar/TraceBar.xcodeproj -scheme TraceBar -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All existing tests pass (HopResult is not constructed in tests; ICMPParsingTests use `parseResponse` directly).

**Step 6: Commit**

```bash
git add TraceBar/TraceBar/Services/ICMPEngine.swift
git commit -m "Add icmpType/icmpCode to HopResult for diagnostic visibility"
```

---

### Task 2: Create icmp-probe CLI tool

**Files:**
- Create: `tools/icmp-probe.swift`

**Step 1: Write the CLI tool**

```swift
/// icmp-probe: machine-readable ICMP probe tool
/// Compiles against the real ICMPEngine.swift — no code duplication.
///
/// Build:
///   cd tools && swiftc -O -o icmp-probe icmp-probe.swift \
///     ../TraceBar/TraceBar/Services/ICMPEngine.swift
///
/// Run:
///   ./icmp-probe <host> [--rounds 3] [--max-hops 30] [--interval 1.0]

import Foundation
import Darwin

// MARK: - Argument Parsing

struct Config {
    var host: String = ""
    var rounds: Int = 3
    var maxHops: Int = 30
    var interval: Double = 1.0
}

func parseArgs() -> Config? {
    let args = CommandLine.arguments
    guard args.count >= 2 else { return nil }

    var config = Config()
    config.host = args[1]

    var i = 2
    while i < args.count {
        switch args[i] {
        case "--rounds":
            i += 1
            guard i < args.count, let v = Int(args[i]) else { return nil }
            config.rounds = v
        case "--max-hops":
            i += 1
            guard i < args.count, let v = Int(args[i]) else { return nil }
            config.maxHops = v
        case "--interval":
            i += 1
            guard i < args.count, let v = Double(args[i]) else { return nil }
            config.interval = v
        default:
            return nil
        }
        i += 1
    }
    return config
}

// MARK: - JSON Output

func jsonString(_ s: String) -> String {
    "\"\(s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
}

func hopToJSON(_ hop: HopResult) -> String {
    let typeStr = hop.icmpType.map { "\($0)" } ?? "null"
    let codeStr = hop.icmpCode.map { "\($0)" } ?? "null"
    return "{\"hop\":\(hop.hop),\"address\":\(jsonString(hop.address)),\"latency_ms\":\(String(format: "%.3f", hop.latencyMs)),\"icmp_type\":\(typeStr),\"icmp_code\":\(codeStr)}"
}

func roundToJSON(host: String, round: Int, result: ProbeRoundResult) -> String {
    let ts = ISO8601DateFormatter().string(from: Date())
    let hopsJSON = result.hops.map { hopToJSON($0) }.joined(separator: ",")
    let destReached = result.destinationHop > 0
    return "{\"host\":\(jsonString(host)),\"round\":\(round),\"timestamp\":\(jsonString(ts)),\"destination_hop\":\(result.destinationHop),\"destination_reached\":\(destReached),\"hops\":[\(hopsJSON)]}"
}

// MARK: - Entry Point

@main struct ICMPProbe {
    static func main() {
        guard let config = parseArgs() else {
            let name = CommandLine.arguments[0]
            fputs("Usage: \(name) <host> [--rounds 3] [--max-hops 30] [--interval 1.0]\n", stderr)
            Foundation.exit(1)
        }

        let engine = ICMPEngine()

        for round in 1...config.rounds {
            let result = engine.probeRound(host: config.host, maxHops: config.maxHops)
            print(roundToJSON(host: config.host, round: round, result: result))
            fflush(stdout)
            if round < config.rounds {
                usleep(UInt32(config.interval * 1_000_000))
            }
        }
    }
}
```

**Step 2: Build the tool**

Run:
```bash
cd /Users/bryan/code/tracebar/tools && swiftc -O -o icmp-probe icmp-probe.swift ../TraceBar/TraceBar/Services/ICMPEngine.swift
```
Expected: Compiles with no errors.

**Step 3: Smoke test against 8.8.8.8**

Run:
```bash
cd /Users/bryan/code/tracebar/tools && ./icmp-probe 8.8.8.8 --rounds 1 2>&1
```
Expected: One JSON line with `destination_reached: true`, hops array with addresses, positive latencies for responding hops.

**Step 4: Validate JSON is well-formed**

Run:
```bash
cd /Users/bryan/code/tracebar/tools && ./icmp-probe 8.8.8.8 --rounds 1 | python3 -m json.tool
```
Expected: Pretty-printed valid JSON.

**Step 5: Commit**

```bash
git add tools/icmp-probe.swift
git commit -m "Add icmp-probe CLI tool for machine-readable ICMP validation"
```

---

### Task 3: Create validate-icmp.sh wrapper script

**Files:**
- Create: `tools/validate-icmp.sh`

This script runs `icmp-probe` and `mtr` against a set of targets, compares results, and reports pass/fail. It requires `jq` and `mtr` (with sudo for mtr).

**Step 1: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROBE="$SCRIPT_DIR/icmp-probe"
ROUNDS=3
MAX_HOPS=30
INTERVAL=1.0
TARGETS=("8.8.8.8" "1.1.1.1" "cloudflare.com")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

log_pass() { echo -e "${GREEN}PASS${NC}: $1"; ((PASS++)); }
log_fail() { echo -e "${RED}FAIL${NC}: $1"; ((FAIL++)); }
log_warn() { echo -e "${YELLOW}WARN${NC}: $1"; ((WARN++)); }
log_info() { echo -e "INFO: $1"; }

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required"; exit 1; }
command -v mtr >/dev/null 2>&1 || { echo "Error: mtr is required"; exit 1; }

# Build icmp-probe if needed
if [[ ! -x "$PROBE" ]] || [[ "$SCRIPT_DIR/icmp-probe.swift" -nt "$PROBE" ]] || \
   [[ "$SCRIPT_DIR/../TraceBar/TraceBar/Services/ICMPEngine.swift" -nt "$PROBE" ]]; then
    log_info "Building icmp-probe..."
    (cd "$SCRIPT_DIR" && swiftc -O -o icmp-probe icmp-probe.swift \
        ../TraceBar/TraceBar/Services/ICMPEngine.swift) || {
        echo "Error: Failed to build icmp-probe"; exit 1;
    }
fi

# Allow overriding targets via args
if [[ $# -gt 0 ]]; then
    TARGETS=("$@")
fi

TMPDIR_BASE=$(mktemp -d)
trap "rm -rf $TMPDIR_BASE" EXIT

for target in "${TARGETS[@]}"; do
    echo ""
    echo "========================================="
    echo "Target: $target"
    echo "========================================="

    probe_out="$TMPDIR_BASE/${target//\//_}_probe.jsonl"
    mtr_out="$TMPDIR_BASE/${target//\//_}_mtr.json"

    # Run icmp-probe
    log_info "Running icmp-probe ($ROUNDS rounds)..."
    "$PROBE" "$target" --rounds "$ROUNDS" --max-hops "$MAX_HOPS" --interval "$INTERVAL" > "$probe_out" 2>&1 || true

    # Run mtr (needs sudo)
    log_info "Running mtr ($ROUNDS rounds)..."
    sudo mtr "$target" -w -c "$ROUNDS" -j -i 1 --no-dns > "$mtr_out" 2>&1 || {
        log_warn "mtr failed for $target (may need sudo)"
        continue
    }

    # Use last round from icmp-probe for comparison
    last_round=$(tail -1 "$probe_out")

    # --- Check 1: Destination reached ---
    our_reached=$(echo "$last_round" | jq '.destination_reached')
    our_dest_hop=$(echo "$last_round" | jq '.destination_hop')
    mtr_hub_count=$(jq '.report.hubs | length' "$mtr_out")

    if [[ "$our_reached" == "true" ]]; then
        log_pass "$target: destination reached (hop $our_dest_hop)"
    else
        # Check if mtr also failed to reach
        mtr_last_hub=$(jq '.report.hubs[-1].host' "$mtr_out")
        if [[ "$mtr_last_hub" == "\"$target\"" ]]; then
            log_fail "$target: mtr reached destination but we did not"
        else
            log_warn "$target: neither tool reached destination"
        fi
    fi

    # --- Check 2: Hop count comparison ---
    our_hop_count=$(echo "$last_round" | jq '.hops | length')
    if [[ "$our_reached" == "true" ]]; then
        diff=$((our_dest_hop - mtr_hub_count))
        abs_diff=${diff#-}
        if [[ "$abs_diff" -le 1 ]]; then
            log_pass "$target: hop count matches (ours=$our_dest_hop, mtr=$mtr_hub_count)"
        else
            log_fail "$target: hop count mismatch (ours=$our_dest_hop, mtr=$mtr_hub_count)"
        fi
    fi

    # --- Check 3: No duplicate addresses ---
    dup_count=$(echo "$last_round" | jq '[.hops[] | select(.address != "") | .address] | group_by(.) | map(select(length > 1)) | length')
    if [[ "$dup_count" -eq 0 ]]; then
        log_pass "$target: no duplicate hop addresses"
    else
        dups=$(echo "$last_round" | jq '[.hops[] | select(.address != "") | .address] | group_by(.) | map(select(length > 1)) | map(.[0])')
        log_fail "$target: duplicate hop addresses found: $dups"
    fi

    # --- Check 4: No hops past destination ---
    if [[ "$our_reached" == "true" ]]; then
        post_dest=$(echo "$last_round" | jq --argjson dh "$our_dest_hop" '[.hops[] | select(.hop > $dh)] | length')
        if [[ "$post_dest" -eq 0 ]]; then
            log_pass "$target: no hops past destination"
        else
            log_fail "$target: $post_dest hops found past destination (hop $our_dest_hop)"
        fi
    fi

    # --- Check 5: Hop address comparison with mtr ---
    if [[ "$our_reached" == "true" ]]; then
        mismatches=0
        match_count=0
        max_compare=$((our_dest_hop < mtr_hub_count ? our_dest_hop : mtr_hub_count))
        for ((h=1; h<=max_compare; h++)); do
            our_addr=$(echo "$last_round" | jq -r --argjson h "$h" '.hops[] | select(.hop == $h) | .address')
            mtr_addr=$(jq -r --argjson h "$((h-1))" '.report.hubs[$h].host' "$mtr_out")
            if [[ -z "$our_addr" || "$our_addr" == "" ]]; then
                continue  # timeout in our trace
            fi
            if [[ -z "$mtr_addr" || "$mtr_addr" == "???" ]]; then
                continue  # timeout in mtr
            fi
            if [[ "$our_addr" == "$mtr_addr" ]]; then
                ((match_count++))
            else
                ((mismatches++))
                log_info "  Hop $h address differs: ours=$our_addr mtr=$mtr_addr"
            fi
        done
        total=$((match_count + mismatches))
        if [[ "$total" -gt 0 ]]; then
            match_pct=$((match_count * 100 / total))
            if [[ "$match_pct" -ge 70 ]]; then
                log_pass "$target: hop addresses match ($match_count/$total, ${match_pct}%)"
            else
                log_fail "$target: hop addresses diverge ($match_count/$total, ${match_pct}%)"
            fi
        fi
    fi

    # --- Check 6: Consistency across rounds ---
    if [[ "$ROUNDS" -gt 1 ]]; then
        dest_hops=$(jq -s '[.[] | .destination_hop]' "$probe_out")
        unique_dests=$(echo "$dest_hops" | jq 'unique | length')
        if [[ "$unique_dests" -le 2 ]]; then
            log_pass "$target: destination hop stable across rounds ($dest_hops)"
        else
            log_fail "$target: destination hop unstable across rounds ($dest_hops)"
        fi
    fi
done

# Summary
echo ""
echo "========================================="
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${WARN} warnings${NC}"
echo "========================================="

[[ "$FAIL" -eq 0 ]]
```

**Step 2: Make executable**

Run:
```bash
chmod +x /Users/bryan/code/tracebar/tools/validate-icmp.sh
```

**Step 3: Commit**

```bash
git add tools/validate-icmp.sh
git commit -m "Add validate-icmp.sh wrapper for mtr comparison testing"
```

---

### Task 4: End-to-end validation run

**Step 1: Run the validation script**

Run:
```bash
cd /Users/bryan/code/tracebar && sudo tools/validate-icmp.sh
```

Note: `sudo` is needed for mtr. Our icmp-probe runs without sudo internally.

**Step 2: Review results and fix any issues**

If any FAIL results, investigate and fix. Common issues:
- Duplicate addresses → check receiver deduplication logic
- Post-destination hops → check `destHop` tracking in `probeRound()`
- Hop count mismatch → check early termination logic

**Step 3: Final commit if fixes were needed**

```bash
git add -A && git commit -m "Fix issues found during ICMP validation"
```
