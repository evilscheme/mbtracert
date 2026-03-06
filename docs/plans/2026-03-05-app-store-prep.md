# App Store Submission Prep — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prepare TraceBar for Mac App Store submission by adding the required privacy manifest, drafting App Store metadata, and scaffolding a GitHub Pages site for privacy policy and support.

**Architecture:** All changes are additive — no existing code is modified. PrivacyInfo.xcprivacy is auto-included by Xcode's file system synchronization (PBXFileSystemSynchronizedRootGroup). GitHub Pages files live in `docs/` and are served from the `main` branch.

**Tech Stack:** Xcode plist (XML), Markdown, HTML+CSS (no JS)

---

### Task 1: Create PrivacyInfo.xcprivacy

**Files:**
- Create: `TraceBar/TraceBar/PrivacyInfo.xcprivacy`

**Step 1: Create the privacy manifest**

Write `TraceBar/TraceBar/PrivacyInfo.xcprivacy` with this exact content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

**Why these values:**
- `NSPrivacyTracking: false` — no tracking of any kind
- `NSPrivacyCollectedDataTypes: empty` — all diagnostic data (IPs, latencies) stays on-device
- `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` — the app uses `@AppStorage` for 8+ user preferences (target host, color scheme, intervals, etc.)

**Step 2: Verify Xcode picks it up**

```bash
cd TraceBar && xcodebuild -project TraceBar.xcodeproj -scheme TraceBar -configuration Debug build 2>&1 | tail -5
```

Expected: Build succeeds. The file is auto-included because the project uses `PBXFileSystemSynchronizedRootGroup`.

**Step 3: Commit**

```bash
git add TraceBar/TraceBar/PrivacyInfo.xcprivacy
git commit -m "feat: add privacy manifest for App Store submission"
```

---

### Task 2: Draft App Store Metadata

**Files:**
- Create: `docs/app-store-metadata.md`

**Step 1: Write the metadata file**

Create `docs/app-store-metadata.md` with all fields needed for App Store Connect. The key fields:

- **App Name:** TraceBar
- **Subtitle:** Live Traceroute in Your Menubar
- **Description:** ~4000 chars max, write ~170 words covering: what it does, who it's for, key features (continuous monitoring, heatmaps, sparklines, 13 color schemes, configurable intervals), privacy stance, no root required
- **Promotional Text:** Short hook that can be updated without a new app version
- **Keywords:** `traceroute,mtr,network,ping,latency,diagnostic,menubar,monitor,hops,icmp` (100 char max, comma-separated, no spaces)
- **What's New:** "Initial release."
- **Category:** Utilities
- **Secondary Category:** Developer Tools
- **Price:** Free
- **Age Rating:** 4+
- **Copyright:** 2025-2026 Bryan Burns
- **Support URL:** https://evilscheme.github.io/tracebar/support
- **Privacy Policy URL:** https://evilscheme.github.io/tracebar/privacy
- **Contact:** tracebar@evilscheme.org

**Step 2: Commit**

```bash
git add docs/app-store-metadata.md
git commit -m "docs: draft App Store metadata for submission"
```

---

### Task 3: Create GitHub Pages Landing Page

**Files:**
- Create: `docs/index.html`

**Step 1: Write the landing page**

Create `docs/index.html` — a clean, minimal static HTML page with:

- App name "TraceBar" as heading
- Tagline: "Continuous graphical traceroute monitoring in your macOS menubar"
- Brief feature list (3-4 bullets)
- Placeholder for App Store badge/link (comment: "<!-- App Store link goes here after approval -->")
- Links to Privacy Policy and Support pages
- Footer with copyright

Style: Clean system font stack (`-apple-system, BlinkMacSystemFont, sans-serif`), light/dark mode via `prefers-color-scheme`, centered layout, no external dependencies.

**Step 2: Commit**

```bash
git add docs/index.html
git commit -m "docs: add GitHub Pages landing page"
```

---

### Task 4: Create Privacy Policy Page

**Files:**
- Create: `docs/privacy.html`

**Step 1: Write the privacy policy**

Create `docs/privacy.html` — static HTML page with a clear, honest privacy policy:

Key points to cover:
- **No data collection** — TraceBar does not collect, store, or transmit personal data
- **No analytics or tracking** — no third-party SDKs, no telemetry
- **Local only** — all network diagnostic data (IP addresses, latency measurements) exists only in memory and is discarded when the app closes
- **User preferences** — stored locally via macOS UserDefaults, never transmitted
- **Network access** — the app sends ICMP packets to the user-specified target host for traceroute functionality; no other network communication occurs
- **No accounts** — no sign-up, login, or user identification
- **Contact:** tracebar@evilscheme.org
- **Effective date:** 2026-03-05

Same styling as index.html (share CSS via inline `<style>` block or identical styles).

**Step 2: Commit**

```bash
git add docs/privacy.html
git commit -m "docs: add privacy policy page for App Store"
```

---

### Task 5: Create Support Page

**Files:**
- Create: `docs/support.html`

**Step 1: Write the support page**

Create `docs/support.html` — static HTML page with:

- **Contact:** tracebar@evilscheme.org
- **FAQ section** with 4-5 common questions:
  1. "How do I change the target host?" → Open Settings (click menubar icon → gear icon or Cmd+,)
  2. "What do the colors mean?" → Colors represent latency. Green/cool = low latency, red/warm = high. Choose from 13 color schemes in Settings.
  3. "Why do some hops show asterisks?" → Some routers don't respond to ICMP packets. This is normal.
  4. "Does TraceBar need root/admin access?" → No. It uses unprivileged ICMP sockets that work without elevated permissions.
  5. "What macOS versions are supported?" → macOS 14.6 (Sonoma) and later.
- **System Requirements:** macOS 14.6+, network connection

Same styling as other pages.

**Step 2: Commit**

```bash
git add docs/support.html
git commit -m "docs: add support page for App Store"
```

---

### Task 6: Final Verification

**Step 1: Verify all files exist**

```bash
ls -la TraceBar/TraceBar/PrivacyInfo.xcprivacy
ls -la docs/app-store-metadata.md
ls -la docs/index.html docs/privacy.html docs/support.html
```

**Step 2: Build the project**

```bash
cd TraceBar && xcodebuild -project TraceBar.xcodeproj -scheme TraceBar -configuration Release build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

**Step 3: Run tests**

```bash
cd TraceBar && xcodebuild -project TraceBar.xcodeproj -scheme TraceBar test 2>&1 | tail -20
```

Expected: All 81 tests pass.

**Step 4: Verify privacy manifest is in the built product**

```bash
find ~/Library/Developer/Xcode/DerivedData/TraceBar-*/Build/Products/Release/TraceBar.app -name "PrivacyInfo*" 2>/dev/null || echo "Check DerivedData manually"
```

Expected: `PrivacyInfo.xcprivacy` appears in the app bundle.
