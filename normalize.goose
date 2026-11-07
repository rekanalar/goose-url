// WHATWG normalization for the url package.
//
// normalize writes the canonical text of one absolute URL of a special
// scheme into out and gives true. The rules follow Node new URL(text).href.
// A failure gives false and leaves out unchanged.
//
// Stated limits: file: and non-special schemes are refused. A host with a
// byte of 128 and up is refused. There is no IDNA and no punycode.
namespace url;

import std;

const NLOW = "0123456789abcdef";

// The encode sets of WHATWG, as Node 22 applies them. kind 0 is the path,
// 1 the query, 2 the fragment, 3 the username and 4 the password. Tab, LF
// and CR never reach this table, because normalize strips them first.
fn n_enc(kind: i64, c: u8) -> bool {
    if c < 0x20 || c >= 0x7f { return true; }
    if kind == 0 {
        return c == 0x20 || c == 0x22 || c == 0x3c || c == 0x3e || c == 0x5e
            || c == 0x60 || c == 0x7b || c == 0x7d;
    }
    if kind == 1 {
        return c == 0x20 || c == 0x22 || c == 0x27 || c == 0x3c || c == 0x3e;
    }
    if kind == 2 {
        return c == 0x20 || c == 0x22 || c == 0x3c || c == 0x3e || c == 0x60;
    }
    if kind == 4 && c == 0x3a { return true; }
    return c == 0x20 || c == 0x22 || c == 0x3b || c == 0x3c || c == 0x3d || c == 0x3e
        || c == 0x40 || c == 0x5b || c == 0x5d || c == 0x5e || c == 0x60
        || c == 0x7b || c == 0x7c || c == 0x7d;
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

// n_path resolves the dot segments of one path text and writes the result
// with a leading slash. A backslash is a slash, as a special scheme reads
// it. A ".." segment drops the last segment. The output holds at least
// one segment, so an empty path becomes "/".
fn n_path(out: u8[>..]&, s: const u8[:]) {
    var segs: const u8[:][>..] = [];
    var pos: i64 = 0;
    if s.len > 0 { pos = 1; }
    while pos <= s.len {
        var end = pos;
        while end < s.len && s[end] != '/' && s[end] != '\\' { end += 1; }
        let seg = s[pos..end];
        let more = end < s.len;
        if n_double_dot(seg) {
            if segs.len > 0 { segs.resize(segs.len - 1); }
            if !more { segs.push(""); }
        } else if n_single_dot(seg) {
            if !more { segs.push(""); }
        } else {
            segs.push(seg);
        }
        pos = end + 1;
    }
    if segs.len == 0 { segs.push(""); }
    out.push('/');
    var k = 0;
    while k < segs.len {
        if k > 0 { out.push('/'); }
        out.append(segs[k]);
        k += 1;
    }
}

// n_ipv4_num parses one IPv4 number of s from index i. The radix is 16
// after 0x, 8 after a single 0, and 10 otherwise. An empty prefix after
// the radix mark is 0. It gives the value, the index after the number and
// the flag. A value above 2^53 minus 1 fails.
fn n_ipv4_num(s: const u8[:], i: i64) -> i64, i64, bool {
    let n = s.len;
    if n == 0 { return 0, i, false; }
    var r: i64 = 10;
    var j = i;
    if j + 1 < n && s[j] == '0' && (s[j + 1] == 'x' || s[j + 1] == 'X') {
        r = 16;
        j += 2;
    } else if j < n && s[j] == '0' {
        r = 8;
        j += 1;
    }
    if j >= n { return 0, j, true; }
    var v: i64 = 0;
    while j < n && s[j] != '.' {
        var d: i64 = -1;
        if s[j] >= '0' && s[j] <= '9' { d = s[j] - '0'; }
        else if r == 16 && s[j] >= 'a' && s[j] <= 'f' { d = (s[j] - 'a') + 10; }
        else if r == 16 && s[j] >= 'A' && s[j] <= 'F' { d = (s[j] - 'A') + 10; }
        if d < 0 || d >= r { return 0, j, false; }
        v = v * r + d;
        if v > 0x1fffffffffffff { return 0, j, false; }
        j += 1;
    }
    return v, j, true;
}

// n_dots splits s on dots and keeps the empty parts.
fn n_dots(s: const u8[:]) -> const u8[:][>..] {
    var parts: const u8[:][>..] = [];
    var pos: i64 = 0;
    while pos <= s.len {
        var end = pos;
        while end < s.len && s[end] != '.' { end += 1; }
        parts.push(s[pos..end]);
        pos = end + 1;
    }
    return parts;
}

// n_ends_in_number says whether the last label of s is a number, after
// one trailing empty label is set aside. Node reads 0x10 and 0777 as
// numbers, so the check uses the radix parse too.
fn n_ends_in_number(s: const u8[:]) -> bool {
    var parts: const u8[:][>..] = n_dots(s);
    var last = parts[parts.len - 1];
    if last.len == 0 {
        if parts.len < 2 { return false; }
        last = parts[parts.len - 2];
        if last.len == 0 { return false; }
    }
    var all = true;
    for c in last {
        if !is_digit(c) { all = false; }
    }
    if all { return true; }
    let v, end, ok = n_ipv4_num(last, 0);
    return ok && end == last.len;
}

// n_ipv4_text writes the dotted decimal form of s. The first labels are
// bytes. The last label fills the bytes that are left, so 127.1 becomes
// 127.0.0.1 and 999 becomes 0.0.3.231.
fn n_ipv4_text(out: u8[>..]&, s: const u8[:]) -> bool {
    var parts: const u8[:][>..] = n_dots(s);
    if parts.len > 1 && parts[parts.len - 1].len == 0 { parts.resize(parts.len - 1); }
    if parts.len > 4 { return false; }
    var nums: i64[>..] = [];
    var i = 0;
    while i < parts.len {
        let v, end, ok = n_ipv4_num(parts[i], 0);
        if !ok || end != parts[i].len { return false; }
        if i < parts.len - 1 {
            if v > 255 { return false; }
        } else {
            var limit: i64 = 1;
            var k = 0;
            while k < 5 - parts.len { limit *= 256; k += 1; }
            if v >= limit { return false; }
        }
        nums.push(v);
        i += 1;
    }
    var bytes: i64[>..] = [];
    i = 0;
    while i < parts.len - 1 { bytes.push(nums[i]); i += 1; }
    let last = nums[nums.len - 1];
    var k = 5 - parts.len;
    while k > 0 {
        k -= 1;
        bytes.push((last >> (8 * k)) & 255);
    }
    for b, idx in bytes {
        if idx > 0 { out.push('.'); }
        format(out, b);
    }
    return true;
}

// n_forbidden_domain says whether the decoded host byte is a forbidden
// domain code point, as Node refuses it. Tab, LF and CR never reach here
// outside a %XX escape, and a decoded one fails too.
fn n_forbidden_domain(c: u8) -> bool {
    if c < 0x20 { return true; }
    return c == 0x20 || c == 0x23 || c == 0x25 || c == 0x2f || c == 0x3a
        || c == 0x3c || c == 0x3e || c == 0x3f || c == 0x40 || c == 0x5b
        || c == 0x5c || c == 0x5d || c == 0x5e || c == 0x7c || c == 0x7f;
}

// n_domain normalizes one plain host: percent-decode, refuse the
// forbidden code points, lower the ASCII case, and turn a host that ends
// in a number into its dotted decimal form.
fn n_domain(out: u8[>..]&, s: const u8[:]) -> bool {
    var dec: u8[>..] = [];
    var i = 0;
    while i < s.len {
        let c = s[i];
        if c == '%' && i + 2 < s.len {
            let hi, ok1 = hex_value(s[i + 1]);
            let lo, ok2 = hex_value(s[i + 2]);
            if ok1 && ok2 {
                dec.push((hi * 16 + lo) as u8);
                i += 3;
                continue;
            }
        }
        dec.push(c);
        i += 1;
    }
    for c in dec {
        if c >= 0x80 || n_forbidden_domain(c) { return false; }
    }
    var low: u8[>..] = [];
    push_lower(low, dec[..]);
    // A label that reads as punycode needs IDNA, which stays out. Refuse it.
    for part in n_dots(low[..]) {
        if part.len >= 4 && same_lower(part[..4], "xn--") { return false; }
    }
    if n_ends_in_number(low[..]) {
        return n_ipv4_text(out, low[..]);
    }
    out.append(low[..]);
    return true;
}

// n_v4_tail reads the strict dotted decimal form at the end of an IPv6
// text: no radix marks, no leading zeros, every number at most 255. It
// gives the two high and low pieces, and the index after.
fn n_v4_tail(s: const u8[:], i: i64) -> i64, i64, i64, bool {
    var nums: i64[>..] = [];
    var j = i;
    var k = 0;
    while k < 4 {
        let start = j;
        var v: i64 = 0;
        while j < s.len && is_digit(s[j]) {
            v = v * 10 + (s[j] - '0');
            j += 1;
        }
        if j == start { return 0, 0, j, false; }
        if j - start > 1 && s[start] == '0' { return 0, 0, j, false; }
        if v > 255 { return 0, 0, j, false; }
        nums.push(v);
        if k < 3 {
            if j >= s.len || s[j] != '.' { return 0, 0, j, false; }
            j += 1;
        }
        k += 1;
    }
    return nums[0] * 256 + nums[1], nums[2] * 256 + nums[3], j, true;
}

// n_ipv6_parse reads the text between the brackets into eight pieces. One
// :: may fill the missing pieces, and a strict IPv4 tail counts as two
// pieces. The parse fails on a second ::, on a group above four hex
// digits and on a piece count above eight.
fn n_ipv6_parse(s: const u8[:], pieces: i64[>..]&) -> bool {
    pieces.clear();
    let n = s.len;
    var i: i64 = 0;
    var compressed = false;
    var cpos: i64 = 0;
    if n >= 2 && s[0] == ':' && s[1] == ':' {
        compressed = true;
        i = 2;
    } else if n > 0 && s[0] == ':' {
        return false;
    }
    while i < n {
        let gstart = i;
        var count = 0;
        var val: i64 = 0;
        while i < n && count < 4 {
            let hv, ok = hex_value(s[i]);
            if !ok { break; }
            val = val * 16 + hv;
            count += 1;
            i += 1;
        }
        if count == 0 { return false; }
        if i < n && s[i] == '.' {
            let p1, p2, end, ok = n_v4_tail(s, gstart);
            if !ok || end != n { return false; }
            pieces.push(p1);
            pieces.push(p2);
            break;
        }
        if i < n && count == 4 {
            let hv, ok = hex_value(s[i]);
            if ok { return false; }
        }
        pieces.push(val);
        if i >= n { break; }
        if s[i] != ':' { return false; }
        if i + 1 < n && s[i + 1] == ':' {
            if compressed { return false; }
            compressed = true;
            cpos = pieces.len;
            i += 2;
        } else {
            i += 1;
            if i >= n { return false; }
        }
    }
    if pieces.len > 8 { return false; }
    if compressed {
        if pieces.len >= 8 { return false; }
        let fill = 8 - pieces.len;
        var full: i64[>..] = [];
        var k = 0;
        while k < pieces.len {
            if k == cpos {
                var z = 0;
                while z < fill { full.push(0); z += 1; }
            }
            full.push(pieces[k]);
            k += 1;
        }
        if full.len == cpos {
            var z = 0;
            while z < fill { full.push(0); z += 1; }
        }
        pieces.clear();
        for f in full { pieces.push(f); }
        return true;
    }
    return pieces.len == 8;
}

fn n_hex_piece(out: u8[>..]&, v: i64) {
    var buf: u8[4];
    var k = 0;
    var x = v;
    if x == 0 {
        out.push('0');
        return;
    }
    while x > 0 {
        let d = (x % 16) as i32;
        buf[k] = NLOW[d];
        k += 1;
        x /= 16;
    }
    while k > 0 {
        k -= 1;
        out.push(buf[k]);
    }
}

// n_ipv6_write writes the eight pieces in the canonical form: lower-case
// hex, and the longest run of two zeros or more becomes ::. A tie takes
// the left run.
fn n_ipv6_write(out: u8[>..]&, pieces: i64[>..]) {
    var best: i64 = -1;
    var bestlen: i64 = 0;
    var i: i64 = 0;
    while i < 8 {
        if pieces[i] == 0 {
            var j = i;
            while j < 8 && pieces[j] == 0 { j += 1; }
            if j - i > bestlen { bestlen = j - i; best = i; }
            i = j;
        } else {
            i += 1;
        }
    }
    if bestlen < 2 { best = -1; }
    if best == 0 && bestlen == 8 {
        out.append("::");
        return;
    }
    var k: i64 = 0;
    while k < 8 {
        if best >= 0 && k >= best && k < best + bestlen {
            if k == best {
                if best > 0 { out.push(':'); }
                out.push(':');
            }
            k += 1;
            continue;
        }
        var skip = false;
        if best >= 0 && k == best + bestlen && best > 0 { skip = true; }
        if k > 0 && !skip { out.push(':'); }
        n_hex_piece(out, pieces[k]);
        k += 1;
    }
}

// normalize writes the canonical text of s into out and gives true. The
// rules follow Node new URL(text).href for http, https, ws, wss and ftp.
// It gives false, and leaves out unchanged, when s is not a valid URL of
// one of these schemes, or when the host holds a byte of 128 and up.
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
    if !special { return false; }

    // Skip the slashes, then read the authority.
    let rest = inp[si + 1..];
    var p: i64 = 0;
    while p < rest.len && (rest[p] == '/' || rest[p] == '\\') { p += 1; }
    var aend = p;
    while aend < rest.len && rest[aend] != '/' && rest[aend] != '\\'
        && rest[aend] != '?' && rest[aend] != '#' {
        aend += 1;
    }
    let auth = rest[p..aend];
    let tail = rest[aend..];
    if auth.len == 0 { return false; }

    // Split the userinfo at the last @.
    var at: i64 = -1;
    for c, i in auth {
        if c == '@' { at = i; }
    }

    // The host and the port.
    var hostport: const u8[:] = auth;
    if at >= 0 { hostport = auth[at + 1..]; }
    var hostout: u8[>..] = [];
    var port: i64 = -1;
    if hostport.len > 0 && hostport[0] == '[' {
        var j: i64 = 1;
        while j < hostport.len && hostport[j] != ']' { j += 1; }
        if j >= hostport.len { return false; }
        let after = hostport[j + 1..];
        if after.len > 0 {
            if after[0] != ':' { return false; }
            let pv, ok = n_port(after[1..]);
            if !ok { return false; }
            port = pv;
        }
        var pieces: i64[>..] = [];
        if !n_ipv6_parse(hostport[1..j], pieces) { return false; }
        if pieces.len != 8 { return false; }
        hostout.push('[');
        n_ipv6_write(hostout, pieces[..]);
        hostout.push(']');
    } else {
        var ci: i64 = -1;
        for c, i in hostport {
            if c == ':' { ci = i; break; }
        }
        var hosttext: const u8[:] = hostport;
        if ci >= 0 {
            hosttext = hostport[..ci];
            let pv, ok = n_port(hostport[ci + 1..]);
            if !ok { return false; }
            port = pv;
        }
        if !n_domain(hostout, hosttext) { return false; }
    }
    if hostout.len == 0 { return false; }

    // The userinfo, encoded with its own sets.
    var ui: u8[>..] = [];
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

    // Split the tail into the path, the query and the fragment.
    var qpos: i64 = -1;
    var fpos: i64 = -1;
    for c, i in tail {
        if c == '?' && qpos < 0 { qpos = i; }
        if c == '#' && fpos < 0 { fpos = i; }
    }
    // A ? after the # belongs to the fragment.
    if fpos >= 0 && qpos > fpos { qpos = -1; }
    var pend: i64 = tail.len;
    if qpos >= 0 && qpos < pend { pend = qpos; }
    if fpos >= 0 && fpos < pend { pend = fpos; }
    let ptext = tail[..pend];
    var qtext: const u8[:] = tail[..tail.len];
    var ftext: const u8[:] = tail[..tail.len];
    if qpos >= 0 && (fpos < 0 || qpos < fpos) {
        var qend: i64 = tail.len;
        if fpos >= 0 { qend = fpos; }
        qtext = tail[qpos + 1..qend];
        if fpos >= 0 { ftext = tail[fpos + 1..]; }
    } else if fpos >= 0 {
        ftext = tail[fpos + 1..];
    }

    // Everything parsed. Build the result, then append it to out.
    var res: u8[>..] = [];
    res.append(scheme);
    res.append("://");
    if ui.len > 0 {
        res.append(ui[..]);
        res.push('@');
    }
    res.append(hostout[..]);
    if port >= 0 && port != default_port(scheme) {
        res.push(':');
        format(res, port);
    }
    var pathbuf: u8[>..] = [];
    n_path(pathbuf, ptext);
    n_encode(res, pathbuf[..], 0);
    if qpos >= 0 {
        res.push('?');
        n_encode(res, qtext, 1);
    }
    if fpos >= 0 {
        res.push('#');
        n_encode(res, ftext, 2);
    }
    out.append(res[..]);
    return true;
}
