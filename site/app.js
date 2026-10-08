import { createZymbol } from './vendor/browser.js';

const $ = id => {
  const element = document.getElementById(id);
  if (!element) throw new Error('Missing page element: ' + id);
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

function family() {
  return view.form.elements.namedItem('family').value;
}

function rgb(hex) {
  if (!/^#[\da-fA-F]{6}$/.test(hex)) throw new Error('Invalid color value');
  return [1, 3, 5].map(index => Number.parseInt(hex.slice(index, index + 2), 16));
}

function options() {
  const selected = family();
  const correction = view.correction.value;
  if (selected === 'micro' && correction === 'H') throw new Error('Micro QR does not support H correction');
  return { family: selected, errorCorrection: correction };
}

function renderOptions() {
  const foreground = rgb(view.foreground.value);
  const background = rgb(view.background.value);
  if (foreground.every((channel, index) => channel === background[index])) {
    throw new Error('Foreground and background colors must differ');
  }
  return { foreground, background };
}

function status(message, error = false) {
  view.status.textContent = message;
  view.status.classList.toggle('is-error', error);
}

function refreshExample(payload, opts) {
  view.example.textContent = [
    "import { createZymbol } from '@zymbol/qr';",
    '',
    'const qr = await createZymbol();',
    'const symbol = qr.encode(' + JSON.stringify(payload) + ', ' + JSON.stringify(opts) + ');',
    'const svg = qr.renderSvg(symbol);',
  ].join('\n');
}

function updateControls() {
  const micro = family() === 'micro';
  const high = view.correction.querySelector('option[value="H"]');
  high.disabled = micro;
  if (micro && view.correction.value === 'H') view.correction.value = 'M';
  view.scaleValue.textContent = view.scale.value + '×';
  view.bytes.textContent = encoder.encode(view.payload.value).length + ' bytes';
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
    if (!payload) throw new Error('Enter content to encode');
    const selected = options();
    const symbol = state.engine.encode(payload, selected);
    const svg = state.engine.renderSvg(symbol, renderOptions());
    const blob = new Blob([svg], { type: 'image/svg+xml;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const previous = state.previewUrl;
    state.previewUrl = url;
    view.image.src = url;
    view.image.alt = 'Generated ' + (symbol.family === 'micro' ? 'Micro QR' : 'QR Code') + ' for the current content';
    view.image.hidden = false;
    view.placeholder.hidden = true;
    if (previous) URL.revokeObjectURL(previous);
    state.symbol = symbol;
    state.svg = svg;
    view.svgButton.disabled = false;
    view.pngButton.disabled = false;
    view.description.textContent = (symbol.family === 'micro' ? 'Micro QR · ' : 'QR Code · ') + symbol.version + ' · ' + symbol.errorCorrection + ' correction';
    view.size.textContent = symbol.size + ' × ' + symbol.size;
    status('Rendered locally. Ready to export.');
    refreshExample(payload, selected);
  } catch (error) {
    clearPreview();
    status(error instanceof Error ? error.message : 'Unable to generate symbol.', true);
  }
}

function scheduleRender() {
  updateControls();
  clearTimeout(state.timeout);
  state.timeout = setTimeout(render, 130);
}

function save(blob, extension) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = (family() === 'micro' ? 'zymbol-micro-qr' : 'zymbol-qr') + '.' + extension;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 3000);
}

view.svgButton.addEventListener('click', () => {
  if (!state.symbol || !state.svg) return;
  save(new Blob([state.svg], { type: 'image/svg+xml;charset=utf-8' }), 'svg');
});

view.pngButton.addEventListener('click', () => {
  if (!state.engine || !state.symbol) return;
  try {
    const scale = Number(view.scale.value);
    const bytes = state.engine.renderPng(state.symbol, { ...renderOptions(), scale });
    save(new Blob([bytes], { type: 'image/png' }), 'png');
    status('PNG generated locally.');
  } catch (error) {
    status(error instanceof Error ? error.message : 'PNG rendering failed.', true);
  }
});

async function copy(text, button) {
  const label = button.textContent;
  try {
    await navigator.clipboard.writeText(text);
    button.textContent = 'Copied';
    setTimeout(() => { button.textContent = label; }, 1400);
  } catch {
    status('Clipboard unavailable. Select and copy the command manually.', true);
  }
}

$('copy-install').addEventListener('click', event => {
  copy('npm install @zymbol/qr', event.currentTarget);
});
$('copy-code').addEventListener('click', event => {
  copy(view.example.textContent, event.currentTarget);
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
  url: { value: 'https://github.com/ekkolon/zymbol', family: 'qr', ec: 'M' },
  numeric: { value: '123456789012345', family: 'micro', ec: 'L' },
  wifi: { value: 'WIFI:T:WPA;S:Zymbol;P:password123;;', family: 'qr', ec: 'M' },
};
for (const button of document.querySelectorAll('[data-sample]')) {
  button.addEventListener('click', () => {
    const sample = samples[button.dataset.sample];
    if (!sample) return;
    view.payload.value = sample.value;
    view.form.querySelector('input[value="' + sample.family + '"]').checked = true;
    view.correction.value = sample.ec;
    render();
  });
}

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
  status('Unable to initialize the WebAssembly runtime. Reload to retry.', true);
  console.error('Zymbol initialization failed:', error);
}
