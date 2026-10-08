import type { CoreInitOptions, Zymbol } from './api.js';

export { ZymbolError } from './api.js';
export type * from './api.js';

/** Explicit loading for workers, custom asset hosting and bundled servers. */
export declare function createZymbol(options: CoreInitOptions): Promise<Zymbol>;
