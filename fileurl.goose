// File URL and path conversion for the url package.
//
// file_url_to_path is Node fileURLToPath, and path_to_file_url is Node
// pathToFileURL, each with the windows option of Node as a flag. The path
// must be absolute: a drive path or a UNC path for Windows, a path with a
// leading slash otherwise. A UNC path starts with two backslashes or with
// two forward slashes. Node resolves a relative path against the working
// directory. The Rust Url::from_file_path refuses it. This package
// refuses it too.
namespace url;

import std;

// path_decode writes s with its escapes reversed. A broken escape, or a
// result that is no UTF-8, is a fault, as decodeURIComponent of Node.
fn path_decode(out: u8[>..]&, s: const u8[:]) -> bool {
    var tmp: u8[>..] = [];
    if !decode(tmp, s, false) { return false; }
    var cps: i64[>..] = [];
    if !utf8_cps(cps, tmp[..]) { return false; }
    out.append(tmp[..]);
    return true;
}

// has_separator_escape says whether the text holds %2F, or %5C when
// backslash is true, in any case of the hex digits.
fn has_separator_escape(s: const u8[:], backslash: bool) -> bool {
    var i: i64 = 0;
    while i + 2 < s.len {
        if s[i] == '%' {
            let a = s[i + 1];
            let b = s[i + 2] | 0x20;
            if a == '2' && b == 'f' { return true; }
            if backslash && a == '5' && b == 'c' { return true; }
        }
        i += 1;
    }
    return false;
}

// file_url_to_path writes the path of a file URL into out. It gives false
// where Node throws: a scheme other than file, a host on POSIX, an
// encoded separator, a broken escape, or a Windows path with no drive.
fn file_url_to_path(out: u8[>..]&, href: const u8[:], windows: bool) -> bool {
    var n: u8[>..] = [];
    if !normalize(n, href) { return false; }
    if n.len < 7 || n[..7] != "file://" { return false; }
    let rest = n[7..];
    var he: i64 = 0;
    while he < rest.len && rest[he] != '/' { he += 1; }
    let host = rest[..he];
    var pe: i64 = he;
    while pe < rest.len && rest[pe] != '?' && rest[pe] != '#' { pe += 1; }
    let pathname = rest[he..pe];
    if !windows {
        if host.len > 0 { return false; }
        if has_separator_escape(pathname, false) { return false; }
        var dec: u8[>..] = [];
        if !path_decode(dec, pathname) { return false; }
        out.append(dec[..]);
        return true;
    }
    if has_separator_escape(pathname, true) { return false; }
    var back: u8[>..] = [];
    for c in pathname { back.push(if c == '/' { '\\' } else { c }); }
    var dec: u8[>..] = [];
    if !path_decode(dec, back[..]) { return false; }
    if host.len > 0 {
        var uni: u8[>..] = [];
        if !domain_to_unicode(uni, host) { return false; }
        out.append("\\\\");
        out.append(uni[..]);
        out.append(dec[..]);
        return true;
    }
    // A drive path: a letter, a colon, the rest.
    if dec.len < 3 || !is_letter(dec[1]) || dec[2] != ':' { return false; }
    out.append(dec[1..]);
    return true;
}

// file_url_byte appends one byte of a path to the URL text, escaped as
// pathToFileURL escapes it: the percent sign, the controls, the space,
// ? and #, and the backslash for POSIX.
fn file_url_byte(out: u8[>..]&, c: u8, windows: bool) {
    // Node escapes these bytes in a file URL path, as node_url.cc does.
    if c <= 0x20 || c == 0x22 || c == 0x23 || c == 0x25 || c == 0x3c || c == 0x3e
        || c == 0x3f || c == 0x5b || c == 0x5d || c == 0x5e || c == 0x7c || c == 0x7e
        || c == 0x7f || (!windows && c == '\\') {
        out.push('%');
        out.push(HEX[(c as i32) >> 4]);
        out.push(HEX[(c as i32) & 15]);
    } else {
        out.push(c);
    }
}

// resolve_segments writes the escaped, resolved segments of a path text,
// each with its slash in front. A "." goes, a ".." drops a segment but never
// the root, and an empty segment goes. This is the rule of path.resolve of
// Node.
fn resolve_segments(res: u8[>..]&, rest: const u8[:], windows: bool) {
    // starts holds the length of res before each segment.
    var starts: i64[>..] = [];
    var i: i64 = 0;
    while i < rest.len {
        var e = i;
        while e < rest.len && rest[e] != '/' { e += 1; }
        let seg = rest[i..e];
        if seg.len == 0 || seg == "." {
        } else if seg == ".." {
            if starts.len > 0 {
                res.resize(starts[starts.len - 1]);
                starts.resize(starts.len - 1);
            }
        } else {
            starts.push(res.len);
            res.push('/');
            for c in seg { file_url_byte(res, c, windows); }
        }
        i = e + 1;
    }
}

// host_text_ok says whether a host text can be written as the host of a
// URL. Node sets the host of a UNC path with set_hostname, which refuses a
// host with a slash, a colon or an at sign.
fn host_text_ok(h: const u8[:]) -> bool {
    for c in h {
        if c == '/' || c == ':' || c == '@' || c == '?' || c == '#' || c == ' ' {
            return false;
        }
    }
    return true;
}

// unc_file_url writes the file URL of a UNC path that starts with two
// backslashes. Node uses the path as it is: the server name is the text up
// to the next backslash, and the URL parser removes the dot segments.
fn unc_file_url(out: u8[>..]&, path: const u8[:]) -> bool {
    // The prefix of an extended UNC path is not part of the server name.
    var prefix: i64 = 2;
    if path.len >= 8 && path[0] == '\\' && path[1] == '\\' && path[2] == '?' && path[3] == '\\'
        && path[4] == 'U' && path[5] == 'N' && path[6] == 'C' && path[7] == '\\' {
        prefix = 8;
    }
    var he = prefix;
    while he < path.len && path[he] != '\\' { he += 1; }
    // Node throws for a path with no resource path and for an empty server.
    if he >= path.len || he == prefix { return false; }
    let host = path[prefix..he];
    if !host_text_ok(host) { return false; }
    var text: u8[>..] = [];
    text.append("file://");
    text.append(host);
    // The path starts at the backslash that ends the server name.
    for c in path[he..] {
        file_url_byte(text, if c == '\\' { '/' } else { c }, true);
    }
    return normalize(out, text[..]);
}

// slash_unc_file_url writes the file URL of a UNC path that starts with two
// forward slashes. Node resolves the path first, so the dot segments go and
// the empty segments go too.
fn slash_unc_file_url(out: u8[>..]&, path: const u8[:]) -> bool {
    var norm: u8[>..] = [];
    for c in path {
        if c == '\\' { norm.push('/'); } else { norm.push(c); }
    }
    // The server name and the share are the first two segments.
    var host: u8[>..] = [];
    var share: u8[>..] = [];
    var rest_start: i64 = 0;
    var found: i64 = 0;
    var i: i64 = 0;
    while i < norm.len && found < 2 {
        var e = i;
        while e < norm.len && norm[e] != '/' { e += 1; }
        if e > i {
            if found == 0 { host.append(norm[i..e]); } else { share.append(norm[i..e]); }
            found += 1;
            rest_start = e;
        }
        i = e + 1;
    }
    // A path with no share is not a UNC path. Node resolves it against the
    // working directory.
    if found < 2 { return false; }
    if !host_text_ok(host[..]) { return false; }
    // The share is the root of the path. A ".." never goes above it.
    var res: u8[>..] = [];
    resolve_segments(res, norm[rest_start..], true);
    var text: u8[>..] = [];
    text.append("file://");
    text.append(host[..]);
    text.push('/');
    text.append(share[..]);
    text.append(res[..]);
    if res.len == 0 { text.push('/'); }
    return normalize(out, text[..]);
}

// drive_file_url writes the file URL of a Windows path that starts with a
// drive letter.
fn drive_file_url(out: u8[>..]&, path: const u8[:]) -> bool {
    var norm: u8[>..] = [];
    for c in path {
        if c == '\\' { norm.push('/'); } else { norm.push(c); }
    }
    var res: u8[>..] = [];
    resolve_segments(res, norm[2..], true);
    var text: u8[>..] = [];
    text.append("file:///");
    text.append(norm[..2]);
    text.append(res[..]);
    // The root alone, or a path that ended with a separator, ends with one.
    if res.len == 0 || norm[norm.len - 1] == '/' { text.push('/'); }
    return normalize(out, text[..]);
}

// path_to_file_url writes the file URL of an absolute path into out. It
// gives false for a relative path. Node resolves such a path against the
// working directory. The Rust Url::from_file_path refuses it. This package
// refuses it too.
fn path_to_file_url(out: u8[>..]&, path: const u8[:], windows: bool) -> bool {
    if windows {
        // A UNC path starts with two backslashes.
        if path.len >= 2 && path[0] == '\\' && path[1] == '\\' {
            return unc_file_url(out, path);
        }
        // A drive path starts with a letter, a colon and a separator.
        if path.len >= 3 && is_letter(path[0]) && path[1] == ':'
            && (path[2] == '\\' || path[2] == '/') {
            return drive_file_url(out, path);
        }
        // A UNC path may also start with two forward slashes.
        if path.len >= 3 && path[0] == '/' && path[1] == '/' {
            return slash_unc_file_url(out, path);
        }
        // Every other path is relative or has no drive. Node resolves it
        // against the working directory.
        return false;
    }
    if path.len == 0 || path[0] != '/' { return false; }
    var res: u8[>..] = [];
    resolve_segments(res, path, false);
    var text: u8[>..] = [];
    text.append("file://");
    text.append(res[..]);
    // The root alone, or a path that ended with a slash, ends with one.
    if res.len == 0 || path[path.len - 1] == '/' { text.push('/'); }
    return normalize(out, text[..]);
}
