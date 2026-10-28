#!/usr/bin/env python3
"""Build a local comparison page from Astir's second-pass native pin captures.

Only the requested HTML file is written. PNG captures are referenced in place.
"""

from __future__ import annotations

import argparse
import html
import json
import os
from pathlib import Path
from urllib.parse import quote


DIRECTIONS = [
    {
        "id": "cutout",
        "name": "Cutout",
        "language": "Category as an object",
        "description": "Custom vector category objects, presented as small stickers on the map.",
        "category": "Does the object silhouette read at a glance, without relying on its color?",
        "identity": "The object identifies a kind of place. Check how selection supplies the specific place name.",
        "density": "Irregular silhouettes can separate neighbors, but their detail may fade at small sizes.",
    },
    {
        "id": "wayfinder",
        "name": "Wayfinder",
        "language": "Category as a map symbol",
        "description": "A solid ink map marker with a white pictogram and a colored ownership accent.",
        "category": "Does the white symbol remain recognizable inside the colored marker?",
        "identity": "A familiar marker anchors the place. Its specific identity still depends on selection and the name.",
        "density": "A consistent silhouette is easy to scan; compare how much of the map the filled shape covers.",
    },
    {
        "id": "letterpress",
        "name": "Letterpress",
        "language": "Place as a typographic mark",
        "description": "A serif initial from the place name, treated as an ink stamp.",
        "category": "An initial carries less category information. Consider whether that tradeoff fits the task.",
        "identity": "A name initial can cue a remembered place, but nearby places may share the same letter.",
        "density": "Simple letterforms can stay legible in a crowd. Watch for a field of indistinguishable initials.",
    },
    {
        "id": "totem",
        "name": "Totem",
        "language": "Meaning in a vertical stack",
        "description": "An icon and ownership status arranged vertically as one compact place marker.",
        "category": "Can the category icon be recognized independently from the status treatment?",
        "identity": "The stack separates category and status. Check that selection makes the exact place unambiguous.",
        "density": "The narrow shape saves horizontal space, while its height can overlap labels or nearby markers.",
    },
    {
        "id": "contour",
        "name": "Contour",
        "language": "Category in a few lines",
        "description": "A floating outline icon with a white keyline, giving the map more visual room.",
        "category": "Does the outline remain recognizable over roads, park textures, and native labels?",
        "identity": "The category leads; the selected name establishes the individual place. Check the perceived anchor.",
        "density": "Less fill leaves more cartography visible, but fine lines may lose contrast on busy map areas.",
    },
]

STATES = {
    "overview": "Overview",
    "selected": "Selected place",
    "compact": "Compact screen",
}


def esc(value: str) -> str:
    return html.escape(value, quote=True)


def make_data(captures: Path, output: Path) -> list[dict]:
    data = []
    for direction in DIRECTIONS:
        item = dict(direction)
        item["captures"] = {}
        for state in STATES:
            filename = (f"compact-{item['id']}.png" if state == "compact"
                        else f"pin-{item['id']}-{state}.png")
            relative = Path(os.path.relpath(captures / filename, output.parent)).as_posix()
            item["captures"][state] = {
                "src": quote(relative, safe="/"),
                "available": (captures / filename).is_file(),
            }
        data.append(item)
    return data


def cards_markup(data: list[dict]) -> str:
    cards = []
    for number, item in enumerate(data, start=1):
        capture = item["captures"]["overview"]
        alt = f"Astir {item['name']} pins — overview capture"
        available = capture["available"]
        image = (
            f'<a class="capture-link" href="{esc(capture["src"])}" target="_blank" rel="noopener" '
            f'aria-label="Open {esc(alt)} at original resolution"{" hidden" if not available else ""}>'
            f'<img src="{esc(capture["src"])}" alt="{esc(alt)}" loading="lazy" decoding="async">'
            '<span class="image-hint">Open original <span aria-hidden="true">↗</span></span></a>'
            f'<div class="capture-pending"{" hidden" if available else ""}>'
            '<strong>Capture pending</strong><span>This view appears when its native PNG capture is available.</span></div>'
        )
        detail = (
            '<div class="pin-detail"><p class="detail-label">Pin detail · same capture</p>'
            f'<a class="detail-window" href="{esc(capture["src"])}" target="_blank" rel="noopener" '
            f'aria-label="Open original {esc(item["name"])} overview capture; detail above is a CSS magnification"'
            f'{" hidden" if not available else ""}>'
            f'<img src="{esc(capture["src"])}" alt="Magnified pin within the unchanged {esc(item["name"])} overview capture" '
            'loading="lazy" decoding="async"></a>'
            f'<div class="detail-pending"{" hidden" if available else ""}>Overview capture pending</div>'
            '<p class="detail-source">Overview capture · enlarged view</p></div>'
        )
        cards.append(
            f'<article class="direction-card" data-direction="{item["id"]}">'
            f'<header class="card-heading"><span class="direction-number">{number:02d}</span>'
            f'<h3>{esc(item["name"])}</h3><p>{esc(item["language"])}</p></header>'
            f'{detail}<div class="capture-container">{image}</div>'
            f'<p class="direction-description">{esc(item["description"])}</p>'
            f'<button class="pick-button" type="button" data-pick="{item["id"]}" aria-pressed="false">'
            '<span class="pick-mark" aria-hidden="true">+</span> Compare</button></article>'
        )
    return "\n".join(cards)


def tradeoffs_markup(data: list[dict]) -> str:
    return "\n".join(
        '<tr>'
        f'<th scope="row"><span class="table-number">{number:02d}</span>{esc(item["name"])}</th>'
        f'<td>{esc(item["category"])}</td><td>{esc(item["identity"])}</td><td>{esc(item["density"])}</td>'
        '</tr>'
        for number, item in enumerate(data, start=1)
    )


TEMPLATE = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light">
<title>Astir — Five different languages for a place</title>
<style>
:root{--paper:#f7f5ee;--surface:#fffdf8;--ink:#282923;--muted:#6e7065;--rule:#dcddd1;--coral:#d85545;--coral-wash:#f6e6de;--shadow:0 13px 36px #3432250d}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:var(--paper);color:var(--ink);font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}h1,h2,h3,p{margin:0}a{color:inherit;text-underline-offset:4px;text-decoration-color:#a9aa9e}button{font:inherit;color:inherit;cursor:pointer;touch-action:manipulation}button:disabled{cursor:not-allowed;opacity:.45}button:focus-visible,a:focus-visible{outline:3px solid var(--coral);outline-offset:5px}[hidden]{display:none!important}img{display:block;max-width:100%}.shell{width:min(1560px,calc(100% - 88px));margin-inline:auto}.masthead{padding:25px 0 20px;display:flex;align-items:center;justify-content:space-between;gap:20px;border-bottom:1px solid var(--rule)}.wordmark{font-size:28px;letter-spacing:-1.5px;font-weight:760;text-decoration:none}.wordmark span{color:var(--coral)}.masthead p{font-size:11px;color:var(--muted)}.masthead nav{display:flex;gap:22px;font-size:11px;font-weight:600}.masthead nav a{text-decoration:none}.hero{padding:58px 0 43px;display:grid;grid-template-columns:1.4fr 1fr;gap:65px;align-items:end}.kicker,.section-number{display:block;font-size:10px;letter-spacing:.13em;text-transform:uppercase;font-weight:750;color:var(--coral)}h1{font-family:Georgia,"Times New Roman",serif;font-size:clamp(45px,5.5vw,78px);line-height:1.04;letter-spacing:-2.6px;font-weight:400;max-width:850px;margin-top:13px}h1 em{font-weight:400;color:var(--coral)}.hero-note{max-width:430px;padding:2px 0 5px 22px;border-left:2px solid var(--coral)}.hero-note p{font-size:14px;line-height:1.7;color:var(--muted)}.hero-note p+p{margin-top:12px}.hero-note strong{color:var(--ink);font-weight:600}.provenance{font-size:11px;color:var(--muted);padding:14px 0;border-top:1px solid var(--rule);border-bottom:1px solid var(--rule);display:flex;justify-content:space-between;gap:25px}.section{padding:43px 0 49px;scroll-margin-top:20px}.section-top{display:flex;justify-content:space-between;align-items:end;gap:22px;margin-bottom:27px}.heading-line{display:flex;align-items:baseline;gap:15px}h2{font:400 33px/1.2 Georgia,"Times New Roman",serif;letter-spacing:-.8px}.section-copy{font-size:12px;line-height:1.7;color:var(--muted);margin-top:11px;max-width:720px}.state-switch{display:flex;gap:3px;background:#eaeae0;border-radius:100px;padding:4px;flex-shrink:0}.state-switch button{border:0;background:transparent;border-radius:100px;font-size:11px;font-weight:650;padding:8px 15px;white-space:nowrap}.state-switch button[aria-pressed=true]{background:var(--surface);box-shadow:0 2px 6px #2425210d}.five-up{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:22px}.direction-card{min-width:0;display:flex;flex-direction:column;align-items:flex-start}.card-heading{min-height:105px;width:100%}.direction-number{font-size:10px;letter-spacing:.12em;font-weight:700;color:var(--coral)}h3{font-size:23px;letter-spacing:-.8px;font-weight:650;margin:5px 0 5px}.card-heading p{font-size:11px;line-height:1.5;color:var(--muted);max-width:190px}.capture-container{width:100%}.capture-link{display:block;position:relative;width:100%;border:1px solid #d6d7cb;border-radius:23px;overflow:hidden;background:#e7e8dc;box-shadow:var(--shadow);transition:transform .16s,border-color .16s;text-decoration:none}.capture-link:hover{transform:translateY(-3px);border-color:#a8ab9c}.capture-link img{width:100%;height:auto}.image-hint{position:absolute;right:10px;bottom:10px;padding:6px 9px;border-radius:100px;background:#fffdf8ee;box-shadow:0 1px 7px #0001;font-size:9px;color:var(--ink);opacity:0;transition:opacity .16s}.image-hint span{font-size:12px;margin-left:5px}.capture-link:hover .image-hint,.capture-link:focus-visible .image-hint{opacity:1}.capture-pending{min-height:390px;aspect-ratio:9/19.5;display:flex;flex-direction:column;justify-content:center;text-align:center;gap:9px;padding:25px;border:1px dashed #c9ccbd;background:#eeeee4;border-radius:23px;color:var(--muted)}.capture-pending strong{font-weight:600;font-size:12px}.capture-pending span{font-size:11px;line-height:1.65}.direction-description{font-size:12px;color:var(--muted);line-height:1.65;margin:16px 0 19px}.pick-button{margin-top:auto;background:transparent;border:1px solid var(--rule);border-radius:100px;display:flex;align-items:center;gap:8px;padding:6px 12px;color:var(--muted);font-size:11px;font-weight:650}.pick-mark{font-size:14px;line-height:1}.pick-button[aria-pressed=true]{border-color:var(--coral);background:var(--coral-wash);color:var(--coral)}.gallery-footnote{margin-top:24px;font-size:11px;color:var(--muted);border-top:1px solid var(--rule);padding-top:15px}.criteria{border-top:1px solid var(--rule)}.table-wrap{margin-top:25px;overflow:auto;border-bottom:1px solid var(--rule)}table{width:100%;border-collapse:collapse;text-align:left;font-size:12px;line-height:1.7}thead th{font-size:10px;letter-spacing:.07em;text-transform:uppercase;padding:0 23px 14px 0;color:var(--muted);font-weight:700}thead th:first-child{width:15%}thead th:not(:first-child){width:28.33%}tbody th,tbody td{vertical-align:top;border-top:1px solid var(--rule);padding:19px 23px 20px 0}tbody th{font-weight:650;font-size:13px;white-space:nowrap}tbody td{color:var(--muted)}.table-number{font-size:9px;color:var(--coral);display:block;margin-bottom:4px;letter-spacing:.1em}.read-note{font-size:12px;line-height:1.75;color:var(--muted);max-width:810px;margin-top:22px}.footer{padding:22px 0 109px;border-top:1px solid var(--rule);display:flex;justify-content:space-between;gap:20px;color:var(--muted);font-size:11px}.compare-tray{position:fixed;left:50%;bottom:21px;transform:translateX(-50%);z-index:10;display:flex;align-items:center;gap:22px;max-width:calc(100vw - 28px);background:var(--ink);color:var(--surface);padding:9px 10px 9px 22px;border-radius:100px;box-shadow:0 10px 40px #28292333}.compare-summary{font-size:12px;white-space:nowrap}.compare-tray button{border:0;border-radius:100px;background:var(--surface);padding:9px 17px;font-size:11px;font-weight:700;white-space:nowrap}.compare-tray .clear-picks{padding:8px 0;background:transparent;color:#dbddcf;font-weight:400}.live-status{position:fixed;width:1px;height:1px;overflow:hidden;clip-path:inset(50%)}dialog{padding:0;width:min(920px,calc(100vw - 28px));max-width:calc(100vw - 28px);max-height:calc(100dvh - 28px);border:1px solid #ffffff20;border-radius:22px;background:var(--paper);color:var(--ink)}dialog::backdrop{background:#171b17db;backdrop-filter:blur(8px)}.dialog-header{position:sticky;top:0;z-index:2;background:var(--paper);padding:16px 22px;display:flex;justify-content:space-between;align-items:center;gap:20px;border-bottom:1px solid var(--rule)}.dialog-header h2{font-family:inherit;font-size:15px;font-weight:650;letter-spacing:0}.close-compare{border:1px solid var(--rule);border-radius:100px;padding:7px 13px;font-size:11px;background:transparent}.compare-grid{display:grid;grid-template-columns:1fr 1fr;gap:27px;padding:23px 25px;align-items:start}.compare-grid article{min-width:0}.compare-grid h3{font-size:19px;margin:0 0 13px}.compare-grid h3 span{display:block;font-size:10px;font-weight:500;color:var(--muted);letter-spacing:0;margin-top:4px}.compare-grid .capture-link{max-width:355px;margin-inline:auto}.dialog-note{padding:0 25px 23px;font-size:11px;color:var(--muted)}.noscript{margin-top:20px;padding:14px 18px;background:var(--coral-wash);border-radius:12px;font-size:12px}
@media(min-width:1500px){.five-up{gap:30px}}@media(max-width:1150px){.shell{width:calc(100% - 48px)}.hero{gap:35px}.five-up{gap:14px}.card-heading{min-height:111px}.card-heading p{font-size:10px}.direction-description{font-size:11px}.capture-link,.capture-pending{border-radius:19px}.masthead>p{display:none}}@media(max-width:900px){.hero{grid-template-columns:1fr;gap:28px;padding:41px 0 33px}.hero-note{max-width:650px}.five-up{grid-template-columns:repeat(3,minmax(0,1fr));gap:30px 20px}.card-heading{min-height:105px}.card-heading p{font-size:11px}.direction-description{font-size:12px}.section-top{align-items:start;flex-direction:column;gap:18px}.provenance{display:block}.provenance span{display:block}.provenance span+span{margin-top:5px}table{min-width:760px}.footer{font-size:10px}.hero h1{max-width:660px}}@media(max-width:550px){.shell{width:calc(100% - 32px)}.masthead{padding:18px 0}.masthead nav{font-size:10px;gap:15px}.hero h1{font-size:47px;letter-spacing:-1.7px}.hero-note p{font-size:13px}.hero .kicker{font-size:9px}.five-up{grid-template-columns:repeat(2,minmax(0,1fr));gap:28px 14px}.card-heading{min-height:104px}.card-heading h3{font-size:21px}.card-heading p{font-size:10px}.direction-description{font-size:11px}.capture-link,.capture-pending{border-radius:17px}.capture-pending{min-height:300px;padding:18px}.section{padding-top:32px}h2{font-size:29px}.state-switch{width:100%;justify-content:space-between}.state-switch button{font-size:10px;padding:8px 11px;flex:1}.gallery-footnote{font-size:10px}.compare-tray{width:calc(100% - 24px);padding:10px 13px;border-radius:18px;gap:12px;justify-content:space-between;flex-wrap:wrap}.compare-summary{font-size:11px;max-width:100%;overflow:hidden;text-overflow:ellipsis}.compare-tray button{padding:8px 12px}.compare-grid{gap:13px;padding:17px}.compare-grid h3{font-size:17px}.compare-grid h3 span{font-size:9px}.dialog-header{padding:14px 17px}.dialog-header h2{font-size:13px}.dialog-note{padding:0 17px 19px;font-size:10px}.footer{display:block}.footer span{display:block}.footer span+span{margin-top:7px}.image-hint{display:none}}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}*{transition:none!important}}
</style>
<style>
/* Provisional focus supplied for the overview captures: normalized x/y and
   magnification. Verify framing against the final native captures. No PNG is
   cropped, edited, or re-encoded; overflow only defines the viewing window.
   JavaScript derives vertical positioning from each PNG's natural aspect. */
.pin-detail{width:100%;margin-bottom:22px}.detail-label{font-size:10px;font-weight:650;letter-spacing:.01em;margin-bottom:9px}.detail-window{display:block;width:100%;aspect-ratio:1;position:relative;overflow:hidden;background:#e7e8dc;border:1px solid #d6d7cb;border-radius:17px;box-shadow:var(--shadow)}.detail-window img{position:absolute;width:__DETAIL_WIDTH__%;max-width:none;height:auto;left:__DETAIL_LEFT__%;top:__DETAIL_TOP__%;display:block}.detail-source{font-size:9px;color:var(--muted);margin-top:7px}.detail-pending{width:100%;aspect-ratio:1;display:grid;place-items:center;padding:20px;border:1px dashed #c9ccbd;border-radius:17px;background:#eeeee4;color:var(--muted);font-size:11px;text-align:center}@media(max-width:550px){.pin-detail{margin-bottom:18px}.detail-label{font-size:9px}.detail-source{font-size:8px}.detail-window,.detail-pending{border-radius:13px}}
</style>
</head>
<body>
<div class="shell">
<header class="masthead"><a class="wordmark" href="#" aria-label="Astir, back to top">astir<span>.</span></a><p>A native map pin study · Second pass</p><nav aria-label="On this page"><a href="#directions">Five directions</a><a href="#criteria">What to assess</a></nav></header>
<main>
<div class="hero"><div><span class="kicker">REC-657 · Five new native pinsets</span><h1>Five different languages<br>for <em>a place.</em></h1></div><div class="hero-note"><p>Objects, symbols, letters, stacks, and outlines. Five distinct ways to make a place recognizable on Astir’s map.</p><p><strong>No preferred direction yet.</strong> Review category recognition, place identity, and map density across the native captures.</p></div></div>
<div class="provenance"><span>Development-only native captures · This page is a comparison artifact, not the Astir app.</span><span>Map detail can vary with network and coverage.</span></div>
<noscript><p class="noscript">Overview captures are shown below. JavaScript enables state switching and two-direction comparison. Each available image opens its original PNG.</p></noscript>
<section class="section" id="directions" aria-labelledby="directions-title"><div class="section-top"><div><div class="heading-line"><span class="section-number">01</span><h2 id="directions-title">Five directions, equal footing</h2></div><p class="section-copy">Inspect each pin in an enlarged window, then review its full map below. The detail windows always show the unchanged overview capture; the state switch changes the full phone images. Select two directions to compare, or click a capture to open its original PNG.</p></div><div class="state-switch" role="group" aria-label="Capture state"><button type="button" data-state="overview" aria-pressed="true">Overview</button><button type="button" data-state="selected" aria-pressed="false">Selected place</button><button type="button" data-state="compact" aria-pressed="false">Compact screen</button></div></div><div class="five-up">__CARDS__</div><p class="gallery-footnote">These treatments use custom vectors, SF Symbols, or typography instead of standard category emoji. Detail windows magnify the same screenshot with CSS; no capture pixels are altered. The screenshots are visual evidence, not a claim that all functionality has been tested.</p></section>
<section class="section criteria" id="criteria" aria-labelledby="criteria-title"><div class="heading-line"><span class="section-number">02</span><h2 id="criteria-title">What earns its place on the map?</h2></div><p class="section-copy">Use these tradeoffs as review prompts, not measured findings. Check the same visual language at overview scale, in selection, and on the smaller screen.</p><div class="table-wrap" role="region" aria-label="Pin direction tradeoffs" tabindex="0"><table><thead><tr><th scope="col">Direction</th><th scope="col">Category recognition</th><th scope="col">Place identity</th><th scope="col">Map density</th></tr></thead><tbody>__TRADEOFFS__</tbody></table></div><p class="read-note">Across all five, inspect whether ownership status remains legible, whether the selected place feels attached to the correct point, and how comfortably surrounding map labels can be read. Visual clarity in a screenshot does not establish gesture behavior, hit targets, accessibility, or coordinate accuracy.</p></section>
</main>
<footer class="footer"><span>Astir · Second-pass pin exploration</span><span>Local PNG captures · No external fonts, scripts, or image assets</span></footer>
</div>
<aside class="compare-tray" aria-label="Comparison selection" hidden><p class="compare-summary">Choose two directions</p><button class="clear-picks" type="button">Clear</button><button class="open-compare" type="button" disabled>Compare two</button></aside>
<p class="live-status" id="status" aria-live="polite"></p>
<dialog aria-labelledby="comparison-title"><header class="dialog-header"><h2 id="comparison-title">Side by side</h2><button class="close-compare" type="button">Close</button></header><div class="compare-grid"></div><p class="dialog-note">Click an available image to open its original PNG. Framing, native labels, and loaded map detail may vary between captures.</p></dialog>
<script>
"use strict";
const directions=__DATA__;
// Normalized focal coordinates are configurable at generation time. They must
// be visually checked when final captures arrive; this is not an auto-detector.
const detailFocus=__DETAIL_FOCUS__;
const stateNames={overview:"Overview",selected:"Selected place",compact:"Compact screen"};
let currentState="overview";
let selected=[];
const tray=document.querySelector(".compare-tray");
const dialog=document.querySelector("dialog");
const status=document.querySelector("#status");

function alignDetail(img){
 if(!img.naturalWidth||!img.naturalHeight)return;
 img.style.width=`${detailFocus.zoom*100}%`;
 img.style.left=`${50-detailFocus.x*detailFocus.zoom*100}%`;
 img.style.top=`${50-detailFocus.y*detailFocus.zoom*100*(img.naturalHeight/img.naturalWidth)}%`;
}
function bindDetail(img){
 img.addEventListener("load",()=>alignDetail(img));
 img.addEventListener("error",()=>{
  const detail=img.closest(".pin-detail");
  detail.querySelector(".detail-window").hidden=true;
  detail.querySelector(".detail-pending").hidden=false;
 });
 if(img.complete)alignDetail(img);
}
document.querySelectorAll(".detail-window img").forEach(bindDetail);

function direction(id){return directions.find(item=>item.id===id);}
function setPending(container,pending){
 container.querySelector(".capture-link").hidden=pending;
 container.querySelector(".capture-pending").hidden=!pending;
}
function bindCapture(container){
 const img=container.querySelector("img");
 img.addEventListener("error",()=>{
  setPending(container,true);
  const card=container.closest("[data-direction]");
  if(card)direction(card.dataset.direction).captures[currentState].available=false;
 });
 if(img.complete&&img.naturalWidth===0&&img.getAttribute("src"))setPending(container,true);
}
document.querySelectorAll(".capture-container").forEach(bindCapture);
function refreshCapture(container,item){
 const capture=item.captures[currentState];
 const link=container.querySelector(".capture-link");
 const img=link.querySelector("img");
 const alt=`Astir ${item.name} pins — ${stateNames[currentState].toLowerCase()} capture`;
 link.href=capture.src;
 link.setAttribute("aria-label",`Open ${alt} at original resolution`);
 img.alt=alt;
 setPending(container,!capture.available);
 img.src=capture.src;
}
function refreshTray(){
 tray.hidden=selected.length===0;
 document.querySelector(".compare-summary").textContent=selected.map(id=>direction(id).name).join(" + ")+(selected.length===1?" · choose one more":"");
 document.querySelector(".open-compare").disabled=selected.length!==2;
 document.querySelectorAll("[data-pick]").forEach(button=>{
  const picked=selected.includes(button.dataset.pick);
  button.setAttribute("aria-pressed",String(picked));
  button.querySelector(".pick-mark").textContent=picked?"−":"+";
 });
}
document.querySelectorAll("[data-state]").forEach(button=>button.addEventListener("click",()=>{
 currentState=button.dataset.state;
 document.querySelectorAll("[data-state]").forEach(control=>control.setAttribute("aria-pressed",String(control===button)));
 document.querySelectorAll(".direction-card").forEach(card=>refreshCapture(card.querySelector(".capture-container"),direction(card.dataset.direction)));
 status.textContent=`Showing ${stateNames[currentState].toLowerCase()} captures for all five directions.`;
}));
document.querySelectorAll("[data-pick]").forEach(button=>button.addEventListener("click",()=>{
 const id=button.dataset.pick;
 if(selected.includes(id))selected=selected.filter(pick=>pick!==id);
 else if(selected.length<2)selected.push(id);
 else {status.textContent="Two directions are selected. Deselect one or clear your selection before choosing another.";return;}
 refreshTray();
 status.textContent=selected.length===2?"Two directions selected. Open Compare two to view them side by side.":selected.length===1?"One direction selected. Choose one more.":"Comparison selection cleared.";
}));
document.querySelector(".clear-picks").addEventListener("click",()=>{selected=[];refreshTray();status.textContent="Comparison selection cleared.";});
document.querySelector(".open-compare").addEventListener("click",()=>{
 const grid=document.querySelector(".compare-grid");
 grid.replaceChildren();
 document.querySelector("#comparison-title").textContent=`Side by side · ${stateNames[currentState]}`;
 selected.forEach(id=>{
  const item=direction(id);
  const original=document.querySelector(`.direction-card[data-direction="${id}"]`);
  const article=document.createElement("article");
  const heading=document.createElement("h3");
  heading.textContent=item.name;
  const subtitle=document.createElement("span");
  subtitle.textContent=item.language;
  heading.append(subtitle);
  const detail=original.querySelector(".pin-detail").cloneNode(true);
  const container=original.querySelector(".capture-container").cloneNode(true);
  article.append(heading,detail,container);
  grid.append(article);
  bindDetail(detail.querySelector("img"));
  bindCapture(container);
 });
 dialog.showModal();
});
document.querySelector(".close-compare").addEventListener("click",()=>dialog.close());
dialog.addEventListener("click",event=>{
 if(event.target!==dialog)return;
 const bounds=dialog.getBoundingClientRect();
 if(event.clientX<bounds.left||event.clientX>bounds.right||event.clientY<bounds.top||event.clientY>bounds.bottom)dialog.close();
});
</script>
</body>
</html>
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--captures-dir", type=Path, required=True,
                        help="Directory containing pin-{style}-{overview,selected}.png and compact-{style}.png")
    parser.add_argument("--output", type=Path, default=Path("index.html"),
                        help="HTML path inside the capture directory (default: index.html)")
    parser.add_argument("--detail-focus-x", type=float, default=0.39,
                        help="Overview pin focus as a fraction of image width; verify against final captures (default: 0.39)")
    parser.add_argument("--detail-focus-y", type=float, default=0.283,
                        help="Overview pin focus as a fraction of image height; verify against final captures (default: 0.283)")
    parser.add_argument("--detail-zoom", type=float, default=8.0,
                        help="CSS image width relative to the square pin-detail viewport (default: 8)")
    args = parser.parse_args()
    if not 0 <= args.detail_focus_x <= 1 or not 0 <= args.detail_focus_y <= 1:
        parser.error("Detail focus coordinates must be between 0 and 1")
    if not 1 <= args.detail_zoom <= 30:
        parser.error("--detail-zoom must be between 1 and 30")
    captures = args.captures_dir.expanduser().resolve()
    if not captures.is_dir():
        parser.error(f"Capture directory does not exist: {captures}")
    requested_output = args.output.expanduser()
    output = (requested_output if requested_output.is_absolute() else captures / requested_output).resolve()
    try:
        output.relative_to(captures)
    except ValueError:
        parser.error("--output must be inside --captures-dir")
    if output.suffix.lower() not in {".html", ".htm"}:
        parser.error("--output must have an .html or .htm extension")
    if not output.parent.is_dir():
        parser.error("The output parent directory must already exist")
    data = make_data(captures, output)
    detail_focus = {"x": args.detail_focus_x, "y": args.detail_focus_y, "zoom": args.detail_zoom}
    rendered = (TEMPLATE.replace("__CARDS__", cards_markup(data))
                .replace("__TRADEOFFS__", tradeoffs_markup(data))
                .replace("__DATA__", json.dumps(data, ensure_ascii=False).replace("<", "\\u003c"))
                .replace("__DETAIL_FOCUS__", json.dumps(detail_focus))
                .replace("__DETAIL_WIDTH__", f"{args.detail_zoom * 100:g}")
                .replace("__DETAIL_LEFT__", f"{50 - args.detail_focus_x * args.detail_zoom * 100:g}")
                .replace("__DETAIL_TOP__", f"{50 - args.detail_focus_y * args.detail_zoom * 100 / 0.46:g}"))
    output.write_text(rendered, encoding="utf-8")
    available = sum(capture["available"] for item in data for capture in item["captures"].values())
    print(f"Gallery written: {output}")
    print(f"Native PNG captures present at generation: {available}/15")


if __name__ == "__main__":
    main()
