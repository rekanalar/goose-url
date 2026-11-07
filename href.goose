// The href helpers of the url package.
//
// resolve_href is new URL(ref, base).href of Node and the WHATWG rules.
// can_parse is URL.canParse. defrag is urldefrag of Python. is_abs and
// request_uri are IsAbs and RequestURI of Go. path_segments is
// path_segments of the Rust url crate.
namespace url;

import std;

// ref_clean removes tab, LF and CR, then the outer bytes of 0x20 and
// below, as normalize does.
fn ref_clean(out: u8[>..]&, s: const u8[:]) {
    var buf: u8[>..] = [];
    for c in s {
        if c != 0x09 && c != 0x0a && c != 0x0d { buf.push(c); }
    }
    var lo: i64 = 0;
    var hi: i64 = buf.len;
    while lo < hi && buf[lo] <= 0x20 { lo += 1; }
    while hi > lo && buf[hi - 1] <= 0x20 { hi -= 1; }
    out.append(buf[lo..hi]);
}

// scheme_end gives the index of the colon of a scheme at the start of s,
// or -1.
fn scheme_end(s: const u8[:]) -> i64 {
    for c, i in s {
        if c == ':' { return if i > 0 { i } else { -1 }; }
        if i == 0 {
            if !is_letter(c) { return -1; }
        } else if !is_scheme_char(c) {
            return -1;
        }
    }
    return -1;
}

fn is_slash(c: u8, special: bool) -> bool {
    return c == '/' || (special && c == '\\');
}

// drive_start says whether the path text starts with a drive letter after
// its slash: "/c:" followed by the end or by a slash, a ? or a #.
fn drive_start(p: const u8[:]) -> bool {
    return p.len >= 3 && p[0] == '/' && is_letter(p[1]) && (p[2] == ':' || p[2] == '|')
        && (p.len == 3 || p[3] == '/' || p[3] == '\\' || p[3] == '?' || p[3] == '#');
}

// drive_start_plain is drive_start for a text with no leading slash.
fn drive_start_plain(t: const u8[:]) -> bool {
    return t.len >= 2 && is_letter(t[0]) && (t[1] == ':' || t[1] == '|')
        && (t.len == 2 || t[2] == '/' || t[2] == '\\' || t[2] == '?' || t[2] == '#');
}

// resolve_href writes the href of the reference ref against the base into
// out. It gives false where Node throws.
fn resolve_href(out: u8[>..]&, ref: const u8[:], base: const u8[:]) -> bool {
    var b: u8[>..] = [];
    if !normalize(b, base) { return false; }
    var r: u8[>..] = [];
    ref_clean(r, ref);
    let bsi = scheme_end(b[..]);
    let bscheme = b[..bsi];
    let bspecial = default_port(bscheme) >= 0 || bscheme == "file";
    var t: const u8[:] = r[..];
    let rsi = scheme_end(r[..]);
    if rsi > 0 {
        // A scheme: absolute, unless it names the scheme of a special base
        // and no two slashes follow it.
        var rs: u8[>..] = [];
        push_lower(rs, r[..rsi]);
        let after = r[rsi + 1..];
        let same = rs[..] == bscheme && bspecial;
        if !same || (after.len >= 2 && after[0] == '/' && after[1] == '/' && bscheme != "file") {
            return normalize(out, r[..]);
        }
        t = after;
    }
    // The parts of the base: the prefix up to the path, the path, the rest.
    let bs = b[..];
    let has_auth = bs.len >= bsi + 3 && bs[bsi + 1] == '/' && bs[bsi + 2] == '/';
    var aend: i64 = bsi + 1;
    if has_auth {
        aend = bsi + 3;
        while aend < bs.len && bs[aend] != '/' && bs[aend] != '?' && bs[aend] != '#' { aend += 1; }
    }
    var pend = aend;
    while pend < bs.len && bs[pend] != '?' && bs[pend] != '#' { pend += 1; }
    var qend = pend;
    while qend < bs.len && bs[qend] != '#' { qend += 1; }
    let prefix = bs[..aend];
    let path = bs[aend..pend];
    let query = bs[pend..qend];
    var text: u8[>..] = [];
    // Ada refuses a reference with no # against a base with an opaque path.
    // A reference with a # resolves as against any other base.
    if !has_auth && !(path.len > 0 && path[0] == '/') {
        var hash = false;
        for c in t { if c == '#' { hash = true; } }
        if !hash { return false; }
    }
    if t.len >= 2 && is_slash(t[0], bspecial) && is_slash(t[1], bspecial) {
        text.append(bs[..bsi + 1]);
        text.append(t);
    } else if t.len >= 1 && is_slash(t[0], bspecial) {
        text.append(prefix);
        // A file: base keeps its drive letter for a path with one slash.
        if bscheme == "file" && drive_start(path) && !drive_start(t) {
            text.append(path[..3]);
        }
        text.append(t);
    } else if t.len == 0 {
        text.append(prefix);
        text.append(path);
        text.append(query);
    } else if t[0] == '?' {
        text.append(prefix);
        text.append(path);
        text.append(t);
    } else if t[0] == '#' {
        text.append(prefix);
        text.append(path);
        text.append(query);
        text.append(t);
    } else if bscheme == "file" && drive_start_plain(t) {
        // A drive letter starts a new path in a file: URL.
        text.append(prefix);
        text.append("/");
        text.append(t);
    } else {
        text.append(prefix);
        var cut: i64 = path.len;
        while cut > 0 && path[cut - 1] != '/' { cut -= 1; }
        var dir: u8[>..] = [];
        if cut > 0 { dir.append(path[..cut]); } else { dir.append(path); dir.append("/"); }
        if has_auth || path[0] == '/' {
            text.append(dir[..]);
            text.append(t);
        } else {
            // An opaque base resolves dots after its first segment, which
            // stays, as ada does it. The path of the reference takes the
            // encode set of a path, not the set of an opaque path.
            let pe2 = n_path_end(t);
            var tpath: u8[>..] = [];
            n_encode(tpath, t[..pe2], 0);
            var rem: u8[>..] = [];
            rem.append(dir[..]);
            rem.append(tpath[..]);
            var f: i64 = 0;
            while rem[f] != '/' { f += 1; }
            var fixed: u8[>..] = [];
            n_path(fixed, rem[f..], 2);
            text.append(rem[..f]);
            text.append(fixed[..]);
            text.append(t[pe2..]);
        }
    }
    return normalize(out, text[..]);
}

// can_parse is URL.canParse of Node with no base: the text is an absolute
// URL.
fn can_parse(s: const u8[:]) -> bool {
    var o: u8[>..] = [];
    return normalize(o, s);
}

// can_parse_base is URL.canParse of Node with a base.
fn can_parse_base(s: const u8[:], base: const u8[:]) -> bool {
    var o: u8[>..] = [];
    return resolve_href(o, s, base);
}

// defrag splits the text at the first #: the URL without the fragment, and
// the fragment without the #. The fragment is empty when there is no #.
fn defrag(s: const u8[:]) -> const u8[:], const u8[:] {
    for c, i in s {
        if c == '#' { return s[..i], s[i + 1..]; }
    }
    return s, s[s.len..];
}

// is_abs says whether the text starts with a scheme, as IsAbs of Go.
fn is_abs(s: const u8[:]) -> bool {
    return scheme_end(s) > 0;
}

// request_uri writes the path and the query of the URL as an HTTP request
// line holds them, as RequestURI of Go: the path, or "/" when it is empty,
// then "?" and the query.
fn request_uri(out: u8[>..]&, u: const Url&) {
    if u.path.len == 0 { out.append("/"); } else { out.append(u.path); }
    if u.has_query {
        out.append("?");
        out.append(u.query);
    }
}

// path_segments pushes the segments of a path that starts with a slash, as
// path_segments of Rust does. It gives false for any other path.
fn path_segments(out: const u8[:][>..]&, path: const u8[:]) -> bool {
    if path.len == 0 || path[0] != '/' { return false; }
    var start: i64 = 1;
    for c, i in path {
        if i > 0 && c == '/' {
            out.push(path[start..i]);
            start = i + 1;
        }
    }
    out.push(path[start..]);
    return true;
}
