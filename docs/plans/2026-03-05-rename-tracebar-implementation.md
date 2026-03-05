# Rename MenubarTracert → TraceBar Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rename the app from "MenubarTracert" to "TraceBar" everywhere — directories, Xcode project, code, scripts, CI, and docs.

**Architecture:** Bulk rename via `git mv` for directories/files, then find-replace in all config and source files. No code logic changes.

**Tech Stack:** git, sed (for pbxproj bulk replace), xcodebuild (verification)

---

### Task 1: Rename directories and files on disk

**Files:**
- Rename: `MenubarTracert/MenubarTracert/MenubarTracertApp.swift` → `MenubarTracert/MenubarTracert/TraceBarApp.swift`
- Rename: `MenubarTracert/MenubarTracert/MenubarTracert.entitlements` → `MenubarTracert/MenubarTracert/TraceBar.entitlements`
- Rename: `MenubarTracert/MenubarTracert/` → `MenubarTracert/TraceBar/`
- Rename: `MenubarTracert/MenubarTracert.xcodeproj/` → `MenubarTracert/TraceBar.xcodeproj/`
- Rename: `MenubarTracert/` → `TraceBar/`

**Step 1: Rename files inside the app target directory first**

```bash
cd /Users/bryan/conductor/workspaces/mbtracert/quebec-v1
git mv MenubarTracert/MenubarTracert/MenubarTracertApp.swift MenubarTracert/MenubarTracert/TraceBarApp.swift
git mv MenubarTracert/MenubarTracert/MenubarTracert.entitlements MenubarTracert/MenubarTracert/TraceBar.entitlements
```

**Step 2: Rename the inner directory (app target)**

```bash
git mv MenubarTracert/MenubarTracert MenubarTracert/TraceBar
```

**Step 3: Rename the xcodeproj**

```bash
git mv MenubarTracert/MenubarTracert.xcodeproj MenubarTracert/TraceBar.xcodeproj
```

**Step 4: Rename the top-level project directory**

```bash
git mv MenubarTracert TraceBar
```

**Step 5: Verify the new structure**

```bash
find TraceBar -maxdepth 3 -type d
ls TraceBar/TraceBar/TraceBarApp.swift
ls TraceBar/TraceBar/TraceBar.entitlements
ls TraceBar/TraceBar.xcodeproj/project.pbxproj
```

Expected: All paths exist under `TraceBar/`.

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor: rename directories and files from MenubarTracert to TraceBar"
```

---

### Task 2: Update Xcode project.pbxproj

**Files:**
- Modify: `TraceBar/TraceBar.xcodeproj/project.pbxproj`

The pbxproj has ~20 references to `MenubarTracert`. A global replace is safe here since every occurrence should change.

**Step 1: Replace all occurrences in project.pbxproj**

Replace every instance of `MenubarTracert` with `TraceBar` in `TraceBar/TraceBar.xcodeproj/project.pbxproj`. This covers:
- Target name
- Product name and reference (`MenubarTracert.app` → `TraceBar.app`)
- Entitlements path (`MenubarTracert/MenubarTracert.entitlements` → `TraceBar/TraceBar.entitlements`)
- Bundle identifier (`org.evilscheme.MenubarTracert` → `org.evilscheme.TraceBar`)
- Source folder path
- Build configuration list names

Use replace_all since every occurrence should change.

**Step 2: Verify the pbxproj has no remaining old references**

```bash
grep -c "MenubarTracert" TraceBar/TraceBar.xcodeproj/project.pbxproj
```

Expected: `0`

**Step 3: Commit**

```bash
git add TraceBar/TraceBar.xcodeproj/project.pbxproj
git commit -m "refactor: update Xcode project references to TraceBar"
```

---

### Task 3: Update Swift source code

**Files:**
- Modify: `TraceBar/TraceBar/TraceBarApp.swift` (struct name, line 4)
- Modify: `TraceBar/TraceBar/ViewModels/TracerouteViewModel.swift` (dispatch queue label, line 42)

**Step 1: Rename the app struct**

In `TraceBar/TraceBar/TraceBarApp.swift`, change:
```swift
struct MenubarTracertApp: App {
```
to:
```swift
struct TraceBarApp: App {
```

**Step 2: Update dispatch queue label**

In `TraceBar/TraceBar/ViewModels/TracerouteViewModel.swift`, change:
```swift
private let probeQueue = DispatchQueue(label: "org.evilscheme.MenubarTracert.probe")
```
to:
```swift
private let probeQueue = DispatchQueue(label: "org.evilscheme.TraceBar.probe")
```

**Step 3: Commit**

```bash
git add TraceBar/TraceBar/TraceBarApp.swift TraceBar/TraceBar/ViewModels/TracerouteViewModel.swift
git commit -m "refactor: rename Swift struct and queue label to TraceBar"
```

---

### Task 4: Update build script (create-dmg.sh)

**Files:**
- Modify: `scripts/create-dmg.sh`

**Step 1: Replace all MenubarTracert references**

Replace every `MenubarTracert` with `TraceBar` in `scripts/create-dmg.sh`. This covers lines 6, 7, 9, 83, 94, 119, 132, 136, 138.

Use replace_all since every occurrence should change.

**Step 2: Verify no remaining old references**

```bash
grep -c "MenubarTracert" scripts/create-dmg.sh
```

Expected: `0`

**Step 3: Commit**

```bash
git add scripts/create-dmg.sh
git commit -m "refactor: update create-dmg.sh references to TraceBar"
```

---

### Task 5: Update CI workflows

**Files:**
- Modify: `.github/workflows/build.yml` (lines 24-25)
- Modify: `.github/workflows/release.yml` (line 59)

**Step 1: Update build.yml**

Change:
```yaml
            -project MenubarTracert/MenubarTracert.xcodeproj \
            -scheme MenubarTracert \
```
to:
```yaml
            -project TraceBar/TraceBar.xcodeproj \
            -scheme TraceBar \
```

**Step 2: Update release.yml**

Change:
```yaml
          name: MenubarTracert-DMG
```
to:
```yaml
          name: TraceBar-DMG
```

**Step 3: Commit**

```bash
git add .github/workflows/build.yml .github/workflows/release.yml
git commit -m "refactor: update CI workflows for TraceBar rename"
```

---

### Task 6: Update documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md`

**Step 1: Update CLAUDE.md**

Replace all `MenubarTracert` with `TraceBar` throughout the file. This covers:
- Project overview description
- Bundle ID
- Architecture diagram
- Build & Run instructions
- Log checking commands

**Step 2: Update README.md**

Replace all `MenubarTracert` with `TraceBar` throughout the file. This covers:
- Title (`# TraceBar`)
- Build instructions
- Architecture diagram

**Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: update CLAUDE.md and README.md for TraceBar rename"
```

---

### Task 7: Verify build

**Step 1: Build the project**

```bash
cd /Users/bryan/conductor/workspaces/mbtracert/quebec-v1
xcodebuild build \
    -project TraceBar/TraceBar.xcodeproj \
    -scheme TraceBar \
    -configuration Debug \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`

**Step 2: If build fails, fix issues and recommit**

Any failures are likely path references we missed. Search for remaining `MenubarTracert` strings:

```bash
grep -r "MenubarTracert" --include='*.swift' --include='*.yml' --include='*.sh' --include='*.md' --include='*.pbxproj' --include='*.entitlements' .
```

Fix any findings, commit, and re-verify.
