// Author the sword-energy textures (no Python/Pillow needed): node tools/build_slash_whip_textures.js
//
//   textures/slash_whip_energy.png  1024x256 RGB, tiles in U (arc tail -> sword). The VisualShader
//                              advects this along the arc, so every channel is a *flow* pattern:
//                              R = long speed streaks, G = backward-leaning tear teeth, B = broad
//                              soft energy sheets.
//   textures/slash_whip_shape.png   1024x256 RGBA silhouette in arc UV space (U tail -> sword, V inner
//                              -> outer radius). A = cut-paper silhouette (thin whip tail, flame
//                              teeth on the outer edge, wide bright head at the sword), R = bright
//                              inner face near the head, G = thin static highlight needles.
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const ROOT = path.resolve(__dirname, '..');
const W = 1024, H = 256, SS = 3; // supersampling per axis

// ---------- PNG writer ----------
const CRC = new Int32Array(256);
for (let n = 0; n < 256; n++) {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  CRC[n] = c;
}
function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function writePNG(file, w, h, channels, pixels) {
  const bpp = channels;
  const raw = Buffer.alloc((w * bpp + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * bpp + 1)] = 0;
    pixels.copy(raw, y * (w * bpp + 1) + 1, y * w * bpp, (y + 1) * w * bpp);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = channels === 4 ? 6 : 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
  ]);
  fs.writeFileSync(file, png);
  console.log('wrote', path.relative(ROOT, file));
}

// ---------- rasterizer: polygons in UV space, supersampled, optional U wrap ----------
function inside(poly, x, y) {
  let c = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) c = !c;
  }
  return c;
}
class Layer {
  constructor(wrap) { this.shapes = []; this.wrap = wrap; }
  // value: 0..1 coverage target, mode 'add' | 'cut'
  add(poly, value = 1, mode = 'add') { this.shapes.push({ poly, value, mode }); }
  bake() {
    const out = new Float32Array(W * H);
    for (const s of this.shapes) {
      const offsets = this.wrap ? [-1, 0, 1] : [0];
      let minx = 1e9, maxx = -1e9, miny = 1e9, maxy = -1e9;
      for (const [x, y] of s.poly) { minx = Math.min(minx, x); maxx = Math.max(maxx, x); miny = Math.min(miny, y); maxy = Math.max(maxy, y); }
      for (const off of offsets) {
        const px0 = Math.max(0, Math.floor((minx + off) * W) - 1), px1 = Math.min(W - 1, Math.ceil((maxx + off) * W) + 1);
        const py0 = Math.max(0, Math.floor(miny * H) - 1), py1 = Math.min(H - 1, Math.ceil(maxy * H) + 1);
        if (px1 < px0 || py1 < py0) continue;
        const poly = s.poly.map(([x, y]) => [x + off, y]);
        for (let py = py0; py <= py1; py++) {
          for (let px = px0; px <= px1; px++) {
            let hit = 0;
            for (let sy = 0; sy < SS; sy++) for (let sx = 0; sx < SS; sx++) {
              if (inside(poly, (px + (sx + 0.5) / SS) / W, (py + (sy + 0.5) / SS) / H)) hit++;
            }
            if (!hit) continue;
            const cov = hit / (SS * SS);
            const i = py * W + px;
            if (s.mode === 'cut') out[i] *= 1 - cov * s.value;
            else out[i] = Math.max(out[i], Math.min(1, cov * s.value));
          }
        }
      }
    }
    return out;
  }
}
const to8 = (v) => Math.max(0, Math.min(255, Math.round(v * 255)));

// Pointed streak: a long lens leaning by `slant` (dv per du), fat at `peak` (0..1 of its length).
function streak(u0, v0, len, width, slant = 0, peak = 0.45, pts = 10) {
  const top = [], bot = [];
  for (let i = 0; i <= pts; i++) {
    const t = i / pts;
    const u = u0 + len * t, v = v0 + slant * len * t;
    const w = width * Math.pow(Math.sin(Math.PI * Math.pow(t, Math.log(0.5) / Math.log(peak))), 0.7);
    top.push([u, v - w * 0.5]); bot.push([u, v + w * 0.5]);
  }
  return top.concat(bot.reverse());
}

// ================= slash_energy.png (flow tile) =================
{
  const R = new Layer(true), G = new Layer(true), B = new Layer(true);
  // R: speed streaks — many, long, thin, mostly parallel to the arc, slightly fanning.
  const seedStreaks = [
    [0.02, 0.10, 0.62, 0.045, 0.02], [0.40, 0.17, 0.48, 0.030, -0.03], [0.70, 0.07, 0.55, 0.035, 0.015],
    [0.12, 0.30, 0.70, 0.050, 0.04], [0.58, 0.36, 0.42, 0.028, -0.02], [0.84, 0.27, 0.46, 0.040, 0.03],
    [0.05, 0.50, 0.55, 0.038, -0.03], [0.46, 0.55, 0.64, 0.052, 0.025], [0.78, 0.47, 0.40, 0.026, -0.015],
    [0.22, 0.68, 0.58, 0.044, 0.03], [0.66, 0.72, 0.50, 0.034, -0.025], [0.92, 0.64, 0.44, 0.030, 0.02],
    [0.00, 0.86, 0.66, 0.048, -0.02], [0.52, 0.90, 0.45, 0.036, 0.03], [0.30, 0.94, 0.34, 0.024, -0.01],
  ];
  for (const [u, v, len, w, slant] of seedStreaks) R.add(streak(u, v, len, w, slant, 0.4), 1);
  // fainter secondary streaks give the band a layered, brushed look
  for (const [u, v, len, w, slant] of [
    [0.25, 0.04, 0.30, 0.016, 0.01], [0.60, 0.22, 0.26, 0.014, -0.01], [0.15, 0.42, 0.33, 0.015, 0.02],
    [0.88, 0.40, 0.28, 0.013, -0.015], [0.38, 0.61, 0.30, 0.016, 0.01], [0.95, 0.78, 0.36, 0.015, 0.02],
    [0.08, 0.76, 0.24, 0.012, -0.02], [0.72, 0.97, 0.30, 0.014, 0.0],
  ]) R.add(streak(u, v, len, w, slant, 0.5), 0.55);
  // G: tear teeth — triangles leaning backward (toward the tail = -U), spread over V so that any
  // V band of the arc meets teeth as the field moves.
  const teeth = [];
  for (let i = 0; i < 11; i++) {
    const u = (i * 0.0913 + 0.02) % 1.0;
    const v = (i * 0.2347 + 0.07) % 1.0;
    const len = 0.11 + (i % 3) * 0.035, h = 0.10 + (i % 4) * 0.03;
    // base along U at v, apex behind (-U) and above (+V-ish random sign)
    const dir = i % 2 ? 1 : -1;
    teeth.push([[u, v], [u + len, v + 0.01 * dir], [u - len * 0.55, v + h * dir]]);
  }
  for (const t of teeth) G.add(t, 1);
  // B: broad soft sheets — a few very long wide lenses (low frequency brightness surges)
  for (const [u, v, len, w, slant] of [
    [0.00, 0.20, 0.95, 0.26, 0.04], [0.45, 0.62, 0.90, 0.30, -0.05], [0.75, 0.92, 0.80, 0.22, 0.03],
  ]) B.add(streak(u, v, len, w, slant, 0.5, 14), 1);
  const r = R.bake(), g = G.bake(), b = B.bake();
  const px = Buffer.alloc(W * H * 3);
  for (let i = 0; i < W * H; i++) { px[i * 3] = to8(r[i]); px[i * 3 + 1] = to8(g[i]); px[i * 3 + 2] = to8(b[i]); }
  writePNG(path.join(ROOT, 'textures/slash_whip_energy.png'), W, H, 3, px);
}

// ================= slash_shape.png (silhouette) =================
{
  const A = new Layer(false), Rl = new Layer(false), Gl = new Layer(false);
  const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
  // piecewise-smooth band width (fraction of V) and outer edge
  const keys = [[0.0, 0.015], [0.12, 0.025], [0.25, 0.05], [0.38, 0.11], [0.50, 0.20], [0.62, 0.30], [0.75, 0.38], [0.88, 0.44], [1.0, 0.46]];
  function width(u) {
    for (let i = 0; i < keys.length - 1; i++) {
      const [u0, w0] = keys[i], [u1, w1] = keys[i + 1];
      if (u >= u0 && u <= u1) return w0 + (w1 - w0) * smooth(u0, u1, u);
    }
    return keys[keys.length - 1][1];
  }
  const outer = (u) => 0.78 + 0.02 * smooth(0.0, 0.6, u) - 0.02 * smooth(0.6, 1.0, u); // 0.78 -> 0.80 -> 0.78
  const N = 256;
  const us = Array.from({ length: N + 1 }, (_, i) => i / N);
  // main band (from u = 0.07: the very start is made of detached wisps)
  const bandTop = us.filter((u) => u >= 0.07).map((u) => [u, outer(u)]);
  const bandBot = us.filter((u) => u >= 0.07).map((u) => [u, outer(u) - width(u)]).reverse();
  A.add(bandTop.concat(bandBot), 1);
  // fraying tail: three detached wisps, each tapering to a point at the back
  A.add(streak(-0.02, 0.785, 0.16, 0.022, 0.0, 0.8), 1);
  A.add(streak(0.00, 0.745, 0.13, 0.014, -0.05, 0.85), 0.9);
  A.add(streak(0.03, 0.815, 0.10, 0.012, 0.06, 0.85), 0.85);
  // flame teeth on the OUTER edge, leaning backward toward the tail (reference: top-left tips)
  const teethAt = [[0.20, 0.07, 0.08], [0.29, 0.10, 0.13], [0.39, 0.13, 0.18], [0.50, 0.15, 0.20], [0.62, 0.13, 0.17], [0.75, 0.10, 0.12], [0.88, 0.07, 0.08]];
  for (const [u, len, h] of teethAt) {
    const o = outer(u);
    A.add([[u - len * 0.15, o - 0.02], [u + len, o - 0.01], [u + len * 0.55, o + h * 0.55], [u - len * 0.75, o + h]], 1);
  }
  // sharp notches splitting the band into layers (dark gaps that read as separate energy ribbons)
  for (const [u, len, dv] of [[0.36, 0.17, 0.045], [0.50, 0.20, 0.07], [0.63, 0.18, 0.09], [0.76, 0.14, 0.07]]) {
    const o = outer(u);
    const vi = o - width(u) * 0.55 + dv; // inside the band
    A.add([[u, vi], [u + len, vi - 0.006], [u + len * 0.35, vi + 0.018]], 1, 'cut');
  }
  // ragged inner edge near the head: small backward cuts
  for (const [u, len] of [[0.60, 0.08], [0.72, 0.10], [0.84, 0.09], [0.93, 0.07]]) {
    const vb = outer(u) - width(u);
    A.add([[u, vb - 0.01], [u + len, vb - 0.01], [u + len * 0.4, vb + 0.045]], 1, 'cut');
  }
  // R: bright inner face — inner 45% of the band from u 0.5 onward, tapering into the body
  const faceTop = us.filter((u) => u >= 0.40).map((u) => [u, outer(u) - width(u) * (1 - 0.42 * smooth(0.40, 0.80, u))]);
  const faceBot = us.filter((u) => u >= 0.40).map((u) => [u, outer(u) - width(u) - 0.02]).reverse();
  Rl.add(faceTop.concat(faceBot), 1);
  // G: static highlight needles inside the body
  Gl.add(streak(0.47, 0.70, 0.22, 0.012, 0.02, 0.5), 1);
  Gl.add(streak(0.66, 0.60, 0.20, 0.010, -0.02, 0.5), 1);
  Gl.add(streak(0.80, 0.74, 0.16, 0.009, 0.015, 0.5), 1);
  const a = A.bake(), r = Rl.bake(), g = Gl.bake();
  const px = Buffer.alloc(W * H * 4);
  for (let i = 0; i < W * H; i++) { px[i * 4] = to8(r[i] * a[i]); px[i * 4 + 1] = to8(g[i] * a[i]); px[i * 4 + 2] = 0; px[i * 4 + 3] = to8(a[i]); }
  writePNG(path.join(ROOT, 'textures/slash_whip_shape.png'), W, H, 4, px);
}
