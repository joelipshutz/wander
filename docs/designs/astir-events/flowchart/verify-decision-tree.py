#!/usr/bin/env python3
"""Reproducible, dependency-free STATIC checks for the Events decision tree.

This deliberately does not launch a browser. It cannot establish visual layout,
readability, hit targets, gesture behavior, actual network activity or rendering.
Run from any directory: python3 path/to/flowchart/verify-decision-tree.py
"""
from __future__ import annotations

import base64
from collections import Counter, defaultdict
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
FLOW = ROOT / "flowchart"
EXPECTED_SCREENS = 172
failures: list[str] = []
checks: list[str] = []


def check(condition: bool, description: str) -> None:
    (checks if condition else failures).append(description)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def digest(value: str | bytes) -> str:
    return hashlib.sha256(value.encode() if isinstance(value, str) else value).hexdigest()


class Inventory(HTMLParser):
    def __init__(self, source: str):
        super().__init__(convert_charrefs=True)
        self.tags: list[tuple[str, dict]] = []
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        if tag in {"img", "video", "audio", "source", "script", "link", "iframe", "object", "embed"}:
            self.tags.append((tag, dict(attrs)))


def script_json(source: str, id: str):
    pattern = r'<script\b(?=[^>]*\bid="' + re.escape(id) + r'")[^>]*>([\s\S]*?)</script>'
    matches = re.findall(pattern, source)
    check(len(matches) == 1, f"Exactly one embedded {id} block")
    return json.loads(matches[0]) if len(matches) == 1 else None


def articles(source: str) -> dict[str, str]:
    matches = re.findall(r'<article\b[^>]*\bdata-id="([^"<>]+)"[^>]*>[\s\S]*?</article>', source)
    blocks = re.findall(r'<article\b[^>]*\bdata-id="[^"<>]+"[^>]*>[\s\S]*?</article>', source)
    check(len(matches) == len(set(matches)) == EXPECTED_SCREENS,
          f"Source has {EXPECTED_SCREENS} unique canonical screen articles")
    return dict(zip(matches, blocks))


MEDIA_TAG = re.compile(r"<(?:img|video)\b[^>]*>")
INTRINSIC_ATTR = re.compile(r'\s+(?:width|height)="[0-9]+"|\s+data-no-pan(?=\s|>)')


def without_added_intrinsics(block: str) -> str:
    return MEDIA_TAG.sub(lambda m: INTRINSIC_ATTR.sub("", m.group()), block)


def jpeg_size(payload: str) -> tuple[int, int]:
    data = base64.b64decode(payload.split(",", 1)[1], validate=True)
    if data[:2] != b"\xff\xd8":
        raise ValueError("Preview image is not JPEG")
    index = 2
    while index < len(data):
        if data[index] != 255:
            index += 1
            continue
        while index < len(data) and data[index] == 255:
            index += 1
        marker = data[index]
        index += 1
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
            continue
        length = int.from_bytes(data[index:index + 2], "big")
        if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            height, width = struct.unpack(">HH", data[index + 3:index + 7])
            return width, height
        if length < 2:
            raise ValueError("Invalid JPEG segment length")
        index += length
    raise ValueError("No JPEG frame dimensions")


def mp4_size(payload: str) -> tuple[int, int]:
    data = base64.b64decode(payload.split(",", 1)[1], validate=True)
    position = data.find(b"tkhd")
    if position < 4:
        raise ValueError("No MP4 track header")
    length = int.from_bytes(data[position - 4:position], "big")
    end = position - 4 + length
    width, height = struct.unpack(">II", data[end - 8:end])
    return width >> 16, height >> 16


def verify():
    paths = [ROOT / "astir-events-linear.html", ROOT / "astir-events-flowchart.html",
             FLOW / "continuous-layout.json", FLOW / "decision-tree.json",
             FLOW / "canvas-camera.js", FLOW / "decision-layout.js", FLOW / "canvas-review.js"]
    stamps = {p: (p.stat().st_mtime_ns, p.stat().st_size) for p in paths}
    source = read(paths[0])
    canvas = read(paths[1])
    layout = json.loads(read(paths[2]))
    tree = json.loads(read(paths[3]))
    original_cards, canvas_cards = articles(source), articles(canvas)
    expected_by_stage = {s["id"]: {id for lane in s["lanes"] for id in lane["ids"]} for s in layout}
    expected = set().union(*expected_by_stage.values())
    check(len(expected) == EXPECTED_SCREENS, "Continuous layout has exactly 172 unique screen IDs")
    check(set(original_cards) == set(canvas_cards) == expected, "Original, canvas and layout contain identical screen IDs")
    original_media = MEDIA_TAG.findall(source)
    # Reject a changed baseline rather than silently deleting genuine original attributes.
    check(not any(INTRINSIC_ATTR.search(tag) for tag in original_media),
          "Linear source has no intrinsic attributes that normalization would hide")
    altered = [id for id in expected if id in original_cards and id in canvas_cards
               and original_cards[id] != without_added_intrinsics(canvas_cards[id])]
    check(not altered, "Canonical screen article content is unchanged except added intrinsic media attributes" +
          (f"; altered IDs: {', '.join(altered)}" if altered else ""))

    original_assets = script_json(source, "preview-assets")
    canvas_assets = script_json(canvas, "preview-assets")
    check(original_assets == canvas_assets, "All embedded base64 image payloads and keys are unchanged")
    source_inventory, canvas_inventory = Inventory(source), Inventory(canvas)
    original_videos = [a.get("src") for tag, a in source_inventory.tags if tag == "video"]
    canvas_videos = [a.get("src") for tag, a in canvas_inventory.tags if tag == "video"]
    check(original_videos == canvas_videos, "All embedded video payloads are unchanged and in source order")
    dimensions = {id: jpeg_size(payload) for id, payload in canvas_assets.items()}
    preview_tags = [a for tag, a in canvas_inventory.tags if tag == "img" and "data-asset" in a]
    check(all(a["data-asset"] in canvas_assets for a in preview_tags), "Every image preview refers to an embedded asset")
    check(all(a.get("data-large") in canvas_assets for a in preview_tags if a.get("data-large")),
          "Every larger image preview refers to an embedded asset")
    check(all((int(a.get("width", 0)), int(a.get("height", 0))) == dimensions.get(a["data-asset"])
              for a in preview_tags), "Image intrinsic dimensions match their JPEG payloads")
    video_tags = [a for tag, a in canvas_inventory.tags if tag == "video"]
    check(all(a.get("src", "").startswith("data:video/mp4;base64,") and
              (int(a.get("width", 0)), int(a.get("height", 0))) == mp4_size(a["src"]) and
              "data-no-pan" in a for a in video_tags),
          "Video dimensions match embedded MP4 payloads and player controls are excluded from panning")

    embedded = script_json(canvas, "canvas-layout")
    check(embedded.get("tree") == tree, "Generated HTML contains the current decision-tree JSON")
    check(embedded.get("sections") == layout, "Generated HTML contains the current continuous screen inventory")
    stages = tree["stages"]
    stage_ids = [s["id"] for s in stages]
    check(len(stage_ids) == len(set(stage_ids)) and set(stage_ids) == set(expected_by_stage),
          "Decision graph has exactly the 13 known stages")
    valid_types = {"decision", "screen", "handoff", "note"}
    valid_statuses = {"open", "reference"}
    valid_kinds = {"yes", "no", "state", "action", "retry", "reference"}
    all_ids = [n["id"] for s in stages for n in s["nodes"]]
    check(len(all_ids) == len(set(all_ids)), "All graph node IDs are globally unique")
    policy_language = re.compile(r"\bOD0[1-9]\b|\bopen (?:design|policy|choice)\b|\bremain(?:s)? open\b|\b(?:are|is) (?:proposed|unapproved)\b|\bnot selected behavior\b", re.I)
    bad_policy_status = []
    stats = []
    all_graph_screens = []
    for stage in stages:
        sid = stage["id"]
        nodes, edges = stage["nodes"], stage["edges"]
        ids = {n["id"] for n in nodes}
        screens = [n.get("screenId") for n in nodes if n["type"] == "screen"]
        all_graph_screens.extend(screens)
        check(len(screens) == len(set(screens)) and set(screens) == expected_by_stage.get(sid),
              f"{sid}: exact original screen coverage, each screen once")
        check(all(n["type"] in valid_types and ("status" not in n or n["status"] in valid_statuses) for n in nodes),
              f"{sid}: valid node types and approval statuses")
        check(all(n["id"] == n["screenId"] for n in nodes if n["type"] == "screen"),
              f"{sid}: screen node IDs retain canonical source IDs")
        check(all(isinstance(n.get("label"), str) and n["label"].strip() for n in nodes if n["type"] != "screen"),
              f"{sid}: decisions, notes and handoffs have visible labels")
        check(all(n["id"].startswith(sid + "-d-") for n in nodes if n["type"] == "decision"),
              f"{sid}: decision IDs use the stage namespace")
        for n in nodes:
            if n["type"] == "handoff":
                target = n.get("targetStage")
                check(target in expected_by_stage, f"{sid}/{n['id']}: handoff targets a real stage")
                if "targetScreen" in n:
                    check(n["targetScreen"] in expected_by_stage.get(target, set()),
                          f"{sid}/{n['id']}: preview target belongs to destination stage")
            if policy_language.search(n.get("label", "")) and n.get("status") != "open":
                bad_policy_status.append(n["id"])
        check(all(e.get("from") in ids and e.get("to") in ids for e in edges),
              f"{sid}: every edge endpoint exists in this stage")
        check(all(isinstance(e.get("label"), str) and e["label"].strip() and e.get("kind", "state") in valid_kinds for e in edges),
              f"{sid}: all branches have nonempty labels and supported kinds")
        signatures = [(e.get("from"), e.get("to"), e.get("label"), e.get("kind", "state")) for e in edges]
        check(len(signatures) == len(set(signatures)), f"{sid}: no duplicated graph edges")
        outgoing = Counter(e["from"] for e in edges)
        check(all(outgoing[n["id"]] >= 2 for n in nodes if n["type"] == "decision"),
              f"{sid}: every decision has at least two visible branches")
        adjacency = defaultdict(list)
        for edge in edges:
            if edge.get("kind") != "retry" and edge.get("from") in ids and edge.get("to") in ids:
                adjacency[edge["from"]].append(edge["to"])
        active, done, cycles = set(), set(), []
        def visit(id):
            if id in active:
                cycles.append(id)
                return
            if id in done:
                return
            active.add(id)
            for target in adjacency[id]:
                visit(target)
            active.remove(id)
            done.add(id)
        for id in ids:
            visit(id)
        check(not cycles, f"{sid}: acyclic including reference edges; explicit retry edges excluded" +
              (f"; cycle nodes: {cycles}" if cycles else ""))
        stats.append({"stage": sid, "nodes": len(nodes), "screens": len(screens),
                      "decisions": sum(n["type"] == "decision" for n in nodes), "edges": len(edges),
                      "open_nodes": sum(n.get("status") == "open" for n in nodes)})
    check(len(all_graph_screens) == len(set(all_graph_screens)) == EXPECTED_SCREENS,
          "Entire graph preserves exactly 172 unique canonical screens")
    check(not bad_policy_status, "Explicit open-policy / proposal language has status=open" +
          (f"; missing: {', '.join(bad_policy_status)}" if bad_policy_status else ""))

    scripts = re.findall(r"<script\b([^>]*)>([\s\S]*?)</script>", canvas)
    active_scripts = [body for attrs, body in scripts if not re.search(r'type=[\"\']application/json[\"\']', attrs)]
    active_js = "\n".join(active_scripts)
    expected_js = "\n".join(read(p) for p in paths[4:])
    check(len(active_scripts) == 1 and active_js.strip() == expected_js.strip(),
          "Embedded controller source matches camera, decision layout and canvas review files")
    check(not any(tag == "script" and a.get("src") for tag, a in canvas_inventory.tags),
          "No external script src is present")
    network_attrs = []
    for tag, attrs in canvas_inventory.tags:
        names = ("href",) if tag == "link" else ("data",) if tag == "object" else ("src", "srcset")
        for name in names:
            value = attrs.get(name, "")
            if value and not value.startswith(("data:", "#")):
                network_attrs.append(f"{tag}.{name}")
    check(not network_attrs, "No nonembedded automatic resource URL attributes" +
          (f"; found: {network_attrs}" if network_attrs else ""))
    css = "\n".join(re.findall(r"<style\b[^>]*>([\s\S]*?)</style>", canvas))
    css_urls = re.findall(r"url\(\s*['\"]?([^)'\"]+)", css)
    check(not any(not value.startswith(("data:", "#")) for value in css_urls) and not re.search(r"@import\b", css),
          "No CSS external URL or import literals")
    request_calls = re.findall(r"\b(?:fetch|XMLHttpRequest|WebSocket|EventSource|importScripts|sendBeacon)\s*\(|\bimport\s*\(", active_js)
    check(not request_calls, "No direct network-request API calls or dynamic import literals in controller source")
    namespace_identifiers = {"http://www.w3.org/2000/svg", "http://www.w3.org/1999/xhtml"}
    http_literals = re.findall(r"https?://[^\"'`\s<>)]+", active_js)
    check(all(value in namespace_identifiers for value in http_literals),
          "Controller HTTP(S) literals are only SVG/XHTML namespace identifiers, not resource URLs")
    changed_during_run = [p.name for p in paths if (p.stat().st_mtime_ns, p.stat().st_size) != stamps[p]]
    check(not changed_during_run, "Input files remained unchanged during this verification snapshot" +
          (f"; rerun after changes settle: {changed_during_run}" if changed_during_run else ""))
    return {"verification": "static-only", "passed": not failures, "check_count": len(checks) + len(failures),
            "passed_checks": len(checks), "failures": failures, "screen_count": len(all_graph_screens),
            "embedded_image_assets": len(canvas_assets), "image_tags": len(preview_tags),
            "embedded_videos": len(canvas_videos), "stages": stats,
            "sha256": {"linear_html": digest(source), "decision_tree_html": digest(canvas),
                       "decision_tree_json": digest(read(paths[3])),
                       "embedded_assets": digest(json.dumps(canvas_assets, sort_keys=True))},
            "limitations": ["No browser was launched and no browser/security restriction was bypassed.",
                            "No visual, gesture, click, keyboard, accessibility or performance behavior was tested.",
                            "Resource checks inspect source literals only; they are not a browser network trace.",
                            "Graph structure and explicit open labels are checked; product semantics still require human review."]}


if __name__ == "__main__":
    try:
        result = verify()
    except (KeyError, ValueError, TypeError, OSError, IndexError, struct.error) as error:
        # Do not dump HTML/base64 payloads if a malformed source fails parsing.
        result = {"verification": "static-only", "passed": False, "error_type": type(error).__name__,
                  "error": str(error)[:300], "failures": failures,
                  "limitation": "This is not a browser verification."}
    print(json.dumps(result, indent=2))
    sys.exit(0 if result.get("passed") else 1)
