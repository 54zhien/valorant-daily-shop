#!/usr/bin/env node
// ValPeek 图标生成器（零依赖）
//
//   node Icon/gen.mjs              # 主方案（默认 A）
//   CONCEPT=c node Icon/gen.mjs    # 换方案（a/b/c）
//
// 关键认知（对着 apple.icon 示例才看懂的）：
//   iOS 26 的图标是**分层素材 + 一份配置**，不是一张画好的画。
//   · 一层 = 透明画布 + 形状本身。示例里 `凪.svg` 就一条 fill="#FFFFFF" 的 path，
//     没有底色、没有玻璃、没有阴影。
//   · 底色 fill / 玻璃 glass / 通透 translucency / 投影 shadow 全写在 icon.json，
//     由系统渲染。自己把玻璃、高光、投影烤进图里，等于让系统再叠一遍。
//   所以这里产出「alpha 素材层 + 配置」，成图交给系统。
//
// 产出：
//   Icon/ValPeek.icon/Assets/*.svg   纯 alpha 分层素材（无底色 / 无玻璃 / 无投影）
//   Icon/ValPeek.icon/icon.json      fill / glass / translucency / shadow
//   Icon/out/flat-<theme>.svg        兜底稿（喂 Assets.xcassets 的三张 PNG，同样不画玻璃）
//   Icon/out/preview-<theme>.svg     模拟系统玻璃的评审稿（只看效果，不进包）
//   Icon/out/concept-<id>.svg        三个候选方案，同一个评审口径
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(HERE, 'out');
const BUNDLE = path.join(HERE, 'ValPeek.icon');
const S = 1024;

/* ================= 几何 ================= */

const V_W = 179, V_H = 146;
// 官方 V 顶点（val-shop/capture/v_to_polygon.py 对 179px 原始标逐行采样）。
// 左臂上段与下段共边，合并成一条缎带 —— 分成三段描边会在接缝处各画一条线。
const V_PARTS = [
  [[0, 0], [0, 72], [3, 76], [19, 95], [58, 142], [116, 142], [77, 95]],
  [[176, 0], [101, 95], [157, 95], [173, 77], [178, 70], [178, 1]],
];

function vPathD(width, cx, bottom) {
  const s = width / V_W, h = V_H * s, ox = cx - width / 2, oy = bottom - h;
  return V_PARTS.map(p => p.map(([x, y], i) =>
    `${i === 0 ? 'M' : 'L'} ${(ox + x * s).toFixed(2)} ${(oy + y * s).toFixed(2)}`).join(' ') + ' Z');
}

function squirclePath(size = S, n = 5.2, samples = 1600) {
  const a = size / 2, pts = [];
  for (let i = 0; i < samples; i++) {
    const t = (i / samples) * Math.PI * 2;
    const ct = Math.cos(t), st = Math.sin(t);
    pts.push([a + a * Math.sign(ct) * Math.abs(ct) ** (2 / n),
              a + a * Math.sign(st) * Math.abs(st) ** (2 / n)]);
  }
  return 'M ' + pts.map(([x, y]) => `${x.toFixed(2)} ${y.toFixed(2)}`).join(' L ') + ' Z';
}
const SQ = squirclePath();

/* ================= 三个候选方案 =================
   层里只用 alpha 与「大致是什么材质」的颜色：
   · 卡牌/环 = 白色 + 低 alpha（系统玻璃会把它变成磨砂件）
   · V 标    = 实色品牌红，glass:false（保住颜色，不被玻璃洗淡）
*/

const CONCEPTS = {
  a: {
    label: 'A 斜卡 + V',
    fill: 'srgb:0.058824,0.098039,0.137255,1.00000',
    layers: [
      {
        name: '卡牌', glass: true,
        body: `<g transform="rotate(-10 512 512)">
      <rect x="272" y="176" width="480" height="672" rx="60" fill="#FFFFFF" fill-opacity="0.16"/>
      <rect x="272" y="176" width="480" height="672" rx="60" fill="none" stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="4"/>
    </g>`,
      },
      {
        name: 'V', glass: false,
        body: vPathD(440, 512, 676).map(d => `<path d="${d}" fill="#FF4655"/>`).join('\n      '),
      },
    ],
    // 评审稿专用：同一块卡牌按磨砂玻璃画一遍（.icon 里没有这些，系统自己会做）
    decor: `<g transform="rotate(-10 512 512)">
      <rect x="272" y="176" width="480" height="672" rx="60" fill="url(#glassFill)"/>
      <rect x="272" y="176" width="480" height="672" rx="60" fill="none" stroke="url(#glassEdge)" stroke-width="4"/>
      <ellipse cx="400" cy="272" rx="190" ry="84" fill="url(#glassSpec)" transform="rotate(-16 400 272)"/>
      <rect x="272" y="616" width="480" height="232" rx="60" fill="url(#glassShade)"/>
    </g>`,
  },

  b: {
    label: 'B 取景环 + V',
    fill: 'srgb:0.058824,0.098039,0.137255,1.00000',
    layers: [
      {
        name: '取景环', glass: true,
        body: `<path fill-rule="evenodd" fill="#FFFFFF" fill-opacity="0.85"
      d="M 512 162 a 350 350 0 1 0 0.01 0 Z M 512 242 a 270 270 0 1 1 -0.01 0 Z"/>`,
      },
      {
        name: 'V', glass: false,
        body: vPathD(420, 512, 672).map(d => `<path d="${d}" fill="#FF4655"/>`).join('\n      '),
      },
    ],
    flat: (t) => `<path fill-rule="evenodd" fill="${t.glass}"
      d="M 512 162 a 350 350 0 1 0 0.01 0 Z M 512 242 a 270 270 0 1 1 -0.01 0 Z"/>`,
    decor: `<path fill-rule="evenodd" fill="url(#ringFill)"
      d="M 512 162 a 350 350 0 1 0 0.01 0 Z M 512 242 a 270 270 0 1 1 -0.01 0 Z"/>
    <path fill-rule="evenodd" fill="none" stroke="url(#glassEdge)" stroke-width="4"
      d="M 512 162 a 350 350 0 1 0 0.01 0 Z M 512 242 a 270 270 0 1 1 -0.01 0 Z"/>
    <ellipse cx="392" cy="286" rx="150" ry="66" fill="url(#glassSpec)" transform="rotate(-28 392 286)"/>`,
  },

  c: {
    label: 'C 单 V',
    fill: 'srgb:0.058824,0.098039,0.137255,1.00000',
    layers: [
      {
        name: 'V', glass: false,
        body: vPathD(660, 512, 668).map(d => `<path d="${d}" fill="#FF4655"/>`).join('\n      '),
      },
    ],
    decor: '',
  },
};

const PRIMARY = process.env.CONCEPT || 'b';
if (!CONCEPTS[PRIMARY]) throw new Error(`未知方案 ${PRIMARY}，可选 ${Object.keys(CONCEPTS).join('/')}`);

/* ================= 外观取值 =================
   .icon 由系统自动适配；这两组只服务兜底 PNG 与评审稿。 */
const THEMES = {
  light: { fill: '#0F1923', glass: 'rgba(255,255,255,0.18)', rim: 'rgba(255,255,255,0.60)', v: ['#FF4655'] },
  dark: { fill: '#080F16', glass: 'rgba(255,255,255,0.11)', rim: 'rgba(255,255,255,0.40)', v: ['#E5484F'] },
  tinted: { fill: '#15181C', glass: 'rgba(255,255,255,0.15)', rim: 'rgba(255,255,255,0.52)', v: ['#EDF0F3'] },
};

/* ================= SVG 组装 ================= */

const layerSvg = (body) => `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}">
  ${body}
</svg>
`;

// 把方案层按外观重上色。.icon 里存原稿（纯 alpha），这里只给兜底图/评审稿用。
// outlineOnly：兜底 PNG 不画玻璃，玻璃层只留边线 —— 免得出来一整块灰塑料。
function themeLayer(layer, theme, { outlineOnly = false } = {}) {
  const t = THEMES[theme];
  let body = layer.body;
  if (layer.glass) {
    body = body
      .replaceAll('fill-opacity="0.85"', '').replaceAll('fill-opacity="0.16"', '')
      .replaceAll('stroke-opacity="0.55"', '')
      .replaceAll('fill="#FFFFFF"', outlineOnly ? 'fill="none"' : `fill="${t.glass}"`)
      .replaceAll('stroke="#FFFFFF"', `stroke="${t.rim}"`);
  } else {
    body = body.replaceAll('fill="#FF4655"', `fill="${t.v[0]}"`);
  }
  return body;
}

// 兜底稿：底色 + 层，**不画玻璃/投影** —— 就是 .icon 那两层的平面版本，
// V 保持同一个实色，别让兜底图和真图标差太多。
const flatSvg = (c, theme) => `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}">
  <rect width="${S}" height="${S}" fill="${THEMES[theme].fill}"/>
  ${c.flat ? c.flat(THEMES[theme]) : c.layers.filter(l => l.glass).map(l => themeLayer(l, theme)).join('\n  ')}
  ${c.layers.filter(l => !l.glass).map(l => themeLayer(l, theme)).join('\n  ')}
</svg>
`;

// 评审稿：底色 + 磨砂玻璃模拟（decor）+ 层 + 一道斜向镜面光。
// 这里的「玻璃」是手画的近似，只为看效果；真正的玻璃在系统那边。
const previewSvg = (c, theme) => `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}">
  <defs>
    <linearGradient id="glassFill" x1="0.12" y1="0" x2="0.88" y2="1">
      <stop offset="0"    stop-color="#FFFFFF" stop-opacity="0.30"/>
      <stop offset="0.42" stop-color="#FFFFFF" stop-opacity="0.10"/>
      <stop offset="1"    stop-color="#FFFFFF" stop-opacity="0.04"/>
    </linearGradient>
    <linearGradient id="glassEdge" x1="0.05" y1="0" x2="0.95" y2="1">
      <stop offset="0"    stop-color="#FFFFFF" stop-opacity="0.85"/>
      <stop offset="0.5"  stop-color="#FFFFFF" stop-opacity="0.28"/>
      <stop offset="1"    stop-color="#FFFFFF" stop-opacity="0.45"/>
    </linearGradient>
    <radialGradient id="glassSpec" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.30"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="glassShade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#000000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000000" stop-opacity="0.16"/>
    </linearGradient>
    <linearGradient id="ringFill" x1="0.2" y1="0" x2="0.8" y2="1">
      <stop offset="0"    stop-color="#FFFFFF" stop-opacity="0.34"/>
      <stop offset="0.45" stop-color="#FFFFFF" stop-opacity="0.14"/>
      <stop offset="1"    stop-color="#FFFFFF" stop-opacity="0.06"/>
    </linearGradient>
    <radialGradient id="amb" cx="0.32" cy="0.86" r="0.72">
      <stop offset="0" stop-color="#FF3B4E" stop-opacity="0.18"/>
      <stop offset="1" stop-color="#FF3B4E" stop-opacity="0"/>
    </radialGradient>
    <filter id="lift" x="-25%" y="-25%" width="150%" height="150%">
      <feDropShadow dx="0" dy="14" stdDeviation="20" flood-color="#000000" flood-opacity="0.5"/>
    </filter>
    <clipPath id="sq"><path d="${SQ}"/></clipPath>
  </defs>
  <g clip-path="url(#sq)">
    <rect width="${S}" height="${S}" fill="${THEMES[theme].fill}"/>
    <rect width="${S}" height="${S}" fill="url(#amb)"/>
    ${c.decor || ''}
    <g filter="url(#lift)">${c.layers.filter(l => !l.glass).map(l => themeLayer(l, theme)).join('\n      ')}</g>
    <path d="${SQ}" fill="none" stroke="#FFFFFF" stroke-opacity="0.08" stroke-width="3"/>
  </g>
</svg>
`;

/* ================= 写盘 ================= */

fs.mkdirSync(OUT, { recursive: true });
fs.mkdirSync(path.join(BUNDLE, 'Assets'), { recursive: true });
const write = (p, s) => { fs.writeFileSync(p, s); console.log(`  ${path.relative(HERE, p).padEnd(36)} ${String(s.length).padStart(6)} B`); };

const primary = CONCEPTS[PRIMARY];

// 1) 交付物：.icon 包 —— 纯 alpha 层 + 配置
for (const f of fs.readdirSync(path.join(BUNDLE, 'Assets'))) fs.rmSync(path.join(BUNDLE, 'Assets', f));
for (const layer of primary.layers) {
  write(path.join(BUNDLE, 'Assets', `${layer.name}.svg`), layerSvg(layer.body));
}

const iconJson = {
  fill: { solid: primary.fill },
  groups: [{
    layers: primary.layers.map(l => ({
      ...(l.glass ? { glass: true } : {}),
      hidden: false,
      'image-name': `${l.name}.svg`,
      name: l.name,
      position: { scale: 1, 'translation-in-points': [0, 0] },
    })),
    shadow: { kind: 'neutral', opacity: 0.5 },
    translucency: { enabled: true, value: 0.5 },
  }],
  'supported-platforms': { circles: ['watchOS'], squares: 'shared' },
};
write(path.join(BUNDLE, 'icon.json'), JSON.stringify(iconJson, null, 2) + '\n');

// 2) 兜底稿 + 评审稿
for (const theme of Object.keys(THEMES)) {
  write(path.join(OUT, `flat-${theme}.svg`), flatSvg(primary, theme));
  write(path.join(OUT, `preview-${theme}.svg`), previewSvg(primary, theme));
}

// 3) 候选方案（同一口径，浅色外观）
for (const [id, c] of Object.entries(CONCEPTS)) {
  write(path.join(OUT, `concept-${id}.svg`), previewSvg(c, 'light'));
}

console.log(`\n主方案 ${PRIMARY}（${primary.label}）：${primary.layers.length} 层，`
  + `其中玻璃层 ${primary.layers.filter(l => l.glass).length}`);
console.log(`换方案：CONCEPT=b node Icon/gen.mjs`);





