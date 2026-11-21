#!/usr/bin/env python3
"""Fetch specifically licensed Wikimedia Commons photographs for local modeling.

This utility only downloads files to assets/references/photos/. It never commits
files, installs packages, changes network policy, or handles credentials.

Use it on a trusted Mac with Wikimedia Commons access. HTTP 403 is reported as
an error; it is not circumvented.
"""
import json
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = pathlib.Path(__file__).resolve().parents[1]
DEST = BASE / "assets" / "references" / "photos"
API = "https://commons.wikimedia.org/w/api.php"
MAX_BYTES = 12 * 1024 * 1024
FILES = {
    "IPod-Nano-5G-front-back.png": "nano5_front_back.png",
    "IPod-Nano-5G-front.png": "nano5_front.png",
    "IPod-Nano-5G-back.png": "nano5_back.png",
    "IPod-nano-5G-camera-view-1.png": "nano5_camera.png",
}
HEADERS = {"User-Agent": "NanoDeskReferenceTool/1.0 (personal modeling reference)"}


def fetch(url):
    request = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(request, timeout=30) as response:
        actual = urllib.parse.urlparse(response.geturl())
        if actual.scheme != "https" or actual.hostname not in (
            "commons.wikimedia.org", "upload.wikimedia.org"
        ):
            raise RuntimeError("Unexpected download host: " + str(actual.hostname))
        data = response.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise RuntimeError("Download exceeds the 12 MiB safety limit")
        return data


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    failures = []
    for source_name, output_name in FILES.items():
        print("Retrieving:", source_name)
        args = urllib.parse.urlencode(
            {"action": "query", "format": "json", "prop": "imageinfo",
             "iiprop": "url", "titles": "File:" + source_name}
        )
        try:
            raw = fetch(API + "?" + args)
            result = json.loads(raw)
            pages = result["query"]["pages"]
            info = next(iter(pages.values()))["imageinfo"][0]
            url = info["url"]
            parsed = urllib.parse.urlparse(url)
            if parsed.scheme != "https" or parsed.hostname != "upload.wikimedia.org":
                raise RuntimeError("Refusing unexpected image host")
            data = fetch(url)
            if not data.startswith(b"\x89PNG\r\n\x1a\n"):
                raise RuntimeError("Not a PNG file")
            (DEST / output_name).write_bytes(data)
            print("Saved:", str(DEST / output_name), len(data), "bytes")
        except (urllib.error.URLError, OSError, ValueError, KeyError, RuntimeError) as exc:
            failures.append(source_name)
            print("FAILED:", str(exc), file=sys.stderr)
    print("Attribution and licenses:", DEST / "README.md")
    if failures:
        print("Some downloads failed; no access restrictions were bypassed.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
