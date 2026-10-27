#!/usr/bin/env python3
"""Read-only transfer checks. No network, signing, keychain writes, or secret output."""

import argparse
import json
import plistlib
import re
import subprocess
from datetime import datetime
from pathlib import Path


MAIN = "com.grayline.wander"
CLIP = MAIN + ".Clip"
GROUPS = "com.apple.security.application-groups"
DOMAINS = "com.apple.developer.associated-domains"
TEAM = "com.apple.developer.team-identifier"
SHARED = "group.com.grayline.wander.shared"
CONTINUATION = "group.com.grayline.wander.clip"
HOSTS = ("astirmovement.com", "www.astirmovement.com", "getrec.me")
PRODUCTS = {
    MAIN: ("Wander", "Wander/Resources/Wander.entitlements"),
    CLIP: ("AstirClip", "WanderAppClip/Resources/AstirClip.entitlements"),
    MAIN + ".share": ("WanderShareExtension", "WanderShareExtension/WanderShareExtension.entitlements"),
    MAIN + ".widgets": ("WanderWidgets", "WanderWidgets/WanderWidgets.entitlements"),
    MAIN + ".nearbywidgets": ("WanderNearbyWidgets", "WanderNearbyWidgets/WanderNearbyWidgets.entitlements"),
}
ROUTES = ("/profiles/*", "/places/*", "/lists/*", "/invites/*", "/plans/*", "/share/tiktok", "/activities/*")
CARD_ROUTES = ("/cards/profiles/*", "/cards/places/*", "/cards/activities/*", "/cards/lists/*", "/cards/invites/*")


class Report:
    def __init__(self):
        self.checks = []

    def check(self, name, passed):
        self.checks.append({"check": name, "passed": bool(passed)})

    def result(self):
        return {"passed": bool(self.checks) and all(c["passed"] for c in self.checks), "checks": self.checks}


def read_plist(path):
    value = plistlib.loads(path.read_bytes())
    if not isinstance(value, dict):
        raise ValueError("Expected a dictionary")
    return value


def check_entitlements(report, bundle, ent, prefix, source=False, signing_kind="distribution"):
    expected_groups = [SHARED, CONTINUATION] if bundle == MAIN else [CONTINUATION] if bundle == CLIP else [SHARED]
    report.check(bundle + ":app-groups", sorted(ent.get(GROUPS, [])) == sorted(expected_groups))
    if bundle not in (MAIN, CLIP):
        report.check(bundle + ":no-push", "aps-environment" not in ent)
        return
    domains = ["appclips:" + host for host in HOSTS]
    if bundle == MAIN:
        domains += ["applinks:" + host for host in HOSTS] + ["webcredentials:clerk.getrec.me"]
    report.check(bundle + ":associated-domains", sorted(ent.get(DOMAINS, [])) == sorted(domains))
    report.check(bundle + ":apple-sign-in", ent.get("com.apple.developer.applesignin") == ["Default"])
    if bundle == MAIN:
        report.check(bundle + ":clip-association", ent.get("com.apple.developer.associated-appclip-app-identifiers") == [prefix + CLIP])
        push_environment = "development" if signing_kind == "development" else "production"
        report.check(bundle + ":push-environment", ent.get("aps-environment") == ("$(APS_ENVIRONMENT)" if source else push_environment))
    else:
        report.check(bundle + ":parent-association", ent.get("com.apple.developer.parent-application-identifiers") == [prefix + MAIN])
        report.check(bundle + ":no-push", "aps-environment" not in ent)
        if not source:
            report.check(bundle + ":on-demand-install", ent.get("com.apple.developer.on-demand-install-capable") is True)


def check_source(report, root, team):
    project = (root / "project.yml").read_text()
    teams = re.findall(r"^\s+DEVELOPMENT_TEAM:\s*(\S+)\s*$", project, re.M)
    report.check("source:signing-team", bool(teams) and all(t == team for t in teams))
    targets = project.split("\ntargets:\n", 1)[1]
    for bundle, (target, ent_path) in PRODUCTS.items():
        match = re.search(r"^  " + re.escape(target) + r":\n(.*?)(?=^  \S|\Z)", targets, re.M | re.S)
        block = match.group(1) if match else ""
        report.check(bundle + ":source-bundle-id", bool(re.search(r"^\s+PRODUCT_BUNDLE_IDENTIFIER:\s*" + re.escape(bundle) + r"\s*$", block, re.M)))
        report.check(bundle + ":entitlements-path", bool(re.search(r"^\s+CODE_SIGN_ENTITLEMENTS:\s*" + re.escape(ent_path) + r"\s*$", block, re.M)))
        if bundle == MAIN:
            report.check("source:release-push", bool(re.search(r"^        Release:\n(?:(?!^        \S).)*APS_ENVIRONMENT: production", block, re.M | re.S)))
        try:
            check_entitlements(report, bundle, read_plist(root / ent_path), "$(AppIdentifierPrefix)", source=True)
        except (OSError, ValueError, TypeError):
            report.check(bundle + ":source-entitlements-readable", False)


def command(args):
    # Capture diagnostics but never print subprocess output (paths, profiles, or keys).
    try:
        return subprocess.run(args, capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return subprocess.CompletedProcess(args, 1, b"", b"")


def check_archive(report, archive, team, prefix, signing_kind="distribution"):
    applications = sorted((archive / "Products/Applications").glob("*.app"))
    report.check("archive:one-main-app", len(applications) == 1)
    if len(applications) != 1:
        return
    app = applications[0]
    products = [app, *sorted((app / "AppClips").glob("*.app")), *sorted((app / "PlugIns").glob("*.appex"))]
    found = []
    versions = []
    for index, product in enumerate(products):
        try:
            info = read_plist(product / "Info.plist")
            bundle = info.get("CFBundleIdentifier")
        except (OSError, ValueError):
            report.check("archive:product-" + str(index) + "-readable", False)
            continue
        found.append(bundle)
        versions.append((info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")))
        if bundle not in PRODUCTS:
            report.check("archive:unexpected-product", False)
            continue
        expected_parent = app.parent if bundle == MAIN else app / ("AppClips" if bundle == CLIP else "PlugIns")
        report.check(bundle + ":product-location", product.parent == expected_parent)
        report.check(bundle + ":strict-signature", command(["codesign", "--verify", "--strict", str(product)]).returncode == 0)
        displayed = command(["codesign", "-d", "--entitlements", "-", "--xml", str(product)])
        try:
            ent = plistlib.loads(displayed.stdout)
            if displayed.returncode or not isinstance(ent, dict):
                raise ValueError("Unreadable entitlements")
        except (ValueError, TypeError):
            report.check(bundle + ":signed-entitlements-readable", False)
            continue
        report.check(bundle + ":signing-team", ent.get(TEAM) == team)
        report.check(bundle + ":application-identifier", ent.get("application-identifier") == prefix + bundle)
        report.check(bundle + ":signing-kind", ent.get("get-task-allow") is (signing_kind == "development"))
        check_entitlements(report, bundle, ent, prefix, signing_kind=signing_kind)
        decoded = command(["security", "cms", "-D", "-i", str(product / "embedded.mobileprovision")])
        try:
            profile = plistlib.loads(decoded.stdout)
            if decoded.returncode or not isinstance(profile, dict):
                raise ValueError("Unreadable profile")
            report.check(bundle + ":profile-team", profile.get("TeamIdentifier") == [team])
            report.check(bundle + ":profile-prefix", profile.get("ApplicationIdentifierPrefix") == [prefix.rstrip(".")])
            expiry = profile.get("ExpirationDate")
            report.check(bundle + ":profile-current", isinstance(expiry, datetime) and expiry > datetime.utcnow())
            granted = profile.get("Entitlements", {})
            report.check(bundle + ":profile-application-id", granted.get("application-identifier") == prefix + bundle)
            report.check(bundle + ":profile-signing-kind", granted.get("get-task-allow") is (signing_kind == "development"))
            report.check(bundle + ":profile-groups", set(ent.get(GROUPS, [])) <= set(granted.get(GROUPS, [])))
        except (ValueError, TypeError, AttributeError):
            report.check(bundle + ":profile-readable", False)
    report.check("archive:exact-five-products", len(found) == len(PRODUCTS) and set(found) == set(PRODUCTS))
    report.check("archive:consistent-versions", bool(versions) and all(v == versions[0] and all(v) for v in versions))
    report.check("archive:deep-signature", command(["codesign", "--verify", "--deep", "--strict", str(app)]).returncode == 0)


def check_aasa(report, data, prefixes, kind, cards=False):
    if kind == "clerk":
        apps = data.get("webcredentials", {}).get("apps", [])
        report.check("aasa:clerk-app-identifiers", all(prefix + bundle in apps for prefix in prefixes for bundle in (MAIN, CLIP)))
        return
    details = data.get("applinks", {}).get("details", [])
    for n, prefix in enumerate(prefixes):
        entries = [d for d in details if prefix + MAIN in d.get("appIDs", []) or d.get("appID") == prefix + MAIN]
        # This repository's AASA contract uses simple positive paths/components.
        # Reject conditional/exclusion rules rather than claim to model Apple routing.
        paths = set()
        simple = len(entries) == 1
        for entry in entries:
            paths.update(entry.get("paths", []))
            simple = simple and all(not p.startswith("NOT ") for p in entry.get("paths", []))
            for component in entry.get("components", []):
                simple = simple and set(component) <= {"/", "comment"}
                if "/" in component:
                    paths.add(component["/"])
        report.check("aasa:main-routes-" + str(n + 1), simple and set(ROUTES + (CARD_ROUTES if cards else ())) <= paths)
        report.check("aasa:clip-" + str(n + 1), prefix + CLIP in data.get("appclips", {}).get("apps", []))


def identifier(value):
    if not re.fullmatch(r"[A-Z0-9]{10}", value):
        raise argparse.ArgumentTypeError("Use a 10-character identifier, without a trailing dot")
    return value


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    source = modes.add_parser("source")
    source.add_argument("root", type=Path)
    source.add_argument("--team", type=identifier, required=True)
    archive = modes.add_parser("archive")
    archive.add_argument("path", type=Path)
    archive.add_argument("--team", type=identifier, required=True)
    archive.add_argument("--app-id-prefix", type=identifier, required=True)
    archive.add_argument("--signing-kind", choices=("development", "distribution"), required=True,
                         help="Expected signing stage; automatic archives may use development signing before export")
    aasa = modes.add_parser("aasa")
    aasa.add_argument("path", type=Path)
    aasa.add_argument("--kind", choices=("website", "clerk"), required=True)
    aasa.add_argument("--app-id-prefix", type=identifier, action="append", required=True)
    aasa.add_argument("--cards", action="store_true")
    args = parser.parse_args(argv)
    report = Report()
    try:
        if args.mode == "source":
            check_source(report, args.root, args.team)
        elif args.mode == "archive":
            check_archive(report, args.path, args.team, args.app_id_prefix + ".", args.signing_kind)
        else:
            check_aasa(report, json.loads(args.path.read_text()), [p + "." for p in args.app_id_prefix], args.kind, args.cards)
    except (OSError, ValueError, TypeError, KeyError, IndexError, AttributeError):
        report.check(args.mode + ":input-readable-and-supported", False)
    result = report.result()
    print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
