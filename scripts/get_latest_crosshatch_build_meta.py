#!/usr/bin/env python3

import json
import sys
import urllib.request


def main() -> int:
    url = "https://download.lineageos.org/api/v2/devices/crosshatch/builds"
    with urllib.request.urlopen(url, timeout=30) as response:
        builds = json.load(response)

    if not isinstance(builds, list) or not builds:
        raise SystemExit("no builds returned by Lineage API")

    latest = builds[0]
    files = latest.get("files", [])
    ota = next((f for f in files if f.get("filename", "").endswith("-signed.zip")), None)
    boot = next((f for f in files if f.get("filename") == "boot.img"), None)
    if ota is None:
        raise SystemExit("latest build is missing signed ota zip metadata")

    meta = {
        "device": "crosshatch",
        "version": latest["version"],
        "date": latest["date"],
        "date_stamp": latest["date"].replace("-", ""),
        "filename": ota["filename"],
        "url": ota["url"],
        "os_patch_level": latest["os_patch_level"],
        "os_patch_month": latest["os_patch_level"][:7],
        "boot_url": boot["url"] if boot else "",
        "release_tag": f"crosshatch-{latest['date'].replace('-', '')}",
    }
    json.dump(meta, sys.stdout, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
