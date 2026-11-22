# NanoDesk

English · [日本語](README.ja.md) · [한국어](README.ko.md)

NanoDesk brings a silver fifth-generation iPod nano to the Mac desktop as an interactive 3D model. Its Japanese interface browses and controls Music.app, displays albums in Cover Flow, and records video with the Mac camera.

## Install on macOS

You need an Apple Silicon Mac running macOS 15 or later, Git, and Xcode 16 or later. Install Xcode and open it once to complete setup.

```bash
git clone https://github.com/okuda1506/nanodesk.git
cd nanodesk
./scripts/install-macos.sh
```

The script builds and locally signs the Release version, installs it at `~/Applications/NanoDesk.app`, and launches it. To open it again, go to your home folder in Finder, open **Applications**, and double-click **NanoDesk**. The app's controls are in the **NanoDesk** menu-bar menu. To update, quit NanoDesk, move the existing app bundle out of that folder, and rerun the script from the updated checkout.

## Controls

| Action | How to |
|---|---|
| Browse and select | Drag around the click wheel to scroll, click its center to select, and click **MENU** to go back. |
| Rotate and move | Drag the housing to rotate. Option-drag to move the device. Double-click the housing or choose **Reset Orientation** to face front. |
| Resize | Pinch, Command-scroll, or choose **Increase Size**, **Decrease Size**, or **Reset Size**. |
| Manage the desktop view | Use the menu bar to show or hide the device, reset its position, toggle **Always on Top** or **Click Through**, or quit. Turn off **Click Through** to interact with the device. |
| Lock the click wheel | Rotate to see the top edge and click the Hold switch. The orange strip indicates that wheel input and rotation-triggered Cover Flow changes are locked. Click again to unlock. Music continues playing. |

## Play music

Songs you buy from the iTunes Store appear under **曲** (Songs) on the NanoDesk iPod once they’re in your Mac’s Music library. Reopen **曲** to see newly added songs.

Open **ミュージック** (Music) → **曲** (Songs). Allow NanoDesk to control Music in the macOS Automation prompt. Scroll to a playable song in your Music library and press center to open **再生中** (Now Playing). Selecting the current song opens its playback screen at the current position. The bottom, left, and right wheel buttons control play/pause, previous, and next even while browsing. If access was denied, enable Music under **System Settings → Privacy & Security → Automation → NanoDesk**, then reopen **曲**.

## Browse albums in Cover Flow

From the home, music, songs, or Now Playing screen, rotate the device sideways with a two-finger twist or Command-drag. You can also select **ミュージック → Cover Flow**. Turn the wheel to browse albums by artist. Move quickly to jump by initial. Press center to open an album, then select a track and press center to play. Rotate upright to return.

## Record video

Select **ビデオカメラ** (Video Camera) from the home menu and grant camera access. Grant microphone access to record sound. Press center to start and again to stop and save. A red dot and timer indicate recording. **MENU** returns home and finalizes an active recording.

Choose **Open Camera Roll in Finder** in the NanoDesk menu to find your clips in **Movies/NanoDesk/Camera Roll**. Video is saved as H.264 MP4 at 640 × 480 and targets 30 fps, with AAC audio when the microphone is available. The portrait preview is mirrored. Saved video is landscape and unmirrored.

NanoDesk is an unofficial fan project. Apple does not endorse it.
