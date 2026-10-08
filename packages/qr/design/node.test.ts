import { readFile, writeFile } from 'node:fs/promises';
import { createZymbol } from './api.js';
import { createZymbol as createExplicit } from './core.js';

const qr = await createZymbol();
await writeFile('qr.png', qr.png('Node.js'));

const bytes = await readFile(new URL('./zymbol.wasm', import.meta.url));
const explicit = await createExplicit({ wasm: bytes });
const symbol = explicit.encode(Buffer.from([0, 128, 255]));
const result = explicit.decode(symbol);
const buffer: Buffer = Buffer.from(result.bytes);
void buffer;
