// Render the design mockups without building or exercising the iOS app.
const { chromium } = require('playwright');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 900, height: 1900 }, deviceScaleFactor: 2 });
    await page.goto(pathToFileURL(path.join(__dirname, 'index.html')).href);
    await page.evaluate(() => document.fonts.ready);
    for (const theme of ['light', 'dark']) {
      for (const screen of ['profile', 'list']) {
        await page.locator(`#${screen}-${theme}`).screenshot({ path: path.join(__dirname, `${screen}-${theme}.png`) });
      }
    }
    await page.screenshot({ path: path.join(__dirname, 'comparison.png'), fullPage: true });
    console.log('Rendered Profile and List detail in Light and Dark. Design mockups only.');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
