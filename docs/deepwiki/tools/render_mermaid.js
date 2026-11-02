#!/usr/bin/env node
// Render Mermaid diagrams to SVG in headless Chromium (light and dark variants).
//
// usage: node render_mermaid.js <in.json> <out.json>
//   in.json : {"themes": {"light": {...themeVariables}, "dark": {...}}, "fontFamily": "...",
//              "diagrams": [{"key": "abc123", "code": "flowchart LR ..."}]}
//   out.json: {"abc123": {"light": "<svg ...>", "dark": "<svg ...>"}, ...}
//            a diagram that fails to render gets {"error": "..."} instead.
//
// Needs the `playwright` package (with a Chromium build) and the `mermaid` package
// (`npm install` in this directory, see package.json).
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

function mermaidPath() {
  try {
    return require.resolve('mermaid/dist/mermaid.min.js');
  } catch (e) {
    return path.join(__dirname, 'node_modules', 'mermaid', 'dist', 'mermaid.min.js');
  }
}

(async () => {
  const input = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const out = {};
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 } });
  await page.setContent(`<!doctype html><html><head><meta charset="utf-8"><style>
    body { font-family: ${input.fontFamily}; font-size: 14px; }
  </style></head><body><div id="host"></div></body></html>`);
  await page.addScriptTag({ path: mermaidPath() });
  let failures = 0;
  for (const variant of ['light', 'dark']) {
    await page.evaluate(({ vars, fontFamily }) => {
      mermaid.initialize({
        startOnLoad: false,
        securityLevel: 'strict',
        theme: 'base',
        fontFamily,
        themeVariables: Object.assign({ fontFamily, fontSize: '14px' }, vars),
        flowchart: { htmlLabels: true, padding: 14, nodeSpacing: 40, rankSpacing: 46, curve: 'basis', useMaxWidth: true },
        sequence: { useMaxWidth: true, mirrorActors: false, actorMargin: 48, messageMargin: 32 },
        class: { useMaxWidth: true },
        state: { useMaxWidth: true },
      });
    }, { vars: input.themes[variant], fontFamily: input.fontFamily });
    for (const d of input.diagrams) {
      const id = `mm-${d.key}-${variant[0]}`;
      const res = await page.evaluate(async ({ id, code }) => {
        try {
          const { svg } = await mermaid.render(id, code);
          return { svg };
        } catch (e) {
          document.querySelectorAll(`#${id}, #d${id}`).forEach((n) => n.remove());
          return { error: String(e && e.message ? e.message : e).slice(0, 500) };
        }
      }, { id, code: d.code });
      out[d.key] = out[d.key] || {};
      if (res.error) {
        failures++;
        out[d.key].error = res.error;
        console.error(`mermaid error (${d.key}, ${variant}): ${res.error.replace(/\n/g, ' | ')}`);
      } else {
        out[d.key][variant] = res.svg;
      }
    }
  }
  await browser.close();
  fs.writeFileSync(process.argv[3], JSON.stringify(out));
  console.log(`rendered ${input.diagrams.length} diagrams x 2 themes, ${failures} failures`);
})();
