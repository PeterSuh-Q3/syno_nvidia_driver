#!/usr/bin/env python3
"""Generate the release manifest for the split K5 NVIDIA 580/595 layers."""
import hashlib
import json
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "out/release-assets-nvidia"
OUT = ROOT / "nvidia-layer-index.json"
PLATFORMS = ("epyc7002", "epyc7003", "geminilakenk", "icelaked", "r1000nk", "v1000nk")
VERSIONS = {
    "580.173.02": {"branches": ("open", "proprietary"), "dir": "kver5-580"},
    "595.99.02": {"branches": ("open", "proprietary"), "dir": "kver5-595"},
}


def layer(path: Path) -> dict:
    if not path.is_file():
        raise SystemExit(f"missing asset: {path}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return {"file": path.name, "sha256": digest}


manifest = {"schema": 1, "kernel": "5.10.55", "drivers": {}}
for version, cfg in VERSIONS.items():
    entry = {"platforms": {}, "userspace": None, "gsp": None, "ffmpeg": None}
    for platform in PLATFORMS:
        entry["platforms"][platform] = {
            flavor: layer(ASSETS / f"{cfg['dir']}-{flavor}" / f"nv-ko-{version}-{flavor}-{platform}-51055.tgz")
            for flavor in cfg["branches"]
        }
    # Userspace and GSP are platform/flavor-independent. Read their single
    # canonical archive from shared/<major>, not duplicated flavor directories.
    for key, filename in (("userspace", f"nv-userspace-{version}.tgz"), ("gsp", f"nv-gsp-{version}.tgz")):
        entry[key] = layer(ASSETS / "shared" / version.split(".", 1)[0] / filename)
    with tarfile.open(ASSETS / "shared" / version.split(".", 1)[0] / f"nv-gsp-{version}.tgz", "r:gz") as archive:
        entry["gsp"]["chips"] = sorted(
            name.rsplit("/", 1)[-1]
            for name in archive.getnames()
            if name.rsplit("/", 1)[-1].startswith("gsp_") and name.endswith(".bin")
        )
    ffmpeg = ASSETS / "shared/optional" / f"nv-ffmpeg-{version}.tgz"
    entry["ffmpeg"] = layer(ffmpeg) if ffmpeg.is_file() else None
    manifest["drivers"][version] = entry

OUT.write_text(json.dumps(manifest, indent=2) + "\n")
print(f"wrote {OUT}")
