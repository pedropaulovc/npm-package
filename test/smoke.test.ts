/**
 * Smoke test: validate types work at runtime.
 * Customize this for your package.
 */

import type { Example } from '../index';

const example: Example = { id: 'test' };
console.log('Type check passed:', example);
console.log('\nPASSED');
