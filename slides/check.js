#!/usr/bin/env node
// Layout check for the built deck: the X widget in the top-right corner must not touch the
// slide content on any frame.  Run after `node slides/build.js`.
//   node slides/check.js            (needs Google Chrome; or set CHROME=/path/to/chromium)
// Drives headless Chrome over the DevTools protocol (Node's built-in WebSocket, no npm deps),
// steps through every frame and measures the gap between each part of the corner widget and
// every piece of content (text runs, code plates, markers, callouts, images).
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const MIN_GAP = +(process.env.MIN_GAP || 8);   // stage px (the slide is 1920x1080)
const here = __dirname;
const deck = 'file://' + path.join(here, 'index.html');

/* runs in the page: { frame: gap } for frames that show the corner widget */
const MEASURE = `(async () => {
  while (!window.__deck) await new Promise(r => setTimeout(r, 50));
  await document.fonts.ready;
  const st = document.getElementById('stage');
  const out = {};
  for (let i = 0; i < __deck.F.length; i++) {
    __deck.show(i, false);
    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
    const s = st.getBoundingClientRect().width / 1920;
    const root = st.lastElementChild, c = root.querySelector('.corner');
    if (!c) continue;
    const parts = [...c.querySelectorAll('[data-k]')].map(e => e.getBoundingClientRect());
    const rs = [];
    const tw = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let n;
    while ((n = tw.nextNode())) {
      if (!n.data.trim() || n.parentElement.closest('.corner,.wall')) continue;   // the $STEP wall is a backdrop
      const r = document.createRange(); r.selectNodeContents(n);
      rs.push(...r.getClientRects());
    }
    for (const e of root.querySelectorAll('.plate,.mark,.call,img,svg,.chip')) if (!e.closest('.corner')) rs.push(e.getBoundingClientRect());
    let gap = Infinity;
    for (const p of parts) for (const r of rs) {
      if (!r.width || !r.height) continue;
      const dx = Math.max(0, r.left - p.right, p.left - r.right), dy = Math.max(0, r.top - p.bottom, p.top - r.bottom);
      gap = Math.min(gap, Math.max(dx, dy) / s);
    }
    out[i + 1] = Math.round(gap);
  }
  return JSON.stringify(out);
})()`;

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'deckcheck-'));
  const chrome = spawn(process.env.CHROME || 'google-chrome', ['--headless=new', '--no-sandbox', '--disable-gpu', '--hide-scrollbars',
    '--window-size=1920,1080', '--remote-debugging-port=0', `--user-data-dir=${tmp}`, deck], { stdio: 'ignore' });
  const cleanup = () => { chrome.kill(); fs.rmSync(tmp, { recursive: true, force: true }); };
  try {
    let port;
    for (let t = 0; !port; t++) {
      if (t > 200) throw new Error('Chrome did not start');
      try { port = fs.readFileSync(path.join(tmp, 'DevToolsActivePort'), 'utf8').split('\n')[0]; } catch (_) { await new Promise(r => setTimeout(r, 50)); }
    }
    let target;
    for (let t = 0; !target; t++) {
      if (t > 100) throw new Error('no page target');
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      target = list.find(x => x.type === 'page' && x.url.startsWith('file:'));
      if (!target) await new Promise(r => setTimeout(r, 100));
    }
    const ws = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
    const reply = await new Promise((res, rej) => {
      ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id === 1) res(m); };
      ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression: MEASURE, awaitPromise: true, returnByValue: true } }));
      setTimeout(() => rej(new Error('timed out measuring the deck')), 60000);
    });
    ws.close();
    if (reply.result.exceptionDetails) throw new Error(reply.result.exceptionDetails.exception.description);
    const gaps = JSON.parse(reply.result.result.value);
    const bad = Object.entries(gaps).filter(([, g]) => g < MIN_GAP);
    const [closeFrame, closeGap] = Object.entries(gaps).sort((a, b) => a[1] - b[1])[0] || [];
    if (bad.length) {
      for (const [f, g] of bad) console.error(`check: frame ${f}: the corner widget is ${g}px from the content (min ${MIN_GAP}px)`);
      process.exitCode = 1;
    } else console.log(`check: corner widget clear of the content on ${Object.keys(gaps).length} frames (closest: frame ${closeFrame}, ${closeGap}px)`);
  } finally { cleanup(); }
}
main().catch(e => { console.error('check: ' + e.message); process.exit(1); });
