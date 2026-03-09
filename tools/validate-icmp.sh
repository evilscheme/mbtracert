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

log_pass() { echo -e "${GREEN}PASS${NC}: $1"; PASS=$((PASS + 1)); }
log_fail() { echo -e "${RED}FAIL${NC}: $1"; FAIL=$((FAIL + 1)); }
log_warn() { echo -e "${YELLOW}WARN${NC}: $1"; WARN=$((WARN + 1)); }
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

    # Run mtr (no sudo needed)
    log_info "Running mtr ($ROUNDS rounds)..."
    mtr "$target" -w -c "$ROUNDS" -j -i 1 --no-dns > "$mtr_out" 2>&1 || {
        log_warn "mtr failed for $target"
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
        mtr_last_hub=$(jq -r '.report.hubs[-1].host' "$mtr_out")
        if [[ "$mtr_last_hub" == "$target" ]]; then
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
                match_count=$((match_count + 1))
            else
                mismatches=$((mismatches + 1))
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
