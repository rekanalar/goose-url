// The known default ports and the checked setters of the url package.
//
// Each setter checks the value first. A bad value gives false and leaves
// the Url as it was, as the Rust set_scheme and set_host do. A setter
// stores a slice, so the value text must outlive the Url value. A setter
// never escapes the value: it refuses the bytes that the part may not
// hold. Use escape functions first when the text needs them.
namespace url;

import std;

fn same_lower(a: const u8[:], b: const u8[:]) -> bool {
    if a.len != b.len { return false; }
    for c, i in a {
        var d = c;
        if d >= 'A' && d <= 'Z' { d += 32; }
        if d != b[i] { return false; }
    }
    return true;
}

// default_port gives the known port of a scheme, or -1. The list is the
// one of the Rust port_or_known_default: http, https, ws, wss and ftp.
fn default_port(scheme: const u8[:]) -> i32 {
    if same_lower(scheme, "http") || same_lower(scheme, "ws") { return 80; }
    if same_lower(scheme, "https") || same_lower(scheme, "wss") { return 443; }
    if same_lower(scheme, "ftp") { return 21; }
    return -1;
}

// port_or_default gives the port of the URL, or the default port of its
// scheme when the URL has no port, or -1.
fn port_or_default(u: const Url&) -> i32 {
    if u.port >= 0 { return u.port; }
    return default_port(u.scheme);
}

// clean says whether s holds no control byte, no space and no byte of
// banned.
fn clean(s: const u8[:], banned: const u8[:]) -> bool {
    for c in s {
        if c <= ' ' || c == 127 || in_set(c, banned) { return false; }
    }
    return true;
}

// set_scheme sets the scheme. It must start with a letter and hold only
// letters, digits, +, - and ".". The case stays as given.
fn set_scheme(u: Url&, s: const u8[:]) -> bool {
    if s.len == 0 || !is_letter(s[0]) { return false; }
    for c in s {
        if !is_scheme_char(c) { return false; }
    }
    u.scheme = s;
    u.has_scheme = true;
    return true;
}

// set_host sets the host. An IPv6 host has no brackets and holds only
// hex digits, ":" and ".". Other hosts hold none of / ? # @ [ ] : and
// \. An empty host is a fault.
fn set_host(u: Url&, s: const u8[:]) -> bool {
    if s.len == 0 || !clean(s, "/?#@[]\\") { return false; }
    var v6 = false;
    for c in s {
        if c == ':' { v6 = true; }
    }
    for c in s {
        if v6 && c != ':' && c != '.' && hex_value(c) < 0 { return false; }
    }
    u.host = s;
    u.has_authority = true;
    return true;
}

// set_port sets the port from its text. Empty text removes the port. A
// valid port holds digits only and has a value up to 65535.
fn set_port(u: Url&, text: const u8[:]) -> bool {
    if text.len == 0 {
        u.port = -1;
        u.port_text = text;
        return true;
    }
    let p, ok = port_number(text);
    if !ok { return false; }
    u.port = p;
    u.port_text = text;
    return true;
}

// set_userinfo sets the userinfo. It holds none of / ? # @. Empty text
// removes it.
fn set_userinfo(u: Url&, s: const u8[:]) -> bool {
    if !clean(s, "/?#@") { return false; }
    u.userinfo = s;
    return true;
}

// set_path sets the path. It holds none of ? #. A URL with a host needs a
// path that is empty or starts with "/".
fn set_path(u: Url&, s: const u8[:]) -> bool {
    if !clean(s, "?#") { return false; }
    if u.host.len > 0 && s.len > 0 && s[0] != '/' { return false; }
    u.path = s;
    return true;
}

// set_query sets the query without its "?". It holds no #. Empty text
// removes the query.
fn set_query(u: Url&, s: const u8[:]) -> bool {
    if !clean(s, "#") { return false; }
    u.query = s;
    u.has_query = s.len > 0;
    return true;
}

// set_fragment sets the fragment without its "#". Empty text removes it.
fn set_fragment(u: Url&, s: const u8[:]) -> bool {
    if !clean(s, "") { return false; }
    u.fragment = s;
    return true;
}
