"""Exercise release selection, noninteractive skips, and application rollback offline."""

import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("studio", ROOT / "lib/proxmark_studio.py")
studio = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(studio)


class StudioInstaller(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.app = self.folder / "Proxmark Studio.app"
        self.state = self.folder / "state/release.json"
        self.image = b"verified release image"
        self.digest = hashlib.sha256(self.image).hexdigest()
        self.metadata = {"tag_name": "v0.0.18", "draft": False, "prerelease": False,
                         "assets": [self.asset("arm64"), self.asset("x64")]}
        self.downloads = []
        self.commands = []
        self.fail_copy = False
        self.bad_bundle = False
        self.linker_only = False
        self.open_checks = iter([False, False])
        for target, replacement in [("download", self.download), ("run", self.fake_run),
                                    ("running", lambda app: next(self.open_checks)),
                                    ("platform.machine", lambda: "arm64")]:
            mock = patch.object(studio, target, replacement) if "." not in target else patch.object(studio.platform, "machine", replacement)
            mock.start()
            self.addCleanup(mock.stop)

    def asset(self, architecture):
        name = "ProxmarkStudio-0.0.18-macos-{}.dmg".format(architecture)
        return {"name": name, "browser_download_url": studio.REPOSITORY + "/releases/download/v0.0.18/" + name,
                "digest": "sha256:" + self.digest}

    def bundle(self, path, version="0.0.17", payload="old application"):
        (path / "Contents/MacOS").mkdir(parents=True)
        (path / "Contents/MacOS/proxmark-studio").write_text(payload)
        (path / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": studio.IDENTIFIER,
            "CFBundleShortVersionString": version, "CFBundleExecutable": "proxmark-studio"}))

    def download(self, url, path):
        self.downloads.append(url)
        path.write_bytes(json.dumps(self.metadata).encode() if url == studio.API else self.image)

    def fake_run(self, *args, check=True):
        self.commands.append(tuple(str(arg) for arg in args))
        if args[0] == "ditto":
            if self.fail_copy:
                raise OSError("copy failed")
            self.bundle(args[2], "9.9.9" if self.bad_bundle else "0.0.18", "new application")
        if args[:2] == ("codesign", "--verify") and self.linker_only:
            return subprocess.CompletedProcess(args, 1, "", "unsealed bundle")
        if args[:2] == ("codesign", "-dv"):
            return subprocess.CompletedProcess(args, 0, "", "Signature=adhoc")
        if args[:2] == ("codesign", "--force"):
            self.linker_only = False
        return subprocess.CompletedProcess(args, 0, "", "")

    def update(self, **options):
        return studio.update(self.app, self.state, **options)

    def test_selects_exact_architecture_and_rejects_development_or_bad_assets(self):
        self.assertIn("macos-x64.dmg", studio.release_asset(self.metadata, "x86_64")[1])
        for field, value in [("prerelease", True), ("draft", True), ("tag_name", "latest")]:
            bad = dict(self.metadata, **{field: value})
            with self.assertRaises(ValueError):
                studio.release_asset(bad, "arm64")
        for field, value in [("browser_download_url", "https://example.com/download"), ("digest", "")]:
            bad = dict(self.metadata, assets=[dict(self.asset("arm64"), **{field: value})])
            with self.assertRaises(ValueError):
                studio.release_asset(bad, "arm64")

    def test_dry_run_no_upgrade_and_running_skip_without_network(self):
        self.assertIn("dry-run", self.update(dry_run=True))
        self.bundle(self.app)
        self.assertIn("no-upgrade", self.update(no_upgrade=True))
        self.open_checks = iter([True])
        self.assertIn("running", self.update())
        self.assertEqual(self.downloads, [])
        self.assertEqual(self.commands, [])

    def test_no_upgrade_still_installs_missing_app(self):
        self.assertTrue(self.update(no_upgrade=True).startswith("installed:"))
        self.assertEqual(studio.app_info(self.app)["CFBundleShortVersionString"], "0.0.18")

    def test_incomplete_adhoc_signature_is_sealed_before_installation(self):
        self.linker_only = True
        self.assertTrue(self.update().startswith("installed:"))
        self.assertFalse(self.linker_only)
        self.assertTrue(any(command[:2] == ("codesign", "--force") for command in self.commands))

    def test_successful_update_is_idempotent_and_never_opens_app_or_device(self):
        self.bundle(self.app)
        self.assertTrue(self.update().startswith("updated:"))
        self.assertEqual(json.loads(self.state.read_text())["sha256"], self.digest)
        self.open_checks = iter([False])
        self.assertIn("is current", self.update())
        self.assertEqual(len(self.downloads), 3)  # metadata twice; image only once
        self.assertTrue(set(command[0] for command in self.commands) <= {"hdiutil", "ditto", "xattr", "lipo", "codesign"})

    def test_newer_installed_release_is_not_downgraded(self):
        self.bundle(self.app, version="1.0.0")
        self.assertIn("newer", self.update())
        self.assertEqual(self.downloads, [studio.API])

    def test_bad_checksum_leaves_existing_app_and_state_intact(self):
        self.bundle(self.app)
        self.metadata["assets"][0]["digest"] = "sha256:" + "0" * 64
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            self.update()
        self.assertEqual((self.app / "Contents/MacOS/proxmark-studio").read_text(), "old application")
        self.assertFalse(self.state.exists())
        self.assertEqual(self.commands, [])

    def test_bad_bundle_or_failed_copy_keeps_previous_installation(self):
        for failure in ("bad_bundle", "fail_copy"):
            with self.subTest(failure=failure):
                if not self.app.exists():
                    self.bundle(self.app)
                setattr(self, failure, True)
                self.open_checks = iter([False, False])
                with self.assertRaises((ValueError, OSError)):
                    self.update()
                self.assertEqual(studio.app_info(self.app)["CFBundleShortVersionString"], "0.0.17")
                self.assertFalse(self.state.exists())
                setattr(self, failure, False)

    def test_app_opened_during_download_defers_replacement(self):
        self.bundle(self.app)
        self.open_checks = iter([False, True])
        self.assertIn("deferred", self.update())
        self.assertEqual(studio.app_info(self.app)["CFBundleShortVersionString"], "0.0.17")
        self.assertFalse(self.state.exists())

    def test_failed_state_commit_restores_previous_app_and_record(self):
        self.bundle(self.app)
        self.state.parent.mkdir()
        self.state.write_text('{"previous": true}')
        with patch.object(Path, "replace", side_effect=OSError("state write failed")):
            with self.assertRaisesRegex(OSError, "state write failed"):
                self.update()
        self.assertEqual(studio.app_info(self.app)["CFBundleShortVersionString"], "0.0.17")
        self.assertEqual(json.loads(self.state.read_text()), {"previous": True})
        self.assertEqual(list(self.folder.glob(".proxmark-studio-*")), [])


class BootstrapIntegration(unittest.TestCase):
    def test_bash_wrapper_with_default_and_optional_flags(self):
        for dry_run, upgrade, flags in [("0", "1", ""), ("1", "0", " --dry-run --no-upgrade")]:
            with self.subTest(dry_run=dry_run, upgrade=upgrade):
                result = subprocess.run(["/bin/bash", "-c", '''
                    set -uo pipefail
                    DOTFILES_DIR="$1"
                    source "$1/lib/core.sh"
                    source "$1/lib/apps.sh"
                    PLATFORM=mac
                    DRY_RUN="$2"
                    UPGRADE_PACKAGES="$3"
                    print_info() { :; }
                    print_skip() { printf '%s\\n' "$1"; }
                    python3() { printf 'skipped: %s\\n' "$*"; }
                    install_or_update_proxmark_studio
                ''', "test", str(ROOT), dry_run, upgrade], capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "skipped: " + str(ROOT / "lib/proxmark_studio.py") + flags)


if __name__ == "__main__":
    unittest.main()
