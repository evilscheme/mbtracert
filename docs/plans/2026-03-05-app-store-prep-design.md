# App Store Submission Prep — Design

**Date:** 2026-03-05
**Status:** Approved
**Approach:** Minimum required changes (Approach A)

## Context

TraceBar is a macOS menubar app for continuous graphical traceroute monitoring. The codebase is ~90% ready for App Store submission. This design covers the remaining gaps.

## Scope

### 1. PrivacyInfo.xcprivacy

Create privacy manifest at `TraceBar/TraceBar/PrivacyInfo.xcprivacy`:

- `NSPrivacyTracking`: false
- `NSPrivacyTrackingDomains`: empty
- `NSPrivacyCollectedDataTypes`: empty (all data stays on-device)
- `NSPrivacyAccessedAPITypes`: UserDefaults (reason `CA92.1` — app's own settings via AppStorage)

Add to Xcode project resources.

### 2. App Store Metadata Drafts

Create `docs/app-store-metadata.md` with copy-pasteable text:

- **App Name:** TraceBar
- **Subtitle:** Live Traceroute in Your Menubar
- **Description:** ~170 words covering features, audience, privacy
- **Keywords:** traceroute,mtr,network,ping,latency,diagnostic,menubar,monitor,hops,icmp
- **Category:** Utilities
- **Price:** Free
- **Age Rating:** 4+
- **Support URL:** https://evilscheme.github.io/tracebar/support
- **Privacy Policy URL:** https://evilscheme.github.io/tracebar/privacy
- **Contact:** tracebar@evilscheme.org

### 3. GitHub Pages Site

Create `docs/` folder with static HTML (no JS, no frameworks):

- `docs/index.html` — Landing page (app name, tagline, future App Store link)
- `docs/privacy.html` — Privacy policy (no collection, no tracking, all local)
- `docs/support.html` — Support page with FAQ and contact email

GitHub Pages serves from `docs/` on `main`.

## Out of Scope

- Accessibility audit (v1.1)
- In-app About section (v1.1)
- Localization (v1.1)
- Screenshots/preview video (manual step in App Store Connect)
