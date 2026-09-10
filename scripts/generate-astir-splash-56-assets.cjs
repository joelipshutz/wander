#!/usr/bin/env node
// Reproduce approved direction 56 without changing its photograph or glyph paths.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const assert = require('assert/strict');
const sharp = require(process.env.SHARP_MODULE || 'sharp');

const root = path.resolve(__dirname, '..');
const source = path.join(root, 'docs/brand/astir-splash-56');
const catalog = path.join(root, 'Wander/Resources/Assets.xcassets');
const provenance = JSON.parse(fs.readFileSync(path.join(source, 'provenance.json')));
const type = JSON.parse(fs.readFileSync(path.join(source, 'source-type.json')));
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const glyphHash = crypto.createHash('sha256').update(JSON.stringify(type.paths)).digest('hex');
const expectedWidth = 1600, expectedHeight = 764;

function saveCatalog(name) {
  const directory = path.join(catalog, `${name}.imageset`);
  fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(path.join(directory, 'Contents.json'), JSON.stringify({
    images: [{ filename: `${name}.png`, idiom: 'universal', scale: '1x' },
      { idiom: 'universal', scale: '2x' }, { idiom: 'universal', scale: '3x' }],
    info: { author: 'xcode', version: 1 }
  }, null, 2) + '\n');
  return path.join(directory, `${name}.png`);
}

function bounds(data, width, height) {
  let minX = width, minY = height, maxX = -1, maxY = -1, count = 0;
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    if (!data[(y * width + x) * 4 + 3]) continue;
    count++; minX = Math.min(minX, x); minY = Math.min(minY, y);
    maxX = Math.max(maxX, x); maxY = Math.max(maxY, y);
  }
  return { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1, nonzeroPixels: count };
}

// Independent topology check: four separated glyphs and an open R counter.
function topology(data, width, height, region) {
  const visited = new Uint8Array(width * height), components = [], holes = [];
  for (let y = region.y; y < region.y + region.height; y++) {
    for (let x = region.x; x < region.x + region.width; x++) {
      const start = y * width + x;
      if (visited[start]) continue;
      const filled = data[start * 4 + 3] > 0, queue = [start];
      let count = 0, touchesEdge = false;
      visited[start] = 1;
      while (queue.length) {
        const p = queue.pop(), px = p % width, py = Math.floor(p / width); count++;
        if (px === region.x || py === region.y || px === region.x + region.width - 1 || py === region.y + region.height - 1) touchesEdge = true;
        for (const [nx, ny] of [[px-1,py],[px+1,py],[px,py-1],[px,py+1]]) {
          if (nx < region.x || ny < region.y || nx >= region.x + region.width || ny >= region.y + region.height) continue;
          const n = ny * width + nx;
          if (!visited[n] && (data[n * 4 + 3] > 0) === filled) { visited[n] = 1; queue.push(n); }
        }
      }
      if (filled) components.push(count); else if (!touchesEdge) holes.push(count);
    }
  }
  return { nonzeroComponents: components.length, componentPixelCounts: components.sort((a,b)=>b-a), enclosedTransparentCounters: holes.length, counterPixelCounts: holes };
}

async function main() {
  assert.equal(glyphHash, provenance.sourceGlyphPathsSha256, 'Archived glyph paths changed');
  const stillSource = path.join(source, '56-signal-glimmer.png');
  assert.equal(sha(stillSource), provenance.sourceAssetSha256, 'Approved still changed');
  const g = type.letters;
  const glyphs = `<g transform="${g.transform}">${type.paths.map((d,i)=>`<path data-letter="${'STIR'[i]}" d="${d}"/>`).join('')}</g>`;
  // Preserve the exact alpha-mask structure and original SVG canvas from round09.
  const rect = `x="${g.x-2}" y="308" width="${g.width+4}" height="424"`;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="2200" height="1050" viewBox="0 0 2200 1050"><title>Astir 56: unchanged STIR-only white alpha mask</title><defs><mask id="stir" maskUnits="userSpaceOnUse" ${rect} style="mask-type:alpha"><g fill="white">${glyphs}</g></mask></defs><g mask="url(#stir)"><rect ${rect} fill="white"/></g></svg>\n`;
  const svgFile = path.join(source, 'STIR-mask.svg');
  fs.writeFileSync(svgFile, svg);
  const stillFile = saveCatalog('AstirLaunchWordmark'), maskFile = saveCatalog('AstirLaunchSTIRMask');
  fs.copyFileSync(stillSource, stillFile);
  await sharp(Buffer.from(svg)).resize({ width: expectedWidth }).png().toFile(maskFile);
  const [still, mask] = await Promise.all([stillFile, maskFile].map(async file => sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true })));
  for (const image of [still, mask]) {
    assert.equal(image.info.width, expectedWidth); assert.equal(image.info.height, expectedHeight); assert.equal(image.info.channels, 4);
  }
  const region = { x: 510, y: 215, width: 890, height: 330 };
  let alphaDifferences = 0, pixelsOutsideRegion = 0, nonWhitePixels = 0, transparentPixels = 0;
  for (let y = 0; y < expectedHeight; y++) for (let x = 0; x < expectedWidth; x++) {
    const p = (y * expectedWidth + x) * 4, a = mask.data[p+3];
    const inRegion = x >= region.x && x < region.x + region.width && y >= region.y && y < region.y + region.height;
    if (inRegion && a !== still.data[p+3]) alphaDifferences++;
    if (!inRegion && a) pixelsOutsideRegion++;
    if (a && (mask.data[p] !== 255 || mask.data[p+1] !== 255 || mask.data[p+2] !== 255)) nonWhitePixels++;
    if (!a) transparentPixels++;
  }
  const topo = topology(mask.data, expectedWidth, expectedHeight, region);
  assert.equal(alphaDifferences, 0, 'Mask alpha must exactly match archived still throughout STIR region');
  assert.equal(pixelsOutsideRegion, 0, 'Mask leaks into statue/base/other artwork');
  assert.equal(nonWhitePixels, 0, 'Visible mask pixels must be white');
  assert.equal(topo.nonzeroComponents, 4, 'Expected four separate glyphs');
  assert.equal(topo.enclosedTransparentCounters, 1, 'Expected the transparent R counter');
  const result = {
    complete: true, method: 'Sharp native SVG rasterization and raw RGBA comparison; no browser or device capture',
    sharpVersion: sharp.versions.sharp, librsvgVersion: sharp.versions.rsvg, vipsVersion: sharp.versions.vips,
    size: [expectedWidth, expectedHeight], stillByteIdenticalToApprovedSource: sha(stillFile) === provenance.sourceAssetSha256,
    stillSha256: sha(stillFile), maskSha256: sha(maskFile), maskSvgSha256: sha(svgFile), glyphPathsSha256: glyphHash,
    maskBounds: bounds(mask.data, expectedWidth, expectedHeight), comparisonRegion: region,
    alphaDifferencesWithinSTIR: alphaDifferences, nonzeroMaskPixelsOutsideSTIRRegion: pixelsOutsideRegion,
    nonWhiteMaskPixels: nonWhitePixels, transparentPixels, ...topo
  };
  fs.writeFileSync(path.join(source, 'validation.json'), JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify(result, null, 2));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
