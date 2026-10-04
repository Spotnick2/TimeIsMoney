"""Validate the packager archive without extracting paths."""
import sys
from pathlib import Path, PurePosixPath
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent.parent
ADDON = "TimeIsMoney"

# The embedded LibGlass-1.0 (a .pkgmeta external): its XML is the TOC line, and the
# archive holds exactly the files it ships (LibGlass docs/GLASS-MATERIAL.md).
LIBGLASS = "Libs/LibGlass-1.0"
LIBGLASS_FILES = ["LibGlass-1.0.xml", "LibGlass.lua", "LibStub/LibStub.lua", "LICENSE"] + [
    f"Media/{name}.tga" for name in (
        "bar_edge", "bar_fill", "bar_mask", "body_mask", "body_mask_small", "gloss", "grain", "rim5",
        "rim5_small", "rim_dark5", "rim_dark5_small", "shadow", "shadow_small", "sheen2", "track_fade")]


def check(path):
    inputs = set()
    for line in (ROOT / f"{ADDON}.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip().replace("\\", "/")
        if line and not line.startswith("#"):
            parsed = PurePosixPath(line)
            if parsed.is_absolute() or ".." in parsed.parts or ":" in line:
                raise ValueError(f"unsafe TOC input: {line}")
            if not (ROOT / line).is_file():
                raise ValueError(f"missing TOC input: {line}")
            if line.startswith(LIBGLASS + "/"):
                if line != f"{LIBGLASS}/LibGlass-1.0.xml":
                    raise ValueError(f"unexpected library TOC input: {line}")
                inputs |= {f"{ADDON}/{LIBGLASS}/{name}" for name in LIBGLASS_FILES}
            else:
                inputs.add(f"{ADDON}/{line}")
    expected = inputs | {f"{ADDON}/{ADDON}.toc", f"{ADDON}/LICENSE"}
    media = ROOT / "Media"
    if media.exists():
        expected |= {
            f"{ADDON}/{p.relative_to(ROOT).as_posix()}"
            for p in media.rglob("*")
            if p.is_file() and p.suffix.lower() in {".tga", ".blp", ".ogg"}
        }
    with ZipFile(path) as archive:
        names = [entry.filename for entry in archive.infolist() if not entry.is_dir()]
        if len(names) != len(set(names)):
            raise ValueError("duplicate archive entries")
        actual = set(names)
        if actual != expected:
            raise ValueError(f"missing={sorted(expected - actual)}; extra={sorted(actual - expected)}")
        manifest = archive.read(f"{ADDON}/{ADDON}.toc").decode("utf-8-sig")
        versions = [line.split(":", 1)[1].strip()
                    for line in manifest.splitlines() if line.startswith("## Version:")]
        if len(versions) != 1 or versions[0] in {"", "dev", "@project-version@"}:
            raise ValueError(f"unsubstituted or invalid release version: {versions}")
    print(f"package: exact {len(expected)} files and substituted version verified")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python Tools/check_package.py <release.zip>")
    check(sys.argv[1])
