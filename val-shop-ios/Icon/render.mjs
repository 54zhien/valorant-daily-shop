#!/usr/bin/env node
// 把 Icon/gen.mjs 产出的 SVG 栅格化成 1024×1024 PNG（用本机 Chrome，headless）
//
//   node Icon/render.mjs                 只渲染到 Icon/out/png/
//   node Icon/render.mjs --install       顺便覆盖 App/Assets.xcassets 里的三张 1024
//
// 为什么要这一步留在仓库里：上一版 PNG 是手工截的图，谁也复现不出来。
// Chrome 路径可用环境变量 CHROME 指过去；找不到就直接报错，不猜。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(HERE, 'out');
const HTML_DIR = path.join(OUT, 'html');
const PNG_DIR = path.join(OUT, 'png');
const ASSETS = path.join(HERE, '..', 'App', 'Assets.xcassets', 'AppIcon.appiconset');

const S = 1024;
const THEMES = ['light', 'dark', 'tinted'];
const KINDS = ['flat', 'preview'];
const CONCEPTS = ['b', 'd', 'e'];

const CHROME_CANDIDATES = [
  process.env.CHROME,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
].filter(Boolean);

function findChrome() {
  for (const c of CHROME_CANDIDATES) if (fs.existsSync(c)) return c;
  throw new Error(`没找到 Chrome/Edge，用 CHROME=/path/to/chrome 指定。试过：\n  ${CHROME_CANDIDATES.join('\n  ')}`);
}

// 页面背景取图标自己的底色，避免圆角外那一圈抗锯齿边缘出现白边
const PAGE_BG = { light: '#0F1923', dark: '#080F16', tinted: '#11151A' };

function html(svg, bg) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>
  html,body{margin:0;padding:0;background:${bg};overflow:hidden}
  svg{display:block;width:${S}px;height:${S}px}
</style></head><body>${svg}</body></html>`;
}

const chrome = findChrome();
console.log(`Chrome: ${chrome}`);
fs.mkdirSync(HTML_DIR, { recursive: true });
fs.mkdirSync(PNG_DIR, { recursive: true });

const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'valpeek-icon-'));
let installed = 0;

for (const kind of KINDS) {
  for (const theme of THEMES) {
    const svgPath = path.join(OUT, `${kind}-${theme}.svg`);
    if (!fs.existsSync(svgPath)) throw new Error(`缺 ${svgPath}，先跑 node Icon/gen.mjs`);
    const svg = fs.readFileSync(svgPath, 'utf8');

    const page = path.join(HTML_DIR, `${kind}-${theme}.html`);
    fs.writeFileSync(page, html(svg, PAGE_BG[theme]));
    const png = path.join(PNG_DIR, `${kind}-${theme}.png`);

    const r = spawnSync(chrome, [
      '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
      '--force-device-scale-factor=1', '--user-data-dir=' + profile,
      `--window-size=${S},${S}`, '--screenshot=' + png,
      'file:///' + page.replace(/\\/g, '/'),
    ], { stdio: 'inherit' });

    if (r.status !== 0 || !fs.existsSync(png)) throw new Error(`渲染失败：${kind}-${theme}（exit ${r.status}）`);
    console.log(`  ${path.relative(HERE, png).padEnd(34)} ${String(fs.statSync(png).size).padStart(8)} B`);
  }
}

// 候选方案只渲染浅色，用来挑样式
for (const id of CONCEPTS) {
  const svgPath = path.join(OUT, `concept-${id}.svg`);
  if (!fs.existsSync(svgPath)) continue;
  const page = path.join(HTML_DIR, `concept-${id}.html`);
  fs.writeFileSync(page, html(fs.readFileSync(svgPath, 'utf8'), PAGE_BG.light));
  const png = path.join(PNG_DIR, `concept-${id}.png`);
  const r = spawnSync(chrome, [
    '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
    '--force-device-scale-factor=1', '--user-data-dir=' + profile,
    `--window-size=${S},${S}`, '--screenshot=' + png,
    'file:///' + page.replace(/\\/g, '/'),
  ], { stdio: 'inherit' });
  if (r.status !== 0 || !fs.existsSync(png)) throw new Error(`渲染失败：concept-${id}（exit ${r.status}）`);
  console.log(`  ${path.relative(HERE, png).padEnd(34)} ${String(fs.statSync(png).size).padStart(8)} B`);
}

if (process.argv.includes('--install')) {
  const map = { light: 'AppIcon-1024.png', dark: 'AppIcon-1024-dark.png', tinted: 'AppIcon-1024-tinted.png' };
  for (const [theme, name] of Object.entries(map)) {
    fs.copyFileSync(path.join(PNG_DIR, `bleed-${theme}.png`), path.join(ASSETS, name));
    console.log(`  → ${path.relative(HERE, path.join(ASSETS, name))}`);
    installed++;
  }
}

fs.rmSync(profile, { recursive: true, force: true });
console.log(`\n完成：${KINDS.length * THEMES.length} 张${installed ? `，装进 xcassets ${installed} 张` : ''}`);
console.log('提示：Chromium 截图可能带 alpha，装库前跑 python Icon/finalize.py 压平成 RGB。');






