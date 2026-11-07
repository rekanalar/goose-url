#!/usr/bin/env node
// Compares the output of test/idna_dump.goose with Node for every code
// point from U+0080 to U+10FFFF without the surrogates.
//
// Usage: goose build -o tmp/idna_dump test/idna_dump.goose
//        tmp/idna_dump | node test/check_idna_data.mjs
import { readFileSync } from 'node:fs';
const got = readFileSync(0, 'utf8').split('\n');
let at = 0, bad = 0, n = 0;
for (let cp = 0x80; cp <= 0x10FFFF; cp++) {
  if (cp >= 0xD800 && cp <= 0xDFFF) continue;
  let want;
  try { want = new URL('http://a' + String.fromCodePoint(cp) + 'b.com/').href; } catch { want = 'ERR'; }
  if (got[at] !== want) { if (bad++ < 400) console.log(cp.toString(16), 'goose', got[at], 'node', want); }
  at++; n++;
}
console.log(`checked ${n} code points, ${bad} differ`);
process.exit(bad ? 1 : 0);
