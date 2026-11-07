#!/usr/bin/env node
// Makes test/normalize_cases.goose for goose-url from Node URL.
//
// Usage, in the package directory:
//   node test/make_normalize_cases.mjs > test/normalize_cases.goose
//
// Every case holds the result that Node gave for new URL(input).href, or
// the fact that Node threw. The seed is fixed, so the output is stable.
// The count of cases goes to standard error.
'use strict';

let state = 20261107;
function rnd() {
  state = (state + 0x6D2B79F5) | 0;
  let t = Math.imul(state ^ (state >>> 15), 1 | state);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];

// Goose string escapes. The backslash, the quote and the control bytes
// go out as \xNN, so the text stays one line.
function esc(s) {
  let out = '"';
  for (const ch of s) {
    const c = ch.codePointAt(0);
    if (c === 0x5c || c === 0x22 || c < 0x20 || c > 0x7e) {
      out += '\\x' + c.toString(16).padStart(2, '0');
    } else {
      out += ch;
    }
  }
  return out + '"';
}

// The oracle. Gives {href} or {fail: true}.
function oracle(input) {
  try {
    return { href: new URL(input).href };
  } catch (e) {
    return { fail: true };
  }
}

const cases = [];
function add(input) {
  if (cases.some((c) => c.input === input)) return;
  // A host with a byte of 128 and up is out of scope for this package.
  for (const ch of input) {
    if (ch.codePointAt(0) > 0x7e) return;
  }
  const r = oracle(input);
  if (!r.fail && !/^[\x20-\x7e]*$/.test(r.href)) return;
  cases.push({ input, want: r });
}

const SCHEMES = ['http', 'https', 'ws', 'wss', 'ftp'];
function scheme() {
  const s = pick(SCHEMES);
  const form = int(8);
  if (form === 0) return s + '://';
  if (form === 1) return s + ':';
  if (form === 2) return s + ':/';
  if (form === 3) return s + ':\\';
  if (form === 4) return s + ':\\\\';
  if (form === 5) return s.toUpperCase() + '://';
  if (form === 6) return s + '://';
  return s + ':////';
}

const HOSTS = ['example.com', 'EXAMPLE.com', 'a.b.c', 'a_b', 'a~b', 'a!b', 'a,b', 'a-b',
  'a$b', 'a&b', "a'b", '1.2.3.4', '0x7f.1', '0177.0.0.1', '127.1', '1.2.3', '999', '65536',
  '4294967295', '4294967296', '1.2.3.4.5', '08', '09', '1.2.3.4.', '1.2.3.4..', 'a.b.', '.', '..',
  '0', '0x', '0x10', '0777', '1.0x2.3.4', '1.02.3.4', '%41.com', 'a%2Eb', 'a%25b', 'a%2Fb',
  'a%zzb', 'a_b.c_d', 'XN--A.COM'];

const V6 = ['[::1]', '[1::8]', '[::]', '[0:0:1:0:0:0:0:1]', '[::ffff:1.2.3.4]',
  '[::ffff:0:1.2.3.4]', '[1:0:0:1:0:0:0:1]', '[1:2:3:4:5:6:7:8]', '[FE80::1]',
  '[::ffff:255.255.255.255]', '[::ffff:1.2.3.256]', '[1::2::3]', '[12345::]',
  '[1:2:3:4:5:6:7]', '[1:2:3:4:5:6:7:1.2.3.4]', '[::1.2.3.4]', '[::ffff:0.2.3.4]',
  '[::ffff:00.2.3.4]', '[1:2:3:4:5:6:7::]', '[::2:3:4:5:6:7:8]', '[0:1:0:1:0:1:0:1]',
  '[fe80:0:0:0:200:5eff:fe00:5213]', '[::ffff:0:0]'];

const USERS = ['', 'u', 'u:p', 'u:p:q', ':p', ':', 'u%40s:p%40s', 'a b', 'a^b', 'a|b',
  'a{b', 'a~b', 'u%20v', '%41', "a'b", 'a<b', 'a=b', 'a;b', 'a[b', 'a]b', 'a`b', 'a"b',
  'a%b', 'a:b@c'];
const PORTS = ['', ':80', ':443', ':21', ':0', ':65535', ':65536', ':080', ':a', ':-1',
  ':99999999999', ':0x50', ':+80', ':65534'];
const PATHS = ['', '/', '/x', '/x/y', '/x/./y', '/x/../y', '/../x', '/./', '/x/..',
  '/a/b/../../c', '/%2e/x', '/%2e%2e/x', '/x/%2e.', '/x y', '/x%20y', '/a b/c d',
  '/x^y', '/x{y}z', '/x|y', '/x%y', '/%41', '/x`y', '/a//b', '/x/', '//', '/...',
  '/%2e%2e%2e/x', '/a/./b/../c/./d', '/x"y', '/x<y', '/x#y'];
const QUERIES = ['', '?', '?a=1', '?a b', '?a^b', "?a'b", '?a<b', '?a|b', '?%41', '?%',
  '?a{b', '?a`b', '?a=b&c=d', '?a"b', '?a\\b'];
const FRAGS = ['', '#', '#x', '#a b', '#a^b', '#a{b}', '#a`b', '#%41', '#%', '#a|b',
  '#a"b', '#a<b'];

// Hand-shape cases: each pool crossed with the others a bounded number of
// times, plus every pair of pools.
function seedCases() {
  for (const s of SCHEMES) {
    add(s + '://example.com/');
    add(s + ':example.com');
    add(s + ':/\\/example.com');
    add(s + '://EXAMPLE.com:80/x y?q a#f b');
  }
  for (const h of HOSTS) { add('http://' + h + '/x'); add('https://' + h + ':443'); }
  for (const h of V6) { add('http://' + h + '/x'); add('ws://' + h + ':80/'); }
  for (const u of USERS) add('http://' + u + '@example.com/x');
  for (const p of PORTS) add('http://example.com' + p + '/x');
  for (const p of PATHS) add('http://example.com' + p);
  for (const q of QUERIES) add('http://example.com/a' + q);
  for (const f of FRAGS) add('http://example.com/a' + f);
  // Userinfo against the odd hosts.
  for (const u of USERS.slice(1, 12)) {
    add('http://' + u + '@' + pick(HOSTS) + '/' + pick(PATHS));
  }
  // Port and userinfo together, and v6 with a port.
  for (let i = 0; i < 40; i += 1) {
    add(scheme() + pick(USERS) + '@' + pick(HOSTS) + pick(PORTS) + pick(PATHS)
      + pick(QUERIES) + pick(FRAGS));
    add('http://' + pick(V6) + pick(PORTS) + pick(PATHS) + pick(QUERIES));
    add('https://' + pick(USERS) + '@' + pick(V6) + pick(PORTS) + pick(PATHS));
    add(pick(SCHEMES) + ':' + pick(PATHS.slice(1)) + pick(QUERIES));
    add(pick(SCHEMES) + ':\\\\' + pick(HOSTS) + pick(PORTS) + pick(PATHS));
  }
  // Tab, LF and CR removal, and outer space trim.
  for (const t of ['\t', '\n', '\r', ' ', ' \t ', '\t\n']) {
    add(t + 'http://example.com/x');
    add('http://example.com/x' + t);
    add('http://ex\tample.com/x');
    add('http://example.com/x\ty?q\rb');
  }
}

// Pseudo-random composites until the target count is reached.
function fuzzCases(target) {
  let tries = 0;
  while (cases.length < target && tries < target * 12) {
    tries += 1;
    const kind = int(10);
    let input;
    if (kind < 4) {
      input = scheme() + pick(USERS) + '@' + pick(HOSTS) + pick(PORTS) + pick(PATHS)
        + pick(QUERIES) + pick(FRAGS);
    } else if (kind < 6) {
      input = scheme() + pick(V6) + pick(PORTS) + pick(PATHS) + pick(QUERIES) + pick(FRAGS);
    } else if (kind < 8) {
      input = scheme() + pick(HOSTS) + pick(PORTS) + pick(PATHS) + pick(QUERIES) + pick(FRAGS);
    } else if (kind === 8) {
      input = scheme() + pick(PATHS) + pick(PATHS) + pick(QUERIES) + pick(FRAGS);
    } else {
      input = scheme() + pick(USERS) + '@' + pick(HOSTS) + pick(HOSTS) + pick(PORTS)
        + pick(PATHS) + pick(QUERIES);
    }
    add(input);
  }
}

seedCases();
fuzzCases(600);

let out = '';
out += '// Cases made by test/make_normalize_cases.mjs with Node v22.22.1.\n';
out += '// Do not edit by hand. Make the file again with the script.\n\n';
out += 'namespace normalize_cases;\n\n';
out += 'import std;\nimport url from "..";\n\n';
out += '// expect_ok checks that normalize gives want for s.\n';
out += 'fn expect_ok(s: const u8[:], want: const u8[:]) {\n';
out += '    var got: u8[>..] = [];\n';
out += '    if !url::normalize(got, s) || got != want {\n';
out += '        print("normalize ok-case failed. input: ", s);\n';
out += '        print("  want: ", want, "  got: ", got);\n';
out += '        assert(false);\n';
out += '    }\n';
out += '}\n\n';
out += '// expect_no checks that normalize refuses s.\n';
out += 'fn expect_no(s: const u8[:]) {\n';
out += '    var got: u8[>..] = [];\n';
out += '    if url::normalize(got, s) {\n';
out += '        print("normalize no-case failed. input: ", s, " gave: ", got);\n';
out += '        assert(false);\n';
out += '    }\n';
out += '}\n\n';
out += 'fn check_normalize() {\n';
for (const c of cases) {
  if (c.want.fail) {
    out += '    expect_no(' + esc(c.input) + ');\n';
  } else {
    out += '    expect_ok(' + esc(c.input) + ', ' + esc(c.want.href) + ');\n';
  }
}
out += '}\n';

process.stdout.write(out);
process.stderr.write(cases.length + ' cases\n');
