"""Exercise the macOS CLI installer without Homebrew, dialogs, or vault access."""

import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]


class OnePasswordQuarantine(unittest.TestCase):
    def check_installer(self, *, installed=True, quarantined=True, fail_clear=False, dry_run=False):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            binaries = folder / "bin"
            binaries.mkdir()
            events = folder / "events"
            events.touch()
            attribute = folder / "quarantine"
            if quarantined:
                attribute.touch()
            fixture = folder / "op-fixture"
            fixture.write_text(textwrap.dedent("""\
                #!/bin/bash
                if [ -f "$OP_TEST_ATTRIBUTE" ]; then
                    printf 'blocked-op\n' >> "$OP_TEST_EVENTS"
                    exit 99
                fi
                printf 'op\n' >> "$OP_TEST_EVENTS"
                printf '2.42.0\n'
                """))
            fixture.chmod(0o700)
            if installed:
                (binaries / "op").symlink_to(fixture)
            shell = textwrap.dedent("""\
                set -uo pipefail
                source "$1/lib/core.sh"
                source "$1/lib/packages.sh"
                source "$1/lib/apps.sh"
                PLATFORM=mac
                print_info() { :; }
                print_skip() { :; }
                print_ok() { :; }
                print_warn() { :; }
                print_error() { :; }
                spinner_run() {
                    shift
                    [ "$DRY_RUN" = 1 ] && return 0
                    "$@"
                }
                homebrew_available() { return 0; }
                brew() {
                    printf 'install\n' >> "$OP_TEST_EVENTS"
                    cp "$OP_TEST_FIXTURE" "$OP_TEST_BIN/op"
                    touch "$OP_TEST_ATTRIBUTE"
                }
                xattr() {
                    if [ "$1" = -dr ]; then
                        printf 'clear\n' >> "$OP_TEST_EVENTS"
                        [ "$OP_TEST_FAIL_CLEAR" = 1 ] && return 1
                        rm "$OP_TEST_ATTRIBUTE"
                    elif [ -f "$OP_TEST_ATTRIBUTE" ]; then
                        printf 'com.apple.quarantine\n'
                    fi
                    return 0
                }
                install_1password_cli_macos
                result=$?
                printf 'result=%s failures=%s installed=%s skipped=%s\n' \
                    "$result" "$VALIDATED_FAIL" "$INSTALLED_PACKAGES" "$SKIPPED_PACKAGES"
                """)
            env = dict(os.environ, PATH=str(binaries) + ":/usr/bin:/bin",
                       OP_TEST_EVENTS=str(events), OP_TEST_ATTRIBUTE=str(attribute),
                       OP_TEST_FIXTURE=str(fixture), OP_TEST_BIN=str(binaries),
                       OP_TEST_FAIL_CLEAR=str(int(fail_clear)), DRY_RUN=str(int(dry_run)))
            result = subprocess.run(["/bin/bash", "-c", shell, "test", str(ROOT)],
                                    env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout.strip(), events.read_text().splitlines(), attribute.exists()

    def test_existing_quarantined_cli_is_cleared_before_version_probe(self):
        status, events, quarantined = self.check_installer()
        self.assertEqual(events, ["clear", "op"])
        self.assertEqual(status, "result=0 failures=0 installed=0 skipped=1")
        self.assertFalse(quarantined)

    def test_existing_clean_cli_needs_no_attribute_write(self):
        status, events, _ = self.check_installer(quarantined=False)
        self.assertEqual(events, ["op"])
        self.assertIn("result=0 failures=0", status)

    def test_clear_failure_does_not_launch_cli(self):
        status, events, quarantined = self.check_installer(fail_clear=True)
        self.assertEqual(events, ["clear"])
        self.assertEqual(status, "result=1 failures=1 installed=0 skipped=0")
        self.assertTrue(quarantined)

    def test_dry_run_neither_clears_nor_launches_cli(self):
        status, events, quarantined = self.check_installer(dry_run=True)
        self.assertEqual(events, [])
        self.assertEqual(status, "result=0 failures=0 installed=0 skipped=1")
        self.assertTrue(quarantined)

    def test_fresh_install_still_clears_before_version_probe(self):
        status, events, quarantined = self.check_installer(installed=False)
        self.assertEqual(events, ["install", "clear", "op"])
        self.assertEqual(status, "result=0 failures=0 installed=1 skipped=0")
        self.assertFalse(quarantined)


if __name__ == "__main__":
    unittest.main()
