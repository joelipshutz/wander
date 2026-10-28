#!/usr/bin/env python3
"""Generate a local, dependency-free gallery for Astir's map design captures."""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path


PINS = [
    ("porcelain", "Porcelain", "Start here", "A quieter presence that gives the map room to breathe."),
    ("signal", "Signal", "Bolder alternative", "A stronger visual accent when place recognition needs more emphasis."),
    ("bookmark", "Bookmark", "Memory cue", "A saved-place silhouette with a different rhythm across the map."),
    ("ticket", "Ticket", "Graphic alternative", "A compact, graphic treatment to compare against the softer families."),
    ("compass", "Compass", "Directional character", "A more geometric expression of a place on the map."),
]

MAPS = [
    ("quiet", "Quiet", "Current baseline", "Standard · flat · muted", "The current native map configuration. Our starting recommendation for a calm backdrop."),
    ("atlas", "Atlas", "More map emphasis", "Standard · flat · default", "Native map colors receive more emphasis. Compare how clearly the Astir pins stand apart."),
    ("night", "Night", "Supported appearance", "Standard · flat · muted · Dark", "The system Dark appearance of the same native cartography, not a new map style."),
    ("dimension", "Terrain", "Richer geography", "Standard · realistic · default · flat camera", "More terrain detail where supported. Keeps the existing camera behavior; forced perspective was excluded after reducing visible-pin density."),
    ("hybrid", "Hybrid", "Optional exploration", "Hybrid · flat", "Aerial imagery with native roads and labels. Useful geographic context, with a busier backdrop."),
]


def esc(value: str) -> str:
    return html.escape(value, quote=True)


def capture_markup(filename: str, alt: str, *, extra: str = "") -> str:
    return (
        f'<button class="capture {extra}" type="button" data-lightbox="{esc(filename)}" '
        f'aria-label="Enlarge {esc(alt)}">'
        f'<img src="{esc(filename)}" alt="{esc(alt)}" loading="lazy" decoding="async">'
        '<span class="capture-missing" hidden>Capture unavailable<span>Generate this screenshot to view it here.</span></span>'
        '<span class="enlarge" aria-hidden="true">↗</span></button>'
    )


def pin_cards() -> str:
    cards = []
    for ident, name, badge, description in PINS:
        image = f"pin-{ident}-overview.png"
        cards.append(
            f'<article class="design-card pin-card" data-id="{ident}">'
            f'<div class="card-heading"><span class="eyebrow">{esc(badge)}</span><h3>{name}</h3></div>'
            f'{capture_markup(image, f"{name} pins — overview")}'
            f'<p class="card-copy">{esc(description)}</p>'
            f'<button class="compare-toggle" type="button" data-pick="pin:{ident}" aria-pressed="false">'
            '<span aria-hidden="true">＋</span> Compare</button></article>'
        )
    return "\n".join(cards)


def map_cards() -> str:
    cards = []
    for ident, name, badge, specification, description in MAPS:
        cards.append(
            f'<article class="design-card map-card{" baseline-card" if ident == "quiet" else ""}" data-id="{ident}">'
            f'<div class="card-heading"><span class="eyebrow">{esc(badge)}</span><h3>{name}</h3></div>'
            f'{capture_markup(f"map-{ident}.png", f"{name} native map")}'
            f'<p class="native-spec">{esc(specification)}</p><p class="card-copy">{esc(description)}</p>'
            f'<button class="compare-toggle" type="button" data-pick="map:{ident}" aria-pressed="false">'
            '<span aria-hidden="true">＋</span> Compare</button></article>'
        )
    return "\n".join(cards)


HTML = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<title>Astir — A place on the map</title>
<style>
:root{--paper:#f6f3ec;--card:#fffdf8;--ink:#242521;--muted:#686b62;--line:#deded3;--coral:#db5849;--soft-coral:#f5e6de;--radius:22px;--shadow:0 12px 32px #29271d0c}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:var(--paper);color:var(--ink);font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}button,a{-webkit-tap-highlight-color:transparent}button{font:inherit;color:inherit;cursor:pointer}button:disabled{cursor:not-allowed;opacity:.45}button:focus-visible,a:focus-visible{outline:3px solid var(--coral);outline-offset:5px}a{color:inherit;text-decoration-color:#a5a697;text-underline-offset:4px}a:hover{text-decoration-color:var(--coral)}button{touch-action:manipulation}img{display:block;max-width:100%}button[hidden],[hidden]{display:none!important}
.shell{width:min(1580px,calc(100% - 88px));margin:auto}.masthead{padding:27px 0 22px;border-bottom:1px solid var(--line);display:flex;align-items:center;justify-content:space-between;gap:20px}.brand{font-size:27px;font-weight:760;letter-spacing:-1.5px}.brand-dot{color:var(--coral)}.masthead nav{display:flex;gap:24px;font-size:12px;font-weight:650}.masthead nav a{text-decoration:none}.meta{font-size:11px;color:var(--muted);letter-spacing:.01em}.hero{padding:66px 0 51px;display:grid;grid-template-columns:1.45fr 1fr;gap:75px;align-items:end}.eyebrow,.section-number{display:block;font-size:10px;letter-spacing:.12em;text-transform:uppercase;font-weight:750;color:var(--muted)}.hero .eyebrow{color:var(--coral);margin-bottom:14px}h1,h2,h3,p{margin:0}h1{font-family:Georgia,"Times New Roman",serif;font-size:clamp(44px,5.6vw,80px);line-height:1.02;letter-spacing:-2.8px;font-weight:400;max-width:700px}h1 em{font-style:italic;color:var(--coral)}.lede{font-size:17px;color:var(--muted);max-width:550px;margin-top:24px;line-height:1.6}.recommendation{background:var(--card);border:1px solid var(--line);border-top:3px solid var(--coral);padding:25px 27px;border-radius:3px 3px 18px 18px;box-shadow:var(--shadow)}.recommendation h2{font-size:24px;letter-spacing:-.7px;margin:8px 0 10px}.recommendation p{color:var(--muted);font-size:13px;line-height:1.65}.recommendation p+p{margin-top:11px}.recommendation strong{color:var(--ink)}.capture-note{padding:15px 0;border-top:1px solid var(--line);border-bottom:1px solid var(--line);display:flex;justify-content:space-between;gap:25px;font-size:11px;color:var(--muted)}
section{padding:50px 0 55px;scroll-margin-top:20px}.section-header{display:flex;justify-content:space-between;align-items:end;gap:25px;margin-bottom:25px}.section-title{display:flex;align-items:baseline;gap:15px}.section-number{color:var(--coral)}h2{font-family:Georgia,"Times New Roman",serif;font-size:35px;line-height:1.15;font-weight:400;letter-spacing:-.8px}.section-intro{max-width:720px;color:var(--muted);font-size:13px;margin-top:13px;line-height:1.65}.segmented{display:inline-flex;gap:3px;padding:4px;background:#eae9e1;border-radius:100px;flex-shrink:0}.segmented button{border:0;border-radius:100px;background:transparent;padding:8px 17px;font-size:12px;font-weight:650;white-space:nowrap}.segmented button[aria-pressed=true]{background:var(--card);box-shadow:0 2px 6px #2425210c}.phone-grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:19px}.design-card{min-width:0;display:flex;flex-direction:column;align-items:flex-start}.card-heading{min-height:61px;width:100%}.card-heading .eyebrow{font-size:9px;letter-spacing:.08em;color:var(--muted);margin-bottom:5px}.card-heading h3{font-size:20px;font-weight:650;letter-spacing:-.7px}.pin-card:first-child .eyebrow,.baseline-card .eyebrow{color:var(--coral)}.capture{position:relative;width:100%;padding:0;border:1px solid #d3d3c8;background:#e8e8de;border-radius:var(--radius);overflow:hidden;box-shadow:var(--shadow);text-align:left;isolation:isolate;transition:transform .18s,border-color .18s}.capture:hover{transform:translateY(-3px);border-color:#aeb1a3}.capture img{width:100%;height:auto}.capture-missing{min-height:360px;display:grid;place-content:center;text-align:center;padding:25px;font-size:13px;color:var(--muted)}.capture-missing span{display:block;margin-top:8px;font-size:11px}.enlarge{position:absolute;right:10px;bottom:10px;width:27px;height:27px;display:grid;place-items:center;border-radius:50%;font-size:17px;background:#fffdf8e8;color:var(--ink);box-shadow:0 1px 8px #0002;opacity:0;transition:opacity .15s}.capture:hover .enlarge,.capture:focus-visible .enlarge{opacity:1}.card-copy{font-size:12px;line-height:1.6;color:var(--muted);margin:15px 0 17px}.native-spec{margin:15px 0 0;font-size:10px;font-weight:700;line-height:1.5;min-height:30px}.native-spec+.card-copy{margin-top:8px}.compare-toggle{margin-top:auto;padding:6px 10px;border:1px solid var(--line);border-radius:100px;background:transparent;font-size:11px;color:var(--muted);font-weight:600;display:flex;align-items:center;gap:6px}.compare-toggle[aria-pressed=true]{border-color:var(--coral);color:var(--coral);background:var(--soft-coral)}.section-footnote{font-size:11px;color:var(--muted);margin-top:24px;padding-top:15px;border-top:1px solid var(--line)}#maps,#reference,#research{border-top:1px solid var(--line)}.reference-layout{display:grid;grid-template-columns:minmax(0,1.3fr) minmax(0,.65fr) minmax(0,.65fr);gap:35px;align-items:start}.reference-prose{padding-right:40px}.reference-prose p{font-size:14px;color:var(--muted);margin-top:20px;line-height:1.75}.reference-prose strong{color:var(--ink)}.reference-shot{max-width:280px;justify-self:end;width:100%}.reference-shot h3{font-size:14px;margin-bottom:13px}.reference-shot p{font-size:11px;color:var(--muted);margin-top:13px}.research-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:28px 40px;margin-top:28px}.research-item{border-top:1px solid var(--line);padding-top:18px}.research-item h3{font-size:14px;margin-bottom:9px}.research-item p{font-size:12px;line-height:1.7;color:var(--muted)}.research-item a{display:inline-block;font-size:11px;margin-top:10px}.footer{display:flex;justify-content:space-between;gap:20px;color:var(--muted);font-size:11px;padding:25px 0 110px;border-top:1px solid var(--line)}
.compare-tray{position:fixed;left:50%;bottom:22px;transform:translateX(-50%);z-index:10;background:var(--ink);color:var(--card);border-radius:100px;padding:9px 10px 9px 21px;display:flex;align-items:center;gap:22px;box-shadow:0 8px 35px #24252135;max-width:calc(100% - 30px)}.compare-tray p{font-size:12px;white-space:nowrap}.compare-tray button{background:var(--card);border:0;border-radius:100px;padding:9px 17px;font-size:11px;font-weight:700;white-space:nowrap}.compare-tray .clear{background:transparent;color:#d9dbd0;padding:8px 0;font-weight:400}.status{position:fixed;width:1px;height:1px;overflow:hidden;clip-path:inset(50%)}dialog{padding:0;border:1px solid #ffffff20;border-radius:22px;background:var(--paper);color:var(--ink);max-width:calc(100vw - 32px);max-height:calc(100dvh - 32px)}dialog::backdrop{background:#171b17d9;backdrop-filter:blur(8px)}.dialog-header{position:sticky;top:0;z-index:2;background:var(--paper);display:flex;align-items:center;justify-content:space-between;gap:20px;padding:15px 20px;border-bottom:1px solid var(--line)}.dialog-header h2{font-family:inherit;font-size:14px;font-weight:650;letter-spacing:0}.close-modal{border:1px solid var(--line);border-radius:100px;background:transparent;font-size:11px;padding:7px 13px}.image-dialog{width:min(950px,calc(100vw - 32px));height:calc(100dvh - 32px)}.lightbox-tools{display:flex;gap:8px;align-items:center}.zoom-toggle{border:1px solid var(--line);background:transparent;border-radius:100px;padding:7px 13px;font-size:11px}.image-stage{height:calc(100% - 64px);overflow:auto;text-align:center;padding:20px;background:#e8e8de}.image-stage img{display:inline-block;max-height:100%;width:auto;max-width:100%;border-radius:12px;vertical-align:top}.image-stage.native-size img{max-width:none;max-height:none;width:auto;border-radius:0}.compare-dialog{width:min(880px,calc(100vw - 32px))}.comparison-grid{display:grid;grid-template-columns:1fr 1fr;gap:22px;padding:24px;align-items:start}.comparison-grid h3{font-size:16px;letter-spacing:-.4px;margin-bottom:12px}.comparison-grid .capture{max-width:340px;display:block;margin:auto}.comparison-grid .compare-kind{display:block;color:var(--muted);font-size:10px;font-weight:500;letter-spacing:.04em;margin-top:5px}.modal-note{font-size:11px;color:var(--muted);padding:0 24px 22px}.noscript{padding:15px;background:var(--soft-coral);font-size:12px;margin-top:20px}
@media(min-width:1500px){.phone-grid{gap:29px}.capture{border-radius:27px}}@media(max-width:1100px){.shell{width:calc(100% - 44px)}.hero{gap:35px}.phone-grid{gap:12px}.card-copy{font-size:11px}.card-heading .eyebrow{font-size:8px}.card-heading h3{font-size:18px}.capture{border-radius:17px}.reference-prose{padding-right:10px}.reference-layout{gap:22px}.research-grid{gap:25px}.masthead .meta{display:none}}@media(max-width:780px){.hero{grid-template-columns:1fr;padding:43px 0 32px;gap:28px}.hero .recommendation{max-width:none}.hero h1{max-width:580px}.lede{font-size:15px;margin-top:20px}.phone-grid{grid-template-columns:repeat(3,minmax(0,1fr));gap:28px 17px}.section-header{align-items:start;flex-direction:column;gap:18px}.capture-note{display:block}.capture-note span{display:block}.capture-note span+span{margin-top:5px}.reference-layout{grid-template-columns:1fr 1fr;gap:24px}.reference-prose{grid-column:1/-1;max-width:600px}.reference-shot{justify-self:start;max-width:250px}.research-grid{grid-template-columns:1fr 1fr}.compare-tray{gap:12px}.compare-tray p{font-size:11px}.compare-tray .clear{font-size:10px}.masthead nav{gap:15px;font-size:11px}h2{font-size:31px}}@media(max-width:500px){.shell{width:calc(100% - 32px)}.masthead{padding:19px 0}.masthead nav a:last-child{display:none}.hero h1{font-size:49px;letter-spacing:-1.9px}.hero .eyebrow{font-size:9px}.phone-grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:25px 14px}.card-heading{min-height:55px}.card-heading h3{font-size:18px}.card-heading .eyebrow{font-size:8px}.capture{border-radius:16px}.card-copy{margin-top:12px}.research-grid{grid-template-columns:1fr}.section-intro{font-size:12px}.reference-layout{gap:16px}.reference-shot h3{font-size:12px}.footer{display:block}.footer span{display:block;margin-top:7px}.compare-tray{width:calc(100% - 24px);border-radius:18px;padding:10px 12px;gap:10px;flex-wrap:wrap;justify-content:space-between}.compare-tray p{max-width:100%;overflow:hidden;text-overflow:ellipsis}.compare-tray button{padding:8px 13px}.comparison-grid{gap:12px;padding:16px}.comparison-grid h3{font-size:14px}.dialog-header{padding:12px 14px}.dialog-header h2{font-size:12px}.lightbox-tools{gap:5px}.zoom-toggle,.close-modal{padding:6px 9px;font-size:10px}.image-stage{padding:12px}.modal-note{padding:0 16px 18px}.recommendation{padding:20px 22px}}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}*{transition:none!important}}
</style>
</head>
<body>
<div class="shell">
<header class="masthead"><a class="brand" href="#" aria-label="Astir, back to top">astir<span class="brand-dot">.</span></a><span class="meta">A map of places worth returning to</span><nav aria-label="On this page"><a href="#pins">Pins</a><a href="#maps">Maps</a><a href="#reference">Reference</a><a href="#research">Research</a></nav></header>
<main>
<div class="hero"><div><span class="eyebrow">Map design study · REC-657</span><h1>A place<br>on <em>the map.</em></h1><p class="lede">Five pin families. Five native map treatments. A closer look at how Astir’s place memories can feel clear, familiar, and distinctly its own.</p></div><aside class="recommendation"><span class="eyebrow">Recommended starting point</span><h2>Porcelain + Quiet</h2><p>Start with a readable pin and a restrained map. <strong>Quiet is the current base-map configuration</strong>; choosing it preserves that foundation.</p><p>Try <strong>Signal</strong> for a bolder presence. Keep Dimension and Hybrid as optional exploration views. The recommendation is a design judgment for review, not a measured result.</p></aside></div>
<div class="capture-note"><span>Development-only exploration · Captured from the Astir iOS app</span><span>Map tiles vary with network and coverage. Click a capture to enlarge.</span></div>
<noscript><p class="noscript">JavaScript enables selection-state switching, enlarged captures, and comparison. The overview gallery remains visible without it.</p></noscript>
<section id="pins" aria-labelledby="pins-title"><div class="section-header"><div><div class="section-title"><span class="section-number">01</span><h2 id="pins-title">A family of place markers</h2></div><p class="section-intro">The same place semantics in five visual treatments. Every family retains category emoji and ownership status rings. Switch states to inspect the selected place in context.</p></div><div class="segmented" role="group" aria-label="Pin capture state"><button type="button" data-state="overview" aria-pressed="true">Overview</button><button type="button" data-state="selected" aria-pressed="false">Selected place</button></div></div><div class="phone-grid">__PIN_CARDS__</div><p class="section-footnote">Compare the visible footprint, contrast against roads and labels, and clarity of selection. These captures introduce no invented ratings, people, or photos.</p></section>
<section id="maps" aria-labelledby="maps-title"><div class="section-header"><div><div class="section-title"><span class="section-number">02</span><h2 id="maps-title">Let the place lead</h2></div><p class="section-intro">Native MapKit configurations, shown with all native points of interest included. No POI filters are applied, retaining the native places available for selection. These are supported map styles and appearance settings, not arbitrary recolored map tiles.</p></div></div><div class="phone-grid">__MAP_CARDS__</div><p class="section-footnote">Quiet and Atlas differ in native emphasis. Night changes supported system appearance. Dimension starts at a 40° pitch; realistic detail depends on geographic coverage. Hybrid adds imagery and its visual texture.</p></section>
<section id="reference" aria-labelledby="reference-title"><div class="reference-layout"><div class="reference-prose"><div class="section-title"><span class="section-number">03</span><h2 id="reference-title">Keep a reference close</h2></div><p><strong>Quiet matches the current base-map configuration:</strong> standard, flat, muted, with all native POIs included. It is a baseline choice, not a newly invented cartographic style.</p><p>The baseline capture is the reference for this exploration. Differences in tiles, coverage, camera framing, and loaded map detail can affect a comparison. A screenshot is visual evidence; it does not establish that every interaction or device state has been validated.</p><p>The compact-screen Porcelain capture adds a useful second scale. Review the selected place, nearby labels, and the space left for map interaction before choosing a direction.</p></div><article class="reference-shot"><h3>Baseline reference</h3>__BASELINE__<p>Existing appearance at the recorded capture state.</p></article><article class="reference-shot"><h3>Porcelain · compact screen</h3>__COMPACT__<p>A smaller canvas for reviewing the recommended pin family.</p></article></div></section>
<section id="research" aria-labelledby="research-title"><div class="section-title"><span class="section-number">04</span><h2 id="research-title">What informed the study</h2></div><p class="section-intro">Primary sources describe useful patterns. Their application to Astir is a design inference; this gallery makes no claim about conversion, preference, or measured usability.</p><div class="research-grid"><article class="research-item"><h3>Apple · a readable foreground</h3><p>Apple recommends distinct selection styling, clustering where annotations overlap, and muted maps when custom content needs to stand out. The map should retain familiar interactions.</p><a href="https://developer.apple.com/design/human-interface-guidelines/maps" target="_blank" rel="noreferrer">Read Apple’s map guidance ↗</a></article><article class="research-item"><h3>Google · recognizable categories</h3><p>Google’s documented map refresh pairs category colors with recognizable icons. For Astir, category emoji and ownership rings retain meaning across the different pin shapes.</p><a href="https://blog.google/products-and-platforms/products/maps/google-maps-gets-new-look/" target="_blank" rel="noreferrer">See Google’s design explanation ↗</a></article><article class="research-item"><h3>Airbnb · selective visual detail</h3><p>Airbnb documents larger informative pins alongside mini-pins and persistent pins during pan and zoom. The transferable idea is a stable visual hierarchy, not a reason to add price-like scores.</p><a href="https://airbnb.tech/ai-ml/improving-search-ranking-for-maps/" target="_blank" rel="noreferrer">Read Airbnb’s map research ↗</a></article><article class="research-item"><h3>Beli · memories with social context</h3><p>Beli describes maps for places visited and places to try, informed by friends’ opinions. That supports reviewing how a map communicates personal place state and trusted context.</p><a href="https://beliapp.com/" target="_blank" rel="noreferrer">See Beli’s product overview ↗</a></article><article class="research-item"><h3>Mapstr · meaning beyond a color</h3><p>Mapstr supports place icons, personal tags, and tried or to-try status. Those are separate meanings to preserve when evaluating a visual pin treatment.</p><a href="https://en.mapstr.com/faq" target="_blank" rel="noreferrer">Read Mapstr’s product FAQ ↗</a></article><article class="research-item"><h3>MapKit · native choices</h3><p>MapKit provides standard, imagery, and hybrid styles with supported emphasis and elevation controls. Native Dark appearance is an appearance choice; arbitrary road and land colors are not part of these configurations.</p><a href="https://developer.apple.com/documentation/MapKit/MapStyle" target="_blank" rel="noreferrer">See native map styles ↗</a><br><a href="https://developer.apple.com/documentation/uikit/uiview/overrideuserinterfacestyle" target="_blank" rel="noreferrer">See supported appearance control ↗</a></article></div></section>
</main><footer class="footer"><span>Astir · Map design exploration</span><span>Local capture gallery · No external fonts, scripts, or image services</span></footer>
</div>
<aside class="compare-tray" aria-label="Selected comparisons" hidden><p id="compare-summary">Choose two captures</p><button class="clear" type="button">Clear</button><button class="open-compare" type="button" disabled>Compare two →</button></aside><p class="status" aria-live="polite" id="status"></p>
<dialog class="compare-dialog" aria-labelledby="comparison-title"><div class="dialog-header"><h2 id="comparison-title">Side by side</h2><button class="close-modal" type="button">Close ✕</button></div><div class="comparison-grid"></div><p class="modal-note">Click either capture to enlarge it. Camera, tile loading, and geographic detail may differ between captures.</p></dialog>
<dialog class="image-dialog" aria-labelledby="image-title"><div class="dialog-header"><h2 id="image-title">Capture</h2><div class="lightbox-tools"><button class="zoom-toggle" type="button" aria-pressed="false">Actual pixels</button><button class="close-modal" type="button">Close ✕</button></div></div><div class="image-stage"><img alt="" src=""></div></dialog>
<script>
"use strict";
const pinData=__PIN_DATA__;
const mapData=__MAP_DATA__;
let pinState="overview";
let picks=[];
const tray=document.querySelector(".compare-tray");
const imageDialog=document.querySelector(".image-dialog");
const compareDialog=document.querySelector(".compare-dialog");
const stage=document.querySelector(".image-stage");
const status=document.querySelector("#status");
const zoomButton=document.querySelector(".zoom-toggle");

function describePick(key){
 const [kind,id]=key.split(":");
 const item=(kind==="pin"?pinData:mapData).find(entry=>entry[0]===id);
 return {key,kind,id,name:item[1],file:kind==="pin"?`pin-${id}-${pinState}.png`:`map-${id}.png`,detail:kind==="pin"?`${pinState==="overview"?"Overview":"Selected place"} · pin family`:"Native map configuration"};
}
function updateTray(){
 tray.hidden=picks.length===0;
 document.querySelector("#compare-summary").textContent=picks.length?picks.map(key=>describePick(key).name).join(" + ")+(picks.length===1?" · choose one more":""):"Choose two captures";
 document.querySelector(".open-compare").disabled=picks.length!==2;
 document.querySelectorAll("[data-pick]").forEach(button=>{
  const active=picks.includes(button.dataset.pick);
  button.setAttribute("aria-pressed",String(active));
  button.firstElementChild.textContent=active?"✓":"＋";
 });
}
function handleImageFailure(img){
 const parent=img.closest(".capture");
 if(!parent)return;
 img.hidden=true;
 parent.querySelector(".capture-missing").hidden=false;
 parent.disabled=true;
 parent.setAttribute("aria-label",`${img.alt}: capture unavailable`);
}
function bindImage(img){
 img.addEventListener("error",()=>handleImageFailure(img));
 if(img.complete&&img.naturalWidth===0&&img.getAttribute("src"))handleImageFailure(img);
}
document.querySelectorAll(".capture img").forEach(bindImage);
document.querySelectorAll("[data-state]").forEach(button=>button.addEventListener("click",()=>{
 pinState=button.dataset.state;
 document.querySelectorAll("[data-state]").forEach(control=>control.setAttribute("aria-pressed",String(control===button)));
 document.querySelectorAll(".pin-card").forEach(card=>{
  const id=card.dataset.id;
  const name=pinData.find(entry=>entry[0]===id)[1];
  const file=`pin-${id}-${pinState}.png`;
  const capture=card.querySelector(".capture");
  const img=capture.querySelector("img");
  const alt=`${name} pins — ${pinState==="overview"?"overview":"selected place"}`;
  capture.dataset.lightbox=file;
  capture.disabled=false;
  capture.setAttribute("aria-label",`Enlarge ${alt}`);
  capture.querySelector(".capture-missing").hidden=true;
  img.hidden=false;
  img.alt=alt;
  img.src=file;
 });
 updateTray();
 status.textContent=`Showing ${pinState==="overview"?"overview":"selected-place"} captures for all five pin families.`;
}));
document.querySelectorAll("[data-pick]").forEach(button=>button.addEventListener("click",()=>{
 const key=button.dataset.pick;
 if(picks.includes(key))picks=picks.filter(pick=>pick!==key);
 else if(picks.length<2)picks.push(key);
 else {status.textContent="Two captures are selected. Deselect one or clear the selection before choosing another.";return;}
 updateTray();
 status.textContent=picks.length===2?"Two captures selected. Open Compare two to view them side by side.":"Choose one more capture to compare.";
}));
document.querySelector(".clear").addEventListener("click",()=>{picks=[];updateTray();status.textContent="Comparison selection cleared.";});
document.querySelector(".open-compare").addEventListener("click",()=>{
 const grid=document.querySelector(".comparison-grid");
 grid.replaceChildren();
 picks.map(describePick).forEach(item=>{
  const article=document.createElement("article");
  const heading=document.createElement("h3");
  heading.textContent=item.name;
  const detail=document.createElement("span");
  detail.className="compare-kind";
  detail.textContent=item.detail;
  heading.append(detail);
  const button=document.createElement("button");
  button.type="button";
  button.className="capture";
  button.dataset.lightbox=item.file;
  button.setAttribute("aria-label",`Enlarge ${item.name} — ${item.detail}`);
  const img=document.createElement("img");
  img.alt=`${item.name} — ${item.detail}`;
  const missing=document.createElement("span");
  missing.className="capture-missing";
  missing.hidden=true;
  missing.textContent="Capture unavailable";
  button.append(img,missing);
  article.append(heading,button);
  grid.append(article);
  bindImage(img);
  img.src=item.file;
 });
 compareDialog.showModal();
});
document.addEventListener("click",event=>{
 const capture=event.target.closest("[data-lightbox]");
 if(!capture||capture.disabled)return;
 const img=imageDialog.querySelector("img");
 img.src=capture.dataset.lightbox;
 img.alt=capture.querySelector("img").alt;
 document.querySelector("#image-title").textContent=img.alt;
 stage.classList.remove("native-size");
 zoomButton.setAttribute("aria-pressed","false");
 zoomButton.textContent="Actual pixels";
 imageDialog.showModal();
});
zoomButton.addEventListener("click",()=>{
 const actual=stage.classList.toggle("native-size");
 zoomButton.setAttribute("aria-pressed",String(actual));
 zoomButton.textContent=actual?"Fit to window":"Actual pixels";
 stage.scrollTo(0,0);
});
document.querySelectorAll("dialog").forEach(dialog=>{
 dialog.querySelector(".close-modal").addEventListener("click",()=>dialog.close());
 dialog.addEventListener("click",event=>{
  if(event.target!==dialog)return;
  const rect=dialog.getBoundingClientRect();
  if(event.clientX<rect.left||event.clientX>rect.right||event.clientY<rect.top||event.clientY>rect.bottom)dialog.close();
 });
});
</script>
</body>
</html>
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--captures-dir", type=Path, required=True, help="Directory containing the native PNG captures")
    parser.add_argument("--output", type=Path, required=True, help="HTML output path within the captures directory; relative paths are resolved there")
    args = parser.parse_args()
    captures = args.captures_dir.expanduser().resolve()
    if not captures.is_dir():
        parser.error(f"Capture directory does not exist: {captures}")
    output = args.output.expanduser()
    output = output.resolve() if output.is_absolute() else (captures / output).resolve()
    try:
        output.relative_to(captures)
    except ValueError:
        parser.error("--output must be within --captures-dir")
    if output.parent != captures:
        parser.error("--output must be directly inside --captures-dir so image references remain simple relative file names")
    if output.suffix.lower() not in {".html", ".htm"}:
        parser.error("--output must have an .html or .htm extension")
    rendered = (HTML.replace("__PIN_CARDS__", pin_cards())
                .replace("__MAP_CARDS__", map_cards())
                .replace("__BASELINE__", capture_markup("baseline.png", "Baseline reference"))
                .replace("__COMPACT__", capture_markup("compact-porcelain.png", "Porcelain pins on a compact screen"))
                .replace("__PIN_DATA__", json.dumps(PINS))
                .replace("__MAP_DATA__", json.dumps(MAPS)))
    output.write_text(rendered, encoding="utf-8")
    print(f"Gallery written: {output}")


if __name__ == "__main__":
    main()
