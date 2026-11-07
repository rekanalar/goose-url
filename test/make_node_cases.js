#!/usr/bin/env node
// Makes test/node_cases.goose for goose-url from Node URLSearchParams and URL.
//
// Usage, in the package directory:
//   node test/make_node_cases.js > test/node_cases.goose
//
// Every case holds the result that Node gave. The Goose test compares the
// result of the package with it. The seed is fixed, so the output is stable.
// The count of cases goes to standard error.
'use strict';

// A small seeded generator, so the output does not change.
let state = 20261107;
function rnd() {
  state = (state + 0x6D2B79F5) | 0;
  let t = Math.imul(state ^ (state >>> 15), 1 | state);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];

// Raw key and value forms, each with the decoded text next to it.
// No form holds a quote, a backslash or a bar, so a Goose string stays plain.
const KEYS = [['a', 'a'], ['b', 'b'], ['c', 'c'], ['A', 'A'], ['%41', 'A'], ['k+y', 'k y'],
  ['k%20y', 'k y'], ['%C3%A9', 'é'], ['é', 'é'], ['x', 'x'], ['ab', 'ab'], ['', '']];
const VALS = [['', ''], ['1', '1'], ['2', '2'], ['x+y', 'x y'], ['x%20y', 'x y'], ['%C3%A9', 'é'],
  ['é', 'é'], ['a%26b', 'a&b'], ['%3D', '='], ['~', '~'], ['*-._', '*-._'], ['!()', '!()'], ['abc', 'abc']];

function query() {
  const n = int(7);
  const parts = [];
  for (let i = 0; i < n; i++) {
    const k = pick(KEYS)[0], v = pick(VALS)[0];
    // A bare key has no equals sign.
    parts.push(int(6) === 0 && k !== '' ? k : `${k}=${v}`);
  }
  return parts.join('&');
}

const q = (s) => JSON.stringify(s);
const out = [];
const w = (s) => out.push(s);
const count = { query: 0, origin: 0 };

w('// Cases made by test/make_node_cases.js with Node ' + process.version + '.');
w('// Do not edit by hand. Make the file again with the script.');
w('');
w('namespace node_cases;');
w('');
w('import std;');
w('import url from "..";');
w('');
w('fn pairs_text(ps: url::Pair[>..]&) -> u8[>..] {');
w('    var s: u8[>..] = [];');
w('    for p, i in ps {');
w('        if i > 0 { s.push(\'|\'); }');
w('        s.append(p.value);');
w('    }');
w('    return s;');
w('}');
w('');
w('fn query_case(qs: const u8[:], key: const u8[:], val: const u8[:], has: bool, has_pair: bool, all: const u8[:],');
w('        set_text: const u8[:], set_n: i64, del_text: const u8[:], del_n: i64,');
w('        dp_text: const u8[:], dp_n: i64, sort_text: const u8[:], sort_n: i64) {');
w('    assert(url::query_has(qs, key) == has);');
w('    assert(url::query_has_pair(qs, key, val) == has_pair);');
w('    var ps: url::Pair[>..] = [];');
w('    assert(url::query_get_all(ps, qs, key));');
w('    let joined = pairs_text(ps);');
w('    assert(joined[..] == all);');
w('    var o: u8[>..] = [];');
w('    assert(url::query_set(o, qs, key, val) == set_n);');
w('    assert(o[..] == set_text);');
w('    o = [];');
w('    assert(url::query_delete(o, qs, key) == del_n);');
w('    assert(o[..] == del_text);');
w('    o = [];');
w('    assert(url::query_delete_pair(o, qs, key, val) == dp_n);');
w('    assert(o[..] == dp_text);');
w('    o = [];');
w('    assert(url::query_sort(o, qs) == sort_n);');
w('    assert(o[..] == sort_text);');
w('}');
w('');
w('fn origin_case(text: const u8[:], want: const u8[:]) {');
w('    let u, ok = url::parse(text);');
w('    assert(ok);');
w('    var o: u8[>..] = [];');
w('    let got = url::origin(o, u);');
w('    if want == "null" {');
w('        assert(!got);');
w('        assert(o.len == 0);');
w('    } else {');
w('        assert(got);');
w('        assert(o[..] == want);');
w('    }');
w('}');
w('');

w('fn check_queries() {');
for (let i = 0; i < 420; i++) {
  const qs = query();
  const [, key] = pick(KEYS);
  const [, val] = pick(VALS);
  const P = () => new URLSearchParams(qs);
  const has = P().has(key);
  const hasPair = P().has(key, val);
  const all = P().getAll(key).join('|');
  const nKey = P().getAll(key).length;
  const nPair = [...P()].filter(([k, v]) => k === key && v === val).length;
  const nAll = [...P()].length;
  const s = P(); s.set(key, val);
  const d = P(); d.delete(key);
  const dp = P(); dp.delete(key, val);
  const so = P(); so.sort();
  w(`    query_case(${q(qs)}, ${q(key)}, ${q(val)}, ${has}, ${hasPair}, ${q(all)}, ${q(s.toString())}, ${nKey}, ${q(d.toString())}, ${nKey}, ${q(dp.toString())}, ${nPair}, ${q(so.toString())}, ${nAll});`);
  count.query++;
}
w('}');
w('');

const SCHEMES = ['http', 'https', 'ws', 'wss', 'ftp', 'HTTP', 'Https', 'file', 'foo', 'ssh'];
const HOSTS = ['example.com', 'EXAMPLE.com', 'a.b.c', 'localhost', 'Host.Name', '[::1]', '[2001:db8::1]', 'h.', '10.0.0.1'];
const PORTS = ['', '', ':80', ':443', ':8080', ':0080', ':21', ':0', ':65535', ':8443'];
const USERS = ['', '', '', 'u@', 'u:p@'];
const PATHS = ['', '/', '/a/b', '/a?x=1#f', '#f'];
w('fn check_origins() {');
let made = 0;
while (made < 160) {
  const text = `${pick(SCHEMES)}://${pick(USERS)}${pick(HOSTS)}${pick(PORTS)}${pick(PATHS)}`;
  let want;
  try { want = new URL(text).origin; } catch (e) { continue; }
  w(`    origin_case(${q(text)}, ${q(want)});`);
  count.origin++;
  made++;
}
// Forms with no authority. Node gives null for each.
for (const text of ['data:text/plain,x', 'mailto:a@b.c', 'urn:isbn:1']) {
  w(`    origin_case(${q(text)}, ${q(new URL(text).origin)});`);
  count.origin++;
}
w('}');

process.stdout.write(out.join('\n') + '\n');
process.stderr.write('cases: ' + JSON.stringify(count) + ' total=' + (count.query + count.origin) + '\n');
