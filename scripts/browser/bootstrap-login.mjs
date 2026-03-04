import { writeFileSync } from 'node:fs';

const marker = process.env.KIMI_BOOTSTRAP_MARKER;
if (marker) {
  writeFileSync(marker, 'ok\n');
}

console.log('bootstrap login completed');
