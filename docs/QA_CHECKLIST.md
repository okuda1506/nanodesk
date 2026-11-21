# Mac validation for the desktop preview

Use an Apple Silicon MacBook Air M3 with macOS 15 or later. Record the macOS and Xcode versions and the tested commit. Build and run the **NanoDesk** scheme on **My Mac** following the [README](../README.md#run-the-desktop-preview).

- [ ] Launch from Xcode and show the device from the NanoDesk status item. Confirm the front faces the viewer and the window has no border, title, background, drop shadow, floor or extra UI. Repeat over a light Finder window, dark content and the desktop wallpaper. Check outlines for black and white fringes at Retina scale.
- [ ] Use the housing to turn through 360° horizontally and vertically. Inspect the rear camera, both sides, top Hold switch and bottom ports at 45° and at full rotation. Check stable pivot, no clipping and no release inertia. Reset from the menu and by double-click.
- [ ] Drag the front wheel. It should remain reserved. Shift-drag the wheel and drag the same region from the rear to verify body rotation. In **Click Through** mode, verify that another app underneath receives clicks and that the menu can restore interaction.
- [ ] Option-drag between displays with different scale factors. Enlarge and shrink with Command-scroll, pinch and the menu. Restart and verify retained position, size, layering and click-through. Disconnect the display and check that the device is still fully visible. Test show, hide, always on top and quit.
- [ ] Compare front and approximately 45° screenshots to the approved [front](../assets/renders/tone_review/front.png) and [45° render](../assets/renders/tone_review/front_45.png). Capture rear and side angles too. Check silhouette, silver gradient, dark wheel and screen, and the absence of narrow bright reflection bands. Use similar apparent size and record differences in reflection, exposure and tone mapping before changing app lighting.
- [ ] Check rotation and idle responsiveness in Instruments if the renderer stutters or keeps drawing while hidden. Capture Xcode errors, missing entity names or the startup alert if the model fails to load.

Record local results in [findings](RISKS_AND_FINDINGS.md). If the desktop shows a rectangle, test the zero-alpha clear and layer compositing before adjusting lighting or editing the asset.
