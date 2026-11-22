# NanoDesk

A native macOS app that brings a **fully rotatable, interactive 3D iPod nano (5th generation)** to your desktop.

The desktop preview presents the approved 3D device in a transparent panel. Its original Japanese menus browse the local Mac's Music library and control playback through the click wheel. VGA capture is a later feature.

> **Project status** · The desktop preview and Japanese music flow are available for Mac validation. The [approved silver A1320 model](docs/MODEL_REVIEW.md) supplies its USDZ. See [implementation findings](docs/RISKS_AND_FINDINGS.md) for the checks performed so far.

## Run the desktop preview

On an Apple Silicon Mac running macOS 15 or later, install Xcode 16 or later. Open `NanoDesk.xcodeproj`, select the **NanoDesk** scheme and **My Mac**, and press **Command-R**. The target uses **Sign to Run Locally**. Use the **NanoDesk** menu-bar item to show or hide the device, reset it, toggle window behavior, or quit.

| Action | Control |
|---|---|
| Rotate in both axes | Drag the housing. Shift-drag anywhere on the device, including the wheel. |
| Open Cover Flow | From Home, a Music menu or Now Playing, twist two fingers over the device or Command-drag it sideways until it is horizontal. Both directions work. You can also select **ミュージック → Cover Flow**. |
| Browse albums | Trace the wheel to move through the sleeves. Turn quickly to scan artist initials, then lift or pause to resume album browsing. Press center for the album’s tracks, then center on a track to play. Turn upright to return. |
| Browse and select | Trace the visible wheel to scroll. Click its center to select and MENU to go back. |
| Control playback | On any screen, click the bottom of the wheel to play/pause, the right to skip to the next song, or the left for the previous song. The menu and its highlight stay in place. |
| Hold switch | Drag the housing downward to see the top edge. Click the slider to lock the wheel and motion-triggered Cover Flow changes. The orange strip marks Hold. Click it again to unlock. Playback continues. |
| Return to the front | Double-click the housing or select **Reset Orientation**. |
| Move | Option-drag the device. |
| Resize | Command-scroll, pinch, or use **Increase Size** and **Decrease Size**. |
| Pass clicks to other apps | Enable **Click Through** from the menu bar. Disable it there to interact again. |

For a command-line build on the Mac from the checkout root:

```bash
xcodebuild -project NanoDesk.xcodeproj -scheme NanoDesk -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode build
open .build/xcode/Build/Products/Debug/NanoDesk.app
```

`swift test` runs the shared rotation, hit-test, and placement tests on macOS or Linux. Use the [Mac QA checklist](docs/QA_CHECKLIST.md) to check window transparency and compare RealityKit with the approved renders.

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

## 3D Modeling References

- **[Photo reference gallery and mechanical modeling guide](docs/3D_MODEL_REFERENCES.md)** — front, back, click wheel, rear camera, top/bottom references, photo attribution and licenses, plus source engineering drawing.
- **[Machine-readable physical dimensions](assets/references/ipod_nano_5g_dimensions.json)** — Apple-published size, display, weight, and camera output; wheel dimensions from the engineering drawing are marked for validation.

Four locally stored photo references are now available in **[assets/references/photos/](assets/references/photos/)** with author/source/license attribution. Use these files first when building the Blender model, and inspect the original Apple dimensional drawing before claiming drawing-verified feature measurements.

**Codex Cloud photo access:** External photo/drawing hosts previously returned HTTP 403. **The four photographs are now committed locally**, so Codex should open them directly from the repository rather than fetch remote links. The Apple-authored Figure 16-64 drawing is **not stored locally** and still requires separate inspection. See [Reference Access Recovery](docs/REFERENCE_ACCESS.md) and [AGENTS.md](AGENTS.md).

## Technology (Planned)

| Area | Technology |
|---|---|
| macOS application | Swift 6, AppKit |
| 3D rendering | RealityKit `RealityRenderer` and a transparent Metal layer |
| 3D source assets | Blender → USDZ |
| Music integration | Apple Events / AppleScript → Music.app |
| Camera and recording | AVFoundation |
| Tests | Swift Testing for portable logic, plus Mac desktop QA |

**Target device:** Apple Silicon Mac, primarily MacBook Air M3. The specification initially targets macOS 15+, subject to API and Xcode verification.

## Development Workflow

Use the Cloud Swift toolchain for portable tests and the Mac Xcode toolchain for the app and its desktop appearance. The [architecture notes](docs/ARCHITECTURE.md) explain how the two targets share code and which render is the visual baseline. Follow [the specification](docs/SPEC.md) for later features such as playlists and video capture.

### Clone the repository

~~~bash
git clone https://github.com/okuda1506/nanodesk.git
cd nanodesk
~~~

### Play a song from Music

With a playable track registered in **Music.app**, face the device front and turn off **Click Through**. Click the center button on **ミュージック**, then on **曲**. NanoDesk can open Music when you first browse. Allow **NanoDesk → Music** in the macOS Automation prompt, select the song with the wheel and click center. Music plays the audio and NanoDesk shows **再生中**. The list reads the Music library directly. A playlist and a subscription are unnecessary.

If permission was denied, use System Settings → Privacy & Security → Automation → NanoDesk → Music, then press center again on **曲** to retry. If the item is not there, try opening **曲** again from the signed app. If the display shows an error code, record the number and the operation that produced it. Try playing the track in Music itself if playback fails. See [Music QA](docs/QA_CHECKLIST.md#mac-validation-for-the-music-flow) for the live checks.

### Video setup (planned)

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
