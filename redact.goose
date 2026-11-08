// Origin, redaction and path joining for the url package.
//
// origin follows Node URL.origin. redacted follows Go URL.Redacted.
// join_path follows Go URL.JoinPath. The host is not normalized beyond
// ASCII lower case, so the origin of a host with non-ASCII bytes or an
// IPv6 address with upper-case digits is not the Node text.
namespace url;

import std;

fn push_lower(out: u8[>..]&, s: const u8[:]) {
    for c in s {
        if c >= 'A' && c <= 'Z' { out.push(c + 32); } else { out.push(c); }
    }
}

// origin writes scheme://host[:port] into out and gives true. A URL of
// another scheme than http, https, ws, wss and ftp, or with no host,
// has the null origin: the result is false and out stays as it was. The
// scheme and the host are in ASCII lower case. The port stays only when it
// differs from the default port. A blob: URL gives the origin of the URL
// that its path holds. A special scheme reads a backslash as a slash, so
// the authority ends at the first backslash.
fn origin(out: u8[>..]&, u: const Url&) -> bool {
    // A blob URL gives the origin of the URL that its path holds. The
    // path is a part of the text of the URL, so the parts of the inner
    // URL stay valid. A blob URL inside a blob URL has the null origin,
    // as in Node.
    var cur = u;
    if same_lower(cur.scheme, "blob") {
        let v, ok = parse(cur.path);
        if !ok { return false; }
        if same_lower(v.scheme, "blob") { return false; }
        cur = v;
    }
    if default_port(cur.scheme) < 0 { return false; }
    // Build the authority and cut it at the first backslash. A special
    // scheme reads a backslash as a slash, so the authority ends there.
    var auth: u8[>..] = [];
    if cur.userinfo.len > 0 {
        auth.append(cur.userinfo[..]);
        auth.push('@');
    }
    // A host with a colon is an IPv6 address. The parser keeps the text
    // without the brackets, so the authority needs them back.
    var v6 = false;
    for c in cur.host {
        if c == ':' { v6 = true; }
    }
    if v6 {
        auth.push('[');
        auth.append(cur.host[..]);
        auth.push(']');
    } else {
        auth.append(cur.host[..]);
    }
    if cur.port_text.len > 0 {
        auth.push(':');
        auth.append(cur.port_text[..]);
    }
    var cut = auth.len;
    for c, i in auth {
        if c == '\\' { cut = i; break; }
    }
    let user, host, port, pt, ok = split_host(auth[..cut]);
    if !ok || host.len == 0 { return false; }
    // The text goes into a buffer of its own, so a fault leaves the
    // buffer of the caller as it was.
    var text: u8[>..] = [];
    push_lower(text, cur.scheme);
    text.append("://");
    // A host with a colon is an IPv6 address. It keeps its text.
    for c in host {
        if c == ':' { v6 = true; }
    }
    if v6 {
        text.push('[');
        push_lower(text, host);
        text.push(']');
    } else {
        // The IDNA rules give the host in ASCII lower case and in the
        // Punycode form.
        var h: u8[>..] = [];
        if !domain_to_ascii(h, host[..]) { return false; }
        push_lower(text, h[..]);
    }
    if port >= 0 && port != default_port(cur.scheme) {
        text.push(':');
        format(text, port);
    }
    out.append(text[..]);
    return true;
}

// redacted writes the URL text into out with the password as xxxxx. The
// password is the userinfo after its first colon, and an empty password
// counts as set, as in Go. A URL with no colon in the userinfo is
// written as build writes it.
fn redacted(out: u8[>..]&, u: const Url&) {
    var shown: u8[>..] = [];
    var t = u;
    var colon = -1;
    for c, i in u.userinfo {
        if c == ':' { colon = i; break; }
    }
    if colon >= 0 {
        shown.append(u.userinfo[..colon + 1]);
        shown.append("xxxxx");
        t.userinfo = shown[..];
    }
    build(out, t);
}

fn has_banned(s: const u8[:]) -> bool {
    for c in s {
        if c == '?' || c == '#' { return true; }
    }
    return false;
}

// add_segments walks the pieces of s between slashes. It skips an empty
// piece and ".". A ".." drops the last segment, and never goes above the
// root. Any other piece joins the path. starts holds the offset of each
// segment in path, so a drop costs no scan.
fn add_segments(path: u8[>..]&, starts: i64[>..]&, s: const u8[:]) {
    var pos = 0;
    while pos <= s.len {
        var end = pos;
        while end < s.len && s[end] != '/' { end += 1; }
        let piece = s[pos..end];
        pos = end + 1;
        if piece.len == 0 || piece == "." { continue; }
        if piece == ".." {
            if starts.len > 0 {
                path.resize(starts[starts.len - 1]);
                starts.resize(starts.len - 1);
            }
            continue;
        }
        starts.push(path.len);
        path.push('/');
        path.append(piece);
    }
}

// join_path joins the elements to the base path as Go JoinPath does. The
// result starts with "/". It drops empty and "." pieces and applies "..".
// It keeps a trailing "/" when the last element ends in "/", or when the
// base ends in "/" and there is no element. It gives false when a part
// holds ? or #, and then out stays as it was. It does not escape.
fn join_path(out: u8[>..]&, base: const u8[:], elems: const u8[:][:]) -> bool {
    if has_banned(base) { return false; }
    for e in elems {
        if has_banned(e) { return false; }
    }
    var path: u8[>..] = [];
    var starts: i64[>..] = [];
    add_segments(path, starts, base);
    for e in elems { add_segments(path, starts, e); }
    var slash = false;
    if elems.len > 0 {
        let l = elems[elems.len - 1];
        slash = l.len > 0 && l[l.len - 1] == '/';
    } else {
        slash = base.len > 0 && base[base.len - 1] == '/';
    }
    if path.len == 0 || slash { path.push('/'); }
    out.append(path[..]);
    return true;
}
