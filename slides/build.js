#!/usr/bin/env node
// Build slides/index.html from slides/src.html + Perl traces + fonts + assets.
//   node slides/build.js
// Replaces the marker blocks in src.html:
//   @@FONTS@@   subset LINE Seed JP / Monaspace Neon as woff2 data URIs
//   @@TRACES@@  bin/regex-calc --trace output for the demo and counts
//   @@QR@@      assets/qr.svg (GitHub URL)
//   @@ICON@@    assets/icon.png as a data URI
const fs = require('fs');
const path = require('path');

const here = __dirname;
const read = (p) => fs.readFileSync(path.join(here, p), 'utf8');

const safeJs = (s) => s.replace(/<\/(script)/gi, '<\\/$1').replace(/<!--/g, '<\\!--');

function fill(html, name, content) {
  const re = new RegExp(`<!-- @@${name}@@ -->[\\s\\S]*?<!-- @@/${name}@@ -->`);
  if (!re.test(html)) { console.error(`build: marker ${name} missing in src.html`); process.exit(1); }
  return html.replace(re, () => `<!-- @@${name}@@ -->\n${content}\n<!-- @@/${name}@@ -->`);
}

const icon = 'data:image/png;base64,' + fs.readFileSync(path.join(here, 'assets/icon.png')).toString('base64');
let html = read('src.html');

// Lint: no space between Japanese and Latin/digits in on-screen text
// ("x 1 文字" -> "xを1文字").  Speaker notes and comments are exempt.
(function lintSpacing(src) {
  const body = src.replace(/notes:\s*(['`])(?:\\.|(?!\1)[^\\])*\1/g, "notes:''")
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '').replace(/<!--[\s\S]*?-->/g, '');
  const JP = '[\\u3001-\\u30ff\\u4e00-\\u9fff\\uff01-\\uff5e]', AN = '[A-Za-z0-9$#@/\\\\()<>{}\\[\\]+*=.-]';
  const re = new RegExp(`${JP}[ \\u3000]+${AN}|${AN}[ \\u3000]+${JP}`);
  const bad = body.split('\n').map((l, i) => [i + 1, l]).filter(([, l]) => re.test(l));
  if (bad.length) {
    for (const [, l] of bad) console.error('build: space between Japanese and Latin text: ' + l.trim().slice(0, 120));
    process.exit(1);
  }
})(html);

// Fonts: subset the OFL sources (slides/fonts/fetch.sh) to the glyphs used in
// the deck and embed them as woff2 data URIs, so the deck renders identically
// offline on any machine.  fonts/subset.py renames the subsets (the OFL keeps
// Reserved Font Names off modified versions) and keeps the copyright/license
// records.  Without sources/fonttools, system fonts are used.
const OFL_NOTICE = `/* Embedded fonts (subsets, renamed), SIL Open Font License 1.1 (https://openfontlicense.org):
   "Deck Sans" = LINE Seed JP, (c) LY Corporation
   "Deck Mono" = Monaspace Neon, Copyright (c) 2023, GitHub, Reserved Font Name "Monaspace"
   License texts: slides/fonts/OFL-*.txt in https://github.com/cp-20/regex-calc */
`;
function fontFaces() {
  const { execFileSync } = require('child_process');
  const os = require('os');
  const srcDir = path.join(here, 'fonts/src');
  const FONTS = [
    ['Deck Sans', 'LINESeedJP', [['Regular', 400], ['Bold', 700], ['ExtraBold', 800]], 'ttf'],
    ['Deck Mono', 'MonaspaceNeon', [['Regular', 400], ['Medium', 500]], 'otf'],
  ];
  if (!fs.existsSync(srcDir)) { console.warn('build: slides/fonts/src missing (run slides/fonts/fetch.sh); using system fonts'); return ''; }
  let ascii = '';
  for (let c = 32; c < 127; c++) ascii += String.fromCharCode(c);
  const chars = [...new Set(ascii + '×→←・…、。「」（）？！：' + html.replace(/<!-- @@[\s\S]*?@@\/[A-Z_]+@@ -->/g, ''))].join('');
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'deckfont-'));
  fs.writeFileSync(path.join(tmp, 'chars.txt'), chars);
  let css = '';
  try {
    for (const [family, file, weights, ext] of FONTS) {
      for (const [w, num] of weights) {
        const src = path.join(srcDir, `${file}-${w}.${ext}`);
        const out = path.join(tmp, `${file}-${w}.woff2`);
        execFileSync('python3', [path.join(here, 'fonts/subset.py'), src, out, family, w, path.join(tmp, 'chars.txt')],
          { stdio: ['ignore', 'ignore', 'pipe'] });
        const b64 = fs.readFileSync(out).toString('base64');
        css += `@font-face{font-family:"${family}";font-weight:${num};font-style:normal;font-display:block;src:url(data:font/woff2;base64,${b64}) format("woff2")}\n`;
      }
    }
  } catch (e) {
    console.warn('build: font subsetting failed (' + String(e.message).split('\n')[0] + '); using system fonts');
    return '';
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  return css && OFL_NOTICE + css;
}
html = fill(html, 'FONTS', `<style>\n${fontFaces()}</style>`);
// Perl traces: the deck's demo comes from the Perl implementation
// (bin/regex-calc --trace --rewrite: one regex $STEP repeated), recorded at build time.
// The CLI prints a pattern only when it differs from the previous pass, so a missing one repeats the last.
function perlTrace(expr) {
  const { execFileSync } = require('child_process');
  const out = execFileSync('perl', ['-I' + path.join(here, '../lib'), path.join(here, '../bin/regex-calc'), '--trace', '--rewrite', expr], { encoding: 'utf8' });
  const passes = [];
  let p = null;
  for (const ln of out.split('\n')) {
    let m;
    if ((m = /^#\d+ (.*)$/.exec(ln))) passes.push(p = { name: m[1], re: p && p.re, repl: p && p.repl, flags: p && p.flags });
    else if (p && (m = /^\s+pattern: (.*)$/.exec(ln))) p.re = m[1].replace(/^\(\?\^:(.*)\)$/, '$1');
    else if (p && (m = /^\s+replace: (.*)$/.exec(ln))) p.repl = m[1];
    else if (p && (m = /^\s+flags  : (.*)$/.exec(ln))) p.flags = m[1];
    else if (p && (m = /^\s+before : (.*)$/.exec(ln))) p.before = m[1];
    else if (p && (m = /^\s+after\s+: (.*)$/.exec(ln))) p.after = m[1];
  }
  for (const q of passes) if (q.name === 'step') delete q.re;    // the deck shows s/$STEP/.../g; the pattern itself is ~200 KB
  const r = /result: (\S+)\s+\((\d+) s\/\/\/ passes\)/.exec(out);
  return { expr, result: r[1], count: +r[2], passes };
}
let traces = [];
try {
  traces = ['(1+2)*4'].map(perlTrace);
} catch (e) { console.warn('build: perl trace failed (' + e.message + ')'); }
html = fill(html, 'TRACES', `<script>window.TRACES = ${safeJs(JSON.stringify(traces))};</script>`);
const qr = fs.existsSync(path.join(here, 'assets/qr.svg')) ? fs.readFileSync(path.join(here, 'assets/qr.svg'), 'utf8').trim() : '';
html = fill(html, 'QR', `<script>window.QR = ${JSON.stringify(qr)};</script>`);
html = fill(html, 'ICON', `<script>window.ICON = ${JSON.stringify(icon)};</script>`);
fs.writeFileSync(path.join(here, 'index.html'), html);
console.log(`build: wrote slides/index.html (${(html.length / 1024).toFixed(0)} KB)`);
