import contextlib
import copy
import importlib.util
import io
import json
import plistlib
import subprocess
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("preflight", Path(__file__).with_name("apple-transfer-preflight.py"))
preflight = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(preflight)
ROOT = Path(__file__).resolve().parents[1]
TEAM = "NEWTEAM001"
PREFIX = "OLDPREFIX1."


def passed(report):
    return report.result()["passed"]


class TransferPreflightTests(unittest.TestCase):
    def entitlements(self, bundle):
        ent = preflight.read_plist(ROOT / preflight.PRODUCTS[bundle][1])
        for key, value in ent.items():
            if isinstance(value, list):
                ent[key] = [v.replace("$(AppIdentifierPrefix)", PREFIX) for v in value]
        ent[preflight.TEAM] = TEAM
        ent["application-identifier"] = PREFIX + bundle
        ent["get-task-allow"] = False
        if bundle == preflight.MAIN:
            ent["aps-environment"] = "production"
        if bundle == preflight.CLIP:
            ent["com.apple.developer.on-demand-install-capable"] = True
        return ent

    def archive(self, missing=None, bad_signature=False, bad_entitlements=False, expired=False, wrong_team=False, profile_failure=False, development=False, expected_signing_kind="distribution"):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        app = root / "Products/Applications/Wander.app"
        paths = {preflight.MAIN: app, preflight.CLIP: app / "AppClips/AstirClip.app"}
        paths.update({b: app / ("PlugIns/" + target + ".appex") for b, (target, _) in preflight.PRODUCTS.items() if b not in paths})
        for bundle, product in paths.items():
            if bundle == missing:
                continue
            product.mkdir(parents=True)
            (product / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": bundle, "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0", "WANDER_POSTHOG_PROJECT_TOKEN": "PRIVATE_MARKER"}))

        def run(args):
            if "--verify" in args:
                return subprocess.CompletedProcess(args, int(bad_signature), b"", b"PRIVATE_MARKER")
            product = Path(args[-1]).parent if args[0] == "security" else Path(args[-1])
            bundle = preflight.read_plist(product / "Info.plist")["CFBundleIdentifier"]
            ent = self.entitlements(bundle)
            ent["get-task-allow"] = development
            if bundle == preflight.MAIN and development:
                ent["aps-environment"] = "development"
            if args[0] == "codesign":
                self.assertIn("--xml", args)
                if wrong_team:
                    ent[preflight.TEAM] = "WRONGTEAM1"
                return subprocess.CompletedProcess(args, 0, b"" if bad_entitlements else plistlib.dumps(ent), b"PRIVATE_MARKER")
            profile = {"TeamIdentifier": [TEAM], "ApplicationIdentifierPrefix": [PREFIX.rstrip(".")], "ExpirationDate": datetime.utcnow() + timedelta(days=-1 if expired else 30), "Entitlements": ent, "DeveloperCertificates": [b"PRIVATE_MARKER"], "ProvisionedDevices": ["PRIVATE_MARKER"]}
            return subprocess.CompletedProcess(args, int(profile_failure), plistlib.dumps(profile), b"PRIVATE_MARKER")

        report = preflight.Report()
        with patch.object(preflight, "command", side_effect=run):
            preflight.check_archive(report, root, TEAM, PREFIX, expected_signing_kind)
        return report

    def test_source_contract(self):
        report = preflight.Report()
        preflight.check_source(report, ROOT, "Y7TVK75RZ8")
        self.assertTrue(passed(report))

    def test_source_wrong_team_fails(self):
        report = preflight.Report()
        preflight.check_source(report, ROOT, TEAM)
        self.assertFalse(passed(report))

    def test_recipient_team_with_preserved_prefix_passes(self):
        self.assertTrue(passed(self.archive()))

    def test_pre_export_development_archive_passes_only_when_explicit(self):
        self.assertTrue(passed(self.archive(development=True, expected_signing_kind="development")))
        self.assertFalse(passed(self.archive(development=True)))

    def test_distribution_archive_fails_when_development_is_expected(self):
        self.assertFalse(passed(self.archive(expected_signing_kind="development")))

    def test_missing_embedded_product_fails(self):
        self.assertFalse(passed(self.archive(missing=preflight.MAIN + ".widgets")))

    def test_untrusted_archive_fails(self):
        self.assertFalse(passed(self.archive(bad_signature=True)))

    def test_empty_entitlements_fail_even_with_zero_exit(self):
        self.assertFalse(passed(self.archive(bad_entitlements=True)))

    def test_expired_profile_fails(self):
        self.assertFalse(passed(self.archive(expired=True)))

    def test_profile_decode_failure_fails(self):
        self.assertFalse(passed(self.archive(profile_failure=True)))

    def test_wrong_signing_team_fails(self):
        self.assertFalse(passed(self.archive(wrong_team=True)))

    def test_sensitive_values_never_enter_report(self):
        for report in (self.archive(), self.archive(bad_signature=True), self.archive(profile_failure=True)):
            self.assertNotIn("PRIVATE_MARKER", json.dumps(report.result()))

    def test_missing_group_and_wrong_clip_parent_fail(self):
        for key, value in [(preflight.GROUPS, []), ("com.apple.developer.parent-application-identifiers", [TEAM + "." + preflight.MAIN])]:
            with self.subTest(key=key):
                ent = self.entitlements(preflight.CLIP)
                ent[key] = value
                report = preflight.Report()
                preflight.check_entitlements(report, preflight.CLIP, ent, PREFIX)
                self.assertFalse(passed(report))

    def aasa(self, prefixes):
        return {"applinks": {"details": [{"appIDs": [p + preflight.MAIN for p in prefixes], "components": [{"/": r} for r in preflight.ROUTES + preflight.CARD_ROUTES]}]}, "appclips": {"apps": [p + preflight.CLIP for p in prefixes]}}

    def test_additive_aasa_preserves_old_and_new_ids(self):
        prefixes = [PREFIX, TEAM + "."]
        report = preflight.Report()
        preflight.check_aasa(report, self.aasa(prefixes), prefixes, "website", True)
        self.assertTrue(passed(report))

    def test_aasa_dropping_old_id_fails(self):
        report = preflight.Report()
        preflight.check_aasa(report, self.aasa([TEAM + "."]), [PREFIX, TEAM + "."], "website")
        self.assertFalse(passed(report))

    def test_aasa_exclusion_or_missing_route_fails(self):
        data = self.aasa([PREFIX])
        changed = copy.deepcopy(data)
        changed["applinks"]["details"][0]["components"][0]["exclude"] = True
        missing = copy.deepcopy(data)
        missing["applinks"]["details"][0]["components"].pop(0)
        for invalid in [changed, missing]:
            report = preflight.Report()
            preflight.check_aasa(report, invalid, [PREFIX], "website")
            self.assertFalse(passed(report))

    def test_clerk_requires_main_and_clip(self):
        for bundles, expected in [([preflight.MAIN], False), ([preflight.MAIN, preflight.CLIP], True)]:
            report = preflight.Report()
            preflight.check_aasa(report, {"webcredentials": {"apps": [PREFIX + b for b in bundles]}}, [PREFIX], "clerk")
            self.assertEqual(passed(report), expected)

    def test_malformed_input_fails_without_echoing_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "aasa.json"
            path.write_text("PRIVATE_MARKER")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = preflight.main(["aasa", str(path), "--kind", "clerk", "--app-id-prefix", "OLDPREFIX1"])
            self.assertEqual(code, 1)
            self.assertNotIn("PRIVATE_MARKER", output.getvalue())


if __name__ == "__main__":
    unittest.main()
