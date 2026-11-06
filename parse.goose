// The parser for the url package. RFC 3986.
//
// parse splits one absolute URL into its parts. The parts are slices over
// the input text, so the input text must outlive the Url value. parse
// never copies and never grows memory.
//
// Every part is a slice of the input, even an empty part. A slice of the
// input keeps the parts in one scope, which the compiler needs.
namespace url;

import std;

// Url holds the parts of one URL. An absent part is an empty slice. The
// port holds -1 when the URL has no port.
struct Url {
    scheme: const u8[:],
    userinfo: const u8[:],
    host: const u8[:],
    port: i32,
    port_text: const u8[:],
    path: const u8[:],
    query: const u8[:],
    fragment: const u8[:],
    has_scheme: bool,
    has_authority: bool,
    has_query: bool,
}

fn is_letter(c: u8) -> bool { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
fn is_digit(c: u8) -> bool { return c >= '0' && c <= '9'; }

fn is_scheme_char(c: u8) -> bool {
    return is_letter(c) || is_digit(c) || c == '+' || c == '-' || c == '.';
}

// split_parts finds the path, the query and the fragment of the text.
// The scan runs once from the left, so an escaped %23 never splits the
// text.
fn split_parts(s: const u8[:]) -> const u8[:], const u8[:], const u8[:], bool {
    var frag_at = -1;
    var query_at = -1;
    var i = 0;
    while i < s.len {
        if s[i] == '#' && frag_at < 0 { frag_at = i; }
        if s[i] == '?' && query_at < 0 && frag_at < 0 { query_at = i; }
        i += 1;
    }
    if frag_at >= 0 {
        let fragment = s[frag_at + 1..];
        if query_at >= 0 {
            return s[..query_at], s[query_at + 1..frag_at], fragment, true;
        }
        return s[..frag_at], s[0..0], fragment, false;
    }
    if query_at >= 0 {
        return s[..query_at], s[query_at + 1..], s[0..0], true;
    }
    return s, s[0..0], s[0..0], false;
}

// cut_userinfo splits the userinfo from the rest of one authority. The
// userinfo ends at the last @, so an @ in the host never splits the
// wrong place.
fn cut_userinfo(a: const u8[:]) -> const u8[:], const u8[:] {
    var at = -1;
    for c, i in a {
        if c == '@' { at = i; }
    }
    if at < 0 { return a[0..0], a; }
    return a[..at], a[at + 1..];
}

// port_number gives the number of a port text. A valid port holds at
// most five digits and a value up to 65535. An empty port is a fault.
fn port_number(t: const u8[:]) -> i32, bool {
    if t.len == 0 || t.len > 5 { return -1, false; }
    var v: i32 = 0;
    for c in t {
        if !is_digit(c) { return -1, false; }
        v = v * 10 + (c - '0');
    }
    if v > 65535 { return -1, false; }
    return v, true;
}

// bad_host gives the parts of an authority that is not valid. The empty
// parts stay rooted in the authority text.
fn bad_host(a: const u8[:]) -> const u8[:], const u8[:], i32, const u8[:], bool {
    return a[0..0], a[0..0], -1, a[0..0], false;
}

// split_host finds the userinfo, the host, the port number and the port
// text of one authority. An IPv6 host stands in brackets, and the host
// slice keeps the inside of the brackets without them.
fn split_host(a: const u8[:]) -> const u8[:], const u8[:], i32, const u8[:], bool {
    let userinfo, rest = cut_userinfo(a);
    if rest.len == 0 { return bad_host(a); }
    if rest[0] == '[' {
        var close = -1;
        for c, i in rest {
            if c == ']' { close = i; break; }
        }
        if close < 0 { return bad_host(a); }
        let host = rest[1..close];
        for c in host {
            if c == ' ' { return bad_host(a); }
        }
        if close + 1 == rest.len { return userinfo, host, -1, rest[0..0], true; }
        if rest[close + 1] != ':' { return bad_host(a); }
        let port_text = rest[close + 2..];
        if port_text.len == 0 { return userinfo, host, -1, port_text, true; }
        let port, ok = port_number(port_text);
        if !ok { return bad_host(a); }
        return userinfo, host, port, port_text, true;
    }
    var colon = -1;
    for c, i in rest {
        if c == ':' { colon = i; }
    }
    if colon < 0 {
        let host = rest;
        for c in host {
            if c == ' ' { return bad_host(a); }
        }
        return userinfo, host, -1, rest[0..0], true;
    }
    let host = rest[..colon];
    for c in host {
        if c == ' ' { return bad_host(a); }
    }
    let port_text = rest[colon + 1..];
    if port_text.len == 0 { return userinfo, host, -1, port_text, true; }
    let port, ok = port_number(port_text);
    if !ok { return bad_host(a); }
    return userinfo, host, port, port_text, true;
}

// parse_ref splits one URL or one reference into its parts. A reference
// may leave out the scheme and the authority. It returns false when the
// text is not valid.
fn parse_ref(s: const u8[:]) -> Url, bool {
    // The scheme ends at the first colon. It must start with a letter and
    // hold only scheme characters.
    var scheme_end = -1;
    var i = 0;
    if s.len > 0 && is_letter(s[0]) {
        while i < s.len && is_scheme_char(s[i]) { i += 1; }
        if i < s.len && s[i] == ':' { scheme_end = i; }
    }
    var scheme = s[0..0];
    var has_scheme = false;
    var pos = 0;
    if scheme_end > 0 {
        scheme = s[..scheme_end];
        has_scheme = true;
        pos = scheme_end + 1;
    }
    var userinfo = s[0..0];
    var host = s[0..0];
    var port: i32 = -1;
    var port_text = s[0..0];
    var has_authority = false;
    if s.len - pos >= 2 && s[pos] == '/' && s[pos + 1] == '/' {
        // The authority runs to the first /, ? or #.
        var end = s.len;
        var j = pos + 2;
        while j < s.len {
            let c = s[j];
            if c == '/' || c == '?' || c == '#' { end = j; break; }
            j += 1;
        }
        let u, h, p, pt, ok = split_host(s[pos + 2..end]);
        if !ok {
            return Url { scheme: scheme, userinfo: s[0..0], host: s[0..0], port: -1, port_text: s[0..0], path: s[0..0], query: s[0..0], fragment: s[0..0], has_scheme: has_scheme, has_authority: false, has_query: false }, false;
        }
        userinfo = u;
        host = h;
        port = p;
        port_text = pt;
        has_authority = true;
        pos = end;
    }
    let path, query, fragment, has_query = split_parts(s[pos..]);
    return Url { scheme: scheme, userinfo: userinfo, host: host, port: port, port_text: port_text, path: path, query: query, fragment: fragment, has_scheme: has_scheme, has_authority: has_authority, has_query: has_query }, true;
}

// parse splits one absolute URL into its parts. It returns false when the
// text is not a valid absolute URL. The parts are slices over the input.
fn parse(s: const u8[:]) -> Url, bool {
    if s.len == 0 {
        return Url { scheme: s[0..0], userinfo: s[0..0], host: s[0..0], port: -1, port_text: s[0..0], path: s[0..0], query: s[0..0], fragment: s[0..0], has_scheme: false, has_authority: false, has_query: false }, false;
    }
    let u, ok = parse_ref(s);
    if !ok || !u.has_scheme { return u, false; }
    return u, true;
}
