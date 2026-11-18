#!/usr/bin/env python3
"""Install tagged macOS Studio releases without opening a Proxmark device."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import tempfile


REPOSITORY = "https://github.com/RfidResearchGroup/ProxmarkStudio"
API = "https://api.github.com/repos/RfidResearchGroup/ProxmarkStudio/releases/latest"
APP = Path("/Applications/Proxmark Studio.app")
IDENTIFIER = "cn.forestweave.proxmarkstudio"


def run(*args, check=True):
    return subprocess.run([str(arg) for arg in args], check=check, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3600)


def download(url, destination):
    run("curl", "--fail", "--location", "--silent", "--show-error",
        "--connect-timeout", os.environ.get("DOTFILES_CURL_CONNECT_TIMEOUT_SEC", "25"),
        "--max-time", os.environ.get("DOTFILES_CURL_MAX_TIME_SEC", "3600"),
        "--output", destination, url)


def release_asset(metadata, architecture):
    tag = metadata.get("tag_name", "")
    if metadata.get("draft", True) or metadata.get("prerelease", True) or not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("GitHub did not return a tagged stable Studio release")
    arch = {"arm64": "arm64", "x86_64": "x64"}.get(architecture)
    if not arch:
        raise ValueError("Unsupported Mac architecture: " + architecture)
    name = "ProxmarkStudio-{}-macos-{}.dmg".format(tag[1:], arch)
    assets = [asset for asset in metadata.get("assets", []) if asset.get("name") == name]
    if len(assets) != 1:
        raise ValueError("No unique Studio release asset for this Mac")
    asset = assets[0]
    url = REPOSITORY + "/releases/download/" + tag + "/" + name
    digest = asset.get("digest", "")
    if asset.get("browser_download_url") != url or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise ValueError("Studio release URL or SHA-256 is missing/invalid")
    return tag[1:], url, digest[7:]


def app_info(app):
    with (app / "Contents/Info.plist").open("rb") as stream:
        return plistlib.load(stream)


def running(app):
    result = run("pgrep", "-f", re.escape(str(app) + "/Contents/MacOS/"), check=False)
    if result.returncode not in (0, 1):
        raise RuntimeError("Cannot determine whether Studio is running")
    return result.returncode == 0


def verify_bundle(app, version, architecture):
    info = app_info(app)
    if info.get("CFBundleIdentifier") != IDENTIFIER or info.get("CFBundleShortVersionString") != version:
        raise ValueError("Downloaded Studio bundle identity/version did not match the release")
    executable = info.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable:
        raise ValueError("Invalid Studio executable name")
    binary = app / "Contents/MacOS" / executable
    run("lipo", "-verify_arch", architecture, binary)
    # Releases are not notarized. The first release has only a linker signature;
    # seal that bundle using the same ad-hoc signing step now used by upstream CI.
    signature = run("codesign", "--verify", "--deep", "--strict", app, check=False)
    if signature.returncode:
        details = run("codesign", "-dv", app, check=False)
        if "Signature=adhoc" not in details.stderr and "not signed at all" not in details.stderr:
            raise RuntimeError("Unexpected invalid Studio signature: " + signature.stderr.strip())
        run("codesign", "--force", "--deep", "--sign", "-", app)
        run("codesign", "--verify", "--deep", "--strict", app)


def install_bundle(image, app, state, record, architecture):
    stage = Path(tempfile.mkdtemp(prefix=".proxmark-studio-", dir=str(app.parent)))
    mount = stage / "mount"
    mount.mkdir()
    incoming = stage / app.name
    previous = stage / "previous.app"
    mounted = False
    completed = False
    state_temp = None
    try:
        run("hdiutil", "attach", "-readonly", "-nobrowse", "-quiet", "-mountpoint", mount, image)
        mounted = True
        run("ditto", mount / "Proxmark Studio.app", incoming)
        run("hdiutil", "detach", "-quiet", mount)
        mounted = False
        # Do this before launching anything, and remove only this app's quarantine.
        attributes = run("xattr", incoming).stdout.splitlines()
        if "com.apple.quarantine" in attributes:
            run("xattr", "-dr", "com.apple.quarantine", incoming)
        verify_bundle(incoming, record["version"], architecture)
        if running(app):
            return "skipped: Studio was opened during the download; update deferred"
        state.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", dir=str(state.parent), delete=False) as stream:
            state_temp = Path(stream.name)
            json.dump(record, stream)
            stream.write("\n")
        existed = app.exists()
        if existed:
            app.rename(previous)
        try:
            incoming.rename(app)
            # Moving within /Applications preserves the verified bundle and its signature.
            state_temp.replace(state)
        except BaseException:
            if app.exists():
                app.rename(incoming)
            if previous.exists():
                previous.rename(app)
            raise
        completed = True
        return "{}: Proxmark Studio {}".format("updated" if existed else "installed", record["version"])
    finally:
        if mounted:
            result = run("hdiutil", "detach", "-quiet", mount, check=False)
            mounted = result.returncode != 0
        if state_temp is not None:
            state_temp.unlink(missing_ok=True)
        # Never delete a still-mounted filesystem or the only recoverable old app.
        if not mounted and (completed or not previous.exists()):
            shutil.rmtree(stage)
        else:
            print("Preserved installation files for recovery: " + str(stage))


def update(app, state, *, dry_run=False, no_upgrade=False):
    if app.is_symlink() or (app.exists() and not app.is_dir()):
        raise ValueError("Studio's application path must be a regular app directory")
    if no_upgrade and app.exists():
        return "skipped: Studio updates disabled by --no-upgrade"
    if dry_run:
        return "skipped: [dry-run] Would install/update Studio from the latest tagged release"
    if running(app):
        return "skipped: Studio is running; update deferred until a later bootstrap run"
    architecture = platform.machine()
    with tempfile.TemporaryDirectory(prefix="dotfiles-studio-") as temporary:
        temporary = Path(temporary)
        metadata = temporary / "release.json"
        download(API, metadata)
        version, url, digest = release_asset(json.loads(metadata.read_text()), architecture)
        record = {"version": version, "sha256": digest}
        if app.exists():
            info = app_info(app)
            if info.get("CFBundleIdentifier") != IDENTIFIER:
                raise ValueError("The existing application is not Proxmark Studio")
            installed = info.get("CFBundleShortVersionString", "")
            if re.fullmatch(r"\d+\.\d+\.\d+", installed) and tuple(map(int, installed.split("."))) > tuple(map(int, version.split("."))):
                return "skipped: Installed Studio is newer than the latest tagged release"
            try:
                previous = json.loads(state.read_text())
            except (OSError, ValueError):
                previous = None
            if installed == version and previous == record:
                return "skipped: Proxmark Studio {} is current".format(version)
        image = temporary / "studio.dmg"
        download(url, image)
        if hashlib.sha256(image.read_bytes()).hexdigest() != digest:
            raise ValueError("Studio download SHA-256 did not match GitHub; existing app left intact")
        return install_bundle(image, app, state, record, architecture)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--no-upgrade", action="store_true")
    options = parser.parse_args()
    state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "dotfiles/proxmark-studio.json"
    try:
        print(update(APP, state, dry_run=options.dry_run, no_upgrade=options.no_upgrade))
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
        print("Proxmark Studio installation failed: " + detail)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
