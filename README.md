# goose-url

[![ci](https://github.com/rekanalar/goose-url/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-url/actions/workflows/ci.yml)

URL parsing and building for the Goose programming language. The rules
are RFC 3986.

The package parses an absolute URL into its parts and rebuilds the text
from the parts. It encodes and decodes percent escapes. It joins a
relative reference against a base URL. Pure Goose, no C.

## Install

Add this to the root file of the program that uses it:

```goose
import url from "rekanalar/goose-url@v0.1.1";
```

## API

| Function | What it does |
|---|---|
| `parse(s)` | splits one absolute URL into its parts; gives `Url, bool` |
| `build(out, u)` | writes the URL text into the buffer of the caller |
| `encode(out, s, safe)` | percent-encodes the bytes that a URL may not hold |
| `decode(out, s, form)` | reverses the escapes; `form` makes `+` a space |
| `join(out, base, ref)` | resolves one reference against one base URL |

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

## License

MIT
