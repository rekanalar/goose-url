// Percent encoding for the url package. RFC 3986 section 2.1.
//
// encode writes one string with every byte that a URL may not hold as
// %XX. decode reverses the escapes. The caller owns the output buffer.
namespace url;

import std;

const UNRESERVED = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
const HEX = "0123456789ABCDEF";

fn in_set(c: u8, set: const u8[:]) -> bool {
    for s in set {
        if s == c { return true; }
    }
    return false;
}

fn hex_value(c: u8) -> i32, bool {
    if c >= '0' && c <= '9' { return c - '0' as i32, true; }
    if c >= 'a' && c <= 'f' { return c - 'a' as i32 + 10, true; }
    if c >= 'A' && c <= 'F' { return c - 'A' as i32 + 10, true; }
    return -1, false;
}

// encode writes s into out with percent escapes. The bytes in the
// unreserved set pass through. The extra bytes in safe pass through too;
// callers use safe for bytes their part allows, such as "/" in a path.
// Every other byte becomes %XX with upper-case hex digits.
fn encode(out: u8[>..]&, s: const u8[:], safe: const u8[:]) {
    for c in s {
        if in_set(c, UNRESERVED) || in_set(c, safe) {
            out.push(c);
        } else {
            var buf: u8[3];
            buf[0] = '%';
            buf[1] = HEX[(c as i32) >> 4];
            buf[2] = HEX[(c as i32) & 15];
            out.append(buf[..]);
        }
    }
}

// decode writes s into out with the percent escapes reversed. In form
// mode a + becomes a space, as HTML forms send it. decode returns false
// when an escape is broken: a trailing % or a hex digit that is not
// valid. Every other byte passes through.
fn decode(out: u8[>..]&, s: const u8[:], form: bool) -> bool {
    var i = 0;
    while i < s.len {
        let c = s[i];
        if form && c == '+' {
            out.push(' ');
            i += 1;
        } else if c == '%' {
            if i + 2 >= s.len { return false; }
            let hi, ok1 = hex_value(s[i + 1]);
            let lo, ok2 = hex_value(s[i + 2]);
            if !ok1 || !ok2 { return false; }
            out.push((hi * 16 + lo) as u8);
            i += 3;
        } else {
            out.push(c);
            i += 1;
        }
    }
    return true;
}
