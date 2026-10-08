import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

// Public URLs use directory indexes, so GitHub Pages needs no rewrite rules.
const origin = 'https://ekkolon.github.io/zymbol/';
const repo = 'https://github.com/ekkolon/zymbol';
const notice = 'QR Code is a registered trademark of DENSO WAVE INCORPORATED.';
const copyright = 'MIT OR Apache-2.0';
const iconPaths = {
  arrow: '<path d="M7 17 17 7M7 7h10v10"/>',
  down: '<path d="M12 4v16m-7-7 7 7 7-7"/>',
  chevron: '<path d="m9 18 6-6-6-6"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  copy: '<rect x="8" y="8" width="13" height="13" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/>',
  check: '<path d="m5 12 5 5L20 7"/>',
  grid: '<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/>',
  shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z"/><path d="m9 12 2 2 4-4"/>',
  sliders: '<path d="M4 7h9m4 0h3M4 17h3m4 0h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/>',
  code: '<path d="m8 5-7 7 7 7m8-14 7 7-7 7m-3-16-2 18"/>',
  file: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M8 13h8M8 17h8"/>',
  image: '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/>',
  terminal: '<rect x="2" y="3" width="20" height="18" rx="2"/><path d="m6 9 4 3-4 3m6 0h5"/>',
  book: '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>',
  lock: '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
  github: '<path d="M9 19c-4.3 1.4-4.3-2.5-6-3m12 6v-3.87a3.37 3.37 0 0 0-.94-2.61c3.14-.35 6.44-1.54 6.44-7A5.44 5.44 0 0 0 19 4.77 5.07 5.07 0 0 0 18.91 1S17.73.65 15 2.48a13.38 13.38 0 0 0-7 0C5.27.65 4.09 1 4.09 1A5.07 5.07 0 0 0 4 4.77a5.44 5.44 0 0 0-1.5 3.78c0 5.42 3.3 6.61 6.44 7A3.37 3.37 0 0 0 8 18.13V22"/>',
};
const icons = `<svg class="icon-defs" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" focusable="false">${Object.entries(iconPaths).map(([name, path]) => `<symbol id="i-${name}" viewBox="0 0 24 24">${path}</symbol>`).join('')}</svg>`;
const icon = (name, label = '') => `<svg class="icon" ${label ? `role="img" aria-label="${label}"` : 'aria-hidden="true"'}><use href="#i-${name}"/></svg>`;
const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const link = (root, path) => `${root}${path}`;

// Five-by-seven module lettering. Kept from the site's original display treatment.
const letters = {
  Z:['11111','00001','00010','00100','01000','10000','11111'],
  Y:['10001','10001','01010','00100','00100','00100','00100'],
  M:['10001','11011','10101','10101','10001','10001','10001'],
  B:['11110','10001','10001','11110','10001','10001','11110'],
  O:['01110','10001','10001','10001','10001','10001','01110'],
  L:['10000','10000','10000','10000','10000','10000','11111'],
};
function wordmark() {
  const rects = [...'ZYMBOL'].flatMap((letter, i) => letters[letter].flatMap((line, y) => [...line].flatMap((cell, x) => cell === '1' ? `<rect x="${i * 6 + x}" y="${y}" width="1" height="1"/>` : []))).join('');
  return `<svg class="wordmark" viewBox="0 0 35 7" shape-rendering="crispEdges" aria-hidden="true">${rects}</svg>`;
}
const brandMark = `<svg class="brand-mark" viewBox="0 0 19 19" shape-rendering="crispEdges" aria-hidden="true"><path fill="currentColor" d="M0 0h7v7H0zM12 0h7v7h-7zM0 12h7v7H0zM8 0h2v2H8zM9 4h2v3H9zM13 9h2v2h-2zM8 9h3v2H8zM16 12h3v2h-3zM9 14h2v5H9zM12 16h3v3h-3zM16 16h3v3h-3z"/><path fill="var(--bg)" d="M1 1h5v5H1zM13 1h5v5h-5zM1 13h5v5H1z"/><path fill="currentColor" d="M2 2h3v3H2zM14 2h3v3h-3zM2 14h3v3H2z"/></svg>`;
const docs = [
  { slug: '', label: 'Overview', title: 'Documentation', desc: 'Install Zymbol, encode QR codes, and work with the Zig or JavaScript API.' },
  { slug: 'getting-started', label: 'Getting started', title: 'Getting started', desc: 'Install Zymbol in JavaScript or Zig and produce your first QR code.' },
  { slug: 'javascript', label: 'JavaScript and TypeScript', title: 'JavaScript and TypeScript', desc: 'Use @zymbol/qr with a typed API powered by Zig and WebAssembly.' },
  { slug: 'zig', label: 'Zig', title: 'Zig', desc: 'Add Zymbol to a Zig 0.17 project and use its native encode and render APIs.' },
  { slug: 'encoding', label: 'Encoding', title: 'Encoding', desc: 'Understand QR Code and Micro QR encoding, versions, modes and error correction.' },
  { slug: 'decoding', label: 'Decoding', title: 'Decoding', desc: 'Decode QR and Micro QR module grids, and understand the image-input boundary.' },
  { slug: 'rendering', label: 'Rendering', title: 'Rendering', desc: 'Generate SVG, PNG and raster output, with color, scale and quiet-zone controls.' },
  { slug: 'testing', label: 'Testing and conformance', title: 'Testing and conformance', desc: 'How Zymbol checks ISO/IEC 18004:2024 behavior, interoperability and portability.' },
];
const docHref = (root, slug) => `${root}docs/${slug ? `${slug}/` : ''}`;
const code = (lang, source) => `<div class="code-block"><div class="code-label">${escape(lang)}</div><pre><code>${escape(source)}</code></pre></div>`;
const docLink = (root, slug, label) => `<a class="text-link" href="${docHref(root, slug)}">${escape(label)} ${icon('chevron')}</a>`;
const external = (href, label) => `<a class="text-link" href="${href}" target="_blank" rel="noopener noreferrer">${escape(label)} ${icon('arrow')}</a>`;
const docContent = {
  '': root => `<p class="lead">Zymbol encodes, decodes and renders QR Code Model 2 and Micro QR. The core is written in Zig and is also available to JavaScript through WebAssembly.</p>
  <div class="doc-quick"><a href="${docHref(root, 'getting-started')}">${icon('terminal')}<span><strong>Start here</strong><small>Install and generate a symbol.</small></span>${icon('chevron')}</a><a href="${docHref(root, 'javascript')}">${icon('code')}<span><strong>JavaScript / TypeScript</strong><small>Use the published npm package.</small></span>${icon('chevron')}</a><a href="${docHref(root, 'zig')}">${icon('terminal')}<span><strong>Zig</strong><small>Use the native library.</small></span>${icon('chevron')}</a></div>
  <h2>What is supported</h2><p>QR Code versions 1–40 and Micro QR M1–M4; standard encoding modes, Reed–Solomon error correction where applicable, and SVG, PNG or raw raster output.</p><p>Decoding starts with a sampled module grid. Finding a code in a photograph or camera feed is outside the library's scope.</p>
  <h2>Reference material</h2><p>The complete native API reference and test records remain in the repository.</p>${external(`${repo}/blob/main/docs/reference/api.md`, 'Native API reference')}${external(`${repo}/tree/main/docs/testing`, 'Engineering test records')}`,
  'getting-started': root => `<p class="lead">Choose the runtime that fits your project. Both packages use the same Zig implementation.</p><h2>JavaScript / TypeScript</h2>${code('terminal', 'npm install @zymbol/qr')}${code('typescript', `import { createZymbol } from '@zymbol/qr';

const zymbol = await createZymbol();
const symbol = zymbol.encode('https://example.com');
const svg = zymbol.renderSvg(symbol);`)}<p>The library loads WebAssembly once during initialization. Encoding and rendering are synchronous afterward.</p>${docLink(root, 'javascript', 'JavaScript usage')}
  <h2>Zig</h2><p>Requires Zig 0.17.0.</p>${code('terminal', 'zig fetch --save https://github.com/ekkolon/zymbol/archive/refs/tags/v1.0.2.tar.gz')}${code('zig', `const zymbol_dep = b.dependency("zymbol", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zymbol", zymbol_dep.module("zymbol"));`)}${docLink(root, 'zig', 'Zig usage')}`,
  'javascript': root => `<p class="lead">The <code>@zymbol/qr</code> package provides a typed API for browsers and Node.js. Its WebAssembly module is compiled from the Zig core.</p>${code('terminal', 'npm install @zymbol/qr')}<h2>Encode and render</h2>${code('typescript', `import { createZymbol } from '@zymbol/qr';

const qr = await createZymbol();
const symbol = qr.encode('https://example.com');
const svg = qr.renderSvg(symbol);
const png = qr.renderPng(symbol, { scale: 8 });`)}<h2>Micro QR</h2><p>Micro QR is selected explicitly. Capacity and error-correction support depend on the version. The encoder reports invalid combinations.</p>${code('typescript', `const micro = qr.encode('123456', {
  family: 'micro',
  errorCorrection: 'L',
});`)}<h2>Decode an existing grid</h2>${code('typescript', `const result = qr.decode(symbol);
const text = new TextDecoder().decode(result.bytes);`)}<p>The decoder takes a module grid, not a JPEG or camera frame. Return values contain their own JavaScript buffers.</p>${external(`${repo}/blob/main/packages/qr/src/types.ts`, 'Public TypeScript types')}`,
  'zig': root => `<p class="lead">Zymbol's native library targets Zig 0.17.0. Functions let you provide your own buffers or use allocating rendering helpers.</p>${code('terminal','zig fetch --save https://github.com/ekkolon/zymbol/archive/refs/tags/v1.0.2.tar.gz')}<h2>Build dependency</h2>${code('zig', `const zymbol_dep = b.dependency("zymbol", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zymbol", zymbol_dep.module("zymbol"));`)}<h2>Render a PNG</h2>${code('zig', `const zymbol = @import("zymbol");

var png = try zymbol.render.pngText(
    allocator, "https://example.com", .{},
);
defer png.deinit();
// png.bytes contains the PNG data.`)}<p>For caller-owned memory, use <code>encodeText</code> with <code>requiredCells</code> and <code>requiredEncodeScratch</code>.</p>${external(`${repo}/blob/main/docs/reference/api.md`, 'Zig API reference')}`,
  'encoding': root => `<p class="lead">Zymbol chooses an appropriate symbol size and encoding mode for the input. You can also specify the version, error correction and mask.</p><h2>Symbol families</h2><div class="doc-comparison"><div><strong>QR Code Model 2</strong><span>Versions 1–40</span><p>Supports numeric, alphanumeric, byte and Kanji modes, along with ECI, FNC1 and Structured Append.</p></div><div><strong>Micro QR</strong><span>M1–M4</span><p>Smaller symbols with version-dependent capacity, modes and error-correction levels. M1 only detects errors.</p></div></div><h2>Error correction</h2><p>QR Code uses four levels: L, M, Q and H. Micro QR has a narrower set, depending on its version. More correction leaves less room for data.</p>${code('typescript', `const symbol = qr.encode('Example', {
  family: 'qr',
  errorCorrection: 'Q',
});`)}<p>The encoder validates unsupported options and reports data that does not fit.</p>${docLink(root, 'rendering', 'Rendering the result')}`,
  'decoding': root => `<p class="lead">Zymbol decodes a sampled, correctly oriented square grid of modules. It corrects recoverable codeword errors and returns the payload bytes and metadata.</p><h2>What the input looks like</h2><p>A grid contains one value per module: <code>0</code> for light, <code>1</code> for dark. Its <code>size</code> specifies the number of modules along each side.</p>${code('typescript', `const result = qr.decode({
  size: symbol.size,
  modules: symbol.modules,
});
const text = new TextDecoder().decode(result.bytes);`)}<h2>What it does not do</h2><p>The library does not locate symbols in images, read cameras or correct perspective. Supply a sampled, oriented grid before decoding. The decoder can handle mirrored grids and reversed reflectance.</p>${external(`${repo}/blob/main/docs/reference/api.md#decoding`, 'Decoding API')}`,
  'rendering': root => `<p class="lead">Render symbols as vector graphics, PNG files or RGBA pixel buffers. The output uses square modules and a quiet zone.</p><h2>SVG</h2>${code('typescript', `const svg = qr.renderSvg(symbol, {
  foreground: [24, 32, 20],
  background: [255, 255, 255],
});`)}<h2>PNG</h2>${code('typescript', `const png = qr.renderPng(symbol, { scale: 8 });`)}<p>PNG scale is measured in pixels per module. The default quiet zone is four modules for QR Code and two for Micro QR.</p><h2>Raster</h2><p>Use <code>renderRaster</code> when you need an RGBA buffer for your own image pipeline.</p>${docLink(root, 'encoding', 'Encoding options')}`,
  'testing': root => `<p class="lead">Zymbol's test suite checks encoding and decoding against the implemented parts of ISO/IEC 18004:2024.</p><div class="doc-proof"><div>${icon('check')}<span><strong>Conformance</strong><p>Reference matrices, codeword layouts, masks, formats and correction limits.</p></span></div><div>${icon('check')}<span><strong>Interoperability</strong><p>Bidirectional cases with ZXing-cpp across QR Code and Micro QR.</p></span></div><div>${icon('check')}<span><strong>Portability</strong><p>Cross-architecture checks, fuzz inputs and regression tests.</p></span></div><div>${icon('check')}<span><strong>Benchmarks</strong><p>Measured encoding, decoding and rendering workloads.</p></span></div></div><h2>Scope</h2><p>Conformance here describes the library's digital symbol behavior. Printing, physical symbol quality and camera-based detection require separate systems.</p>${external(`${repo}/blob/main/docs/testing/conformance.md`, 'Conformance report')}${external(`${repo}/tree/main/docs/testing`, 'All test records')}`,
};

function head({title,description,slug='',root=''}) {
  const url = origin + slug;
  return `<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="theme-color" content="#0b0c09"><meta name="description" content="${escape(description)}"><meta name="robots" content="index,follow"><link rel="canonical" href="${url}"><meta property="og:type" content="website"><meta property="og:site_name" content="Zymbol"><meta property="og:title" content="${escape(title)}"><meta property="og:description" content="${escape(description)}"><meta property="og:url" content="${url}"><meta name="twitter:card" content="summary"><meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self'; img-src 'self' blob: data:; connect-src 'self'; font-src 'self'; object-src 'none'; base-uri 'self'; form-action 'none'"><link rel="icon" href="${root}favicon.svg" type="image/svg+xml"><link rel="stylesheet" href="${root}styles.css"><title>${escape(title)} | Zymbol</title>`;
}
function navigation(root, current) {
  const selected = key => current === key ? ' aria-current="page"' : '';
  const docItems = docs.slice(0,5).map(d=>`<a href="${docHref(root,d.slug)}">${escape(d.label)}</a>`).join('');
  return `<header class="topbar"><div class="shell nav-inner"><a class="brand" href="${root}" aria-label="Zymbol home">${brandMark}<span>zymbol</span></a><nav class="nav-links" aria-label="Main navigation"><a href="${root}"${selected('home')}>Home</a><a href="${root}create/"${selected('create')}>Create</a><details class="nav-dropdown"><summary>Documentation ${icon('chevron')}</summary><div class="nav-menu">${docItems}</div></details></nav><a class="github-link" href="${repo}" target="_blank" rel="noopener noreferrer" aria-label="Zymbol on GitHub">${icon('github')}<span>GitHub</span></a><details class="mobile-menu"><summary aria-label="Open navigation">${icon('menu')}</summary><nav aria-label="Mobile navigation"><a href="${root}">Home</a><a href="${root}create/">Create</a><a href="${root}create-qr-code/">QR Code</a><a href="${root}create-micro-qr/">Micro QR</a><a href="${docHref(root,'')}">Documentation</a><a href="${repo}">GitHub</a></nav></details></div></header>`;
}
function footer(root) {
  return `<footer class="footer"><div class="shell footer-layout"><div class="footer-main"><a class="footer-brand" href="${root}">${brandMark} zymbol</a><p>A QR code library for Zig and JavaScript.</p></div><nav aria-label="Footer links"><a href="${root}create/">Create</a><a href="${docHref(root,'')}">Documentation</a><a href="${repo}">Source</a><a href="${repo}/blob/main/SECURITY.md">Security</a></nav><div class="footer-bottom"><span>${copyright}</span><span>${notice}</span></div></div></footer>`;
}
function page({slug='',title,description,main,current='home',script=''}) {
  const depth = slug ? slug.replace(/\/$/,'').split('/').length : 0;
  const root = '../'.repeat(depth) || './';
  return `<!doctype html><html lang="en"><head>${head({title,description,slug,root})}</head><body>${icons}<a class="skip-link" href="#main">Skip to content</a>${navigation(root,current)}<main id="main">${main(root)}</main>${footer(root)}${script ? `<script type="module" src="${root}${script}"></script>`:''}</body></html>\n`;
}

// Artwork is deliberately not a scannable QR symbol. It demonstrates modules and finder patterns.
function matrix(size, seed, compact=false) {
  let n = seed;
  const next = () => { n = (Math.imul(n,1664525)+1013904223)>>>0; return n/4294967296; };
  const reserved = (x,y) => [[0,0],...(compact?[]:[[size-7,0],[0,size-7]])].some(([a,b])=>x>=a&&x<a+8&&y>=b&&y<b+8);
  let modules='';
  for(let y=0;y<size;y++)for(let x=0;x<size;x++){
    if(reserved(x,y))continue;
    if(next()>.51)modules+=`<rect x="${x}" y="${y}" width="1" height="1" class="module-delay-${((x*3+y*7)%6)}"/>`;
  }
  const finder=(x,y)=>`<path d="M${x} ${y}h7v7h-7z M${x+1} ${y+1}h5v5h-5z M${x+2} ${y+2}h3v3h-3z" fill-rule="evenodd"/>`;
  const patterns=finder(0,0)+(compact?'':finder(size-7,0)+finder(0,size-7));
  return `<svg viewBox="-2 -2 ${size+4} ${size+4}" shape-rendering="crispEdges" aria-hidden="true" class="matrix-svg"><g class="matrix-modules">${modules}</g><g class="matrix-finders">${patterns}</g></svg>`;
}
function home() {
  return page({title:'QR Code and Micro QR for Zig and JavaScript',description:'Zymbol is an open-source QR Code and Micro QR library for Zig and JavaScript, with a WebAssembly-powered QR code generator.',main:root=>`
  <section class="hero home-hero"><div class="ambient ambient-left" aria-hidden="true"></div><div class="ambient ambient-right" aria-hidden="true"></div><div class="shell home-hero-inner"><div class="hero-copy"><p class="eyebrow">QR Code · Micro QR · Zig · WebAssembly</p><h1><span class="visually-hidden">Zymbol</span>${wordmark()}</h1><h2>QR codes, from one Zig library.</h2><p>Encode, decode and render QR Code and Micro QR. Use the native Zig library or its TypeScript package powered by WebAssembly.</p><div class="hero-actions"><a class="button primary" href="${root}create/">Create a QR code ${icon('chevron')}</a><a class="button secondary" href="${docHref(root,'getting-started')}">Read the docs ${icon('arrow')}</a></div></div><div class="hero-matrix" aria-label="Animated illustration of QR code modules">${matrix(29,852)}<span class="matrix-caption">THE MODULE GRID</span></div></div><div class="hero-foot shell"><span>ISO/IEC 18004:2024</span><span>Zig v1.0.2 / npm v1.0.0</span></div></section>
  <section class="section shell first-section"><div class="section-header"><h2>Two symbol formats.</h2><p>The same library supports standard QR codes and the smaller Micro QR format.</p></div><div class="format-showcase"><a href="${root}create-qr-code/" class="format-item"><div class="format-art">${matrix(25,5421)}</div><div class="format-description"><h3>QR Code</h3><p>Versions 1–40, multiple encoding modes and four error-correction levels.</p><span class="inline-link">Create a QR code ${icon('chevron')}</span></div></a><a href="${root}create-micro-qr/" class="format-item"><div class="format-art micro-art">${matrix(15,622,true)}</div><div class="format-description"><h3>Micro QR</h3><p>Versions M1–M4 for smaller amounts of data, with compact symbol dimensions.</p><span class="inline-link">Create a Micro QR ${icon('chevron')}</span></div></a></div></section>
  <section class="section band"><div class="shell"><div class="section-header"><h2>From text to modules.</h2><p>Zymbol handles the steps between your input and the finished symbol.</p></div><div class="process-list"><article class="process-row"><div class="process-icon">${icon('code')}</div><div><h3>Encode</h3><p>Text and binary input, with numeric, alphanumeric, byte and Kanji modes. The library selects a version or uses the one you specify.</p></div><div class="process-visual data-visual" aria-hidden="true"><span>0110 0001</span><span>1100 1010</span><span>0011 0101</span></div></article><article class="process-row"><div class="process-icon">${icon('shield')}</div><div><h3>Error correction</h3><p>Reed–Solomon correction adds redundancy so a reader can recover data when some modules are damaged. The available level depends on the symbol.</p></div><div class="process-visual correction-visual" aria-hidden="true">${matrix(13,85,true)}</div></article><article class="process-row"><div class="process-icon">${icon('image')}</div><div><h3>Render</h3><p>Export SVG, PNG or raw pixels. Set the module scale, colors and quiet zone while keeping the square grid intact.</p></div><div class="process-visual render-visual" aria-hidden="true"><span>SVG</span><span>PNG</span><span>RGBA</span></div></article></div></div></section>
  <section class="section shell"><div class="section-header"><h2>One implementation. Two runtimes.</h2><p>Native Zig for applications and libraries. WebAssembly for browsers and JavaScript.</p></div><div class="runtime-columns"><div><h3>${icon('terminal')} Zig</h3>${code('zig',`const zymbol = @import("zymbol");

var png = try zymbol.render.pngText(
    allocator, "https://example.com", .{},
);
defer png.deinit();`)}<a class="text-link" href="${docHref(root,'zig')}">Zig guide ${icon('chevron')}</a></div><div><h3>${icon('code')} JavaScript / TypeScript</h3>${code('typescript',`import { createZymbol } from '@zymbol/qr';

const qr = await createZymbol();
const symbol = qr.encode('https://example.com');
const svg = qr.renderSvg(symbol);`)}<a class="text-link" href="${docHref(root,'javascript')}">JavaScript guide ${icon('chevron')}</a></div></div></section>
  <section class="section band"><div class="shell standards"><div><div class="section-header"><h2>Built against the standard.</h2><p>Conformance work covers ISO/IEC 18004:2024, including module placement, masks, encoding modes and correction behavior.</p></div><p class="muted">The test suite also includes ZXing-cpp interoperability cases, fuzzing, portability checks and benchmarks. Image detection and print-quality grading are outside the library's scope.</p><a class="text-link" href="${docHref(root,'testing')}">Read about testing ${icon('chevron')}</a></div><div class="standard-graphic" aria-hidden="true">${icon('check')}<span>ISO/IEC<br>18004:2024</span><div class="graphic-rule"></div><small>Model 2 / Micro QR</small></div></div></section>
  <section class="section shell home-ending"><h2>Try it in your browser.</h2><p>Create a symbol, adjust its appearance and export it as SVG or PNG. Your input is processed locally.</p><a class="button primary" href="${root}create/">Open the generator ${icon('chevron')}</a></section>`});
}
function generator({kind}) {
  const specific=kind==='qr'||kind==='micro';
  const title=kind==='micro'?'Micro QR code generator':kind==='qr'?'QR code generator':'QR Code and Micro QR generator';
  const description=kind==='micro'?'Create a Micro QR code online. Set error correction and colors, then export SVG or PNG. Runs locally in your browser.':kind==='qr'?'Create a QR code online from text or a URL. Customize colors, then download SVG or PNG. Runs locally in your browser.':'Create QR Code or Micro QR symbols from text or URLs. Customize colors and export SVG or PNG, processed locally in your browser.';
  const path=kind==='micro'?'create-micro-qr/':kind==='qr'?'create-qr-code/':'create/';
  const intro=kind==='micro'?'Micro QR is designed for smaller amounts of data. Its available sizes and correction levels differ from standard QR codes.':kind==='qr'?'Enter your text or URL, adjust the symbol, then export it as an SVG or PNG file.':'Enter your text or URL, choose a symbol format and download an SVG or PNG file.';
  const qrSelected=kind!=='micro', microSelected=kind==='micro';
  const supportSpecific=kind==='micro'?'Micro QR uses versions M1–M4. Error correction and capacity depend on the version; M1 detects errors but does not correct them.':'Standard QR Code supports versions 1–40 and four error-correction levels: L, M, Q and H.';
  return page({slug:path,title,description,current:'create',script:'app.js',main:root=>`
  <section class="generator-header shell"><div class="breadcrumbs"><a href="${root}">Home</a>${icon('chevron')}<span>${escape(title)}</span></div><h1>${kind==='micro'?'Create a Micro QR code':kind==='qr'?'Create a QR code':'Create a QR or Micro QR code'}</h1><p>${intro}</p><nav class="generator-tabs" aria-label="Generator format"><a href="${root}create/" ${kind==='all'?'aria-current="page"':''}>All formats</a><a href="${root}create-qr-code/" ${kind==='qr'?'aria-current="page"':''}>QR Code</a><a href="${root}create-micro-qr/" ${kind==='micro'?'aria-current="page"':''}>Micro QR</a></nav></section>
  <section class="shell generator-shell"><div class="play-layout"><form class="controls-card" id="play-form" data-fixed-family="${specific?kind:''}" autocomplete="off"><div class="panel-top"><h2>Content &amp; settings</h2></div><div class="panel-content"><div class="field"><label for="payload">Content</label><textarea id="payload" name="payload" spellcheck="false" maxlength="8192" rows="4" placeholder="Enter text or a URL">${kind==='micro'?'1234567890':'https://example.com'}</textarea><div class="field-foot"><span>Text or URL</span><output id="byte-count">0 bytes</output></div></div><fieldset class="field symbol-field" ${specific?'hidden':''}><legend>Format</legend><div class="segmented"><label><input type="radio" name="family" value="qr" ${qrSelected?'checked':''}><span>QR Code</span></label><label><input type="radio" name="family" value="micro" ${microSelected?'checked':''}><span>Micro QR</span></label></div></fieldset>${specific?`<input type="hidden" name="family" value="${kind}">`:''}<div class="field-row"><div class="field"><label for="error-correction">Error correction</label><div class="select-wrap"><select id="error-correction" name="error-correction"><option value="L">L · Low</option><option value="M" selected>M · Medium</option><option value="Q">Q · Quartile</option><option value="H">H · High</option></select>${icon('chevron')}</div></div><div class="field"><label for="scale">PNG size <output id="scale-value">8×</output></label><input type="range" id="scale" name="scale" min="2" max="12" value="8" step="1"><small class="field-hint">Pixels per module</small></div></div><div class="field-row color-row"><div class="field"><label for="foreground">Foreground</label><div class="color-field"><input type="color" id="foreground" name="foreground" value="#182014"><span>Dark modules</span></div></div><div class="field"><label for="background">Background</label><div class="color-field"><input type="color" id="background" name="background" value="#ffffff"><span>Background</span></div></div></div><div class="samples"><span>Try an example</span><div>${kind==='micro'?'<button type="button" data-sample="numeric">Numbers</button><button type="button" data-sample="short">Short text</button>':'<button type="button" data-sample="url">URL</button><button type="button" data-sample="numeric">Numbers</button><button type="button" data-sample="wifi">Wi-Fi</button>'}</div></div></div></form>
  <div class="preview-card"><div class="panel-top"><h2>Preview</h2><span class="runtime-indicator"><span class="status-square" aria-hidden="true"></span><span id="runtime-label">Loading WASM</span></span></div><div class="preview-stage"><div id="preview-container" class="preview-container"><div id="placeholder" class="placeholder" role="status" aria-label="Initializing WebAssembly"><span class="spinner"></span></div><img id="qr-image" alt="Generated QR code from the current content" hidden></div></div><div class="preview-meta"><span id="symbol-description">Initializing encoder…</span><span id="symbol-size">—</span></div><p class="play-status" id="play-status" role="status" aria-live="polite">Loading WebAssembly.</p><div class="download-row"><button type="button" class="button primary" id="download-svg" disabled>${icon('down')} Download SVG</button><button type="button" class="button secondary" id="download-png" disabled>${icon('down')} Download PNG</button></div></div></div>
  <p class="privacy-line">${icon('lock')} Everything runs in this browser. Your content is not uploaded.</p><div class="example-snippet"><div class="snippet-header"><span>Use the JavaScript package</span><button type="button" id="copy-code" class="copy-button">${icon('copy')}<span class="copy-label">Copy</span></button></div><pre><code id="example-code">import { createZymbol } from '@zymbol/qr';

const qr = await createZymbol();
const symbol = qr.encode('https://example.com');
const svg = qr.renderSvg(symbol);</code></pre></div>
  </section><section class="section shell generator-notes"><div><h2>About the format</h2><p>${specific?supportSpecific:'QR Code supports more data and three finder patterns. Micro QR is more compact and uses one finder pattern. The right format depends on how much data you need to encode.'}</p></div><div><h2>Need the library?</h2><p>Generate symbols programmatically with the Zig library or <code>@zymbol/qr</code> for JavaScript and TypeScript.</p><a class="text-link" href="${docHref(root,'getting-started')}">Get started ${icon('chevron')}</a></div></section>`});
}
function docPage(item) {
  const slug=`docs/${item.slug?item.slug+'/':''}`;
  return page({slug,title:item.title,description:item.desc,current:'docs',main:root=>`<div class="docs-shell shell"><aside class="docs-sidebar" aria-label="Documentation pages"><p class="sidebar-title">Documentation</p><nav>${docs.map(d=>`<a ${d.slug===item.slug?'aria-current="page"':''} href="${docHref(root,d.slug)}">${escape(d.label)}</a>`).join('')}</nav><div class="sidebar-bottom">Zig 0.17.0<br>@zymbol/qr 1.0.0</div></aside><div class="docs-main"><div class="breadcrumbs"><a href="${root}">Home</a>${icon('chevron')}${item.slug?`<a href="${docHref(root,'')}">Docs</a>${icon('chevron')}`:''}<span>${escape(item.label)}</span></div><div class="docs-mobile-index"><details><summary>${escape(item.label)} ${icon('chevron')}</summary><nav>${docs.map(d=>`<a href="${docHref(root,d.slug)}">${escape(d.label)}</a>`).join('')}</nav></details></div><article class="prose"><h1>${escape(item.title)}</h1>${docContent[item.slug](root)}</article><nav class="docs-next" aria-label="Documentation pagination">${docs[docs.indexOf(item)+1]?`<a href="${docHref(root,docs[docs.indexOf(item)+1].slug)}"><span>Next</span><strong>${escape(docs[docs.indexOf(item)+1].label)} ${icon('chevron')}</strong></a>`:''}</nav></div></div>`});
}

export function writePages(output) {
  const pages = [
    ['',home()],
    ['create/',generator({kind:'all'})],
    ['create-qr-code/',generator({kind:'qr'})],
    ['create-micro-qr/',generator({kind:'micro'})],
    ...docs.map(item=>[`docs/${item.slug?item.slug+'/':''}`,docPage(item)]),
  ];
  for(const [slug,html] of pages){const path=join(output,slug);mkdirSync(path,{recursive:true});writeFileSync(join(path,'index.html'),html);}
  const sitemap=`<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${pages.map(([slug])=>`<url><loc>${origin}${slug}</loc></url>`).join('')}</urlset>\n`;
  writeFileSync(join(output,'sitemap.xml'),sitemap);
  writeFileSync(join(output,'robots.txt'),`User-agent: *\nAllow: /\nSitemap: ${origin}sitemap.xml\n`);
  return pages.map(([slug])=>slug);
}