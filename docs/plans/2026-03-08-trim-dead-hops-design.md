# Trim Trailing Dead Hops Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** When the destination is firewalled, show only one trailing dead hop (MTR-style sentinel) instead of filling the list with dead rows.

**Architecture:** Add `isCurrentlyResponding` computed property to `HopData` that checks recent probes, then update `visibleHops` to keep at most one trailing dead hop.

**Tech Stack:** Swift, SwiftUI, Swift Testing

---

### Task 1: Add `isCurrentlyResponding` to HopData

**Files:**
- Modify: `TraceBar/TraceBar/Models/TracerouteModels.swift:14-43`
- Test: `TraceBar/TraceBarTests/TracerouteModelsTests.swift`

**Step 1: Write failing tests for `isCurrentlyResponding`**

Add to `TracerouteModelsTests.swift` after the existing `HopDataTests` suite:

```swift
// MARK: - isCurrentlyResponding

@Test func isCurrentlyRespondingEmptyProbes() {
    let hop = makeHop()
    #expect(!hop.isCurrentlyResponding)
}

@Test func isCurrentlyRespondingAllTimeouts() {
    var hop = makeHop()
    hop.probes.append(probe(latencyMs: -1))
    hop.probes.append(probe(latencyMs: -1))
    hop.probes.append(probe(latencyMs: -1))
    #expect(!hop.isCurrentlyResponding)
}

@Test func isCurrentlyRespondingOneRecentSuccess() {
    var hop = makeHop()
    hop.probes.append(probe(latencyMs: -1))
    hop.probes.append(probe(latencyMs: -1))
    hop.probes.append(probe(latencyMs: 15))
    #expect(hop.isCurrentlyResponding)
}

@Test func isCurrentlyRespondingOldSuccessNewTimeouts() {
    var hop = makeHop()
    hop.probes.append(probe(latencyMs: 15))
    hop.probes.append(probe(latencyMs: -1))
    hop.probes.append(probe(latencyMs: -1))
    hop.probes.append(probe(latencyMs: -1))
    #expect(!hop.isCurrentlyResponding)
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project TraceBar/TraceBar.xcodeproj -scheme TraceBar -quiet 2>&1 | tail -20`
Expected: FAIL — `isCurrentlyResponding` does not exist

**Step 3: Implement `isCurrentlyResponding` on HopData**

Add to `TracerouteModels.swift` inside `struct HopData`, after `lossPercent`:

```swift
/// Whether any of the last 3 probes got a response.
var isCurrentlyResponding: Bool {
    let recent = probes.elements.suffix(3)
    return recent.contains(where: { !$0.isTimeout })
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project TraceBar/TraceBar.xcodeproj -scheme TraceBar -quiet 2>&1 | tail -20`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add TraceBar/TraceBar/Models/TracerouteModels.swift TraceBar/TraceBarTests/TracerouteModelsTests.swift
git commit -m "feat: add isCurrentlyResponding to HopData for recent-probe detection"
```

---

### Task 2: Update `visibleHops` to show one trailing sentinel

**Files:**
- Modify: `TraceBar/TraceBar/ViewModels/TracerouteViewModel.swift:39-50`

**Step 1: Replace the `visibleHops` computed property**

Replace lines 39-50 in `TracerouteViewModel.swift` with:

```swift
var visibleHops: [HopData] {
    // If we know the destination hop, cap there
    if let dest = destinationHop {
        let capped = hops.filter { $0.hop <= dest }
        if !capped.isEmpty { return capped }
    }
    // Trim trailing dead hops, keeping one as a "waiting for reply" sentinel
    guard let lastResponding = hops.lastIndex(where: { $0.isCurrentlyResponding }) else {
        return Array(hops.prefix(1))
    }
    let sentinel = min(lastResponding + 1, hops.count - 1)
    return Array(hops.prefix(through: sentinel))
}
```

Key changes from the old code:
- Uses `isCurrentlyResponding` (recent probes) instead of `address.isEmpty == false || lossPercent < 100` (lifetime metrics)
- Keeps one dead hop after last responding as sentinel (MTR-style)
- Returns at most one hop when nothing is responding (instead of all hops)

**Step 2: Build and run**

Run: `xcodebuild test -project TraceBar/TraceBar.xcodeproj -scheme TraceBar -quiet 2>&1 | tail -20`
Expected: All tests PASS, no build errors

**Step 3: Commit**

```bash
git add TraceBar/TraceBar/ViewModels/TracerouteViewModel.swift
git commit -m "fix: trim trailing dead hops with one sentinel row for firewalled destinations"
```
