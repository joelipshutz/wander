"""Pure generated-response contracts; no compiler, subprocess, or network."""
import hashlib
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("replay_compiler_flags", Path(__file__).with_name("record-replay-compiler-flags.py"))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


class ReplayCompilerFlagReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.dd = self.root / "DerivedData"
        self.products = self.root / "Products"
        self.products.mkdir()
        self.response = self.dd / "Build/Intermediates.noindex/PostHog.build/Debug-iphonesimulator/phlibwebp.build/Objects-normal/arm64/abc-common-args.resp"
        self.response.parent.mkdir(parents=True)
        self.response.write_text('-fmodules -Os -DDEBUG=1 -I "headers with spaces"\n')
        self.configuration = self.products / "Wander_iphonesimulator.xctestrun"
        self.configuration.write_bytes(plistlib.dumps({"synthetic": True}))
        self.info = self.products / "Info.plist"
        self.write_info([{"xctestrun": self.configuration.name}])
        self.candidate = "a" * 40

    def write_info(self, entries):
        self.info.write_bytes(plistlib.dumps({"Tests": entries}))

    def collect(self):
        return r.collect(self.dd, self.products, self.candidate)

    def test_valid_receipt_binds_response_and_products_without_claiming_swift_or_binary_verification(self):
        receipt = self.collect()
        self.assertEqual(receipt["checkoutCommit"], self.candidate)
        self.assertEqual(receipt["configuration"], "Debug")
        self.assertEqual(receipt["architecture"], "arm64")
        self.assertEqual(receipt["platform"], "iphonesimulator")
        self.assertTrue(receipt["observedCFlagsVerified"])
        self.assertFalse(receipt["swiftCompilerCommandObserved"])
        self.assertFalse(receipt["binaryIntegrityClaimed"])
        self.assertEqual(receipt["configurationSHA256"], {self.configuration.name: hashlib.sha256(self.configuration.read_bytes()).hexdigest()})
        self.assertEqual(receipt["productInfoSHA256"], hashlib.sha256(self.info.read_bytes()).hexdigest())
        self.assertEqual(receipt["responses"][0]["sha256"], hashlib.sha256(self.response.read_bytes()).hexdigest())
        self.assertEqual(receipt["responses"][0]["optimizationFlags"], ["-Os"])

    def test_missing_contradictory_or_non_size_optimization_rejects(self):
        for flags in ["-DDEBUG=1", "-O0 -DDEBUG=1", "-Os -O0 -DDEBUG=1", "-O3 -Os -DDEBUG=1", "-Os -Ofast -DDEBUG=1", "-Os -Os -DDEBUG=1", "-Oz -DDEBUG=1"]:
            with self.subTest(flags=flags):
                self.response.write_text(flags)
                with self.assertRaises(ValueError): self.collect()

    def test_debug_define_is_required(self):
        for flags in ["-Os", "-Os -DDEBUG=0", "-Os -DNDEBUG=1"]:
            with self.subTest(flags=flags):
                self.response.write_text(flags)
                with self.assertRaises(ValueError): self.collect()

    def test_every_observed_c_response_must_match(self):
        other = self.dd / "Build/Intermediates.noindex/Other.build/Debug-iphonesimulator/Other.build/Objects-normal/arm64/other-common-args.resp"
        other.parent.mkdir(parents=True)
        other.write_text("-O0 -DDEBUG=1")
        with self.assertRaises(ValueError): self.collect()
        other.write_text("-Os -DDEBUG=1")
        self.assertEqual(len(self.collect()["responses"]), 2)

    def test_phlibwebp_evidence_is_required(self):
        other = self.response.parent.parent.parent.parent / "Different.build/Objects-normal/arm64/abc-common-args.resp"
        other.parent.mkdir(parents=True)
        self.response.rename(other)
        with self.assertRaises(ValueError): self.collect()

    def test_other_configuration_platform_or_architecture_rejects(self):
        relative = self.response.relative_to(self.dd)
        for old, new in [("Debug-iphonesimulator", "Release-iphonesimulator"), ("Debug-iphonesimulator", "Debug-iphoneos"), ("arm64", "x86_64")]:
            target = self.dd / str(relative).replace(old, new)
            target.parent.mkdir(parents=True, exist_ok=True)
            self.response.rename(target)
            with self.subTest(value=new), self.assertRaises(ValueError): self.collect()
            target.rename(self.response)

    def test_direct_response_symlink_rejects(self):
        target = self.root / "response.txt"
        self.response.rename(target)
        self.response.symlink_to(target)
        with self.assertRaises(ValueError): self.collect()

    def test_intermediates_ancestor_symlink_rejects(self):
        base = self.dd / "Build/Intermediates.noindex"
        target = self.root / "other-intermediates"
        base.rename(target)
        base.symlink_to(target, target_is_directory=True)
        with self.assertRaises(ValueError): self.collect()

    def test_symlinked_products_or_configuration_rejects(self):
        target = self.root / "configuration.xctestrun"
        self.configuration.rename(target)
        self.configuration.symlink_to(target)
        with self.assertRaises(ValueError): self.collect()
        self.configuration.unlink()
        target.rename(self.configuration)
        original = self.products
        self.products = self.root / "product-link"
        self.products.symlink_to(original, target_is_directory=True)
        with self.assertRaises(ValueError): self.collect()

    def test_missing_or_excessive_response_inventory_rejects(self):
        original = self.response.read_bytes()
        self.response.unlink()
        with self.assertRaises(ValueError): self.collect()
        self.response.write_bytes(original)
        for n in range(128):
            (self.response.parent / (str(n)+"-common-args.resp")).write_bytes(original)
        with self.assertRaises(ValueError): self.collect()

    def test_oversized_response_rejects(self):
        self.response.write_bytes(b"-Os -DDEBUG=1 " + b" " * 262144)
        with self.assertRaises(ValueError): self.collect()

    def test_configuration_list_must_be_present_and_bounded(self):
        for value in [[], "invalid", [{}], [{"xctestrun": 4}], [{"xctestrun": self.configuration.name}] * 17]:
            with self.subTest(value=type(value).__name__):
                self.write_info(value)
                with self.assertRaises(ValueError): self.collect()

    def test_configuration_path_escape_or_missing_rejects(self):
        for value in ["../outside.xctestrun", str(self.configuration), "missing.xctestrun"]:
            with self.subTest(path=value):
                self.write_info([{"xctestrun": value}])
                with self.assertRaises(ValueError): self.collect()

    def test_oversized_info_and_configuration_reject(self):
        original = self.info.read_bytes()
        self.info.write_bytes(b" " * 1048577)
        with self.assertRaises(ValueError): self.collect()
        self.info.write_bytes(original)
        self.configuration.write_bytes(b" " * 4194305)
        with self.assertRaises(ValueError): self.collect()

    def test_malformed_candidate_rejects(self):
        for value in ["", "a" * 39, "A" * 40, "g" * 40]:
            with self.subTest(candidate=value):
                self.candidate = value
                with self.assertRaises(ValueError): self.collect()


if __name__ == "__main__":
    unittest.main()
