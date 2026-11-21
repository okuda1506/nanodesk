# NanoDesk — Codex Repository Instructions

These instructions apply to all work in this repository. Read `docs/SPEC.md` before modifying source or 3D assets.

## Product priorities

1. **Highest priority: faithful 3D recreation of the fifth-generation (2009, A1320) iPod nano.** Form, silhouette, thickness, component placement, curvature and silver material quality matter more than decorative shortcuts or feature count.
2. The device must appear to float alone on a transparent, borderless macOS desktop surface; it is not a 3D view inside a conventional window.
3. Music.app integration and Video Camera are separate later features. The MVP has **video recording only, not still photography**.

## Mandatory reference verification gate for 3D modeling

Before making final geometric or visual fidelity claims, inspect all of:

- `docs/3D_MODEL_REFERENCES.md`
- `assets/references/ipod_nano_5g_dimensions.json`
- **Actual pixels** of front, back, and camera/edge reference photographs
- The fifth-generation mechanical drawing (Figure 16-64), or explicitly record that it is unavailable

**IMPORTANT: The Markdown guide currently embeds photographs from external domains; the binary photos are not included in the repo.** Links being present does not mean the images were successfully viewed. This was confirmed as a blocker when Codex Cloud received HTTP 403 fetching the photos/drawing.

- First check `assets/references/photos/` for locally committed, properly attributed photographs.
- If photographs are absent, first request that the user attach them directly in the Codex conversation or add licensed copies to the repository. See `docs/REFERENCE_ACCESS.md`.
- If images/drawing cannot be opened, mark them `BLOCKED_REFERENCE_IMAGES` / `BLOCKED_DIMENSIONAL_DRAWING` in a findings document.
- **Never claim that photo comparison, authentic appearance, or dimensional drawing validation succeeded unless the relevant source was actually inspected.**
- Blockout mesh creation, asset structure, deterministic geometry, and renders may continue with official verified outer dimensions, **but a photo-accurate final model and PR approval cannot be claimed** until missing references are available.
- Distinguish official measurements, checked drawing annotations, photographic estimates, and unknown dimensions. Never invent "official" dimensions.
- Produce front/back/left/right/top/bottom/45-degree renderings; compare them with the references before design approval.
- Deliver editable Blender source plus a reproducible Python generator when feasible. Do not substitute generated 2D illustrations for a real mesh.

## Privacy, public repository and external source rules

- The repository is **public**. Do not hardcode or commit API tokens, credentials, `.env` files, purchased music, recordings, or private data.
- External photos are separate licensed works. Only commit a photo after verifying its individual license, author, origin and required attribution. See `assets/references/photos/README.md`.
- Use the existing curated Wikimedia Commons sources, and preserve attribution and modification notes. Do not commit Apple's proprietary drawings, product photography, logo assets, or firmware extracts without permission.
- Do not bypass 403 responses, disable cloud security/network restrictions, or install arbitrary fetch helpers. Network access changes require explicit user approval.
- Never print secrets or dump the environment.
- Make changes in a branch and open a PR for Codex implementation work. Never auto-merge.
- Distinguish `CLOUD_IMPLEMENTED`, `CLOUD_TESTED`, `LOCAL_MAC_VERIFIED`, and `BLOCKED_LOCAL_MAC`. Swift on Linux does not validate a native macOS build.

## Immediate action if reference assets are missing

**Stop claiming high-fidelity modeling is verifiable.** Report which individual files could/could not be opened, continue only reversible blockout work, and request photo attachments. Do not silently work from inaccessible external images.
