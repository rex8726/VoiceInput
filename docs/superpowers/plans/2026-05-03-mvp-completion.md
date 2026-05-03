# VoiceInput MVP Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the macOS voice input MVP so the app has a complete first-use path, robust fallback behavior, configurable API timeout, and verifiable release packaging.

**Architecture:** Keep the existing `VoiceInputCore` library as the real app implementation and `VoiceInputLauncher` as a thin launcher. Add focused services for permission status and keep user-facing fallback decisions in `AppDelegate.deliver` / recording pipeline. Use `VoiceInputChecks` as the runnable regression gate because this Command Line Tools environment does not provide XCTest or Swift Testing.

**Tech Stack:** Swift 6.3, SwiftPM, AppKit, SwiftUI, AVFoundation, ApplicationServices Accessibility APIs, Security Keychain, SiliconFlow HTTP APIs.

---

## File Structure

- `Sources/VoiceInputCore/AppModels.swift`: settings and history models. Add `timeoutSeconds` with backward-compatible decoding.
- `Sources/VoiceInputCore/SiliconFlowClient.swift`: apply timeout to requests.
- `Sources/VoiceInputCore/PermissionService.swift`: new focused service for microphone, accessibility, and input monitoring visibility.
- `Sources/VoiceInputCore/VoiceInputApp.swift`: expose permission state in menu and copy raw transcription when refinement fails.
- `Sources/VoiceInputCore/SettingsWindowController.swift`: show permission status, add timeout setting, and keep API test.
- `Tests/VoiceInputChecks/main.swift`: add checks for settings migration, timeout range, and fallback helpers.
- `README.md`: document permissions, fallback behavior, and final MVP verification.

## Task 1: Settings Migration and Timeout

**Files:**
- Modify: `Sources/VoiceInputCore/AppModels.swift`
- Modify: `Sources/VoiceInputCore/SiliconFlowClient.swift`
- Modify: `Sources/VoiceInputCore/SettingsWindowController.swift`
- Modify: `Tests/VoiceInputChecks/main.swift`

- [ ] **Step 1: Write failing checks**

Add checks that decode legacy settings without `timeoutSeconds` and confirm defaults apply.

- [ ] **Step 2: Run checks**

Run: `swift run VoiceInputChecks`

Expected: fails because `timeoutSeconds` is not public/implemented.

- [ ] **Step 3: Implement timeout**

Add `timeoutSeconds` to `AppSettings`, custom decoding with default fallback, and set `request.timeoutInterval`.

- [ ] **Step 4: Run checks**

Run: `swift run VoiceInputChecks`

Expected: passes.

## Task 2: Permission Status

**Files:**
- Create: `Sources/VoiceInputCore/PermissionService.swift`
- Modify: `Sources/VoiceInputCore/VoiceInputApp.swift`
- Modify: `Sources/VoiceInputCore/SettingsWindowController.swift`

- [ ] **Step 1: Add service**

Add a small service that reports microphone, accessibility, and input-monitoring guidance.

- [ ] **Step 2: Add menu visibility**

Show permission status in the menu and provide an item to open System Settings Privacy & Security.

- [ ] **Step 3: Add settings visibility**

Add a permissions section to settings, with concise status labels and an open settings button.

- [ ] **Step 4: Build**

Run: `swift build`

Expected: passes.

## Task 3: Raw Transcription Fallback

**Files:**
- Modify: `Sources/VoiceInputCore/VoiceInputApp.swift`
- Modify: `Tests/VoiceInputChecks/main.swift`

- [ ] **Step 1: Write fallback check**

Add a check for a small pure helper that chooses display message for refined vs raw fallback.

- [ ] **Step 2: Run checks**

Run: `swift run VoiceInputChecks`

Expected: fails until helper exists.

- [ ] **Step 3: Implement fallback**

If STT succeeds but refinement fails, copy raw transcription to clipboard, store it in history, and show “整理失败，已复制原文”.

- [ ] **Step 4: Run checks**

Run: `swift run VoiceInputChecks`

Expected: passes.

## Task 4: Final Verification and Docs

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update docs**

Document timeout, permissions, and raw fallback behavior.

- [ ] **Step 2: Run verification**

Run:

```bash
swift build
swift run VoiceInputChecks
./scripts/build_app.sh
plutil -lint Resources/Info.plist build/VoiceInput.app/Contents/Info.plist
codesign --verify --deep --strict --verbose=2 build/VoiceInput.app
```

Expected: all commands pass.

## Scope Coverage

- Fn/Option+1 trigger: already implemented and checked.
- Recording overlay: already implemented.
- STT and AI refinement: already implemented.
- Automatic paste with clipboard fallback: already implemented and checked.
- Permissions visibility: Task 2.
- API settings and timeout: Task 1.
- Recent history: already implemented.
- Raw fallback on refinement failure: Task 3.
- Release package verification: Task 4.
