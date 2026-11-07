"""Safety guards for the manual updater; never opens a device or invokes Homebrew."""

from contextlib import ExitStack, nullcontext
import importlib.machinery
import importlib.util
from pathlib import Path
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "proxmark-update"
loader = importlib.machinery.SourceFileLoader("proxmark_update", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
updater = importlib.util.module_from_spec(spec)
loader.exec_module(updater)

VERSION = """ [ Client ]
  Iceman/master/v4.23346-282-g992811293-suspect 2026-11-07 13:03:05 f9d0f1f89
 [ Model ]
  Firmware.................. PM5
 [ ARM ]
  OS......... Iceman/HEAD/v4.23346-282-g992811293-suspect 2026-11-07 08:25:05 f9d0f1f89
  --= Nonvolatile Program Memory Size: 1024 KB, Used: 374795 bytes (36%)
  --= Processor Unique ID: 0x123456789ABC
"""


def elf(address=0x08004000, payload=b"firmware"):
    header = struct.pack("<16sHHIIIIIHHHHHH", b"\x7fELF\x01\x01" + b"\0" * 10,
                         2, 40, 1, address, 52, 0, 0, 52, 32, 1, 0, 0, 0)
    program = struct.pack("<IIIIIIII", 1, 84, address, address, len(payload), len(payload), 5, 4)
    return header + program + payload


class FirmwareGuards(unittest.TestCase):
    def test_unknown_model_memory_or_identity_is_rejected(self):
        for invalid in (VERSION.replace("PM5", "GENERIC"), VERSION.replace("1024 KB", "512 KB"),
                        VERSION.replace("Processor Unique ID", "No unique ID")):
            with self.subTest(invalid=invalid), self.assertRaises(updater.Stop):
                updater.identify(invalid)

    def test_branch_label_does_not_require_false_reflash(self):
        self.assertTrue(updater.matching_versions(VERSION))
        self.assertFalse(updater.matching_versions(VERSION.replace("OS......... Iceman/HEAD/v4.23346-282-g992811293", "OS......... Iceman/HEAD/v4.23346-282-g111111111")))
        self.assertFalse(updater.matching_versions(VERSION.replace("08:25:05 f9d0f1f89", "08:25:05 111111111")))

    def test_bootloader_wrong_platform_and_truncated_images_are_rejected(self):
        device = updater.identify(VERSION)
        with tempfile.TemporaryDirectory() as folder:
            image = Path(folder) / "firmware.elf"
            for content in (elf(0x08000000), elf(0x00102000), elf(0x08100000), elf()[:-1]):
                image.write_bytes(content)
                with self.subTest(content=content[:20]), self.assertRaises(updater.Stop):
                    updater.load_segments(image, device)
            image.write_bytes(elf())
            segments = updater.load_segments(image, device)
            readback = Path(folder) / "readback.bin"
            memory = bytearray(device["bytes"])
            memory[0x4000:0x4008] = b"firmware"
            readback.write_bytes(memory)
            updater.verify_readback(readback, segments, device["bytes"])
            memory[0x4000] ^= 1
            readback.write_bytes(memory)
            with self.assertRaises(updater.Stop):
                updater.verify_readback(readback, segments, device["bytes"])

    def test_zero_or_multiple_usb_devices_never_selects_arbitrarily(self):
        with patch.object(updater, "run", return_value=""):
            self.assertIsNone(updater.usb_port("pm3"))
        with patch.object(updater, "run", return_value="1: /dev/tty.usbmodem1\n2: /dev/tty.usbmodem2"):
            with self.assertRaises(updater.Stop):
                updater.usb_port("pm3")


class TransactionGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.prefix = self.home / "homebrew"
        self.keg = self.prefix / "Cellar" / "proxmark3" / "HEAD-9928112"
        self.keg.mkdir(parents=True)
        (self.prefix / "opt").mkdir()
        (self.prefix / "opt" / "proxmark3").symlink_to(self.keg)
        self.receipt = {"used_options": ["--with-blueshark"], "source": {
            "spec": "head", "scm_revision": "a" * 40}}
        self.device = updater.identify(VERSION)

    def perform(self, check):
        updater.perform(SimpleNamespace(check=check), "brew", self.prefix, "pm3", "/dev/cu.usbmodem1",
                        self.keg, VERSION, self.device, {})

    def test_check_is_noop_with_current_client_and_firmware(self):
        calls = []
        def run(args, **kwargs):
            calls.append([str(arg) for arg in args])
            return "a" * 40 + "\tHEAD\n"
        with patch.object(updater, "read_json", return_value=self.receipt), \
                patch.object(updater, "run", side_effect=run), \
                patch.object(updater, "confirm") as confirm, \
                patch.object(updater, "snapshot") as snapshot:
            self.perform(True)
        self.assertEqual(calls, [["git", "ls-remote", updater.REPOSITORY, "HEAD"]])
        confirm.assert_not_called()
        snapshot.assert_not_called()

    def test_rejects_generic_configuration_before_any_update(self):
        self.receipt["used_options"].append("--with-generic")
        with patch.object(updater, "read_json", return_value=self.receipt), \
                patch.object(updater, "run") as run:
            with self.assertRaises(updater.Stop):
                self.perform(False)
        run.assert_not_called()

    def transaction_failure(self, fail_during_flash):
        calls = []
        image = self.home / "image.elf"
        image.write_bytes(elf())
        def run(args, **kwargs):
            calls.append([str(arg) for arg in args])
            if "outdated" in args:
                return '{"formulae":[{"name":"proxmark3"}]}'
            if "--flash" in args:
                raise updater.Stop("simulated flasher failure")
            return ""
        def read_flash(client, port, destination, size):
            destination.write_bytes(b"\0" * size)
        with ExitStack() as stack:
            stack.enter_context(patch.object(updater.Path, "home", return_value=self.home))
            stack.enter_context(patch.object(updater, "read_json", return_value=self.receipt))
            stack.enter_context(patch.object(updater, "run", side_effect=run))
            stack.enter_context(patch.object(updater, "confirm"))
            stack.enter_context(patch.object(updater, "snapshot", return_value={}))
            stack.enter_context(patch.object(updater, "read_flash", side_effect=read_flash))
            stack.enter_context(patch.object(updater, "python315_recipe", return_value=nullcontext()))
            stack.enter_context(patch.object(updater, "uninterrupted_flash", return_value=nullcontext()))
            stack.enter_context(patch.object(updater, "firmware_image", return_value=image))
            stack.enter_context(patch.object(updater, "usb_port", return_value="/dev/cu.usbmodem1"))
            stack.enter_context(patch.object(updater, "require_idle"))
            current = VERSION if fail_during_flash else VERSION.replace("0x123456789ABC", "0xDEADBEEF")
            stack.enter_context(patch.object(updater, "command", return_value=current))
            restore = stack.enter_context(patch.object(updater, "restore_client"))
            with self.assertRaises(updater.Stop):
                self.perform(False)
            self.assertEqual(restore.call_count, 0 if fail_during_flash else 1)
        self.assertEqual(calls[-1], ["brew", "pin", updater.FORMULA])
        self.assertEqual(any("--flash" in call for call in calls), fail_during_flash)

    def test_changed_device_prevents_flash_and_restores_previous_client(self):
        self.transaction_failure(False)

    def test_failed_flash_keeps_new_client_and_repins_it(self):
        self.transaction_failure(True)


if __name__ == "__main__":
    unittest.main()
