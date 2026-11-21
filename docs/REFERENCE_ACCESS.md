# Reference Access Recovery — Codex Cloud HTTP 403

## Why this exists

During first 3D modeling in Codex Cloud, the external photo hosting and engineering drawing URLs listed in `docs/3D_MODEL_REFERENCES.md` returned **HTTP 403**. At that time the repository contained links only. **Four user-supplied reference photographs have since been committed locally** in `assets/references/photos/`; the Apple engineering drawing remains external-only.

**Reference quality is the highest priority of the NanoDesk project. Do not declare a faithful model complete without inspecting the images.**

## Reference availability check

Before geometry refinement, check:

1. Open and inspect the actual pixels of `assets/references/photos/nano5_front_back.png`, `nano5_front.png`, `nano5_back.png`, and `nano5_camera.png` (do not rely only on file names).
2. If not, can images attached to the current Codex task be opened? Record their filenames.
3. Can the original fifth-generation Figure 16-64 mechanical drawing be viewed? It may be attached separately by the user rather than redistributed in the public repo.
4. Log available/unavailable items in a findings document as `VERIFIED_REFERENCE`, `BLOCKED_REFERENCE_IMAGES`, or `BLOCKED_DIMENSIONAL_DRAWING`.

## Existing locally committed images and optional fallback

**Codex should prioritize the four committed images and should not attempt external downloads of those four photos.** If a local file is unavailable in the task's working tree, update from `main` or attach the file to the task. Source pages for attribution:

- Front/back composite: https://commons.wikimedia.org/wiki/File:IPod-Nano-5G-front-back.png
- Front: https://commons.wikimedia.org/wiki/File:IPod-Nano-5G-front.png
- Back: https://commons.wikimedia.org/wiki/File:IPod-Nano-5G-back.png
- Rear camera detail: https://commons.wikimedia.org/wiki/File:IPod-nano-5G-camera-view-1.png
- Fifth-generation dimensional drawing: Figure 16-64, section 16.59 in the document linked from `docs/3D_MODEL_REFERENCES.md`.

If the local files cannot be opened even after updating the working tree, attach the image files directly to the Codex task. Keep the names and attribution visible.

**For repeatable future tasks:** Four licensed photo references are already committed to `assets/references/photos/` with attribution. Keep those copyright notices. Do not publicly commit the Apple-authored drawing without permission. If access to Figure 16-64 is blocked, request a direct task attachment or report the drawing as unverified.

## Optional Mac-local acquisition helper (usually unnecessary now)

A standard-library-only script is available at `scripts/fetch_reference_photos.py`. Run it **on your own Mac** only when you have approved downloading these files and local access to Wikimedia Commons is permitted:

```bash
python3 scripts/fetch_reference_photos.py
```

It downloads the four curated Wikimedia source photos, validates basic PNG headers and the download origin, and stores them in `assets/references/photos/`. It does **not** automatically commit or push anything. Review the downloaded files and their license before committing them.

**The script does not bypass HTTP 403** and may fail in Codex Cloud. Do not loosen Cloud internet policies to make it work automatically.

## Allowed progress without visual sources

- Validate official device exterior: **90.7 x 38.7 x 6.2 mm**.
- Work on repeatable bpy mesh construction, object organization, basic PBR shading, orthographic render setup.
- Produce **provisional blockout** renders and explicitly label all visually unverified features.
- Delay final screen/wheel/camera coordinates, detailed shell curvature, photorealism claims, and user acceptance until actual visual sources are inspected.

## User-facing next step

If all remote photo/drawing sources remain blocked and no local assets exist, **ask the user for files** and report exactly what is unavailable. This is not a failure of the Swift or Blender setup.
