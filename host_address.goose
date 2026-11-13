// Host addresses of the url package: IPv4 numbers, domains and IPv6 text.
//
namespace url;

import std;

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
    // Text with a byte of 128 and up, or a label that reads as Punycode,
    // goes through IDNA. Plain ASCII keeps the short path.
    var low: u8[>..] = [];
    var idna = false;
    for c in dec { if c >= 0x80 { idna = true; } }
    push_lower(low, dec[..]);
    for part in n_dots(low[..]) {
        if part.len >= 4 && same_lower(part[..4], "xn--") { idna = true; }
    }
    if idna {
        var a: u8[>..] = [];
        if !idna_to_ascii(a, dec[..]) { return false; }
        low = copy(a);
    }
    for c in low { if n_forbidden_domain(c) { return false; } }
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
