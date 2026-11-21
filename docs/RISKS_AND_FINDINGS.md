# Desktop preview findings

**CLOUD_IMPLEMENTED** · The preview is configured to load the approved USDZ with the macOS 15 RealityKit APIs in a borderless AppKit panel. The initial preview implements camera-facing setup, quaternion rotation, front reset, position and size controls, and menu-bar actions. The [architecture notes](ARCHITECTURE.md) identify the approved appearance baseline and the app-side lighting.

**CLOUD_TESTED** · Swift 6.4.3 on Linux ran five passing Swift Testing cases for 360° yaw and pitch, quaternion stability, front-only wheel reservation, monitor changes and preference round-tripping. The Cloud check parsed the Xcode project and scheme, app property lists and Swift sources. OpenUSD inspected the bundle source, default prim, coordinates, meter scale, part names and screen UVs. The Apple macOS 15.5 SDK declarations expose the RealityRenderer, asynchronous Entity and EnvironmentResource interfaces used by the preview.

**BLOCKED_LOCAL_MAC** · Xcode compile/link/sign, RealityKit's runtime entity import, GPU draw and transparent desktop compositing, input delivery, display transitions and the silver finish all require Mac validation. Use the [M3 checklist](QA_CHECKLIST.md) before treating the preview as verified.

A transparent view and a clear render background configure separate parts of compositing. If a dark rectangle or an outline appears, inspect alpha in the RealityKit drawable, then the color space and premultiplication at the Metal layer. A fix belongs in presentation while the approved asset is preserved. In interactive mode, AppKit reserves a rectangular window. Whole-window Click Through is the current documented solution. Test finer input delivery only if a public macOS API can support it.

RealityKit may import preview materials or grade highlights differently from Blender. Compare matched screenshots and adjust the procedural environment and intensity in the app. The front texture's import orientation and per-sector precision can be verified during the screen and click-wheel phase. Music.app integration, Automation, camera/microphone permissions and recording are deferred. The Cloud implementation does not close the full Phase 0 exit gate in the product specification.

## Trackpad pinch

**LOCAL_MAC_VERIFIED (user report)** · Command plus two-finger scrolling resized the device. Pinch in and out did not. The two inputs share `zoom(by:)`, so resize math alone does not explain the difference. The report does not establish whether the original responder callback `DeviceCanvas.magnify(with:)` was reached.

**CLOUD_IMPLEMENTED** · The canvas attaches an `NSMagnificationGestureRecognizer` and passes incremental scale factors to `zoom(by:)`. It leaves primary mouse events undelayed. The panel retains `.nonactivatingPanel` and `becomesKeyOnlyIfNeeded`, which govern activation and key focus. `acceptsFirstMouse(for:)` applies to mouse presses. It does not establish that a pinch reaches the canvas. The recognizer handles gestures delivered to its view. Event delivery to an inactive panel still needs to be checked on a Mac.

## Music flow

**LOCAL_MAC_VERIFIED (user report, previous build)** · The desktop preview built and ran on MacBook Air M3 under macOS 27.2.1 / Xcode 27.2, with the main desktop operations working. Trackpad pinch remains deferred.

**CLOUD_IMPLEMENTED** · Japanese menus and now-playing graphics are drawn to the existing 240 × 376 screen surface. The appearance is original. Wheel clicks and ring drags route to the Music flow. A background AppleScript bridge controls Music through the Mac's Automation permission.

**CLOUD_TESTED** · Portable Swift tests cover wheel angle direction and seam, press versus drag, front versus rear, bounded menu selection, zero/one/multiple tracks, permission denial, playback failure, artwork state, progress, pause/resume and returning with MENU. These tests use a mock Music service. The Swift bridge is type-checked on Linux. The Xcode project, entitlements and Swift syntax were inspected.

**BLOCKED_LOCAL_MAC** · Native build and launch, Music scripting and Automation from the hardened app, audible playback, artwork decoding, UV orientation, and display readability through glass still require the [Mac music QA](QA_CHECKLIST.md#mac-validation-for-the-music-flow).
