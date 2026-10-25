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

// 雨棚轮廓：平顶 + 一排半圆锯齿垂边（小店顶上那个小雨棚用它）
function awningPath({ x0, x1, yTop, yBot, n, r }) {
  const w = (x1 - x0) / n, rs = w / 2;
  let d = `M ${x0 + r} ${yTop} L ${x1 - r} ${yTop} A ${r} ${r} 0 0 1 ${x1} ${yTop + r} L ${x1} ${yBot}`;
  for (let i = n - 1; i >= 0; i--) {
    const xa = x0 + i * w, xc = xa + rs;
    d += ` Q ${xc.toFixed(2)} ${(yBot + 2 * rs).toFixed(2)} ${xa.toFixed(2)} ${yBot}`;
  }
  return d + ` L ${x0} ${yTop + r} A ${r} ${r} 0 0 1 ${x0 + r} ${yTop} Z`;
}

// V 两臂内侧那两条直线（绝对坐标），山谷就夹在它们中间。
// 倒梯形沿这两条线走、净空恒定 → 左右间距处处相等，这就是"镶嵌"。
const V_S = 700 / V_W;
const V_OX = 512 - 700 / 2;
const V_OY = 911 - V_H * V_S;
const P = (x, y) => [V_OX + x * V_S, V_OY + y * V_S];
const [LX0, LY0] = P(0, 0), [LX1, LY1] = P(77, 95);       // 左臂内侧
const [RX0, RY0] = P(176, 0), [RX1, RY1] = P(101, 95);    // 右臂内侧
const atY = (x0, y0, x1, y1, y) => x0 + (x1 - x0) * (y - y0) / (y1 - y0);
const valley = (y) => [atY(LX0, LY0, LX1, LY1, y), atY(RX0, RY0, RX1, RY1, y)];

// 倒梯形 + 顶棚 + 门，做成一个可调的函数。
// clear = **垂直于两臂内侧**的净空（不是水平偏移），量纲和"两臂之间的最小间距"一致：
// 右臂左下端到左臂内下段的垂距 = 72.2px（1024 画布），所以 clear 至少取 72 才不显得挤。
function wedgeShop({ clear, top, bot, awnH, awnN, doorW }) {
  const slopeL = Math.abs((LX1 - LX0) / (LY1 - LY0));
  const slopeR = Math.abs((RX1 - RX0) / (RY1 - RY0));
  const shiftL = clear / Math.cos(Math.atan(slopeL));   // 垂距 → 水平偏移
  const shiftR = clear / Math.cos(Math.atan(slopeR));
  const [tl, tr] = valley(top), [bl, br] = valley(bot);
  const x0 = tl + shiftL, x1 = tr - shiftR, y0 = bot;
  const wedge = `M ${x0.toFixed(2)} ${top} L ${x1.toFixed(2)} ${top}`
    + ` L ${(br - shiftR).toFixed(2)} ${y0} L ${(bl + shiftL).toFixed(2)} ${y0} Z`;
  const awnTop = top - awnH;
  const awn = awningPath({ x0, x1, yTop: awnTop, yBot: top, n: awnN, r: 12 });
  const stripeW = (x1 - x0) / awnN;
  const stripes = Array.from({ length: awnN }, (_, i) => i).filter(i => i % 2 === 1)
    .map(i => `<rect x="${(x0 + i * stripeW).toFixed(2)}" y="${awnTop - 4}"`
      + ` width="${stripeW.toFixed(2)}" height="${(top - awnTop + stripeW / 2 + 8).toFixed(2)}" fill="#F2EBDC"/>`)
    .join('\n        ');
  const cx = (bl + br) / 2;
  const doorTop = y0 - doorW * 1.35;
  return {
    wedge, awn, stripes, cx, doorTop, y0, doorW,
    body: `<defs><clipPath id="topAwn"><path d="${awn}"/></clipPath></defs>
      <path d="${wedge}" fill="#FF4655"/>
      <path d="${awn}" fill="#FF4655"/>
      <g clip-path="url(#topAwn)">
        ${stripes}
      </g>
      <path d="M ${(cx - doorW / 2).toFixed(2)} ${y0}
        L ${(cx - doorW / 2).toFixed(2)} ${(doorTop + doorW / 2).toFixed(2)}
        A ${(doorW / 2).toFixed(2)} ${(doorW / 2).toFixed(2)} 0 0 1 ${(cx + doorW / 2).toFixed(2)} ${(doorTop + doorW / 2).toFixed(2)}
        L ${(cx + doorW / 2).toFixed(2)} ${y0} Z" fill="#F2EBDC"/>`,
  };
}

// 山谷里的购物袋：袋身两条斜边**平行于两臂内侧、垂距恒定 clear**，
// 所以袋子永远不碰臂、也不需要描任何边（之前的 halo 那圈白边就是多余的）。
// 提手是方折 + 切角顶，悬在袋口上方，开口天然就是底色（因为提手在袋身之外）。
function bagInValley({ clear, top, bot, handleW, handleTop, handleStroke, chamfer }) {
  const slopeL = Math.abs((LX1 - LX0) / (LY1 - LY0));
  const slopeR = Math.abs((RX1 - RX0) / (RY1 - RY0));
  const shiftL = clear / Math.cos(Math.atan(slopeL));
  const shiftR = clear / Math.cos(Math.atan(slopeR));
  const [tl, tr] = valley(top), [bl, br] = valley(bot);
  const x0 = tl + shiftL, x1 = tr - shiftR;
  const c = chamfer;
  const body = `M ${(x0 + c).toFixed(2)} ${top} L ${(x1 - c).toFixed(2)} ${top}`
    + ` L ${x1.toFixed(2)} ${top + c} L ${(br - shiftR).toFixed(2)} ${bot - c}`
    + ` L ${(br - shiftR - c).toFixed(2)} ${bot} L ${(bl + shiftL + c).toFixed(2)} ${bot}`
    + ` L ${(bl + shiftL).toFixed(2)} ${bot - c} L ${x0.toFixed(2)} ${top + c} Z`;
  const cx = 512, hw = handleW / 2;
  const handle = `M ${cx - hw} ${top} L ${cx - hw} ${handleTop + c}`
    + ` L ${cx - hw + c} ${handleTop} L ${cx + hw - c} ${handleTop}`
    + ` L ${cx + hw} ${handleTop + c} L ${cx + hw} ${top}`;
  const sharp = 'stroke-linejoin="miter" stroke-miterlimit="8" stroke-linecap="butt"';
  return `<path d="${body}" fill="#FF4655"/>
      <path d="${handle}" fill="none" stroke="#FF4655" stroke-width="${handleStroke}" ${sharp}/>`;
}

// 竖边购物袋（袋身两侧是垂直的，所以缝会从上到下收窄 —— 靠选宽度控制最小值）
function bagUpright({ w, top, bot, handleW, handleTop, handleStroke, chamfer }) {
  const cx = 512, x0 = cx - w / 2, x1 = cx + w / 2, c = chamfer;
  const body = `M ${x0 + c} ${top} L ${x1 - c} ${top} L ${x1} ${top + c}`
    + ` L ${x1} ${bot - c} L ${x1 - c} ${bot} L ${x0 + c} ${bot}`
    + ` L ${x0} ${bot - c} L ${x0} ${top + c} Z`;
  const hw = handleW / 2;
  const handle = `M ${cx - hw} ${top} L ${cx - hw} ${handleTop + c}`
    + ` L ${cx - hw + c} ${handleTop} L ${cx + hw - c} ${handleTop}`
    + ` L ${cx + hw} ${handleTop + c} L ${cx + hw} ${top}`;
  const sharp = 'stroke-linejoin="miter" stroke-miterlimit="8" stroke-linecap="butt"';
  return `<path d="${body}" fill="#FF4655"/>
      <path d="${handle}" fill="none" stroke="#FF4655" stroke-width="${handleStroke}" ${sharp}/>`;
}
// 袋子 + 下方的倒三角尾巴：一个轮廓画完。
// 三角两条斜边的斜率 190/236 = 0.805，和两臂内侧的 0.81 几乎一样 →
// 往下走净空基本恒定（y=430 处 82，y=600 处 80），所以尾巴不会贴到臂上。
function bagWithTail({ cx = 512, top, bot, w, chamfer, apexY, handleW, handleTop, handleStroke }) {
  const x0 = cx - w / 2, x1 = cx + w / 2, c = chamfer;
  const body = `M ${x0 + c} ${top} L ${x1 - c} ${top} L ${x1} ${top + c}`
    + ` L ${x1} ${bot} L ${cx} ${apexY} L ${x0} ${bot} L ${x0} ${top + c} Z`;
  const hw = handleW / 2;
  const handle = `M ${cx - hw} ${top} L ${cx - hw} ${handleTop + c}`
    + ` L ${cx - hw + c} ${handleTop} L ${cx + hw - c} ${handleTop}`
    + ` L ${cx + hw} ${handleTop + c} L ${cx + hw} ${top}`;
  const sharp = 'stroke-linejoin="miter" stroke-miterlimit="8" stroke-linecap="butt"';
  return `<path d="${body}" fill="#FF4655"/>
      <path d="${handle}" fill="none" stroke="#FF4655" stroke-width="${handleStroke}" ${sharp}/>`;
}

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
    label: 'B 购物袋（左右快贴两臂）+ 倒三角尾巴',
    fill: 'srgb:0.949020,0.921569,0.862745,1.00000',   // #F2EBDC 米色
    layers: [
      {
        name: 'V', glass: false,
        body: vPathD(700, 512, 911).map(d => `<path d="${d}" fill="#FF4655"/>`).join('\n      '),
      },
      {
        // 山谷下半段用倒梯形填掉：净空 0（贴着两臂，连成一体），
        // 顶上往上做一条雨棚，下沿开一个拱门。
        name: '小店', glass: false,
        body: bagWithTail({ cx: 508, w: 500, top: 240, bot: 430, chamfer: 24, apexY: 666, handleW: 210, handleTop: 176, handleStroke: 32 }),
      },
    ],
    decor: '',
  },

  d: {
    label: 'Q 竖边袋 300 宽（缝 178→49）',
    fill: 'srgb:0.949020,0.921569,0.862745,1.00000',
    layers: [
      { name: 'V', glass: false,
        body: vPathD(700, 512, 911).map(d => `<path d="${d}" fill="#FF4655"/>`).join('\n      ') },
      { name: '小店', glass: false,
        body: bagUpright({ w: 300, top: 360, bot: 520, handleW: 150, handleTop: 292, handleStroke: 32, chamfer: 22 }) },
    ],
    decor: '',
  },

  e: {
    label: 'R 竖边袋 212 宽（全程 ≥72）',
    fill: 'srgb:0.949020,0.921569,0.862745,1.00000',
    layers: [
      { name: 'V', glass: false,
        body: vPathD(700, 512, 911).map(d => `<path d="${d}" fill="#FF4655"/>`).join('\n      ') },
      { name: '小店', glass: false,
        body: bagUpright({ w: 212, top: 344, bot: 512, handleW: 110, handleTop: 280, handleStroke: 30, chamfer: 20 }) },
    ],
    decor: '',
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
   .icon 只写一份（米色底 + 品牌红）；深色/着色由系统自动生成。
   下面这三组**只服务评审稿**（对照表里那三列），不进 App 包。 */
const THEMES = {
  light: { fill: '#F2EBDC', v: ['#FF4655'], awnLight: '#FFFFFF', glass: 'rgba(255,255,255,0.12)', rim: 'rgba(255,255,255,0.55)' },
  dark: { fill: '#1B1A18', v: ['#FF4655'], awnLight: '#EDE7DA', glass: 'rgba(255,255,255,0.09)', rim: 'rgba(255,255,255,0.38)' },
  tinted: { fill: '#15161A', v: ['#EDF0F3'], awnLight: '#F2F4F6', glass: 'rgba(255,255,255,0.13)', rim: 'rgba(255,255,255,0.50)' },
};

/* ================= SVG 组装 ================= */

const layerSvg = (body) => `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}">
  ${body}
</svg>
`;

// 把方案层按外观重上色。.icon 里存原稿（纯 alpha + 品牌色），这里只给兜底图/评审稿用。
// 兜底 PNG 不画玻璃：玻璃层变成一层平涂（rgba 自带 alpha），免得出来一整块灰塑料。
function themeLayer(layer, theme) {
  const t = THEMES[theme];
  let body = layer.body;
  if (layer.glass) {
    body = body
      .replace(/fill-opacity="[\d.]+"/g, '')     // 换成 rgba 后不再需要单独的 opacity
      .replace(/stroke-opacity="[\d.]+"/g, '')
      .replaceAll('fill="#FFFFFF"', `fill="${t.glass}"`)
      .replaceAll('stroke="#FFFFFF"', `stroke="${t.rim}"`);
  } else {
    body = body
      .replaceAll('fill="#FF4655"', `fill="${t.v[0]}"`)   // 小店红和 V 红是同一个 token
      .replaceAll('fill="#F2EBDC"', `fill="${t.fill}"`)   // 门洞跟着底色走
      .replaceAll('fill="#FFFFFF"', `fill="${t.awnLight}"`)
      .replace(/stroke="#FFFFFF" stroke-opacity="[\d.]+"/g, `stroke="${t.rim}"`);
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


























