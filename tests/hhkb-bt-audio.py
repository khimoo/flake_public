import ctypes
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HEADER = Path(os.environ.get("HHKB_AUDIO_HEADER", ROOT / "packages/hhkb-bt-audio/descriptor.h"))
DESCRIPTOR = Path(os.environ.get("HHKB_AUDIO_DESCRIPTOR", ROOT / "tests/fixtures/hhkb-bt-report-descriptor.hex"))


def audio_fields(descriptor):
    globals_ = {0: 0, 7: 0, 8: 0, 9: 0}
    usages = []
    offsets = {}
    fields = {}
    offset = 0
    while offset < len(descriptor):
        prefix = descriptor[offset]
        size = (0, 1, 2, 4)[prefix & 3]
        value = int.from_bytes(descriptor[offset + 1:offset + 1 + size], "little")
        kind, tag = (prefix >> 2) & 3, prefix >> 4
        offset += size + 1
        if kind == 1:
            globals_[tag] = value
        elif kind == 2 and tag == 0:
            usages.append(value)
        elif kind == 0:
            if tag == 8:
                report = globals_[8]
                start = offsets.get(report, 0)
                if globals_[0] == 12 and value & 1 == 0:
                    for index, usage in enumerate(usages[:globals_[9]]):
                        fields[report, start + index * globals_[7]] = usage
                offsets[report] = start + globals_[7] * globals_[9]
            usages = []
    return fields


class AudioDescriptorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        library = Path(cls.directory.name) / "descriptor.so"
        subprocess.run(
            [os.environ.get("CC", "cc"), "-shared", "-fPIC", "-O2", "-I", str(HEADER.parent), "-x", "c", "-", "-o", str(library)],
            input=b'#include "descriptor.h"\nint apply(unsigned char *data, unsigned int size) { return hhkb_audio_patch(data, size); }\n',
            check=True,
        )
        cls.library = ctypes.CDLL(str(library))
        cls.library.apply.argtypes = [ctypes.POINTER(ctypes.c_ubyte), ctypes.c_uint]
        cls.library.apply.restype = ctypes.c_int
        cls.original = bytes.fromhex(DESCRIPTOR.read_text())

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def patch(self, descriptor):
        buffer = (ctypes.c_ubyte * 4096)(*descriptor)
        length = self.library.apply(buffer, len(descriptor))
        return length, bytes(buffer[:length or len(descriptor)])

    def test_only_mute_and_volume_bits_become_inputs(self):
        length, fixed = self.patch(self.original)
        self.assertGreater(length, 0)
        self.assertEqual(audio_fields(fixed), {(2, 4): 0xE2, (2, 5): 0xE9, (2, 6): 0xEA})

    def test_keyboard_and_other_reports_are_preserved(self):
        _, fixed = self.patch(self.original)
        consumer = bytes.fromhex("050c0901a1018502")
        following_report = bytes.fromhex("050c0901a1018503")
        self.assertEqual(fixed[:fixed.index(consumer)], self.original[:self.original.index(consumer)])
        self.assertEqual(fixed[fixed.index(following_report):], self.original[self.original.index(following_report):])

    def test_unknown_descriptor_length_is_untouched(self):
        for descriptor in (self.original[:-1], self.original + b"\0"):
            with self.subTest(length=len(descriptor)):
                self.assertEqual(self.patch(descriptor), (0, descriptor))

    def test_different_consumer_layout_is_untouched(self):
        changed = bytearray(self.original)
        changed[73] = 3
        self.assertEqual(self.patch(changed), (0, bytes(changed)))

    def test_already_correct_input_declaration_is_untouched(self):
        changed = bytearray(self.original)
        changed[189] = 2
        self.assertEqual(self.patch(changed), (0, bytes(changed)))

    def test_second_application_is_untouched(self):
        _, fixed = self.patch(self.original)
        self.assertEqual(self.patch(fixed), (0, fixed))


if __name__ == "__main__":
    unittest.main()
