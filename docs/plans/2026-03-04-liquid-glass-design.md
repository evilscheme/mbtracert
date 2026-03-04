# Liquid Glass Adoption

**Date:** 2026-03-04
**Scope:** TraceroutePanel.swift only

## Context

Apple's macOS 26 introduces Liquid Glass, a dynamic material for controls and navigation. Standard SwiftUI components (MenuBarExtra, TabView, Form, Toggle, Slider, Picker) auto-adopt when built with the latest SDK. Our custom panel content needs targeted changes.

## Changes

All behind `if #available(macOS 26, *)` with existing code as fallback (deployment target remains macOS 14.6).

### 1. Glass button styles for footer

Replace `.buttonStyle(.borderless)` with `.buttonStyle(.glass)` on the Settings, Reset, and Quit buttons. Fallback: `.borderless`.

### 2. Scroll edge effect via safeAreaBar

Wrap column headers and footer in `.safeAreaBar()` so scrolling hop rows get the system blur/obscure treatment beneath these bars.

### 3. Conditional divider removal

Remove `Divider()` between header/content and content/footer on macOS 26+ since `safeAreaBar` provides visual separation. Keep dividers on older macOS.

## Out of scope

- App icon redesign (requires Icon Composer, design work)
- SettingsView changes (auto-adopts via standard components)
- MenubarTracertApp changes (MenuBarExtra auto-adopts)
