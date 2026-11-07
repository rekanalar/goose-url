# goose-url

[![ci](https://github.com/rekanalar/goose-url/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-url/actions/workflows/ci.yml)

URL parsing and building for the [Goose](https://github.com/aardappel/goose) programming language. The rules
are RFC 3986.

The package parses an absolute URL into its parts and rebuilds the text
from the parts. It encodes and decodes percent escapes. It joins a
relative reference against a base URL.

It reads and writes query pairs and form bodies, and it edits a query. It
gives the origin of a URL and hides its password. It joins path parts.
It sets the parts of a URL with checked setters. Pure Goose, no C.

## Install

Add this to the root file of the program that uses it:

```goose
import url from "rekanalar/goose-url@v0.3.0";
```

## API

| Function | What it does |
|---|---|
| `parse(s)` | splits one absolute URL into its parts; gives `Url, bool` |
| `build(out, u)` | writes the URL text into the buffer of the caller |
| `encode(out, s, safe)` | percent-encodes the bytes that a URL may not hold |
| `decode(out, s, form)` | reverses the escapes; `form` makes `+` a space |
| `join(out, base, ref)` | resolves one reference against one base URL |
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
- `origin` lowers only ASCII. There is no IDNA, and an IPv6 address is not made canonical.

## Limits

- The package keeps no copy. A `Url` and a `Pair` hold slices, so the text must outlive them.
- A setter refuses a bad byte. It never escapes the value. Call `escape` first.
- The host is not normalized: no IDNA, no IPv4 check, and no lower case outside `origin`.
- The path is not normalized in `parse`; only `join` removes dot segments.
- There is no `file:` rule and no WHATWG special-scheme parsing.
- A `Url` field set by hand skips the checks. Use the setters.

## Test

```bash
goose run test/run.goose
goose run examples/resolve.goose
goose run examples/edit.goose
```

## License

MIT
