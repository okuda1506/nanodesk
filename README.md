# NanoDesk

A native macOS app that brings a **fully rotatable, interactive 3D iPod nano (5th generation)** to your desktop.

The goal is to display **only the 3D device**, without a visible app window. Use the click wheel to browse and control songs in Apple's Music app, or open the original iPod nano **Video Camera** feature to record VGA video using your Mac's camera.

> **Project status:** Specification and initial repository setup. The macOS app and 3D model have not been implemented yet.

## Planned Features

- Realistic, freely rotatable 3D iPod nano with front, sides, and back
- Transparent, borderless floating desktop presentation
- Functional click wheel, MENU, Select, Previous, Next, and Play/Pause controls
- Browsing and playback of a user-selected Music.app playlist, including purchased iTunes Store tracks
- Now Playing information and volume control
- **Video Camera:** Preview from the Mac camera inside the device screen, record target **640 × 480 at 30 fps** with H.264/AAC, and browse recordings in Camera Roll
- Local settings persistence, menu-bar controls, and appropriate macOS privacy permissions

**Not planned for the MVP:** Still-photo capture, DRM removal, streaming-service duplication, or syncing a physical iPod.

## Specification

The full product requirements, architecture proposal, development phases, risks, and acceptance criteria are documented in **[docs/SPEC.md](docs/SPEC.md)**. This file is the source of truth for Codex.

## Technology (Planned)

| Area | Technology |
|---|---|
| macOS application | Swift, SwiftUI, AppKit |
| 3D rendering | RealityKit / RealityView |
| 3D source assets | Blender → USDZ |
| Music integration | Apple Events / AppleScript → Music.app |
| Camera and recording | AVFoundation |
| Tests | Swift Testing or XCTest |

**Target device:** Apple Silicon Mac, primarily MacBook Air M3. The specification initially targets macOS 15+, subject to API and Xcode verification.

## Development Workflow

1. Connect this GitHub repository to **Codex Cloud**.
2. Ask Codex to read `docs/SPEC.md` and begin with **Phase 0 technical feasibility spikes only**.
3. Have Codex implement testable source code and mocks in Cloud, then commit its changes through GitHub.
4. Clone the repository onto a Mac with Xcode.
5. Build the native project and validate transparent rendering, Music.app integration, permissions, and video capture on the Mac.
6. Return build errors and logs to Codex, iterate, and complete the remaining phases in the order defined by the specification.

A normal Codex Cloud environment does **not** provide the Mac GUI, Xcode, Music.app, or your physical camera. **Cloud implementation alone is not evidence of a working macOS app.**

### Clone the repository

~~~bash
git clone https://github.com/okuda1506/nanodesk.git
cd nanodesk
~~~

Once Codex creates the Xcode project, open the generated `.xcodeproj` or `.xcworkspace` in Xcode, select **My Mac**, and run it with **Command-R**. The build command and minimum supported Xcode version will be documented after Phase 0.

### Music setup

For MVP playback, add downloaded, purchased iTunes Store songs to a playlist in **Music.app**, then select that playlist through NanoDesk after granting macOS Automation permission. NanoDesk does not require an Apple Music subscription or access to your Apple Account credentials.

### Video setup

Video Camera uses the **Mac's physical front-facing camera and microphone**, not the position or direction of the 3D rear camera model. macOS camera/microphone permission is required. The planned default save location is:

~~~text
~/Movies/NanoDesk/Camera Roll/
~~~

The app must honor macOS sandbox/file-access restrictions and report actual recording characteristics rather than assuming the target format was achieved.

## Installation (After Development)

The finished product is intended to be built as a regular **NanoDesk.app** using Xcode. For personal use, the built app can be placed in **/Applications** and opened from Finder, Spotlight, or the Dock. Public distribution, code signing, notarization, and intellectual-property review are separate concerns.

## Project Boundaries and IP

This is a personal, unofficial fan-inspired project, **not affiliated with or endorsed by Apple**. Do not commit purchased music files, credentials, unlicensed 3D assets, Apple firmware, or proprietary UI assets. Reproduction or redistribution of Apple trademarks and device designs may require additional rights review.

## License

No open-source license has been selected. Public repository visibility alone does not grant permission to reuse or redistribute the source.
