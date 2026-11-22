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

`MusicSession` supplies the Japanese menu items to both wheel input and drawing. On the 240 × 376 display, the home menu has a 20-pixel status bar, nine rows and three 80-pixel artwork tiles along the bottom. The music menu starts with Cover Flow and places 曲 sixth. Its list uses the full area below the status bar. The status bar shows a virtual battery icon. The selected row carries a blue gradient and a single white chevron. Selecting an unimplemented entry displays a Japanese notice on the same page.

The home artwork strip uses three original illustrations bundled in `MenuSleeves.jpg`. Once playback supplies usable cover art, it replaces the left tile in memory. Opening a menu can draw the strip before Music authorization. The attached reference images are used for comparison only.

The 曲 screen browses the whole loaded library. Beneath its silver status bar, twelve single-line rows fit on the display. At the top, a subdued シャッフル row precedes the first selectable track. The wheel moves a full-width blue highlight. A separate speaker marks the playing track by its Music persistent ID. The list checks playback while open and redraws when the track or transport state changes. A failed status check clears the marker and leaves the songs selectable.

Now Playing has a centered clock and playback status across the top. Artist, title and album sit above a 240-pixel artwork square. The square fits the whole cover and uses a pair of notes when artwork is missing or unreadable. A faint cover reflection sits behind the progress bar. Elapsed and remaining time flank the bar. The number below it is the current track's one-based position in NanoDesk's loaded song list. An external track without a known list position leaves this line empty. Shuffle and repeat symbols follow Music's settings. A long title scrolls while playing on a visible panel. Animation frames use the current snapshot without issuing Music commands.

`MusicScreenRenderer` draws a 240 × 376 sRGB image into an explicitly opaque RGBA canvas. `DeviceScene` updates a reusable RealityKit texture as the primary color of an unlit material on `ScreenSurface` alone. This keeps the screen colors separate from scene lighting and tone mapping. The texture follows the existing UVs, rotates with the mesh and culls back faces. The bezel and other surfaces retain their imported materials. The rendering checks on Mac include vertical orientation, readability at an angle and no reverse-side display.

`MusicAppBridge` runs fixed AppleScript inside NanoDesk via OSAKit on a serial background queue. Each command uses its own AppleScript language instance and reads structured Apple Event descriptors. Track IDs go through arguments rather than script interpolation. It reads track IDs, titles and artists from the library container, checks that the chosen ID is playing, and uses a timed Music snapshot for position, duration and playback state. The app advances manually to adjacent listed songs and stops at the ends. The visible now-playing view polls about once a second while a track is selected. Status polling does not launch Music. Missing or unreadable cover art uses an original note glyph. Optional artwork stays in memory.

The app's sandbox exception names only `com.apple.Music`. The usage string explains read and playback access. The bridge distinguishes Automation denial, missing Music, timeouts, script preparation errors and invalid replies. It reports the numeric AppleScript code when useful. System signing, the Automation prompt and real Music playback still need a Mac check. The app never reads Music's audio paths or ships library data.
