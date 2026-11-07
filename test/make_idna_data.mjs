#!/usr/bin/env node
// Makes idna_data.goose for goose-url from the Unicode 17.0 data files.
//
// Usage, in the package directory:
//   node test/make_idna_data.mjs <dir> > idna_data.goose
//
// The directory <dir> holds these files, each from
// https://www.unicode.org/Public/17.0.0/ :
//   ucd/UnicodeData.txt
//   ucd/DerivedNormalizationProps.txt
//   idna/IdnaMappingTable.txt
// and this file from the ada release 3.3.0 that Node 22 holds:
//   https://raw.githubusercontent.com/ada-url/ada/v3.3.0/src/ada_idna.cpp
// Put them flat in <dir>, with the file name only.
// The label checks (marks, joiners, bidi) come from the tables of ada,
// because Node applies those tables, not the tables of Unicode 17.0.
// Do not edit idna_data.goose by hand. Make it again with this script.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const dir = process.argv[2];
if (!dir) { console.error('usage: make_idna_data.mjs <dir>'); process.exit(1); }
const read = (f) => readFileSync(join(dir, f), 'utf8').split('\n');
const MAXCP = 0x10FFFF;
const hex = (s) => parseInt(s, 16);

// Reads "A..B ; value" lines into [lo, hi, rest] triples.
function rows(lines, strip = true) {
  const out = [];
  for (let line of lines) {
    if (strip) line = line.replace(/#.*/, '');
    if (!line.trim()) continue;
    const f = line.split(';').map((x) => x.trim());
    const [lo, hi] = f[0].split('..');
    out.push([hex(lo), hex(hi ?? lo), f.slice(1)]);
  }
  return out;
}

// ---- UTS 46 ----------------------------------------------------------
// kind 0 valid, 1 ignored, 2 mapped, 3 disallowed. A deviation is valid
// in the non-transitional processing that Node uses. The STD3 rules are
// off, so the "valid" rows with a note stay valid.
const uts = [];
const pool = [0]; // index 0 means no mapping
for (const [lo, hi, f] of rows(read('IdnaMappingTable.txt'))) {
  const st = f[0];
  let kind;
  if (st === 'valid' || st === 'deviation') kind = 0;
  else if (st === 'ignored') kind = 1;
  else if (st === 'mapped') kind = 2;
  else if (st === 'disallowed') kind = 3;
  else if (st === 'disallowed_STD3_valid') kind = 0;
  else if (st === 'disallowed_STD3_mapped') kind = 2;
  else throw new Error('status ' + st);
  let off = 0;
  if (kind === 2) {
    const m = f[1].split(/\s+/).filter(Boolean).map(hex);
    off = pool.length;
    pool.push(m.length, ...m);
  }
  uts.push([lo, hi, kind, off]);
}
uts.sort((a, b) => a[0] - b[0]);
// The rows must cover every code point once.
let at = 0;
for (const r of uts) { if (r[0] !== at) throw new Error('gap at ' + at.toString(16)); at = r[1] + 1; }
if (at !== MAXCP + 1) throw new Error('table stops at ' + at.toString(16));
const utsM = [];
for (const r of uts) {
  const p = utsM[utsM.length - 1];
  if (p && r[2] !== 2 && p[2] === r[2]) { p[1] = r[1]; } else utsM.push(r.slice());
}

// ---- UnicodeData -----------------------------------------------------
const ccc = new Map(); // cp -> class
const decomp = new Map(); // cp -> single step canonical decomposition
for (const line of read('UnicodeData.txt')) {
  if (!line) continue;
  const f = line.split(';');
  const cp = hex(f[0]);
  const c = +f[3];
  if (c) ccc.set(cp, c);
  if (f[5] && !f[5].startsWith('<')) decomp.set(cp, f[5].split(' ').map(hex));
}
function merge(cps, keyOf) {
  const out = [];
  for (const cp of cps) {
    const k = keyOf(cp);
    const p = out[out.length - 1];
    if (p && p[1] + 1 === cp && p[2] === k) p[1] = cp; else out.push([cp, cp, k]);
  }
  return out;
}
const cccR = merge([...ccc.keys()].sort((a, b) => a - b), (cp) => ccc.get(cp));

// Full canonical decomposition. Hangul is done by formula in the code.
const full = (cp) => {
  const d = decomp.get(cp);
  return d ? d.flatMap(full) : [cp];
};
const decCps = [...decomp.keys()].filter((cp) => cp < 0xAC00 || cp > 0xD7A3).sort((a, b) => a - b);
const decPool = [];
const decOff = [];
for (const cp of decCps) {
  const d = full(cp);
  decOff.push(decPool.length);
  decPool.push(d.length, ...d);
}

// Composition pairs: a two-code-point decomposition that is not excluded.
const fce = new Set();
for (const line of read('DerivedNormalizationProps.txt')) {
  if (line.startsWith('#') || !line.trim()) continue;
  const f = line.replace(/#.*/, '').split(';').map((x) => x.trim());
  if (f[1] !== 'Full_Composition_Exclusion') continue;
  const [lo, hi] = f[0].split('..');
  for (let c = hex(lo); c <= hex(hi ?? lo); c++) fce.add(c);
}
const comp = [];
for (const [cp, d] of decomp) {
  if (d.length === 2 && !fce.has(cp) && (cp < 0xAC00 || cp > 0xD7A3)) comp.push([d[0] * 0x200000 + d[1], cp]);
}
comp.sort((a, b) => a[0] - b[0]);

// ---- The label tables of ada ------------------------------------------
const ada = readFileSync(join(dir, 'ada_idna.cpp'), 'utf8');
function adaList(name) {
  const m = ada.match(new RegExp('constexpr static uint32_t ' + name + '\\[\\] = \\{([^}]*)\\}'));
  if (!m) throw new Error('ada table ' + name);
  return m[1].split(',').map((x) => x.trim()).filter(Boolean).map((x) => parseInt(x, 16));
}
const BIDI = ['L', 'R', 'AL', 'EN', 'ES', 'ET', 'AN', 'CS', 'NSM', 'BN', 'B', 'S', 'WS', 'ON', 'LRE', 'LRO', 'RLE', 'RLO', 'PDF', 'LRI', 'RLI', 'FSI', 'PDI'];
const NONE = BIDI.length;
const markR = merge(adaList('combining').sort((a, b) => a - b), () => 0);
const virama = adaList('virama').sort((a, b) => a - b);
const jt = [];
for (const [name, t] of [['L', 1], ['R', 2], ['D', 3]]) for (const c of adaList(name)) jt.push([c, t]);
jt.sort((a, b) => a[0] - b[0]);
const dirTable = ada.slice(ada.indexOf('static directions dir_table[]'), ada.indexOf('// CheckJoiners and CheckBidi are true'));
const bidiR = [];
for (const m of dirTable.matchAll(/\{(0x[0-9a-f]+), (0x[0-9a-f]+), direction::(\w+)\}/g)) {
  const v = BIDI.indexOf(m[3]);
  if (v < 0) throw new Error('ada direction ' + m[3]);
  bidiR.push([parseInt(m[1], 16), parseInt(m[2], 16), v]);
}
bidiR.sort((a, b) => a[0] - b[0]);

// ---- Output ----------------------------------------------------------
const out = [];
const w = (s) => out.push(s);
const arr = (name, vals) => {
  w(`const ${name}: i64[${vals.length}] = [`);
  for (let i = 0; i < vals.length; i += 24) w('    ' + vals.slice(i, i + 24).join(', ') + ',');
  w('];');
  w('');
};
w('// The tables of the IDNA host mapping and of NFC.');
w('// Made by test/make_idna_data.mjs with Unicode 17.0.0.');
w('// Do not edit by hand. Make the file again with the script.');
w('namespace url;');
w('');
arr('UTS_START', utsM.map((r) => r[0]));
arr('UTS_KIND', utsM.map((r) => r[2]));
arr('UTS_MAP', utsM.map((r) => r[3]));
arr('UTS_POOL', pool);
arr('CCC_START', cccR.map((r) => r[0]));
arr('CCC_END', cccR.map((r) => r[1]));
arr('CCC_VAL', cccR.map((r) => r[2]));
arr('DEC_CP', decCps);
arr('DEC_OFF', decOff);
arr('DEC_POOL', decPool);
arr('COMP_KEY', comp.map((r) => r[0]));
arr('COMP_VAL', comp.map((r) => r[1]));
arr('MARK_START', markR.map((r) => r[0]));
arr('MARK_END', markR.map((r) => r[1]));
arr('VIRAMA', virama);
arr('BIDI_START', bidiR.map((r) => r[0]));
arr('BIDI_END', bidiR.map((r) => r[1]));
arr('BIDI_CLASS', bidiR.map((r) => r[2]));
arr('JT_CP', jt.map((r) => r[0]));
arr('JT_TYPE', jt.map((r) => r[1]));
w('// The bidi class numbers: ' + BIDI.map((n, i) => `${i}=${n}`).join(' ') + ` ${NONE}=NONE.`);
w('// The joining type numbers: 1=L 2=R 3=D.');
process.stdout.write(out.join('\n') + '\n');
process.stderr.write(`uts=${utsM.length} pool=${pool.length} ccc=${cccR.length} dec=${decCps.length} comp=${comp.length} mark=${markR.length} bidi=${bidiR.length} join=${jt.length} virama=${virama.length}\n`);
