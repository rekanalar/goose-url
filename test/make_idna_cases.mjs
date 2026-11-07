#!/usr/bin/env node
// Makes test/idna_cases.goose for goose-url from Node URL.
//
// Usage, in the package directory:
//   node test/make_idna_cases.mjs [count] > test/idna_cases.goose
//
// Every case holds the href that Node gave for the input, or the fact that
// Node threw. The seed is fixed, so the output is stable. The count of
// cases goes to standard error.
'use strict';
process.noDeprecation = true;

let state = 20261107;
function rnd() {
  state = (state + 0x6D2B79F5) | 0;
  let t = Math.imul(state ^ (state >>> 15), 1 | state);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];

function esc(s) {
  let out = '"';
  for (const ch of s) {
    const c = ch.codePointAt(0);
    if (c === 0x5c || c === 0x22 || c < 0x20 || c > 0x7e) {
      for (const b of Buffer.from(ch)) out += '\\x' + b.toString(16).padStart(2, '0');
    } else {
      out += ch;
    }
  }
  return out + '"';
}

const oracle = (input) => {
  try { return { href: new URL(input).href }; } catch { return { fail: true }; }
};

const cases = [];
const seen = new Set();
function add(input) {
  if (seen.has(input)) return;
  seen.add(input);
  cases.push({ kind: 'norm', input, want: oracle(input) });
}
const calls = [];
const callSeen = new Set();
// call(kind, args, want) records one case of a helper function. want is
// a string, or null when Node throws or gives an empty text.
function call(kind, args, want) {
  const key = kind + '\0' + args.join('\0');
  if (callSeen.has(key)) return;
  callSeen.add(key);
  calls.push({ kind, args, want });
}

// One character of each bidi class, joiners, marks and plain ASCII.
const POOL = [
  'a', 'b', 'Z', 'é', 'ß', 'क', 'ख',
  'א', 'ב', 'ا', 'ب', '1', '2', '۱', '١',
  '-', '_', '$', '£', '!', '(', ',', '،',
  '̀', 'ً', '्', '‌', '‍', '­', 'Ａ',
  '中', 'あ', 'ࡰ', 'ე0'.length > 1 ? '\u{10d40}' : 'x',
];
const SUFFIX = ['.com', ''];
const count = +(process.argv[2] || 8000);
const labels = () => {
  const n = 1 + int(3);
  const out = [];
  for (let i = 0; i < n; i++) {
    let l = '';
    for (let k = 1 + int(4); k > 0; k--) l += pick(POOL);
    out.push(l);
  }
  return out.join('.');
};
import punycode from 'node:punycode';
const JOIN = ['\u0628', '\u0627', '\u062f', '\u06a9', '\u200c', '\u200d', '\u094d', '\u0915', 'a', '1'];
const word = (pool, max) => { let l = ''; for (let k = 1 + int(max); k > 0; k--) l += pick(pool); return l; };
// Group 1: labels of mixed bidi classes. Group 2: xn-- labels, valid and
// broken. Group 3: joiner contexts. Group 4: file: URLs. Group 5: URLs of
// non-special schemes. Group 6: percent escapes and case.
const each = Math.floor(count / 6);
while (cases.length < each) add('http://' + labels() + pick(SUFFIX) + '/');
while (cases.length < 2 * each) {
  const src = word(POOL, 4);
  let enc;
  try { enc = punycode.encode(src); } catch { continue; }
  const r = int(5);
  if (r === 1) enc = enc.slice(0, -1);
  else if (r === 2) enc = enc.toUpperCase();
  else if (r === 3) enc = enc + pick(['a', '-', '0', 'zz']);
  add('http://' + pick(['xn--', 'xn--', 'XN--']) + enc + pick(SUFFIX) + '/');
}
while (cases.length < 3 * each) add('http://' + word(JOIN, 5) + (int(3) ? '.' + word(JOIN, 3) : '') + '/');
const SL = ['', '/', '//', '///', '////', '\\', '\\\\', '/\\', '\\/', '//\\'];
const FH = ['', '', 'localhost', 'LOCALHOST', 'host', 'B\u00fccher', 'c:', 'C|', 'c|', '1.2.3.4', '[::1]', 'a b', 'x@y', 'h:80', 'xn--tda', '\u00ad'];
const SEG = ['', 'a', '..', '.', 'c:', 'C|', '%2e', '%2E%2e', 'x y', '\u00e9', 'b', '..', 'c:'];
const segs = () => { let t = ''; for (let k = int(4); k > 0; k--) t += pick(['/', '/', '\\']) + pick(SEG); return t; };
const QF = ['', '', '', '?q', '?q r', '#f', '#f g', '?a#b', '?\'\'#"'];
while (cases.length < 4 * each) add(pick(['file:', 'FILE:', 'File:']) + pick(SL) + pick(FH) + segs() + pick(QF));
const SCH = ['foo', 'a', 'x+y', 'web+x', 'git', 'javascript', 'data', 'mailto', 'custom-scheme', 'Foo', 'a.b-c'];
const NH = ['', '', 'Host', 'h:80', 'u:p@h', '[::1]', '\u00e9', 'h%41', '1.2.3.4', 'a b', 'h:', ':80', 'u@', 'h:99999', 'x\\y', 'EXAMPLE.COM'];
const NP = ['', '/', ':', ' ', 'a b', '/a/../b', '/./a', '//x', '/..//x', 'a/../b', '%2e', ' b ', 'p q ', '\u00e9'];
while (cases.length < 5 * each) add(pick(SCH) + ':' + pick(['', '//', '//', '/', '///']) + pick(NH) + pick(NP) + pick(NP) + pick(QF));
while (cases.length < count) {
  const h = word(POOL, 4) + '.' + word(['a', 'B', 'c', '\u00fc', '\u00df', '\u4e2d'], 3);
  add('http://' + encodeURIComponent(h).replace(/%2E/g, '.').replace(/[a-z0-9]%/g, (m) => m) + '/');
}

import { fileURLToPath, pathToFileURL, domainToASCII, domainToUnicode } from 'node:url';
const nul = (f) => { try { const v = f(); return v === '' ? null : v; } catch { return null; } };
// Group 7: domain calls.
const DOMS = ['B\u00fccher.de', '\u65e5\u672c\u8a9e.jp', 'EXAMPLE.com', 'xn--bcher-kva.de', 'XN--TDA.com', '\u00df.de', '\uff21\uff22.com',
  'a.b', '1.2.3.4', '0x7f.1', '[::1]', 'a b.com', 'a%41.com', '%C3%BC.com', 'xn--', '\u00ad', 'a\u3002b', 'a_b.com', '-a.com', 'a..b', '\u05d0a', 'xn--zca.de', ''];
for (let k = 0; k < 400 && calls.length < 200; k++) {
  const d = k < DOMS.length ? DOMS[k] : word(POOL, 4) + pick(['.com', '.de', '', '.b']);
  call('dom', [d], domainToASCII(d) === '' ? null : domainToASCII(d));
  call('uni', [d], nul(() => domainToUnicode(d)));
}
// Group 8: file URL to path, in both forms.
const FU = ['file:///a/b%20c', 'file:///a%2Fb', 'file:///a%5Cb', 'file://host/a', 'file:///C:/x/y', 'file:///c%3A/x', 'file:///1:/x', 'file://B\u00fccher/x',
  'file:///a%zz', 'file:///a%FF', 'file:///%E4%BD%A0', 'file:///a?q#f', 'file:///', 'http://a/b', 'file:///C:', 'file:///c:%5Cx', 'file:c:\\x', 'FILE://LOCALHOST/a'];
for (let k = 0; k < 400 && calls.length < 600; k++) {
  const u = k < FU.length ? FU[k] : 'file://' + pick(['', '', 'host', 'h\u00e9.de']) + pick(['/', '/', '/C:/', '/c:/']) + segs().replace(/^[\\/]/, '') + pick(['', '', '%2f', '%5C', '%20', '%e4', '%']) + pick(QF);
  for (const win of [false, true]) call('f2p', [u, win], nul(() => fileURLToPath(u, { windows: win })));
}
// Group 9: path to file URL. Only the absolute forms.
const PS = ['a', 'b c', '\u00e9', '..', '.', '%41', '#x', '?y', 'x\\y', 'C:', 'a\tb', 'a\nb', "a'b", 'a^b', 'a`b', '{x}', 'x%'];
const ppath = (win) => {
  let t = '';
  for (let n = 1 + int(4); n > 0; n--) t += pick(win ? ['\\', '/', '\\'] : ['/', '/', '//']) + pick(PS);
  return t + pick(['', '', '/', win ? '\\' : '//']);
};
// The shapes of a path that the random paths rarely hold. A Windows path
// with no drive and no share is left out, because Node resolves it against
// the working directory and the result then depends on it.
const WSHAPES = [
  'C:\\', 'C:\\a', 'C:\\a\\', 'C:\\a\\b', 'C:\\a\\\\b', 'C:\\a\\..\\b', 'C:\\..\\b', 'C:/a/b',
  'C:\\a\\.\\b', 'C:\\a\\..\\..\\b', 'C:\\\\a', 'C:\\a b', 'C:\\a%b', 'C:\\a|b', 'C:\\a~b',
  'C:\\a^b', 'C:\\a[b]', 'C:\\a"b', 'C:\\a#b', 'C:\\a?b', 'C:\\a<b>', 'C:\\a{b}', 'C:\\a`b',
  'C:\\a\tb', 'C:\\a\nb', 'c:\\a', 'd:\\x\\y', 'C:\\', 'C:\\a\\b\\',
  '\\\\h\\s', '\\\\h\\s\\', '\\\\h\\s\\a', '\\\\h\\s\\a\\', '\\\\h\\s\\a\\b', '\\\\h\\s\\a\\..\\b',
  '\\\\h\\s\\..\\b', '\\\\h\\s\\..\\..\\b', '\\\\h\\s\\.\\b', '\\\\h\\s\\\\b', '\\\\h\\s\\/b',
  '\\\\h\\s\\a\\b', '\\\\h\\s\\a b', '\\\\h\\s\\%', '\\\\h\\s', '\\\\h', '\\\\',
  '\\\\?\\UNC\\h\\s\\x', '\\\\?\\UNC\\h\\s', '\\\\h\\s\\a\\..\\..\\b',
  '//h/s', '//h/s/', '//h/s/a', '//h/s/a/', '//h/s//a', '//h/s/..', '//h/s/../a', '//h/../a',
  '//h//s', '//h/s/a\\b', '//h/s/a\\\\b', '//h/s/a\\..\\b',
];
const PSHAPES = [
  '/', '/a', '/a/', '/a/b', '/a//b', '/a/../b', '/../a', '/a/..', '/a/./b', '//x', '///x',
  '/a b', '/a%b', '/a|b', '/a~b', '/a^b', '/a[b]', '/a"b', '/a#b', '/a?b', '/a<b>', '/a{b}',
  '/a`b', '/a\tb', '/a\nb', '/a\\b', '/a//b//c',
];
for (const p of PSHAPES) {
  const want = nul(() => pathToFileURL(p, { windows: false }).href);
  call('p2f', [p, false], want);
}
for (const p of WSHAPES) {
  const want = nul(() => pathToFileURL(p, { windows: true }).href);
  // Node gives file:///C:// for a drive root: a quirk the package leaves out.
  if (want && /^file:\/\/\/[A-Za-z]:\/\/$/.test(want)) continue;
  call('p2f', [p, true], want);
}
for (let k = 0; k < 600 && calls.length < 1400; k++) {
  const p = ppath(false);
  call('p2f', [p, false], nul(() => pathToFileURL(p, { windows: false }).href));
  const wp = pick(['C:', 'd:']) + ppath(true);
  const wu = '\\\\' + pick(['host', 'B\u00fccher']) + '\\' + pick(['share', 's']) + pick(['', '', ppath(true)]);
  for (const wq of [wp, wu]) {
    const want = nul(() => pathToFileURL(wq, { windows: true }).href);
    // Node gives file:///C:// for a drive root: a quirk the package leaves out.
    if (want && /^file:\/\/\/[A-Za-z]:\/\/$/.test(want)) continue;
    call('p2f', [wq, true], want);
  }
}
// Group 10: references against a base.
const BASES = ['http://a/b/c/d?q#f', 'file:///c:/a/b', 'foo://h/a/b?x', 'foo:/a/b', 'mailto:x@y', 'foo:opaque#frag', 'HTTP://Ex.com:80/p/../q', 'file://host/a/b', 'ws://h', 'foo://h', 'https://u:p@h:8/p?q', 'data:text/plain,hi', 'foo:x/y', 'a:b c?q', 'file:///', 'file://h/'];
const REFS = ['g', '/g', '//g/x', '?y', '#s', '', 'http:g', 'http:/g', 'HTTP://G/x', '../g', '../../../g', '.', './', 'c:/x', '/c:/x', '\\\\x', '\\g', 'foo:bar', 'a b', 'g?y#z', '//', '///', 'file:g', 'x:y', 'https:g', 'file:/g', 'file:///g', 'C|/x', '/C|/x', 'g/../h', 'a/./b', '%2e%2e/x'];
for (let k = 0; k < 2500 && calls.length < 2000; k++) {
  const b = pick(BASES);
  const r = k < 40 ? REFS[k % REFS.length] : pick(REFS) + pick(['', '', segs(), pick(QF)]);
  call('res', [r, b], nul(() => new URL(r, b).href));
}

// Group 11: the setters on text. Node gives the href after the setter.
const SETB = ['http://u:p@Example.com:8080/a/b?q=1#f', 'https://h/', 'file:///c:/x', 'file://host/x', 'foo://h:80/p', 'foo:/a/b', 'mailto:x@y', 'foo:opaque', 'ws://h', 'http://[::1]/a', 'ftp://h:21/', 'foo://u@h/x', 'foo://h'];
const SETV = {
  protocol: ['https', 'HTTP:', 'ws:', 'foo', 'file', 'a b', '1a', 'https://x', 'ftp:', 'FILE', 'bar:'],
  username: ['u', 'a b', 'u:v', 'a@b', '\u00e9', '', '%41', 'x/y', 'a\\b', 'a?b', 'a#b', 'p?q#r'],
  password: ['p', 'a b', 'p:q', 'a@b', '\u00e9', '', '%41', 'x/y', 'a\\b', 'p?q#r', 'a?b', 'a#b'],
  hostname: ['h', 'H.COM', 'a:80', '[::1]', 'a b', '', '\u00e9', 'x/y', 'a.b?z', '1.2.3.4', 'localhost', 'xn--tda', 'B\u00fccher', 'a\\b'],
  port: ['80', '8080', '', 'abc', '80abc', '65536', '0', '00080', '-1', ' 80', '21', '443'],
  pathname: ['a', '/a/b', '', 'a b', 'a?b#c', '../x', '\\x\\y', '%41', '\u00e9', '.', '//x', '/..//x'],
  search: ['?x', 'x y', '', 'a#b', '??', '?a=1&b=2', "a'b", '\u00e9'],
  hash: ['#x', 'x y', '', '#', 'a#b', '\u00e9', 'a`b'],
};
const SETK = { protocol: 0, username: 1, password: 2, hostname: 3, port: 4, pathname: 5, search: 6, hash: 7 };
const setCases = [];
const setSeen = new Set();
for (let k = 0; k < 20000 && setCases.length < 1500; k++) {
  const prop = pick(Object.keys(SETV));
  const b = pick(SETB), v = pick(SETV[prop]);
  const key = prop + '\0' + b + '\0' + v;
  if (setSeen.has(key)) continue;
  setSeen.add(key);
  const u = new URL(b);
  const orig = u.href;
  try { u[prop] = v; } catch { continue; }
  setCases.push({ which: SETK[prop], href: b, value: v, want: u.href, orig });
}

const w = (s) => process.stdout.write(s + '\n');
w('// Cases made by test/make_idna_cases.mjs with Node ' + process.version + '.');
w('// Do not edit by hand. Make the file again with the script.');
w('');
w('namespace idna_cases;');
w('');
w('import std;');
w('import url from "..";');
w('');
w('fn check(s: const u8[:], ok: bool, want: const u8[:]) -> i64 {');
w('    var got: u8[>..] = [];');
w('    let r = url::normalize(got, s);');
w('    if r != ok || (ok && got != want) {');
w('        print("idna case failed. input: ", s, "  want: ", want, "  got: ", got);');
w('        return 1;');
w('    }');
w('    return 0;');
w('}');
w('');
w('// check_call compares one helper call. kind: 1 domain_to_ascii, 2 domain_to_unicode,');
w('// 3 file_url_to_path, 4 path_to_file_url, 5 resolve_href.');
w('fn check_call(kind: i64, a: const u8[:], b: const u8[:], win: bool, ok: bool, want: const u8[:]) -> i64 {');
w('    var got: u8[>..] = [];');
w('    var r = false;');
w('    if kind == 1 { r = url::domain_to_ascii(got, a); }');
w('    else if kind == 2 { r = url::domain_to_unicode(got, a); }');
w('    else if kind == 3 { r = url::file_url_to_path(got, a, win); }');
w('    else if kind == 4 { r = url::path_to_file_url(got, a, win); }');
w('    else { r = url::resolve_href(got, a, b); }');
w('    if r != ok || (ok && got != want) {');
w('        print("call case failed. kind: ", kind, "  input: ", a, "  ", b, "  want: ", want, "  got: ", got);');
w('        return 1;');
w('    }');
w('    return 0;');
w('}');
w('');
w('// check_set compares one setter. When the setter gives false, Node must have left');
w('// the href as it was.');
w('fn check_set(which: i64, href: const u8[:], value: const u8[:], want: const u8[:], orig: const u8[:]) -> i64 {');
w('    var got: u8[>..] = [];');
w('    let r = url::with_part(got, href, which, value);');
w('    if (r && got != want) || (!r && want != orig) {');
w('        print("setter case failed. which: ", which, "  href: ", href, "  value: ", value, "  want: ", want, "  got: ", got, "  ok: ", r);');
w('        return 1;');
w('    }');
w('    return 0;');
w('}');
w('');
w('fn test_idna_cases() {');
w('    var bad: i64 = 0;');
for (const c of cases) {
  w(`    bad += check(${esc(c.input)}, ${!c.want.fail}, ${esc(c.want.href || '')});`);
}
const KIND = { dom: 1, uni: 2, f2p: 3, p2f: 4, res: 5 };
for (const c of calls) {
  const a = c.args[0], b = c.kind === 'res' ? c.args[1] : '', win = c.kind === 'f2p' || c.kind === 'p2f' ? c.args[1] : false;
  w(`    bad += check_call(${KIND[c.kind]}, ${esc(a)}, ${esc(b)}, ${win}, ${c.want !== null}, ${esc(c.want || '')});`);
}
for (const c of setCases) {
  w(`    bad += check_set(${c.which}, ${esc(c.href)}, ${esc(c.value)}, ${esc(c.want)}, ${esc(c.orig)});`);
}
w('    assert(bad == 0);');
w('}');
const per = {}; for (const c of calls) per[c.kind] = (per[c.kind] || 0) + 1;
process.stderr.write(`cases=${cases.length} calls=${calls.length} sets=${setCases.length} ${JSON.stringify(per)}\n`);
