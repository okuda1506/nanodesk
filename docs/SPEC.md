# NanoDesk — Product Requirements and Technical Design Specification

| Field | Value |
|---|---|
| Document version | **v1.1 (2026-11-20; Video Camera included)** |
| Project name | NanoDesk |
| Purpose | Source of truth for Codex implementation, engineering decisions, and acceptance testing |
| Primary hardware | Apple Silicon Mac; MacBook Air M3 as the principal physical test device |
| Target OS | macOS 15 or later, subject to validation against the actual installed Xcode/SDK |
| Reference device | **iPod nano, fifth generation (A1320, 2009)**; design components for possible future model swaps |
| Distribution | Personal-use native macOS app; Mac App Store distribution is out of scope initially |
| Language | Swift, preferably Swift 6 as supported by the installed Xcode |

> **Non-negotiable product requirement:** This is **not** an ordinary player window containing a 3D iPod. On the macOS desktop, the **3D iPod nano itself must appear to float independently**, without a visible surrounding application window. Technically, the 3D scene is hosted in a transparent, borderless macOS window. Do **not** add a large main window, browser UI, WebView, background panel, or card behind the device.

---

## 1. Product Vision

Show a realistically proportioned, three-dimensional iPod nano on the Mac desktop. The user can freely rotate the device horizontally and vertically with a mouse or trackpad, inspect its sides and back, and return to the front to operate a functional screen and click wheel. Music is selected from tracks **purchased through the iTunes Store and available in the user's Music.app library**. The iPod interface can browse songs and playlists, start and pause playback, skip tracks, and change volume.

**Desired experience:** While working in other Mac applications, a small 3D iPod remains on the desktop like a physical object. The user can turn it over and use its click wheel. Selecting the original fifth-generation **Video Camera** menu item opens a live view from the Mac camera, allowing VGA video recording.

### 1.1 Interpretations that must not change

- **Standalone desktop appearance:** A real window may be used internally, but it must be borderless, transparent, and visually indistinguishable from a standalone model.
- **True 3D rotation:** Rotate a volumetric model along both horizontal and vertical axes, showing its back and thickness. Tilting a flat 2D image does not meet this requirement.
- **Physical-style input:** Dragging around the click-wheel ring moves a selection or volume; all four directional buttons and the center button must work.
- **Music ownership and playback:** Music.app is the actual audio player; NanoDesk supplies the UI and commands. Do not fetch an Apple purchase-history API, bypass DRM, or implement independent decoding of protected files.
- **Video Camera:** Re-create the video-recording feature supplied with the fifth-generation iPod nano, using the Mac's front-facing camera and microphone. **Do not implement still-photo capture.** The camera sculpted on the model's back is visual; the actual source is the Mac camera.

## 2. Scope and Priorities

**P0 = required for the MVP; P1 = improvement after MVP; P2 = future possibility.**

| ID | Feature | Priority |
|---|---|---|
| F-01 | Standalone 3D iPod appearance in a transparent, borderless window | P0 |
| F-02 | Accurate 3D front, rear, sides, thickness, and materials | P0 |
| F-03 | Mouse/trackpad 360-degree rotation and reset to front | P0 |
| F-04 | Circular drag scrolling on the click wheel | P0 |
| F-05 | Working MENU, Select, Previous, Next, and Play/Pause buttons | P0 |
| F-06 | Home, Music, Playlists, Songs, and Now Playing navigation | P0 |
| F-07 | Music.app permission/connection and playlist selection | P0 |
| F-08 | Playback of a user-selected playlist containing purchased music | P0 |
| F-09 | Title, artist, playback state, position, duration, and volume | P0 |
| F-10 | Menu-bar show/hide, placement, resizing, and quit | P0 |
| F-11 | Persist settings, position, scale, and last screen | P0 |
| F-12 | Recovery UX for denied Automation permission, empty library, absent Music.app, etc. | P0 |
| F-13 | Display album artwork | P1 |
| F-14 | Select housing color, e.g. silver or black | P1 |
| F-15 | Hold switch/input lock and keyboard shortcuts | P1 |
| F-16 | Per-pixel click-through outside the device silhouette | P1, subject to feasibility |
| F-17 | Automatically identify purchased tracks | P1, subject to metadata reliability |
| F-18 | Screen reflections, wheel feedback sounds, inertial animations | P1 |
| F-19 | Shuffle/repeat controls and long-press seeking | P1 |
| F-20 | Search/play the full Apple Music subscription catalog | P2 |
| F-21 | Login launch, multiple devices, interchangeable skins | P2 |
| F-22 | Main Menu > Video Camera with a live preview inside the model's screen | P0 |
| F-23 | Record video and audio using Mac camera/microphone at target 640x480, 30 fps | P0 |
| F-24 | Center-button start/stop, red REC indicator, elapsed timer | P0 |
| F-25 | Save locally and browse/play recordings in Camera Roll | P0 |
| F-26 | Permission, missing-device, and recording/storage error handling | P0 |
| F-27 | Vintage video effects such as film grain | P1 |
| F-28 | Portrait shooting, deletion, alternative destinations, advanced recording preferences | P1 |

**Explicitly excluded from MVP:** iOS/Windows clients; USB sync with a real iPod; an iTunes Store buying UI; Apple Account credentials; downloading streamed tracks; DRM circumvention; **still photography**; FM radio, games, and exhaustive firmware replication. **Video recording is included in P0.**

## 3. Prerequisites and Constraints

1. Music.app must be available on the development and end-user Mac.
2. Purchased iTunes Store songs must be in the Music.app library and playable on that Mac. For cloud-only songs, guide the user to download or authorize playback through Music.app first.
3. Request the macOS **Automation** permission before controlling Music.app. If denied, the 3D device remains viewable and the music UI offers actionable permission instructions.
4. An Apple Music subscription is not required. Do not independently decrypt subscription music.
5. Reliably distinguishing all purchased tracks from all other tracks is **not assumed possible**. For P0, the user selects a playlist they created in Music.app specifically for their purchases; automatic detection is P1.
6. Respect Music.app output routing and queue behavior. Do not duplicate or cache audio files.
7. Video requires camera and, for audio, microphone permission plus an available Mac camera. Recordings remain on the user's Mac; nothing is uploaded.
8. The target recorded output is **640x480 (4:3), 30 fps, H.264 video with AAC audio**. Camera input properties are distinct from exported output properties. If 30 fps is unavailable, clearly report that and verify actual output metadata.

## 4. User Journeys

### U-01: First launch

1. Launch NanoDesk.
2. A front-facing 3D nano appears directly on the desktop, without visible window chrome.
3. Its screen asks to connect to Music.app.
4. Initiate connection and request macOS Automation permission where appropriate.
5. On success, show playlists available through Music.app.
6. The user selects a playlist of purchased music; save the choice.
7. Display the iPod main menu and enable music controls.

### U-02: Play music

1. Drag clockwise or counterclockwise around the click-wheel circumference.
2. Navigate Music > Playlists > selected playlist > Songs.
3. Press Select to play a track through Music.app.
4. Show title, artist, elapsed and total time in Now Playing.
5. Play/Pause, Next, and Previous control Music.app.
6. Dragging the ring on Now Playing changes the Music.app volume.

### U-03: Rotate the device

1. Drag an area of the **housing outside the click wheel** to rotate along both axes.
2. Inspect the back camera detail, edges, thickness, and metallic reflections.
3. Disable front controls when they are not sufficiently facing the viewer.
4. Double-click or choose "Reset Orientation" from the menu bar to face front.

### U-04: Keep the desktop usable

1. Move the floating device with Option-drag or a menu-bar Move Mode.
2. Remember location and scale across launches.
3. Avoid interfering with normal windows, Dock, and Mission Control.
4. Offer menu-bar toggles for Always on Top, normal layering, input lock/click-through mode, and Hide.
5. Let the user choose whether music stops on quit; default is **keep Music.app playing**.

### U-05: Record video

1. Select Video Camera from Main Menu using the wheel and center button.
2. Request system camera/microphone permissions when first needed; avoid unnecessary background capture.
3. Display the live view **only inside the 3D iPod screen**.
4. One press of Select starts recording; show a blinking red indicator and elapsed timer.
5. Another press stops recording and safely writes a file under **~/Movies/NanoDesk/Camera Roll/**.
6. In preview mode, MENU opens Camera Roll. Choose a recording and press Select for playback. While recording, MENU does not navigate away; instead display an instruction to stop first.
7. MENU from Camera Roll returns to Video Camera. Do not open an unrelated large capture window; a separate settings panel is permitted.

## 5. 3D Model Requirements

### 5.1 Appearance and geometry

- Reference: **fifth-generation iPod nano (A1320)**, including its front, back, and sides.
- Reference dimensions: **90.7 mm high x 38.7 mm wide x 6.2 mm thick**. Preserve proportions, but allow the on-screen model to be larger.
- Build the rounded aluminum body, black screen bezel, color display, round click wheel and center button, upper Hold switch, rear camera and microphone detail, bottom connector, and headphone port.
- Default color: silver. Prioritize realistic metal specular response and edge highlights.
- Model the screen and click wheel as sensible components with believable positions/depth, not merely one flat decal.
- Create a distinct back, not a mirrored front. Explain in the README that the rendered back camera's direction is **not connected** to the Mac camera's physical direction.
- Use an efficient real-time mesh; avoid unnecessary high polygon counts.

### 5.2 Editable and runtime assets

- Keep an editable source scene, ideally Blender (e.g. assets/source/ipod_nano_5g.blend).
- Export **USD/USDZ** usable in the selected RealityKit runtime (e.g. NanoModel.usdz); document conversion and verify in Xcode on macOS.
- Where practical, supply a reproducible Blender Python/bpy mesh-generation script. Blender must **not** be needed to run the shipped app.
- Deliver both an editable 3D asset and a buildable native app.
- Do not redistribute third-party assets without permission. Use original geometry and review Apple design/trademark considerations before distribution.

### 5.3 Embedded dynamic screen

- Load the device geometry into a RealityKit scene, considering RealityView where supported.
- Attach an **updating display surface to the front of the 3D body** so it rotates with the device. Spike SwiftUI attachments versus dynamic textures; choose based on macOS hit testing, legibility, and transparency.
- Update screen content when state changes; do not rebuild the entire mesh per frame.
- Prefer English UI strings (Music, Playlists, Songs, Now Playing, Settings). Error messages may be localized.

## 6. Desktop Rendering and Window Behavior

### 6.1 Visual design

- Use NSWindow or NSPanel for a **borderless, titlebar-free, visually transparent** floating presentation.
- Never render a white/black rectangular background, card, browser chrome, or toolbar behind the iPod.
- Initial apparent device height: approximately **350–450 points**, adjustable.
- The internal window bounds must accommodate the model's projected rotation.
- Although a window exists internally, users should not perceive its boundaries.

### 6.2 Controls

- Menu-bar toggle for Always on Top (ahead of normal windows, but not critical OS UI), Show, Hide, and Quit.
- Move with **Option + drag** or menu-bar Move Mode; a normal body drag rotates.
- Scale with **Command + mouse wheel** or a settings slider; avoid conflict with the iPod click wheel.
- Provide Reset Orientation, Reset Position, and Reset Scale.
- When monitor topology changes, bring the model back inside a visible display.

### 6.3 Click-through feasibility

**Transparent pixels do not necessarily pass mouse clicks through to the window underneath.**

- **P0:** Transparent rendering, reliable model interaction, appropriately small window bounds, and a menu-bar input-lock / full click-through toggle.
- **P1:** Experiment with routing clicks outside the projected model silhouette to underlying apps. Do not assume private APIs, unsafe event hooks, or unnecessary Accessibility permissions.
- If reliable per-pixel hit routing is unavailable, ship explicit **interactive** versus **fully click-through** modes and document the limitation.

## 7. Input and Gesture Specification

### 7.1 Hit targets and precedence

Use 3D hit testing to distinguish Body, Screen, WheelRing, MenuButton, CenterButton, PreviousButton, NextButton, and PlayPauseButton. Invisible collision meshes are acceptable.

1. Short press on a button => its action.
2. Circular drag on WheelRing => wheel input.
3. Drag on Body => 3D rotation.
4. Option + body drag => move window.
5. Shift + drag from anywhere => force body rotation (escape hatch for wheel ambiguity).
6. Command + scroll => change scale.
7. If the front is rotated out of view, deactivate front controls.
8. In Video Camera preview/recording, the center button starts/stops recording, never music playback or body rotation.

### 7.2 3D rotation

- Map mouse movement delta-x/delta-y to yaw/pitch for continuous two-axis rotation.
- Allow a complete 360-degree view on both axes, including the back.
- Prevent wild axis flips (quaternion representation is acceptable).
- Rotation sensitivity is adjustable; no uncontrolled inertia on release in P0. Inertia is P1.
- Rotate about the approximate model center; keep it visible within its hosting window.

### 7.3 Click wheel

- Determine cursor polar angle around the wheel using atan2(y, x).
- Unwrap angle crossing at -pi/pi to avoid discontinuities.
- Do not treat the center button or body outside the ring as wheel-drag input.
- Clockwise = down/next, counterclockwise = up/previous; allow reversal in settings.
- Initial tuning target: one item per approximately **15 degrees** of arc; configurable speed, threshold, debounce. Minor 1–2 px jitter must not trigger selection.
- On menus/lists, scroll selection; on Now Playing, change volume (e.g. one unit per step).
- Do not wrap at the end of a list by default.
- Differentiate presses on MENU/Previous/Next/Play-Pause from circular movement.

### 7.4 Buttons

| Input | Menu screens | Now Playing |
|---|---|---|
| MENU (top) | Go back one level | Previous screen |
| Center | Select item/song | Contextual select; default stay on Now Playing |
| Next (right) | Next-track operation if applicable | Next track |
| Previous (left) | Previous-track operation if applicable | Restart current; repeated press previous (validate) |
| Play/Pause (bottom) | Toggle Music.app playback | Toggle Music.app playback |
| Rotate wheel ring | Move highlighted row | Change volume |

- Long-press fast-forward/rewind, MENU hold for Home, and Play button hold for sleep are P1.
- Give visible button feedback.
- If playback cannot start, display a concise reason rather than silently ignoring input.

## 8. Device Screen Navigation

~~~text
Main Menu
  ├─ Music
  │   ├─ Playlists
  │   │   └─ [Selected Playlist]
  │   │       └─ Songs
  │   │           └─ [Track List] → Now Playing
  │   └─ Songs → [Track List] → Now Playing
  ├─ Now Playing
  ├─ Video Camera → [Live Preview / Recording] → Camera Roll → [Recordings] → [Playback]
  └─ Settings
      ├─ Change Playlist
      └─ Connection Status
~~~

- **Main Menu:** Highlight the current selection, scrolling when needed.
- **Playlists:** Present Music.app playlists, selection state, and retry on fetch failure.
- **Songs:** Show track titles and, if available, artists. Truncate or scroll long labels.
- **Now Playing:** Title, artist, playing/paused indicator, elapsed/total time, progress bar, and a temporary volume gauge.
- **Connection Status:** Automation permission state, availability/download state, reconnect action.
- **Video Camera:** Live viewfinder on the device screen, recording time (00:00) and blinking red dot at upper right; center button toggles recording.
- **Camera Roll:** List recordings in date order; center button starts playback inside the iPod screen. **No delete action in P0** to avoid accidental loss; provide an Open in Finder action in settings/menu bar.
- Create an **original iPod-inspired UI**, not a copy of Apple firmware, screen bitmaps, or proprietary fonts.
- Avoid any permanent secondary window; permit a native settings/error sheet only when needed.

## 9. Music.app Integration and Playback

### 9.1 Technology and permissions

- Music.app is the **audio playback engine**.
- Use NSAppleScript, Apple Events, or ScriptingBridge as appropriate; compare feasibility in Phase 0 before choosing.
- Target Music.app (verify bundle identifier com.apple.Music on the actual Mac), not the old iTunes.app.
- Declare NSAppleEventsUsageDescription and any required entitlements. Validate sandbox choices for the intended distribution.
- Never collect Apple Account secrets or decrypt, copy, or redistribute protected audio.

### 9.2 Suggested abstraction (illustrative, not a guarantee of API support)

~~~swift
protocol MusicPlayerControlling {
    func connect() async throws
    func listPlaylists() async throws -> [MusicPlaylist]
    func listTracks(playlistID: String) async throws -> [MusicTrack]
    func play(playlistID: String, trackID: String?) async throws
    func pause() async throws
    func resume() async throws
    func nextTrack() async throws
    func previousTrack() async throws
    func setVolume(_ value: Int) async throws
    func currentPlayback() async throws -> PlaybackSnapshot
}
~~~

- Prefer stable persistent track IDs over titles. If unavailable, explicitly design playlist+index fallback behavior.
- PlaybackSnapshot should include at least trackID?, title, artist, durationSeconds?, positionSeconds, state, and volume.
- Put Apple Events work on an appropriate asynchronous path; never block the rendering/UI thread.
- Respect a permission denial; do not repeatedly force system authorization prompts.

### 9.3 Selected playlist and playback queue

- **The MVP limits its playback scope to a user-selected Music.app playlist.**
- Physically verify that playing a chosen track followed by Next/Previous/automatic advance stays in that playlist.
- If Music.app uses another queue, adjust command ordering and queue creation. Unrelated tracks must not unexpectedly play.
- Poll for changes made externally in Music.app and update the 3D iPod UI.
- Avoid destructive library edits, track deletion, or automatic playlist creation.
- Respect existing shuffle/repeat state; P0 must not silently override it. Surface surprising queue behavior.

### 9.4 Purchased iTunes Store music

- Support purchased iTunes Store files, including DRM-free purchases.
- **P0:** Let the user select their own "Purchased Songs" (or equivalent) playlist in Music.app and browse playable tracks within it.
- **P1:** Research the Music.app scripting dictionary for kind, purchaser information, cloud status, etc. Automatic purchase detection must remain best-effort, not guaranteed.
- For cloud-only tracks, direct the user to download or authorize them in Music.app. Extend this only if Music.app itself can lawfully play them.
- If subscription tracks coexist in that playlist, do not bypass DRM; playback availability follows Music.app, and do not mislabel everything as verified purchased music.

### 9.5 State synchronization

- Poll roughly **once per second** during playback; slow to about 3–5 seconds while paused or hidden.
- Refresh promptly after a command to minimize apparent latency.
- Back off on errors so Music.app is not flooded with retries.
- Synchronize Music.app's own volume (assumed 0–100 after verification), **not system-wide output volume**.
- Follow Music.app track switching, stopping, quitting, and relaunching.

## 9A. Video Camera (original-device feature; P0)

### 9A.1 Authenticity and MVP fidelity

- The **2009 fifth-generation iPod nano includes a built-in video camera and microphone**. This feature recreates its Video Camera, **not a newly invented still camera**.
- Apple's user guide describes Main Menu > Video Camera, pressing the center button to start/stop recording, a red indicator/timer, and MENU > Camera Roll for playback.
- Target **VGA 640x480, H.264 with AAC audio, 30 fps**. These settings emulate the original format, but identical visual quality is **not guaranteed** due to different sensors, optics, and encoders.
- The actual device also offers effects and orientation modes, and limits a recording to 2 GB. For MVP, normal landscape 4:3 recording is required; effects/portrait are P1. Do not deliberately impose the original 2 GB limit, but handle disk exhaustion/filesize safely.

### 9A.2 Camera/microphone and live preview

- Prefer the Mac built-in front camera with AVFoundation (e.g. AVCaptureSession); target the MacBook Air M3, and explain when no camera is available.
- Request camera and microphone separately. Set NSCameraUsageDescription and NSMicrophoneUsageDescription and sandbox capture entitlements where applicable.
- Render camera frames with low latency on the **3D screen's dynamic surface only**. Rotating the body rotates the screen along with it.
- Convert/crop high-resolution or 16:9 input to **4:3 640x480 output**, preserving proportions (center crop rather than stretch).
- Differentiate previewing from recording. Stop unused capture sessions on navigation, hide, or quit. During an active recording, finalize safely before hiding/quitting.
- Separately configure mirrored preview and mirrored saved output: initially **preview mirrored ON, saved video mirrored OFF**. Record the behavior and make configurable if local tests require.

### 9A.3 Recording, encoding, and storage

- File extension: **.mp4** where H.264/AAC support permits, otherwise **.mov**. Document the chosen container in README.
- Output target: **640x480, 30 fps, H.264**, **AAC microphone audio**, approximately **1.5 Mbps video bitrate**; verify metadata on a real recording.
- Implement via AVFoundation. Use AVAssetWriter if necessary to guarantee the specified dimensions, frame rate, and codec. Do not assume AVCaptureMovieFileOutput automatically meets the target.
- Prefer the built-in microphone. If mic permission is denied, offer a clear **silent video** option rather than pretending audio is being captured.
- Finalize asynchronously after stop; never display "Saved" before completion. Handle interruptions, permission revocation, hardware loss, and low storage; preserve partial output where safely possible.
- Generate collision-safe timestamped filenames, e.g. nano_20261120_130500.mp4. **Never overwrite an existing file.**
- Default path: **~/Movies/NanoDesk/Camera Roll/**. Validate access and write permissions. For sandboxed apps use a user-selected folder and security-scoped bookmark where necessary; do **not** assume access to arbitrary directories.
- Editing, upload, external storage integration, still capture, and social sharing are excluded.

### 9A.4 Controls

| State | Center | MENU | Wheel ring |
|---|---|---|---|
| Video Camera (preview) | Start recording | Open Camera Roll | No P0 action |
| Video Camera (recording) | Stop and save | Stay; prompt to stop first | Disabled |
| Camera Roll (list) | Play selected video | Return to preview | Scroll recordings |
| Camera Roll (playback) | Play/Pause | Return to list | No P0 action |

- Pause currently playing Music.app audio on entering Video Camera, matching the original device's behavior. Do not auto-resume music when capture ends.
- Body rotation must not interrupt active recording. Users can invoke Reset Orientation if recording controls face away.
- Red recording indicator and elapsed time belong inside the 3D screen, never in a separate capture window.

### 9A.5 Architecture and testing

- Separate CameraControlling, CameraCaptureService (AVFoundation), CameraPermissionService, CameraRecordingStore, VideoCameraState, and CameraRollViewModel.
- Provide mock preview frames and recording state for **Codex Cloud environments without camera hardware**. Real capture and OS permission verification are Mac-only.
- Unit-test permission refusal, start/stop transitions, completion callbacks, and timer state.
- On a Mac, inspect the generated file metadata **programmatically** for dimensions, fps, video/audio codecs, and presence of audio.

## 10. Settings and Local Persistence

Persist settings using UserDefaults or another appropriate local preference mechanism.

| Example key | Default |
|---|---|
| selectedPlaylistID | None |
| rotationSensitivity | Normal |
| wheelDirection | Clockwise = down/next |
| windowOrigin | Toward bottom right, adjusted to visible screen |
| windowScale | 1.0 |
| windowAlwaysOnTop | true |
| clickThroughMode | false |
| rotationQuaternion | Front-facing |
| stopPlaybackOnQuit | false |
| cameraSaveFolder | ~/Movies/NanoDesk/Camera Roll/ (bookmark if sandboxed) |
| cameraPreviewMirrored | true |
| cameraRecordedVideoMirrored | false |
| cameraRecordingPreset | VGA_640x480_30fps_H264_AAC |

Do not persist credentials or copies of purchased music. If the selected playlist is deleted, clear the saved ID and request reselection.

## 11. Recommended Architecture and Stack

| Layer | Technology and responsibility |
|---|---|
| Native shell | Swift / SwiftUI for preferences; AppKit for transparent window, menu bar, and input |
| 3D | **RealityKit**, RealityView, USDZ; do not center a new implementation on deprecated SceneKit |
| Modeling | Blender, optionally Python generation; not a runtime dependency |
| Music bridge | Apple Events/AppleScript to Music.app behind MusicPlayerControlling |
| Video | AVFoundation (AVCaptureSession; AVAssetWriter if needed), permissions, local storage, live screen texture |
| App state | AppState, PlaybackStore, NanoNavigationState; manage UI updates on MainActor as appropriate |
| Persistence | UserDefaults for preferences |
| Tests | Swift Testing or XCTest plus manual macOS end-to-end tests |
| Installation | Locally built .app; public distribution requires separate signing/notarization/legal assessment |

### 11.1 Proposed structure

~~~text
NanoDesk/
  README.md
  docs/
    SPEC.md
    ARCHITECTURE.md
    IMPLEMENTATION_PLAN.md
    QA_CHECKLIST.md
    RISKS_AND_FINDINGS.md
  NanoDesk.xcodeproj/                 # Or equivalent native Xcode project
  NanoDesk/
    App/NanoDeskApp.swift
    App/AppCoordinator.swift
    Window/FloatingNanoWindowController.swift
    Window/MenuBarController.swift
    Rendering/Nano3DScene.swift
    Rendering/NanoScreenContent.swift
    Input/NanoHitTest.swift
    Input/ClickWheelController.swift
    Input/RotationController.swift
    Features/Navigation/NanoNavigationState.swift
    Features/Playback/PlaybackStore.swift
    Music/MusicPlayerControlling.swift
    Music/MusicAppClient.swift
    Music/MusicAppScriptBridge.swift
    Music/Models.swift
    Camera/CameraControlling.swift
    Camera/CameraPermissionService.swift
    Camera/CameraCaptureService.swift
    Camera/CameraRecordingStore.swift
    Camera/VideoCameraState.swift
    Camera/CameraRollViewModel.swift
    Settings/AppSettings.swift
    Resources/NanoModel.usdz
  assets/
    source/ipod_nano_5g.blend
    scripts/generate_nano_model.py     # Only if adopted
  NanoDeskTests/
    ClickWheelControllerTests.swift
    NanoNavigationStateTests.swift
    PlaybackStoreTests.swift
    MusicAppClientMockTests.swift
    VideoCameraStateTests.swift
    CameraCaptureServiceMockTests.swift
~~~

### 11.2 Engineering principles

- Keep 3D geometry, on-device screen, input, music controller, and camera module **loosely coupled**.
- Mock MusicPlayerControlling to test UI when Music.app is unavailable.
- Centralize scripting commands in one bridge; escape input and normalize errors, rather than concatenating ad hoc AppleScript throughout the codebase.
- Never block the UI thread on script requests.
- Keep settings and user data on the Mac. No backend, analytics SDK, or cloud account is needed.

## 12. Errors, Permissions, and Safety

| Condition | Expected handling |
|---|---|
| Music.app not running | Start/connect when authorized or ask the user to open it |
| Music.app Automation permission not granted | Offer permission workflow/retry; keep the 3D model visible |
| Automation was denied | Explain System Settings > Privacy & Security > Automation |
| No playlist selected | Show selection prompt instead of blindly playing |
| Empty playlist | Explain that no songs are available |
| Unplayable track | Explain/skip; suggest Music.app authorization or download |
| Music.app quits during use | Update state and offer reconnect; app must not crash |
| Slow AppleScript response | Timeout/retry without freezing UI |
| Long titles, Japanese characters, emoji | Render safely without clipping or corruption |
| Device rotated to back | Allow rotation but do not misfire invisible front controls |
| Display connected/disconnected | Restore model to a visible screen |
| Camera/microphone permission missing or denied | Native permission guidance; explicitly identify silent capture |
| Camera missing or busy | Explain and retry without crashing; music still works |
| Quit/hide/permission change/disk full during recording | Safely finalize when possible and report errors |
| Save folder not writable | Never claim success; let the user choose a writable location |

- Do not circumvent OS privacy controls, DRM, or licensing restrictions.
- Limit automation targets to Music.app. Do not request global Accessibility or Screen Recording permission without a documented need. Request camera/microphone access only for Video Camera.
- This is a personal-use prototype; before public release or commercial distribution, review Apple's design, logo, and trademark rights.

## 13. Nonfunctional Requirements

- **Launch:** Display the 3D device through a normal app launch, even if Music.app connection fails.
- **Response:** Smooth 3D rotation, wheel input, and button feedback. Target at least **30 fps** rendering and **under 100 ms** local visual response; Music.app command completion can lag separately.
- **Efficiency:** Optimize for M3 Apple Silicon; reduce update rate while idle to conserve battery. Keep idle CPU use minimal.
- **Reliability:** A stalled Music.app must not freeze the NanoDesk UI.
- **Usability:** Input hit testing must not confuse rotation with wheel control. The transparent host must not excessively obstruct other windows.
- **Maintainability:** Separate rendering, input, and integration layers, allowing a different nano generation in future.
- **Offline:** No internet needed when downloaded purchased tracks are already playable locally. Music.app download/authorization is separate; recording also works offline.
- **Visual quality:** Real depth from front/side/back, without mesh defects, black background artifacts, or misaligned wheel.

## 14. Delivery Phases for Codex

> **Validate high-risk platform assumptions first.** Do not invest in a finished 3D asset or full app before confirming macOS feasibility.

### Phase 0 — Technical spikes (highest priority)

1. Inspect the local Xcode/Swift/macOS versions and SDKs. If Mac access is unavailable, record the limitation.
2. Host a simple rotatable 3D cuboid in a **transparent, borderless** macOS window. Test transparency and mouse interaction.
3. Demonstrate 3D hit testing and rotation in RealityKit.
4. Attach minimal dynamic song-title text to a 3D plane and confirm it rotates with the model.
5. On a Mac, actually test Music.app permissions, playlist enumeration, track listing, playing one song, playback status, pause/resume, skip, and volume adjustment.
6. Probe click-through behavior; determine P0/P1 limits.
7. On a Mac, prototype AVFoundation camera/mic permission and a real **640x480/30 fps H.264/AAC** recording. In Cloud without hardware, mock it and mark it unverified.
8. Record results in docs/RISKS_AND_FINDINGS.md with **Verified / Unverified / Alternatives**.

**Phase 0 exit gate:** The minimal transparent 3D UI, Music.app control, and AVFoundation video capture must each be physically verified on a Mac before declaring Phase 0 fully complete. For a Cloud-only task, label pending checks **BLOCKED_LOCAL_MAC**, and proceed with isolated implementation/testing if useful. **Never claim real-device verification without real-device testing.**

### Phase 1 — Device model and placement

1. Build a fifth-generation nano model with individually identifiable front/back/side/wheel/buttons.
2. Export/load USDZ in the transparent macOS presentation.
3. Implement rotate, move, resize, reset, and persistent placement.
4. Add menu-bar Show/Hide/Quit.

### Phase 2 — Click wheel and simulated iPod UI

1. Implement 3D hit testing for ring, center, four directions, and body.
2. Implement circular scrolling, free device rotation, and conflict resolution.
3. Implement Main Menu/Music/Playlists/Songs/Now Playing with **mock data**.
4. Add tests for angle unwrapping, direction, thresholds, and navigation.

### Phase 3 — Real Music.app playback

1. Implement Automation permission and denial handling.
2. Implement MusicAppClient: playlist listing, track listing, playback and controls.
3. Synchronize Now Playing, progress, volume, and external changes.
4. Verify Next/Previous and automatic progression remain within the selected playlist.
5. Handle unavailable/cloud-only songs and related errors.

### Phase 3.5 — Video Camera (**mandatory P0**)

1. Add Video Camera to Main Menu; complete mock preview/recording states on the 3D screen.
2. Add native camera/mic permission and AVFoundation capture.
3. Show a correctly cropped 4:3 live preview attached to the device screen.
4. Center-button record/stop, red REC indicator, and elapsed timer.
5. Save local 640x480, target-30-fps H.264/AAC output; validate real metadata on Mac.
6. Implement Camera Roll list and video playback inside the iPod screen.
7. Test denied permissions, quit during recording, write failures, audio-less mode, and camera disconnection.

**The MVP is not complete without Phase 3.5. Do not add still-photo capture.**

### Phase 4 — Visual refinement and QA

1. Refine metal/glass materials, legibility, and button feedback.
2. Check sustained CPU, memory, and battery usage on physical hardware.
3. Run regression tests for resolutions, Japanese titles, overlapping windows, and monitor changes.
4. Document setup, usage, permission requests, purchased-song playlist creation, **camera/mic permissions and video save path**, known limits, and build instructions in README.
5. Deliver a locally runnable .app together with source and editable/exported 3D assets.

## 15. MVP Acceptance Criteria

| ID | Test | Pass condition |
|---|---|---|
| AC-01 | Launch | Only the iPod is visible over the desktop, without title bar or black/white rectangle |
| AC-02 | Drag housing | Smooth horizontal and vertical rotation; inspect sides and back |
| AC-03 | Reset rotation | Return to original front-facing orientation |
| AC-04 | Drag wheel | Change menu selection with circular movement; no jump at angle wrap boundary |
| AC-05 | Buttons | MENU, Select, Previous, Next, Play/Pause work correctly |
| AC-06 | Gesture isolation | Ring drag does not rotate device; housing drag does not change volume |
| AC-07 | Playlist | Show songs from the specified Music.app playlist on the device |
| AC-08 | Play | Center selection results in the corresponding song playing audibly through Mac |
| AC-09 | Playback controls | Play/Pause/Next/Previous/volume affect Music.app |
| AC-10 | External changes | Music.app changes are reflected in NanoDesk title/state |
| AC-11 | Queue | Playback does not unexpectedly transition to unrelated songs outside chosen playlist |
| AC-12 | Denied permissions | App does not crash; model remains visible; recovery guidance shown |
| AC-13 | Persistence | Restore placement, scale, and selected playlist after relaunch |
| AC-14 | Menu bar | Show/Hide, Always on Top, Quit work |
| AC-15 | Robustness | No crash when Music.app is closed, playlist empty, or names contain Japanese/emoji |
| AC-16 | Deliverables | Buildable project, editable 3D master, and USDZ available |
| AC-17 | Camera launch | Device screen shows the Mac camera feed; no extra main window |
| AC-18 | Recording | Center button starts/stops; red REC and elapsed time visible |
| AC-19 | File output | Locally saved 640x480 4:3 H.264 video with AAC audio when permitted, target 30 fps; metadata checked |
| AC-20 | Camera Roll | Select and play recorded movies within the device screen |
| AC-21 | Capture failures | Denied access, no camera, low storage, unwritable folder show actionable errors, no crash |
| AC-22 | Quit/hide during capture | Finalize safely and report any save failure |
| AC-23 | Scope | No still-photo shutter or photo-file feature |

### 15.1 Minimum manual test walkthrough

- Prepare at least three downloaded purchased songs in a test playlist in Music.app.
- Test connection and playback while Music.app is open and after it has been quit.
- Rotate fully to back and return; navigate at least two menu levels via the wheel.
- Start/pause/skip a track, then switch to another track directly in Music.app.
- Quit/restart NanoDesk and confirm saved location and playlist.
- Test an ungranted or denied Automation permission.
- On a Mac with camera/mic permission, record 5–10 seconds and inspect size, codec, audio, and frame rate of the result.
- Rotate the 3D housing during recording; stop, open Camera Roll, and play the recording.
- Exercise camera denied, mic denied, and unwritable output-folder failures.

## 16. Engineering Risks and Decision Rules

| Risk | Severity | First experiment | Fallback/decision |
|---|---|---|---|
| RealityKit scene does not blend transparently in NSWindow | High | Display simplest transparent cuboid on Mac | Compare alternative macOS renderers, including Metal; document evidence before switching |
| Screen text/preview does not track 3D rotation reliably | High | Rotate a textured/attached 3D screen | Compare SwiftUI attachments vs dynamic textures |
| Wheel hit tests conflict with body rotation | High | Test separate collision regions and gesture priority | Provide modifier key or explicit mode |
| Music.app scripting differs by OS/permissions | High | Individually verify authorize, list, play, status | Document supported subset; never claim untested integration |
| Queue escapes the selected playlist | High | Continuous three-track playlist test | Revise playback queue/target selection |
| Purchased vs subscription metadata is unreliable | Medium | Inspect Music.app scripting dictionary and real tracks | P0 uses user-selected playlist |
| Transparent host blocks background clicks | Medium | Test mouse behavior on physical Mac | Full click-through toggle; per-pixel passthrough P1 |
| 3D visual quality is insufficient | Medium | Compare front, 45-degree, and rear renders | Keep editable Blender original; iterate per part |
| Camera cannot maintain VGA/30 fps or 3D preview is costly | High | AVFoundation prototype and metadata test | Explicit frame conversion/AVAssetWriter; optimize and document limits |
| Camera/mic privacy and sandbox folder access fail | High | Test denials, sandbox, filesystem access | Save dialog/security-scoped bookmark |
| Codex Cloud has no native Mac GUI, Music.app, or camera | High | Inspect Cloud environment; test with Xcode on Mac | Cloud handles code/mocks; local Mac handles build and integration verification |

## 17. Starting Prompt for Codex

> You are building a native macOS application. Treat **docs/SPEC.md as the authoritative specification** for NanoDesk, a floating 3D fifth-generation iPod nano for the Mac desktop.
>
> **Do not** substitute a normal app window displaying an iPod, a webpage, or a web-based player. The result must appear as **only the 3D device** in a transparent, borderless macOS window. Music.app is responsible for audio playback; the app controls a playlist selected by the user, usually containing purchased iTunes Store songs.
>
> **Start with Phase 0 technical spikes only.** Investigate: (1) transparent macOS rendering of RealityKit 3D content; (2) 3D hit testing; (3) Music.app Automation permission, playlist discovery and real playback commands; (4) a dynamic display on a rotating 3D surface; (5) AVFoundation camera and microphone capture with VGA video output. Record what is verified, unverified, and blocked, with design rationale, in docs/RISKS_AND_FINDINGS.md.
>
> Implement in small, buildable units where possible; write tests for individual behaviors. Isolate AppleScript in a bridge and provide Music.app/camera mocks. Do not circumvent DRM or use undocumented APIs.
>
> **Required later feature:** Re-create the actual fifth-generation **Video Camera**: Mac front-camera preview on the device's 3D screen, center-button start/stop, 640x480 target 30 fps H.264/AAC output, and Camera Roll playback. **Do not build still photography.** Phase 3.5 is mandatory.
>
> Once Phase 0 work is done, report changes, tests, known risks, and prerequisites for the next phase. Continue to later phases only when explicitly requested. If Xcode or a physical Mac is absent, **do not claim hardware validation**; provide the outstanding checks and the commands/steps required on macOS.

## 17A. Codex Cloud vs Local Mac: Division of Work

- **Codex Cloud:** Architecture, Swift source, mocks, testable pure state machines and algorithms, generative model source, README, CI configuration, PRs. GitHub is the source of truth.
- **Local Mac:** Xcode/macOS SDK builds; actual launch; transparent window/RealityKit; Music.app Apple Events permissions and audio playback; camera/microphone capture; measured output media metadata.
- Do not assume a standard Codex Cloud environment can access Xcode, a macOS GUI, or the Mac's physical devices. Writing Swift source in Cloud **does not prove the .app builds or works on macOS**.
- Mark evidence separately in docs/RISKS_AND_FINDINGS.md: **CLOUD_IMPLEMENTED**, **CLOUD_TESTED**, **LOCAL_MAC_VERIFIED**, or **BLOCKED_LOCAL_MAC**.
- Feed Xcode errors, console logs, and minimal reproduction steps from the Mac back to Codex for fixes. Codex desktop/CLI/IDE may help locally.
- Track Cloud results separately from physical acceptance tests in every phase. This project **cannot be certified complete solely through Codex Cloud**.

## 18. References

- Apple — Identify your iPod model: https://support.apple.com/en-us/103823
- Apple — Fifth-generation iPod nano documentation: https://support.apple.com/ja-jp/docs/ipod/132643
- Apple — Fifth-generation iPod nano User Guide (Chapter 5, Video Camera, H.264/AAC): https://cdsassets.apple.com/live/6GJYWVAV/user/ma1194_ipod_nano_5th_gen_userguide.pdf
- Apple — 2009 iPod nano announcement (VGA, H.264, approximate bitrate): https://www.apple.com/jp/newsroom/2009/09/09Apple-Introduces-New-iPod-nano-With-Built-in-Video-Camera/
- Apple — Redownload purchased music: https://support.apple.com/ja-jp/120552
- Apple — Music.app purchased music: https://support.apple.com/ja-jp/guide/music/mus3e2346c2/mac
- Apple — RealityView: https://developer.apple.com/documentation/realitykit/realityview/
- Apple — SceneKit migration: https://developer.apple.com/documentation/realitykit/bringing-your-scenekit-projects-to-realitykit
- Apple — NSWindow: https://developer.apple.com/documentation/appkit/nswindow
- Apple — NSAppleEventsUsageDescription: https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription
- Apple — Security entitlements: https://developer.apple.com/documentation/bundleresources/security-entitlements
- Apple — AVFoundation capture: https://developer.apple.com/documentation/avfoundation/capture_setup
- Apple — Camera/microphone usage descriptions: https://developer.apple.com/documentation/bundleresources/information-property-list
- OpenAI — Using Codex Cloud: https://help.openai.com/en/articles/20001545-using-codex-cloud
- OpenAI — Hosted environments: https://developers.openai.com/api/docs/guides/agents-api/environments/openai-hosted

**Note:** Numerical settings such as model size, wheel sensitivity, polling interval, and video bitrate are initial targets and must be validated. Music.app scripting, transparency, purchase metadata, camera recording capabilities, and privacy permissions remain **unverified on physical hardware** until Phase 0 tests demonstrate them.
