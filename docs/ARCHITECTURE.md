# Native desktop preview

## App and window

The Xcode app target builds the AppKit entry point and shared Swift interaction code. The Swift package exposes the same interaction code to tests on Linux and macOS. Both are dependency-free. The app target copies the tracked `assets/runtime/NanoModel.usdz` as a bundle resource. The app sandbox entitlement grants local bundle and preference access. The app declares an Automation usage description and permits Apple Events to Music.app only. It has no network client.

NanoDesk runs as an accessory app with a status item. `DesktopWindowController` owns a borderless, nonactivating `NSPanel` with clear background and no shadow. A menu toggles the floating level and whole-window mouse pass-through. The status item stays available when the panel ignores mouse events. In interactive mode, the window remains rectangular for event delivery. The model hit test limits gesture starts but cannot send a click to a different app below that window.

Placement uses the visible desktop frames in AppKit's global point coordinates. It starts near the bottom right of the main display. Resize keeps the center when the display has room. Placement chooses the display containing the center or the one with the largest intersection near a seam. If a display disappears, the placement falls back to a visible work area. Center, scale, layering and click-through are stored in sandboxed UserDefaults.

## Rendering

`DeviceScene` loads the USDZ hierarchy asynchronously with `Entity(contentsOf:)`. It validates the required named parts and meter-scale bounds and centers the asset under a separate rotation pivot. The approved mesh, materials and raw USDZ stay intact. The asset default prim is `Body`. The renderer preserves its hierarchy, labeling the loaded root `Body` if the importer aliases that prim to the asset name.

`RealityRenderer` (macOS 15) draws to the drawable of a nonopaque `CAMetalLayer`. The camera background has zero alpha, and the window uses an sRGB color space. The virtual camera sits 0.25 m along +Z, looking toward the origin with a 26° vertical field of view. The default 480-point square panel gives a front height of about 380 points and room for the extent of a full tilt. Multisample antialiasing is enabled. `DeviceCanvas` presents completed frames on the main actor, updates backing size at Retina scale, and coalesces drag updates to a single pending frame. Frames run on input, geometry changes and reveal.

A procedural, linear equirectangular map supplies the image-based light. Broad neutral sources around the object and a soft hemisphere fill shape the reflection without sharp light strips. The map feeds `RealityRenderer.lighting` only. It contributes no camera background, floor, light objects or shadow behind the device. Exposure stays in the scene's light intensity exponent, and SDR tone mapping is enabled. The map is generated from code on a background task. Unexpected opacity can be isolated from material issues by verifying the Metal drawable's clear background and comparing the panel over light and dark desktop content.

The approved visual baseline is [tone_review/front.png](../assets/renders/tone_review/front.png) and [tone_review/front_45.png](../assets/renders/tone_review/front_45.png), approved at commit `e841e92`. They keep the approved studio reflections and deepen the screen and wheel tones. The other render sets document earlier lighting comparisons. The app's physically based lighting can differ from Blender's image grading and Cycles reflections. Tune the app-side map and light exposure after Mac comparison while keeping the approved asset intact.

## Rotation and input

The view sends AppKit pointer events to the window controller. Screen-space yaw and pitch left-multiply the current unit quaternion, so either axis supports a full turn without Euler-angle limits. AppKit points are converted with +Y upward. The model rotates around its bounds center. Drag stops on mouse-up. Reset restores the identity orientation.

For a gesture's initial press, `DeviceScene` constructs a camera ray and transforms it into model coordinates. The CPU hit test uses the imported body's bounds and the front wheel's measured circle. The wheel is active when sufficiently front-facing. The hit test returns a normalized position on the wheel plane in device coordinates. The center occupies 49% of its radius, and the outer ring is divided into four directional sectors. Dragging the ring unwraps angles and scrolls with 15° steps after a three-point movement threshold. A short press must release in the same sector. Shift forces body rotation and Option-drag moves the window.

## Asset coordinates for later screen and wheel features

The USDZ uses meters with +Y up and +Z toward the viewer. Its axis-aligned bounds measure 38.7 × 90.7 × 6.2 mm in X, Y and Z. `ScreenSurface` is a separate front-facing curved mesh under `Body`. Its position is approximately X −15.03 to +15.03 mm, Y −6.60 to +40.50 mm, Z +2.18 to +3.10 mm. The face-varying `st` UV spans 0–1 with U increasing left to right and V increasing bottom to top on the front. A texture orientation pattern on the Mac should confirm the importer's vertical convention before display content is attached. The source display aspect is 240 × 376.

`CenterButton` is under `Body`. `MenuButton`, `PreviousButton`, `NextButton` and `PlayPauseButton` are children of `WheelRing`. Its center is about (0, −26.3, +3.09) mm at the front face and its radius is 13.55 mm. The front wheel now controls the music flow. Playlists and video capture are later phases.


## Japanese music screens and transport

`MusicSession` owns navigation, list selection, errors and playback state. The views are メニュー, ミュージック, 曲 and 再生中. The original navy and cyan interface uses system text, solid blue selection, two-line song rows, and an artwork square above the track information and progress bar. Its layout and styling are distinct from Apple's firmware. The user-supplied source index identifies Apple user-guide images and photographed screens. Those references informed screen size and interaction scope and remain outside the repository.

`MusicScreenRenderer` draws a 240 × 376 sRGB image into an explicitly opaque RGBA canvas. `DeviceScene` updates a reusable RealityKit texture as the primary color of an unlit material on `ScreenSurface` alone. This keeps the screen colors separate from scene lighting and tone mapping. The texture follows the existing UVs, rotates with the mesh and culls back faces. The bezel and other surfaces retain their imported materials. The rendering checks on Mac include vertical orientation, readability at an angle and no reverse-side display.

`MusicAppBridge` runs fixed AppleScript via macOS `/usr/bin/osascript` on a serial background queue. Track IDs go through arguments rather than script interpolation. It reads track IDs, titles and artists from the library container, checks that the chosen ID is playing, and uses a timed Music snapshot for position, duration and playback state. The app advances manually to adjacent listed songs and stops at the ends. The visible now-playing view polls about once a second while a track is selected. Status polling does not launch Music. Missing or unreadable cover art uses an original note glyph. The bridge stages only optional artwork in the app's temporary directory and removes it after use.

The app's sandbox exception names only `com.apple.Music`. The usage string explains read and playback access. System signing, the Automation prompt and the attribution of the helper process need a Mac check. The app never reads Music's audio paths or ships library data.
