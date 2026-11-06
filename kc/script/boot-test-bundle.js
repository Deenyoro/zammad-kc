#!/usr/bin/env node
// Load a compiled legacy UI bundle (public/assets/application-*.js) in headless
// Chromium and fail on any error thrown while it evaluates, or if the core
// classes the app boots with are missing afterwards. Catches KC code that breaks
// the app at load time (2026-11-06: "Loading..." for everyone).
//
// Usage: node boot-test-bundle.js <application-*.js>
// Env:   PLAYWRIGHT_CORE (module path, default "playwright-core"),
//        CHROMIUM (executable path, default: Playwright's bundled one)
const fs = require('fs')
const path = require('path')
const http = require('http')
const { chromium } = require(process.env.PLAYWRIGHT_CORE || 'playwright-core')

const bundle = process.argv[2]
if (!bundle || !fs.existsSync(bundle)) {
  console.error('usage: boot-test-bundle.js <application-*.js>')
  process.exit(2)
}

const html = `<!doctype html><html><head><meta charset="utf-8"></head><body>
<div id="app"></div>
<script src="/${path.basename(bundle)}"></script>
<script>window.__kcBundleLoaded = true</script>
</body></html>`

const server = http.createServer((req, res) => {
  if (req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html' })
    return res.end(html)
  }
  if (req.url === '/' + path.basename(bundle)) {
    res.writeHead(200, { 'Content-Type': 'application/javascript' })
    return fs.createReadStream(bundle).pipe(res)
  }
  // No backend: every API call fails, which is fine - only load-time errors matter.
  res.writeHead(404)
  res.end()
})

server.listen(0, '127.0.0.1', async () => {
  const url = `http://127.0.0.1:${server.address().port}/`
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM || undefined,
    args: ['--no-sandbox'],
  })
  const page = await browser.newPage()
  const errors = []
  page.on('pageerror', (e) => errors.push(e.stack || e.message))
  await page.goto(url, { waitUntil: 'load', timeout: 60000 })
  await page.waitForTimeout(3000) // let deferred inits (setTimeout) run
  const state = await page.evaluate(() => ({
    loaded: window.__kcBundleLoaded === true,
    missing: ['App.Event', 'App.Utils', 'App.i18n', 'App.Config', 'App.Controller', 'App.Run']
      .filter((name) => !name.split('.').reduce((o, k) => (o ? o[k] : undefined), window)),
  }))
  await browser.close()
  server.close()

  const failed = errors.length || !state.loaded || state.missing.length
  if (failed) {
    console.log('Legacy UI bundle boot test FAILED')
    if (!state.loaded) console.log('  the bundle did not finish evaluating')
    if (state.missing.length) console.log('  missing after load: ' + state.missing.join(', '))
    errors.slice(0, 5).forEach((e) => console.log('  error: ' + e.split('\n').slice(0, 3).join(' | ')))
    process.exit(1)
  }
  console.log(`Legacy UI bundle boot test OK: ${path.basename(bundle)} evaluated with no errors`)
})
