"""Package a built tvOS app for a sideloading tool; does not sign it."""
from pathlib import Path
import plistlib
import stat
import sys
import zipfile

def package(app: Path, destination: Path) -> None:
    app = app.resolve(strict=True)
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if "AppleTVOS" not in info.get("CFBundleSupportedPlatforms", []):
        raise ValueError("Expected an AppleTVOS device build, not iOS or a simulator")
    executable = app / info["CFBundleExecutable"]
    if not executable.is_file():
        raise ValueError("Missing application executable")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(app.rglob("*")):
            relative = Path("Payload") / app.name / path.relative_to(app)
            if path.is_symlink():
                item = zipfile.ZipInfo(relative.as_posix())
                item.create_system = 3
                item.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(item, str(path.readlink()))
            elif path.is_file():
                archive.write(path, relative.as_posix())
    with zipfile.ZipFile(destination) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError(f"Corrupt IPA entry: {bad}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: package-ipa.py /path/Watchly.app /path/output.ipa")
    package(Path(sys.argv[1]), Path(sys.argv[2]))
