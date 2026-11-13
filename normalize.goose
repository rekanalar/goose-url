// WHATWG normalization for the url package.
//
// normalize writes the canonical text of one absolute URL into out and
// gives true. The rules follow Node new URL(text).href.
// A failure gives false and leaves out unchanged.
namespace url;

import std;

const NLOW = "0123456789abcdef";

// The encode sets of WHATWG, as Node 22 applies them. kind 0 is the path,
// 1 the special query, 2 the fragment, 3 the username and 4 the password,
// 5 the query of a non-special scheme and 6 the C0 control set. Tab, LF
// and CR never reach this table, because normalize strips them first.
fn n_enc(kind: i64, c: u8) -> bool {
    if c < 0x20 || c >= 0x7f { return true; }
    if kind == 6 { return false; }
    if kind == 5 { return c == 0x20 || c == 0x22 || c == 0x23 || c == 0x3c || c == 0x3e; }
    if kind == 0 {
        return c == 0x20 || c == 0x22 || c == 0x23 || c == 0x3c || c == 0x3e || c == 0x3f
            || c == 0x5e || c == 0x60 || c == 0x7b || c == 0x7d;
    }
    if kind == 1 {
        return c == 0x20 || c == 0x22 || c == 0x27 || c == 0x3c || c == 0x3e || c == 0x23;
    }
    if kind == 2 {
        return c == 0x20 || c == 0x22 || c == 0x3c || c == 0x3e || c == 0x60;
    }
    if kind == 4 && c == 0x3a { return true; }
    if kind >= 3 && kind <= 4 {
        return c == 0x20 || c == 0x22 || c == 0x23 || c == 0x2f || c == 0x3b
            || (kind == 3 && c == 0x3a)
            || c == 0x3c || c == 0x3d || c == 0x3e || c == 0x3f
            || c == 0x40 || c == 0x5b || c == 0x5c || c == 0x5d || c == 0x5e
            || c == 0x60 || c == 0x7b || c == 0x7c || c == 0x7d;
    }
    return false;
}

// n_encode percent-encodes the bytes of the set of kind. An existing %XX
// escape and a bare % pass through unchanged, as Node keeps them.
fn n_encode(out: u8[>..]&, s: const u8[:], kind: i64) {
    for c in s {
        if n_enc(kind, c) {
            var buf: u8[3];
            buf[0] = '%';
            buf[1] = HEX[(c as i32) >> 4];
            buf[2] = HEX[(c as i32) & 15];
            out.append(buf[..]);
        } else {
            out.push(c);
        }
    }
}

// n_port parses a port text: digits only, at most 65535. An empty text
// is no port and gives -1.
fn n_port(t: const u8[:]) -> i64, bool {
    if t.len == 0 { return -1, true; }
    var v: i64 = 0;
    for c in t {
        if !is_digit(c) { return 0, false; }
        v = v * 10 + (c - '0');
        if v > 65535 { return 0, false; }
    }
    return v, true;
}

fn n_single_dot(seg: const u8[:]) -> bool {
    return same_lower(seg, ".") || same_lower(seg, "%2e");
}

fn n_double_dot(seg: const u8[:]) -> bool {
    return same_lower(seg, "..") || same_lower(seg, ".%2e") || same_lower(seg, "%2e.")
        || same_lower(seg, "%2e%2e");
}

// n_seg adds one segment to the result of n_path. In file mode a first
// segment that reads as a drive letter gets the colon.
fn n_seg(res: u8[>..]&, starts: i64[>..]&, seg: const u8[:], mode: i64) {
    res.push('/');
    starts.push(res.len);
    if mode == 1 && starts.len == 1 && seg.len == 2 && is_letter(seg[0])
        && (seg[1] == ':' || seg[1] == '|') {
        res.push(seg[0]);
        res.push(':');
        return;
    }
    res.append(seg);
}

// n_path resolves the dot segments of one path text and writes the result
// with a leading slash. The text starts with a slash, or it is empty.
// mode 0 is a special scheme: a backslash is a slash. mode 1 is file: the
// same, with the drive letter rules. mode 2 is a non-special scheme: only
// the slash splits. A ".." segment drops the last segment. The output
// holds at least one segment, so an empty path becomes "/".
fn n_path(out: u8[>..]&, s: const u8[:], mode: i64) {
    var res: u8[>..] = [];
    var starts: i64[>..] = [];
    var pos: i64 = 0;
    if s.len > 0 { pos = 1; }
    while pos <= s.len {
        var end = pos;
        while end < s.len && s[end] != '/' && (mode == 2 || s[end] != '\\') { end += 1; }
        let seg = s[pos..end];
        let more = end < s.len;
        if n_double_dot(seg) {
            // A lone segment of a file: path that starts like a drive letter stays,
            // as ada keeps it, whatever follows the colon.
            let lone = mode == 1 && starts.len == 1 && res.len >= 3 && is_letter(res[1]) && res[2] == ':';
            if starts.len > 0 && !lone {
                res.resize(starts[starts.len - 1] - 1);
                starts.resize(starts.len - 1);
            }
            if !more { n_seg(res, starts, "", mode); }
        } else if n_single_dot(seg) {
            if !more { n_seg(res, starts, "", mode); }
        } else {
            n_seg(res, starts, seg, mode);
        }
        pos = end + 1;
    }
    if starts.len == 0 { n_seg(res, starts, "", mode); }
    out.append(res[..]);
}

// normalize writes the canonical text of s into out and gives true. The
// rules follow Node new URL(text).href for http, https, ws, wss and ftp.
// It gives false, and leaves out unchanged, when s is not a valid URL of
// one of these schemes, or when the host holds a byte of 128 and up.
// n_path_end gives the index of the first ? or # of the text, or its length.
fn n_path_end(t: const u8[:]) -> i64 {
    for c, i in t {
        if c == '?' || c == '#' { return i; }
    }
    return t.len;
}

// n_query_fragment appends the query and the fragment of rest, which starts
// at the first ? or # of the tail. qkind is the encode set of the query.
fn n_query_fragment(res: u8[>..]&, rest: const u8[:], qkind: i64) {
    var h: i64 = rest.len;
    for c, i in rest {
        if c == '#' { h = i; break; }
    }
    if rest.len > 0 && rest[0] == '?' {
        res.push('?');
        n_encode(res, rest[1..h], qkind);
    }
    if h < rest.len {
        res.push('#');
        n_encode(res, rest[h + 1..], 2);
    }
}

// n_forbidden_host is the forbidden host code point of WHATWG, for the
// opaque host of a non-special scheme.
fn n_forbidden_host(c: u8) -> bool {
    return c == 0 || c == 0x20 || c == 0x23 || c == 0x2f || c == 0x3a || c == 0x3c
        || c == 0x3e || c == 0x3f || c == 0x40 || c == 0x5b || c == 0x5c || c == 0x5d
        || c == 0x5e || c == 0x7c;
}

// n_host writes the host of the text t. A text in brackets is an IPv6
// address. Otherwise a special scheme reads a domain or an IPv4 address,
// and a non-special scheme reads an opaque host.
fn n_host(out: u8[>..]&, t: const u8[:], special: bool) -> bool {
    if t.len > 0 && t[0] == '[' {
        if t[t.len - 1] != ']' { return false; }
        var pieces: i64[>..] = [];
        if !n_ipv6_parse(t[1..t.len - 1], pieces) { return false; }
        if pieces.len != 8 { return false; }
        out.push('[');
        n_ipv6_write(out, pieces[..]);
        out.push(']');
        return true;
    }
    if special { return n_domain(out, t); }
    for c in t {
        if n_forbidden_host(c) { return false; }
    }
    n_encode(out, t, 6);
    return true;
}

// n_auth reads the authority text: the userinfo, the host and the port.
// It gives the port, or -1, and the flag. A userinfo with no host fails.
fn n_auth(auth: const u8[:], special: bool, ui: u8[>..]&, hostout: u8[>..]&) -> i64, bool {
    // Split the userinfo at the last @.
    var at: i64 = -1;
    for c, i in auth {
        if c == '@' { at = i; }
    }
    var hostport: const u8[:] = auth;
    if at >= 0 { hostport = auth[at + 1..]; }
    if at >= 0 && hostport.len == 0 { return -1, false; }
    var port: i64 = -1;
    var hosttext: const u8[:] = hostport;
    if hostport.len > 0 && hostport[0] == '[' {
        var j: i64 = 1;
        while j < hostport.len && hostport[j] != ']' { j += 1; }
        if j >= hostport.len { return -1, false; }
        hosttext = hostport[..j + 1];
        let after = hostport[j + 1..];
        if after.len > 0 {
            if after[0] != ':' { return -1, false; }
            let pv, ok = n_port(after[1..]);
            if !ok { return -1, false; }
            port = pv;
        }
    } else {
        for c, i in hostport {
            if c == ':' {
                if i == 0 { return -1, false; }
                hosttext = hostport[..i];
                let pv, ok = n_port(hostport[i + 1..]);
                if !ok { return -1, false; }
                port = pv;
                break;
            }
        }
    }
    if !n_host(hostout, hosttext, special) { return -1, false; }
    if special && hostout.len == 0 { return -1, false; }

    // The userinfo, encoded with its own sets.
    if at >= 0 {
        let info = auth[..at];
        var colon: i64 = -1;
        for c, i in info {
            if c == ':' { colon = i; break; }
        }
        if colon >= 0 {
            if info[..colon].len > 0 || info[colon + 1..].len > 0 {
                n_encode(ui, info[..colon], 3);
                if info[colon + 1..].len > 0 {
                    ui.push(':');
                    n_encode(ui, info[colon + 1..], 4);
                }
            }
        } else {
            n_encode(ui, info, 3);
        }
    }
    return port, true;
}

// n_authority_end gives the end of the authority in rest from index p. A
// special scheme ends it at a backslash too.
fn n_authority_end(rest: const u8[:], p: i64, special: bool) -> i64 {
    var e = p;
    while e < rest.len && rest[e] != '/' && rest[e] != '?' && rest[e] != '#'
        && !(special && rest[e] == '\\') {
        e += 1;
    }
    return e;
}

// n_file normalizes the part of a file: URL after the scheme.
fn n_file(res: u8[>..]&, rest: const u8[:]) -> bool {
    res.append("//");
    let tailend = n_path_end(rest);
    var ptext: u8[>..] = [];
    var qf: const u8[:] = rest[tailend..];
    var slashes: i64 = 0;
    while slashes < 2 && slashes < rest.len && (rest[slashes] == '/' || rest[slashes] == '\\') { slashes += 1; }
    if slashes == 2 {
        let he = n_authority_end(rest, 2, true);
        let host = rest[2..he];
        if host.len == 2 && is_letter(host[0]) && (host[1] == ':' || host[1] == '|') {
            // A drive letter in the host place is the first path segment.
            ptext.push('/');
            ptext.append(rest[2..tailend]);
        } else {
            if host.len > 0 {
                var h: u8[>..] = [];
                if !n_host(h, host, true) { return false; }
                if h != "localhost" { res.append(h[..]); }
            }
            ptext.append(rest[he..tailend]);
        }
    } else if slashes == 1 {
        ptext.append(rest[..tailend]);
    } else {
        if tailend > 0 { ptext.push('/'); }
        ptext.append(rest[..tailend]);
    }
    var path: u8[>..] = [];
    n_path(path, ptext[..], 1);
    n_encode(res, path[..], 0);
    n_query_fragment(res, qf, 1);
    return true;
}

// n_nonspecial normalizes the part of a URL of a non-special scheme after
// the scheme. It gives the host as it is, with no case change and no IDNA.
fn n_nonspecial(res: u8[>..]&, rest: const u8[:]) -> bool {
    var tail: const u8[:] = rest;
    if rest.len >= 2 && rest[0] == '/' && rest[1] == '/' {
        let ae = n_authority_end(rest, 2, false);
        var ui: u8[>..] = [];
        var hostout: u8[>..] = [];
        let port, ok = n_auth(rest[2..ae], false, ui, hostout);
        if !ok { return false; }
        res.append("//");
        if ui.len > 0 {
            res.append(ui[..]);
            res.push('@');
        }
        res.append(hostout[..]);
        if port >= 0 {
            res.push(':');
            format(res, port);
        }
        tail = rest[ae..];
    }
    let pend = n_path_end(tail);
    let ptext = tail[..pend];
    if ptext.len > 0 {
        if tail.len == rest.len && ptext[0] != '/' {
            // An opaque path: no dot segments, only the control set. A space
            // at the end of it is escaped when a query or a fragment follows.
            if ptext[ptext.len - 1] == ' ' && pend < tail.len {
                n_encode(res, ptext[..ptext.len - 1], 6);
                res.append("%20");
            } else {
                n_encode(res, ptext, 6);
            }
        } else {
            var path: u8[>..] = [];
            n_path(path, ptext, 2);
            // A path of an empty first segment needs "/." with no host.
            if tail.len == rest.len && path.len > 1 && path[1] == '/' { res.append("/."); }
            n_encode(res, path[..], 0);
        }
    }
    n_query_fragment(res, tail[pend..], 5);
    return true;
}

fn normalize(out: u8[>..]&, s: const u8[:]) -> bool {
    // Strip tab, LF and CR, then the outer bytes of 0x20 and below.
    var buf: u8[>..] = [];
    for c in s {
        if c != 0x09 && c != 0x0a && c != 0x0d { buf.push(c); }
    }
    var lo: i64 = 0;
    var hi: i64 = buf.len;
    while lo < hi && buf[lo] <= 0x20 { lo += 1; }
    while hi > lo && buf[hi - 1] <= 0x20 { hi -= 1; }
    let inp = buf[lo..hi];

    // Scheme: one letter, then letters, digits, +, - or ., then :.
    var si: i64 = -1;
    for c, i in inp {
        if c == ':' { si = i; break; }
        if i == 0 {
            if !is_letter(c) { return false; }
        } else if !is_scheme_char(c) {
            return false;
        }
    }
    if si <= 0 { return false; }
    var sl: u8[>..] = [];
    push_lower(sl, inp[..si]);
    let scheme = sl[..];
    let special = default_port(scheme) >= 0;
    let rest = inp[si + 1..];

    // The result is built apart and appended to out on success.
    var res: u8[>..] = [];
    res.append(scheme);
    res.push(':');
    if scheme == "file" {
        if !n_file(res, rest) { return false; }
        out.append(res[..]);
        return true;
    }
    if !special {
        if !n_nonspecial(res, rest) { return false; }
        out.append(res[..]);
        return true;
    }

    // Skip the slashes, then read the authority.
    var p: i64 = 0;
    while p < rest.len && (rest[p] == '/' || rest[p] == '\\') { p += 1; }
    let aend = n_authority_end(rest, p, true);
    let tail = rest[aend..];
    var ui: u8[>..] = [];
    var hostout: u8[>..] = [];
    let port, ok = n_auth(rest[p..aend], true, ui, hostout);
    if !ok { return false; }
    res.append("//");
    if ui.len > 0 {
        res.append(ui[..]);
        res.push('@');
    }
    res.append(hostout[..]);
    if port >= 0 && port != default_port(scheme) {
        res.push(':');
        format(res, port);
    }
    let pend = n_path_end(tail);
    var pathbuf: u8[>..] = [];
    n_path(pathbuf, tail[..pend], 0);
    n_encode(res, pathbuf[..], 0);
    n_query_fragment(res, tail[pend..], 1);
    out.append(res[..]);
    return true;
}
