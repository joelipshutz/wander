import copy
from collections import Counter
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "parent_regression", Path(__file__).with_name("run-parent-regression.py")
)
regression = importlib.util.module_from_spec(spec)
spec.loader.exec_module(regression)


class PerformanceProductsTests(unittest.TestCase):
    def test_ui_inventory_has_disjoint_complete_hosted_and_reference_coverage(self):
        inventory = regression.ui_test_identifiers(Path(__file__).resolve().parents[1])
        hosted = regression.ISOLATED_UI_PERFORMANCE
        reference = regression.REFERENCE_UI_PERFORMANCE
        self.assertFalse(hosted & reference)
        self.assertTrue((hosted | reference).issubset(inventory))
        ordinary = [test for shard in range(8) for test in inventory[shard::8]
                    if test not in hosted | reference]
        self.assertEqual(Counter(ordinary + sorted(hosted) + sorted(reference)), Counter(inventory))

    def test_both_formats_preserve_selection_binaries_and_unit_configuration(self):
        for version in (1, 2):
            with self.subTest(version=version), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                unit = {"BlueprintName": "WanderTests", "TestBundlePath": "units.xctest"}
                ui = {"IsUITestBundle": True, "BlueprintName": "WanderUITests",
                      "OnlyTestIdentifiers": ["MapTests/testFrames"],
                      "TestBundlePath": "ui.xctest", "UserAttachmentLifetime": "keepAlways",
                      "PreferredScreenCaptureFormat": "screenRecording",
                      "SystemAttachmentLifetime": "deleteOnSuccess"}
                document = ({"WanderTests": unit, "WanderUITests": ui} if version == 1 else
                            {"TestConfigurations": [{"TestTargets": [unit, ui]}]})
                expected = copy.deepcopy(document)
                expected_ui = (expected["WanderUITests"] if version == 1 else
                               expected["TestConfigurations"][0]["TestTargets"][1])
                expected_ui.update(PreferredScreenCaptureFormat="screenshots",
                                   SystemAttachmentLifetime="keepNever")
                (root / "Info.plist").write_bytes(plistlib.dumps({
                    "Tests": [{"xctestrun": "tests.plist"}]}))
                configuration = root / "tests.plist"
                configuration.write_bytes(plistlib.dumps(document))
                self.assertEqual(regression.prepare_ui_performance_products(root), 1)
                self.assertEqual(plistlib.loads(configuration.read_bytes()), expected)

    def test_missing_ui_target_fails_without_rewriting_configuration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Info.plist").write_bytes(plistlib.dumps({
                "Tests": [{"xctestrun": "tests.plist"}]}))
            configuration = root / "tests.plist"
            original = plistlib.dumps({"WanderTests": {"BlueprintName": "WanderTests"}})
            configuration.write_bytes(original)
            with self.assertRaisesRegex(ValueError, "No UI test target"):
                regression.prepare_ui_performance_products(root)
            self.assertEqual(configuration.read_bytes(), original)

    def test_configuration_path_cannot_escape_products_bundle(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Info.plist").write_bytes(plistlib.dumps({
                "Tests": [{"xctestrun": "../outside.plist"}]}))
            with self.assertRaisesRegex(ValueError, "inside the products bundle"):
                regression.prepare_ui_performance_products(root)


if __name__ == "__main__":
    unittest.main()
