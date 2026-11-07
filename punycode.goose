// Punycode (RFC 3492) for the url package.
//
// punycode_encode writes the ASCII form of a UTF-8 text. punycode_decode
// reads the ASCII form and writes UTF-8. Both give false on a fault: a bad
// UTF-8 byte, a bad digit, or a number above 4294967295.
//
// The encoder counts the smaller code points with a Fenwick tree, and the
// decoder places the inserts from the last to the first with the same tree.
// Both take n log n time, so a long label stays fast.
namespace url;

import std;

const PC_BASE: i64 = 36;
const PC_TMIN: i64 = 1;
const PC_TMAX: i64 = 26;
const PC_SKEW: i64 = 38;
const PC_DAMP: i64 = 700;
const PC_BIAS: i64 = 72;
const PC_N: i64 = 128;
const PC_MAX: i64 = 0xFFFFFFFF;

// utf8_cps reads the code points of a UTF-8 text into out. It refuses an
// overlong form, a surrogate and a value above U+10FFFF.
fn utf8_cps(out: i64[>..]&, s: const u8[:]) -> bool {
    var i: i64 = 0;
    while i < s.len {
        let b = s[i] as i64;
        var need: i64 = 0;
        var cp: i64 = 0;
        var min: i64 = 0;
        if b < 0x80 { out.push(b); i += 1; continue; }
        else if b >= 0xC2 && b <= 0xDF { need = 1; cp = b & 0x1F; min = 0x80; }
        else if b >= 0xE0 && b <= 0xEF { need = 2; cp = b & 0x0F; min = 0x800; }
        else if b >= 0xF0 && b <= 0xF4 { need = 3; cp = b & 0x07; min = 0x10000; }
        else { return false; }
        if i + need >= s.len { return false; }
        var k: i64 = 1;
        while k <= need {
            let c = s[i + k] as i64;
            if (c & 0xC0) != 0x80 { return false; }
            cp = (cp << 6) | (c & 0x3F);
            k += 1;
        }
        if cp < min || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) { return false; }
        out.push(cp);
        i += need + 1;
    }
    return true;
}

// cps_utf8 writes the UTF-8 form of the code points into out.
fn cps_utf8(out: u8[>..]&, cps: const i64[:]) {
    for cp in cps {
        if cp < 0x80 {
            out.push(cp as u8);
        } else if cp < 0x800 {
            out.push((0xC0 | (cp >> 6)) as u8);
            out.push((0x80 | (cp & 0x3F)) as u8);
        } else if cp < 0x10000 {
            out.push((0xE0 | (cp >> 12)) as u8);
            out.push((0x80 | ((cp >> 6) & 0x3F)) as u8);
            out.push((0x80 | (cp & 0x3F)) as u8);
        } else {
            out.push((0xF0 | (cp >> 18)) as u8);
            out.push((0x80 | ((cp >> 12) & 0x3F)) as u8);
            out.push((0x80 | ((cp >> 6) & 0x3F)) as u8);
            out.push((0x80 | (cp & 0x3F)) as u8);
        }
    }
}

// pc_adapt is the bias adaptation of RFC 3492 section 6.1.
fn pc_adapt(delta: i64, points: i64, first: bool) -> i64 {
    var d = delta;
    if first { d = d / PC_DAMP; } else { d = d / 2; }
    d += d / points;
    var k: i64 = 0;
    while d > ((PC_BASE - PC_TMIN) * PC_TMAX) / 2 {
        d = d / (PC_BASE - PC_TMIN);
        k += PC_BASE;
    }
    return k + ((PC_BASE - PC_TMIN + 1) * d) / (d + PC_SKEW);
}

fn pc_digit(d: i64) -> u8 {
    if d < 26 { return (97 + d) as u8; }
    return (22 + d) as u8;
}

// pc_threshold gives the digit threshold t for the position k and the bias.
fn pc_threshold(k: i64, bias: i64) -> i64 {
    if k <= bias { return PC_TMIN; }
    if k >= bias + PC_TMAX { return PC_TMAX; }
    return k - bias;
}

// fen_add adds v at position i of a Fenwick tree.
fn fen_add(tree: i64[>..]&, i: i64, v: i64) {
    var p = i + 1;
    while p < tree.len {
        tree[p] += v;
        p += p & (0 - p);
    }
}

// fen_sum gives the sum of the positions below i.
fn fen_sum(tree: i64[>..]&, i: i64) -> i64 {
    var p = i;
    var t: i64 = 0;
    while p > 0 {
        t += tree[p];
        p -= p & (0 - p);
    }
    return t;
}

// fen_new gives a tree of n positions that all hold v, built in linear
// time.
fn fen_new(tree: i64[>..]&, n: i64, v: i64) {
    tree.clear();
    var i: i64 = 0;
    while i <= n { tree.push(if i == 0 { 0 } else { v }); i += 1; }
    i = 1;
    while i <= n {
        let j = i + (i & (0 - i));
        if j <= n { tree[j] += tree[i]; }
        i += 1;
    }
}

// fen_kth gives the position of the k-th (from 0) one in a tree of ones and
// zeros. The tree has n positions.
fn fen_kth(tree: i64[>..]&, n: i64, k: i64) -> i64 {
    var pos: i64 = 0;
    var rem = k + 1;
    var step: i64 = 1;
    while step * 2 <= n { step *= 2; }
    while step > 0 {
        if pos + step <= n && tree[pos + step] < rem {
            pos += step;
            rem -= tree[pos];
        }
        step = step / 2;
    }
    return pos;
}

// pc_encode writes the Punycode of the code points into out. It gives
// false on an overflow.
fn pc_encode(out: u8[>..]&, cps: const i64[:]) -> bool {
    var basic: i64 = 0;
    for c in cps {
        if c < 0x80 { out.push(c as u8); basic += 1; }
    }
    if basic > 0 && basic < cps.len { out.push('-'); }
    if basic == cps.len { return true; }
    // The keys sort by value, then by place.
    var keys: i64[>..] = [];
    var i: i64 = 0;
    while i < cps.len {
        if cps[i] >= 0x80 { keys.push(cps[i] * 0x100000000 + i); }
        i += 1;
    }
    sort(keys[..]);
    // The tree marks the places of the code points that are smaller than n.
    var tree: i64[>..] = [];
    fen_new(tree, cps.len, 0);
    i = 0;
    while i < cps.len {
        if cps[i] < 0x80 { fen_add(tree, i, 1); }
        i += 1;
    }
    var n = PC_N;
    var delta: i64 = 0;
    var bias = PC_BIAS;
    var h = basic;
    var next: i64 = 0;
    while next < keys.len {
        let m = keys[next] >> 32;
        delta += (m - n) * (h + 1);
        if delta > PC_MAX { return false; }
        n = m;
        // Pass over the code points of value n, in order.
        var prev: i64 = -1;
        while next < keys.len && (keys[next] >> 32) == n {
            let place = keys[next] & 0xFFFFFFFF;
            // The smaller code points between the last place and this one.
            delta += fen_sum(tree, place) - fen_sum(tree, prev + 1);
            if delta > PC_MAX { return false; }
            // Write delta as a variable-length number.
            var q = delta;
            var k = PC_BASE;
            while true {
                let t = pc_threshold(k, bias);
                if q < t { break; }
                out.push(pc_digit(t + (q - t) % (PC_BASE - t)));
                q = (q - t) / (PC_BASE - t);
                k += PC_BASE;
            }
            out.push(pc_digit(q));
            bias = pc_adapt(delta, h + 1, h == basic);
            delta = 0;
            h += 1;
            prev = place;
            next += 1;
        }
        // The rest of the smaller code points carry into the next pass.
        delta += fen_sum(tree, cps.len) - fen_sum(tree, prev + 1);
        // Code points of value n now count as smaller.
        var j = next - 1;
        while j >= 0 && (keys[j] >> 32) == n {
            fen_add(tree, keys[j] & 0xFFFFFFFF, 1);
            j -= 1;
        }
        delta += 1;
        n += 1;
    }
    return true;
}

// pc_decode reads the Punycode text s and writes its code points into out.
// It gives false on a bad digit, an overflow or a code point out of range.
fn pc_decode(out: i64[>..]&, s: const u8[:]) -> bool {
    // The last "-" ends the basic part. It is consumed with the part.
    var b: i64 = -1;
    var j: i64 = 0;
    while j < s.len {
        if s[j] == '-' { b = j; }
        j += 1;
    }
    var basics: i64[>..] = [];
    j = 0;
    while j < b {
        if s[j] >= 0x80 { return false; }
        basics.push(s[j]);
        j += 1;
    }
    var at: i64 = b + 1;
    // The inserts: the place in the list at that time, and the code point.
    var ins_at: i64[>..] = [];
    var ins_cp: i64[>..] = [];
    var n = PC_N;
    var i: i64 = 0;
    var bias = PC_BIAS;
    while at < s.len {
        let old = i;
        var w: i64 = 1;
        var k = PC_BASE;
        while true {
            if at >= s.len { return false; }
            let c: i64 = s[at];
            at += 1;
            var digit: i64 = 0;
            if c >= 48 && c <= 57 { digit = c - 22; }
            else if c >= 65 && c <= 90 { digit = c - 65; }
            else if c >= 97 && c <= 122 { digit = c - 97; }
            else { return false; }
            if digit > (PC_MAX - i) / w { return false; }
            i += digit * w;
            let t = pc_threshold(k, bias);
            if digit < t { break; }
            if w > PC_MAX / (PC_BASE - t) { return false; }
            w *= PC_BASE - t;
            k += PC_BASE;
        }
        let total = basics.len + ins_at.len + 1;
        bias = pc_adapt(i - old, total, old == 0);
        if i / total > PC_MAX - n { return false; }
        n += i / total;
        i = i % total;
        if n > 0x10FFFF || (n >= 0xD800 && n <= 0xDFFF) { return false; }
        // A basic code point cannot come from an insert.
        if n < 0x80 { return false; }
        ins_at.push(i);
        ins_cp.push(n);
        i += 1;
    }
    // Place the inserts from the last to the first. Each takes the free
    // place that has i free places before it.
    let count = basics.len + ins_at.len;
    var free: i64[>..] = [];
    fen_new(free, count, 1);
    var result: i64[>..] = [];
    var r: i64 = 0;
    while r < count { result.push(-1); r += 1; }
    var t = ins_at.len;
    while t > 0 {
        t -= 1;
        let pos = fen_kth(free, count, ins_at[t]);
        result[pos] = ins_cp[t];
        fen_add(free, pos, -1);
    }
    // The basic code points fill the places that stay free, in order.
    var bi: i64 = 0;
    r = 0;
    while r < count {
        if result[r] < 0 {
            result[r] = basics[bi];
            bi += 1;
        }
        r += 1;
    }
    out.append(result[..]);
    return true;
}

// punycode_encode writes the Punycode of the UTF-8 text s into out.
fn punycode_encode(out: u8[>..]&, s: const u8[:]) -> bool {
    var cps: i64[>..] = [];
    if !utf8_cps(cps, s) { return false; }
    var tmp: u8[>..] = [];
    if !pc_encode(tmp, cps[..]) { return false; }
    out.append(tmp[..]);
    return true;
}

// punycode_decode writes the UTF-8 text of the Punycode s into out.
fn punycode_decode(out: u8[>..]&, s: const u8[:]) -> bool {
    var cps: i64[>..] = [];
    if !pc_decode(cps, s) { return false; }
    cps_utf8(out, cps[..]);
    return true;
}
