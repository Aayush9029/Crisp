# Crisp

Crisp is a macOS menu bar app that keeps AirPods in high-quality AAC output. It pins the default audio input to the built-in microphone (or another chosen input), so macOS does not switch the AirPods to the SCO codec. Status: shipped (1.0.1), small and stable. Public repository `Aayush9029/Crisp`, distributed as a DMG on GitHub Releases.

Stack: Swift 6, SwiftUI, Core Audio (`AudioObject` APIs), XcodeGen. macOS 26 or later, arm64 only.

## Commands

| Task | Command |
|------|---------|
| Generate the Xcode project | `xcodegen generate` |
| Build | `xcodebuild -project Crisp.xcodeproj -scheme Crisp -configuration Debug build` |

The repository has no tests.

## Architecture

| Part | Role |
|------|------|
| `Crisp/App/` | `CrispApp`, `AppDelegate`, About window |
| `Crisp/Audio/AudioInputManager.swift` | Lists input devices, watches device changes, and sets the default input again when macOS changes it |
| `Crisp/Views/` | Menu bar content |

## Rules

- Edit `project.yml`, then run `xcodegen generate`. Do not edit `Crisp.xcodeproj` by hand.
- Persist the chosen input by its device UID (`forcedDeviceUID`), never by `AudioDeviceID`. An `AudioDeviceID` is valid only at runtime and changes after a reconnect. This bug once forced the input to the AirPods.
- Keep the entitlements file empty. The app is not sandboxed and needs no microphone access, because it only changes the default device.
- Bump `MARKETING_VERSION` in `project.yml` for each release. Use the `oss-macos-release` skill to sign, notarize, and publish the DMG.
