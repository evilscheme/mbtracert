# Rename: MenubarTracert → TraceBar

## Summary

Rename the app from "MenubarTracert" to "TraceBar" across all code, configuration, build scripts, CI, and documentation.

## Changes

### Directories (git mv)
- `MenubarTracert/MenubarTracert/` → `TraceBar/TraceBar/`
- `MenubarTracert/MenubarTracert.xcodeproj/` → `TraceBar/TraceBar.xcodeproj/`
- Top-level `MenubarTracert/` → `TraceBar/`

### Files (git mv)
- `MenubarTracertApp.swift` → `TraceBarApp.swift`
- `MenubarTracert.entitlements` → `TraceBar.entitlements`

### Xcode Project (project.pbxproj)
- Target name: `MenubarTracert` → `TraceBar`
- Product name: `MenubarTracert` → `TraceBar`
- Product reference: `MenubarTracert.app` → `TraceBar.app`
- Entitlements path: `MenubarTracert/MenubarTracert.entitlements` → `TraceBar/TraceBar.entitlements`
- Bundle ID: `org.evilscheme.MenubarTracert` → `org.evilscheme.TraceBar`

### Swift Code
- `MenubarTracertApp` struct → `TraceBarApp`
- Dispatch queue label: `org.evilscheme.MenubarTracert.probe` → `org.evilscheme.TraceBar.probe`

### Build Scripts (create-dmg.sh)
- All references to `MenubarTracert` in paths, scheme name, archive name, DMG name, volume name

### CI Workflows
- `build.yml`: project path and scheme
- `release.yml`: artifact name

### Documentation
- `CLAUDE.md`: all references
- `README.md`: title and references

### Excluded
- Historical plan docs in `docs/plans/` — left as-is (historical record)
- `tools/` comments — left as-is

## GitHub Repo Rename (Manual)
Settings → General → Repository name. GitHub auto-redirects old URLs. Update local remote afterward:
```
git remote set-url origin git@github.com:evilscheme/tracebar.git
```

## Verification
- `xcodebuild -project TraceBar/TraceBar.xcodeproj -scheme TraceBar build` must succeed
