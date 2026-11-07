# goose-url

[![ci](https://github.com/rekanalar/goose-url/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-url/actions/workflows/ci.yml)

URL parsing and building for the [Goose](https://github.com/aardappel/goose) programming language. The rules
are RFC 3986, and `normalize` follows WHATWG URL as Node applies it.

The package parses an absolute URL into its parts and rebuilds the text
from the parts. It encodes and decodes percent escapes. It joins a
relative reference against a base URL.

It reads and writes query pairs and form bodies, and it edits a query. It
gives the origin of a URL and hides its password. It joins path parts.
It maps a Unicode host to Punycode with UTS 46 and NFC. It handles
`file:` URLs and non-special schemes, and it converts between a `file:`
URL and a path. Pure Goose, no C.

## Install

Add this to the root file of the program that uses it:

```goose
import url from "rekanalar/goose-url@v1.0.0";
```

## API

| Function | What it does |
|---|---|
| `parse(s)` | splits one absolute URL into its parts; gives `Url, bool` |
| `build(out, u)` | writes the URL text into the buffer of the caller |
| `encode(out, s, safe)` | percent-encodes the bytes that a URL may not hold |
| `decode(out, s, form)` | reverses the escapes; `form` makes `+` a space |
| `join(out, base, ref)` | resolves one reference against one base URL |
| `normalize(out, s)` | writes the Node `new URL(s).href` text; false and `out` unchanged when the URL is bad |
| `resolve_href(out, ref, base)` | writes `new URL(ref, base).href` of Node |
| `can_parse(s)` | true when `new URL(s)` of Node would succeed |
| `can_parse_base(s, base)` | true when `new URL(s, base)` of Node would succeed |
| `defrag(s)` | splits the text at the first `#`, as Python `urldefrag` |
| `is_abs(s)` | true when the text holds a scheme, as Go `ParseRequestURI` checks |
| `request_uri(out, u)` | writes path and query, as Go `RequestURI` |
| `path_segments(out, path)` | splits an absolute path into segments, as Rust `path_segments` |
| `domain_to_ascii(out, s)` | UTS 46 with Punycode, as Node `domainToASCII`; false on a bad domain |
| `domain_to_unicode(out, s)` | reverses Punycode, as Node `domainToUnicode`; false on a bad domain |
| `punycode_encode(out, s)` | RFC 3492 encode of UTF-8 text; false on a bad byte or overflow |
| `punycode_decode(out, s)` | RFC 3492 decode to UTF-8; false on a bad digit or overflow |
| `file_url_to_path(out, href, windows)` | Node `fileURLToPath` for the POSIX and the Windows form |
| `path_to_file_url(out, path, windows)` | Node `pathToFileURL` for the POSIX and the Windows form |
| `with_scheme`, `with_host`, `with_port`, `with_path`, `with_query`, `with_fragment` | write `href` with one part replaced; the value gets the encode set of the part |
| `with_username`, `with_password` | write `href` with the userinfo part replaced; the value gets the userinfo encode set |
| `query_pairs(out, q)` | decodes a query into `Pair` values; gives false after a bad escape |
| `query_get(out, q, key)` | decodes the first value of a key; gives false when absent |
| `append_pair(out, key, value)` | writes one form-encoded pair, with `&` in front when needed |
| `encode_pairs(out, pairs)` | writes all pairs in form encoding |
| `quote(out, s)` | Python `quote`: `/` and unreserved bytes stay |
| `quote_plus(out, s)` | Python `quote_plus`: space becomes `+`, `/` is escaped |
| `query_escape(out, s)` | Go `QueryEscape`; same bytes as `quote_plus` |
| `path_escape(out, s)` | Go `PathEscape`: `$&+=:@` stay, `/` is escaped |
| `form_encode(out, s)` | Rust `form_urlencoded` byte set: only `*-._` and alphanumerics stay |
| `escape(out, s, keep, unreserved, plus)` | the base of all the sets above |
| `default_port(scheme)` | 80, 443 or 21 for http, https, ws, wss, ftp; else -1 |
| `port_or_default(u)` | the port of the URL, else the default of its scheme |
| `query_has(q, key)` | true when a pair has the key |
| `query_has_pair(q, key, value)` | true when a pair has the key and the value |
| `query_get_all(out, q, key)` | collects the pairs of a key into a `Pair` list |
| `query_set(out, q, key, value)` | first pair of the key takes the value, others go, absent key appends; gives the old count or -1 |
| `query_delete(out, q, key)` | removes every pair of the key; gives the count or -1 |
| `query_delete_pair(out, q, key, value)` | removes every pair with the key and the value; gives the count or -1 |
| `query_sort(out, q)` | stable sort by key bytes; gives the pair count or -1 |
| `origin(out, u)` | writes `scheme://host[:port]`; false is the null origin |
| `redacted(out, u)` | writes the URL with the password as `xxxxx` |
| `join_path(out, base, elems)` | joins path parts, cleans dot segments; false when a part holds `?` or `#` |
| `set_scheme`, `set_host`, `set_port`, `set_userinfo`, `set_path`, `set_query`, `set_fragment` | check the value, then set it; give false and change nothing when it is bad |

A `Url` holds `scheme`, `userinfo`, `host`, `port`, `port_text`, `path`,
`query` and `fragment`. The parts are slices over the input text, so the
input text must outlive the `Url` value. The port holds -1 when the URL
has no port.

```goose
let u, ok = url::parse("https://example.com/a/b?q=1");
if ok {
    print(u.host, u.path);  // example.com/a/b
}
```

## Editing and joining

The edit functions read a query text and append the new text to `out`. The
text goes out in form encoding, as `append_pair` writes it. Give an empty
buffer for a fresh text.

```goose
var out: u8[>..] = [];
url::query_set(out, "a=1&b=2&a=3", "a", "9");   // a=9&b=2
```

The query rules follow Node `URLSearchParams`. `set` keeps the place of the
first pair. `delete(key, value)` removes every matching pair. The origin
rules follow Node `URL.origin`. The redaction and join rules follow Go
`URL.Redacted` and `URL.JoinPath`, because Node has no such call.

- `redacted` replaces the text after the first `:` of the userinfo with `xxxxx`. An empty password counts as set, as in Go.
- `join_path` drops empty and `.` parts and applies `..` but never goes above the root.
- `join_path` keeps a trailing `/` when the last part ends in `/`. It never escapes.
- With no part, `join_path` still cleans the base path, as Go does.

The test program holds 583 cases from Node v22. The script `test/make_node_cases.js`
makes them: 420 for the query calls and 163 for the origin. The script has a
fixed seed. The Go rules have hand cases from Go 1.27.

Differences from Node:

- A broken escape makes an edit give -1 and write nothing. Node keeps the text.
- `query_sort` compares key bytes. Node compares UTF-16 code units. The orders differ only for code points above U+FFFF.
- A `blob:` URL has the null origin here. Node gives the origin of the inner URL.
- A host or userinfo with a backslash has the null origin here. Node reads the backslash as a slash and gives the origin of the text before it.
- `origin` lowers only ASCII, and it reads no Punycode. An IPv6 address is not made canonical. Node runs IDNA in `origin`.

## Normalizing

`normalize` follows Node `new URL(text).href`, release v22.22.1. It strips
tab, LF and CR, and the outer spaces. It lowers the scheme and the host,
and reads a backslash as a slash. It removes dot segments, including
`%2e`, and an empty path becomes `/`. It drops a default or empty port,
and it fails on a port above 65535.

It writes IPv4 forms (hex, octal, short) as dotted decimal and IPv6 in canonical
form. It encodes the path, query, fragment and userinfo with the sets that
WHATWG fixes. It keeps an existing `%XX` and a bare `%`.

A host with a byte of 128 and up, or an `xn--` label, goes through
IDNA. The steps are UTS 46 non-transitional mapping, NFC, Punycode,
and the label checks of the URL parser of Node. The mapping and NFC
tables are Unicode 17.0. The label-check tables copy ada 3.3.0, the
parser that Node 22 holds.

The `file:` scheme rules of WHATWG apply. They cover an empty host or
`localhost`. They cover a drive letter on any platform. Backslashes
act as slashes, and a lone first `..` segment stays. The other
schemes are non-special. An opaque path keeps its text, a host gets no IDNA,
and the encode sets stay WHATWG.

```goose
var out: u8[>..] = [];
url::normalize(out, "HTTP://Example.COM:80/a/./b/../c");   // http://example.com/a/c
url::normalize(out, "http://münchen.de/");                 // http://xn--mnchen-3ya.de/
url::normalize(out, "file:/c:/x/y");                       // file:///c:/x/y
```

The test program holds 15144 generated cases from Node v22.22.1. The
scripts `test/make_normalize_cases.mjs` and `test/make_idna_cases.mjs`
make them. Both have the fixed seed 20261107. The count splits as
12000 for `normalize` and 2000 for the host, file and href helpers.
Another 1144 cover the `with_*` calls. The 600 older generated cases
stay, and the hand and hostile-input timing cases sit in
`test/run.goose`.

## File paths

`file_url_to_path` and `path_to_file_url` follow Node
`fileURLToPath` and `pathToFileURL`. The `windows` flag picks the
Windows form. A POSIX path starts with `/`. A Windows path needs a
drive letter and a separator, as `C:\dir\file`. It may also be a UNC
path with two backslashes, as `\\host\share\file`, or with two
forward slashes, as `//host/share/file`.

The path is resolved as Node resolves it. A `.` segment goes. A `..`
segment drops the segment before it. An empty segment goes. A trailing
separator stays.

```goose
var href: u8[>..] = [];
url::path_to_file_url(href, "C:\\Users\\ada\\a b.txt", true);
// file:///C:/Users/ada/a%20b.txt
```

## Setting a part

The package holds two levels for edits:

- `with_host(out, href, v)` reads the href text, encodes `v` with the
  encode set of the part, and writes the new href. The rules are the
  WHATWG rules that Node and Rust apply. The call gives false only when
  WHATWG ignores the value.
- `u.set_host(v)` checks the value and changes the part. The call
  never encodes, because a `Url` holds slices. A slice cannot own
  text that the call allocates. Give an already encoded value, or use
  the `with_*` call.

```goose
var out: u8[>..] = [];
url::with_path(out, "http://a/x", "a b?c");   // http://a/a%20b%3Fc
```

Before v1.0.0 the setters of a `Url` refused a byte that the part may
not hold. No call encoded a value. From v1.0.0 the `with_*` calls
encode the value. The setters still refuse it. Move a raw value from a
setter to the matching `with_*` call.

## Limits

- The package keeps no copy. A `Url` and a `Pair` hold slices, so the text must outlive them.
- A `Url` setter checks the value and never escapes it. Call `escape` first, or use `with_*`.
- `parse` does not normalize. Call `normalize` for the canonical text.
- The IDNA tables are Unicode 17.0, and the label checks copy Node v22.22.1. A later Node can differ for new code points.
- The script `test/check_idna_data.mjs` compares every code point with Node. It is a manual check. It is not part of CI.
- `defrag` and `is_abs` read only ASCII. A scheme with a byte of 128 and up gives false. RFC 3986 allows such a scheme; Node, Rust, Go and Python refuse it.
- `punycode_decode` refuses a basic code point from an insert, as RFC 3492 requires. It gives no reason text.
- `path_to_file_url` refuses a relative path and a Windows path with no drive and no share. Node resolves such a path against the working directory, so the result then depends on it. The Rust `Url::from_file_path` refuses it too.
- `path_to_file_url` gives `file:///C:/` for a drive root. Node on a POSIX host gives `file:///C://`. Node on Windows and Rust give `file:///C:/`.
- Node stops the process for a UNC path with a server name that a URL may not hold. This package gives false.

## Test

```bash
goose run test/run.goose
goose run examples/resolve.goose
goose run examples/edit.goose
```

## License

MIT
