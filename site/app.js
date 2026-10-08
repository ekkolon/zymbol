import { createZymbol } from './vendor/browser.js';

const $ = id => {
  const element = document.getElementById(id);
  if (!element) throw new Error(`Missing generator element: ${id}`);
  return element;
};

const view = {
  form: $('play-form'),
  payload: $('payload'),
  correction: $('error-correction'),
  scale: $('scale'),
  scaleValue: $('scale-value'),
  foreground: $('foreground'),
  background: $('background'),
  bytes: $('byte-count'),
  image: $('qr-image'),
  placeholder: $('placeholder'),
  description: $('symbol-description'),
  size: $('symbol-size'),
  status: $('play-status'),
  runtime: $('runtime-label'),
  svgButton: $('download-svg'),
  pngButton: $('download-png'),
  example: $('example-code'),
};

const encoder = new TextEncoder();
const state = { engine: null, symbol: null, svg: '', previewUrl: null, timeout: 0 };
const fixedFamily = view.form.dataset.fixedFamily;

function family() {
  return fixedFamily || view.form.elements.namedItem('family').value;
}

function rgb(hex) {
  if (!/^#[\da-fA-F]{6}$/.test(hex)) throw new Error('Invalid color value.');
  return [1, 3, 5].map(index => Number.parseInt(hex.slice(index, index + 2), 16));
}

function encodeOptions() {
  const selected = family();
  const correction = view.correction.value;
  if (selected === 'micro' && correction === 'H') throw new Error('Micro QR does not support high (H) correction.');
  return { family: selected, errorCorrection: correction };
}

function renderOptions() {
  const foreground = rgb(view.foreground.value);
  const background = rgb(view.background.value);
  if (foreground.every((value, index) => value === background[index])) {
    throw new Error('Choose different foreground and background colors.');
  }
  return { foreground, background };
}

function status(message, isError = false) {
  view.status.textContent = message;
  view.status.classList.toggle('is-error', isError);
}

function refreshExample(payload, opts) {
  view.example.textContent = [
    "import { createZymbol } from '@zymbol/qr';",
    '',
    'const qr = await createZymbol();',
    `const symbol = qr.encode(${JSON.stringify(payload)}, ${JSON.stringify(opts)});`,
    'const svg = qr.renderSvg(symbol);',
  ].join('\n');
}

function updateControls() {
  const micro = family() === 'micro';
  const high = view.correction.querySelector('option[value="H"]');
  high.disabled = micro;
  if (micro && view.correction.value === 'H') view.correction.value = 'M';
  view.scaleValue.textContent = `${view.scale.value}×`;
  view.bytes.textContent = `${encoder.encode(view.payload.value).length} bytes`;
}

function clearPreview() {
  state.symbol = null;
  state.svg = '';
  view.svgButton.disabled = true;
  view.pngButton.disabled = true;
  view.image.hidden = true;
  view.placeholder.hidden = true;
  view.description.textContent = 'No symbol';
  view.size.textContent = '—';
  if (state.previewUrl) {
    URL.revokeObjectURL(state.previewUrl);
    state.previewUrl = null;
  }
}

function render() {
  updateControls();
  if (!state.engine) return;
  try {
    const payload = view.payload.value;
    if (!payload) throw new Error('Enter text or a URL to continue.');
    const options = encodeOptions();
    const symbol = state.engine.encode(payload, options);
    const svg = state.engine.renderSvg(symbol, renderOptions());
    const blob = new Blob([svg], { type: 'image/svg+xml;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const previous = state.previewUrl;
    state.previewUrl = url;
    view.image.src = url;
    view.image.alt = `Generated ${symbol.family === 'micro' ? 'Micro QR' : 'QR Code'} symbol`;
    view.image.hidden = false;
    view.placeholder.hidden = true;
    if (previous) URL.revokeObjectURL(previous);
    state.symbol = symbol;
    state.svg = svg;
    view.svgButton.disabled = false;
    view.pngButton.disabled = false;
    view.description.textContent = `${symbol.family === 'micro' ? 'Micro QR' : 'QR Code'} · ${symbol.version} · ${symbol.errorCorrection} correction`;
    view.size.textContent = `${symbol.size} × ${symbol.size}`;
    status('Ready to download.');
    refreshExample(payload, options);
  } catch (error) {
    clearPreview();
    status(error instanceof Error ? error.message : 'Unable to generate the symbol.', true);
  }
}

function scheduleRender() {
  updateControls();
  clearTimeout(state.timeout);
  state.timeout = setTimeout(render, 130);
}

function save(blob, extension) {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = `zymbol-${family() === 'micro' ? 'micro-qr' : 'qr'}.${extension}`;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  setTimeout(() => URL.revokeObjectURL(url), 3000);
}

view.svgButton.addEventListener('click', () => {
  if (!state.symbol || !state.svg) return;
  save(new Blob([state.svg], { type: 'image/svg+xml;charset=utf-8' }), 'svg');
});

view.pngButton.addEventListener('click', () => {
  if (!state.engine || !state.symbol) return;
  try {
    const bytes = state.engine.renderPng(state.symbol, { ...renderOptions(), scale: Number(view.scale.value) });
    save(new Blob([bytes], { type: 'image/png' }), 'png');
    status('PNG ready.');
  } catch (error) {
    status(error instanceof Error ? error.message : 'PNG export failed.', true);
  }
});

view.form.addEventListener('submit', event => event.preventDefault());
view.form.addEventListener('input', event => {
  if (event.target === view.scale) {
    updateControls();
    return;
  }
  scheduleRender();
});
view.form.addEventListener('change', render);

const samples = {
  url: 'https://example.com',
  numeric: '123456789012345',
  wifi: 'WIFI:T:WPA;S:Zymbol;P:password123;;',
  short: 'HELLO',
};
for (const button of document.querySelectorAll('[data-sample]')) {
  button.addEventListener('click', () => {
    const sample = samples[button.dataset.sample];
    if (!sample) return;
    view.payload.value = sample;
    if (!fixedFamily) {
      const selected = button.dataset.sample === 'numeric' ? 'micro' : 'qr';
      view.form.querySelector(`input[name="family"][value="${selected}"]`).checked = true;
      view.correction.value = selected === 'micro' ? 'L' : 'M';
    }
    render();
  });
}

async function copyCode(button) {
  const label = button.querySelector('.copy-label');
  try {
    await navigator.clipboard.writeText(view.example.textContent);
    label.textContent = 'Copied';
    setTimeout(() => { label.textContent = 'Copy'; }, 1400);
  } catch {
    status('Clipboard unavailable. Select the code to copy it.', true);
  }
}
$('copy-code').addEventListener('click', event => copyCode(event.currentTarget));

window.addEventListener('pagehide', () => {
  if (state.previewUrl) URL.revokeObjectURL(state.previewUrl);
});

try {
  state.engine = await createZymbol();
  view.runtime.textContent = 'WASM ready';
  render();
} catch (error) {
  view.runtime.textContent = 'WASM unavailable';
  view.placeholder.hidden = true;
  status('WebAssembly could not load. Refresh to try again.', true);
  console.error('Zymbol initialization failed:', error);
}