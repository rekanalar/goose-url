# goose-url

[![ci](https://github.com/rekanalar/goose-url/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-url/actions/workflows/ci.yml)

URL parsing and building for the [Goose](https://github.com/aardappel/goose) programming language. The rules
are RFC 3986.

The package parses an absolute URL into its parts and rebuilds the text
from the parts. It encodes and decodes percent escapes. It joins a
relative reference against a base URL. It reads and writes query pairs
and form bodies. It sets the parts of a URL with checked setters. Pure
Goose, no C.

## Install

Add this to the root file of the program that uses it:

```goose
import url from "rekanalar/goose-url@v0.2.0";
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

## Limits

- The package keeps no copy. A `Url` and a `Pair` hold slices, so the text must outlive them.
- A setter refuses a bad byte. It never escapes the value. Call `escape` first.
- The host is not normalized: no IDNA, no lower case, no IPv4 check.
- The path is not normalized in `parse`; only `join` removes dot segments.
- There is no `file:` rule and no WHATWG special-scheme parsing.
- A `Url` field set by hand skips the checks. Use the setters.

## Test

```bash
goose run test/run.goose
goose run examples/resolve.goose
```

## License

MIT
