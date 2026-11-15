import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("package_ipa", Path(__file__).parents[1] / "package-ipa.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class PackagingTests(unittest.TestCase):
    def app(self, root, platform):
        app = Path(root) / "Watchly.app"
        app.mkdir()
        (app / "Watchly").write_bytes(b"test fixture, not a real executable")
        (app / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "Watchly", "CFBundleSupportedPlatforms": [platform]
        }))
        return app

    def test_payload_structure(self):
        with tempfile.TemporaryDirectory() as root:
            app = self.app(root, "AppleTVOS")
            result = Path(root) / "test.ipa"
            module.package(app, result)
            with zipfile.ZipFile(result) as archive:
                self.assertIn("Payload/Watchly.app/Watchly", archive.namelist())
                self.assertIn("Payload/Watchly.app/Info.plist", archive.namelist())

    def test_rejects_simulator(self):
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(ValueError):
                module.package(self.app(root, "AppleTVSimulator"), Path(root) / "bad.ipa")

    def test_rejects_missing_executable(self):
        with tempfile.TemporaryDirectory() as root:
            app = self.app(root, "AppleTVOS")
            (app / "Watchly").unlink()
            with self.assertRaises(ValueError):
                module.package(app, Path(root) / "bad.ipa")

if __name__ == "__main__":
    unittest.main()
