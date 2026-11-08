// Query editing for the url package.
//
// The functions read a query text, or a form body, and write an edited
// query text into a buffer of the caller. The rules are the rules of Node
// URLSearchParams. The text goes out in form encoding, as append_pair
// writes it.
//
// An edit gives a count. A query with a broken escape keeps the text, as
// Node and Python do. The output appends to out, so give an empty buffer
// for a fresh text.
namespace url;

import std;

// query_has says whether a pair has the key.
fn query_has(q: const u8[:], key: const u8[:]) -> bool {
    var pairs: Pair[>..] = [];
    query_pairs(pairs, q);
    for p in pairs {
        if p.key == key { return true; }
    }
    return false;
}

// query_has_pair says whether a pair has the key and the value.
fn query_has_pair(q: const u8[:], key: const u8[:], value: const u8[:]) -> bool {
    var pairs: Pair[>..] = [];
    query_pairs(pairs, q);
    for p in pairs {
        if p.key == key && p.value == value { return true; }
    }
    return false;
}

// query_get_all collects the pairs of the key into out, in query order.
fn query_get_all(out: Pair[>..]&, q: const u8[:], key: const u8[:]) -> bool {
    var pairs: Pair[>..] = [];
    let ok = query_pairs(pairs, q);
    for p in pairs {
        if p.key == key { out.push(Pair { key: copy(p.key), value: copy(p.value) }); }
    }
    return ok;
}

// query_set gives the key one value. The first pair of the key takes the
// value at its place and the other pairs of the key go. A missing key
// appends the pair. It gives the count of old pairs of the key.
fn query_set(out: u8[>..]&, q: const u8[:], key: const u8[:], value: const u8[:]) -> i64 {
    var pairs: Pair[>..] = [];
    query_pairs(pairs, q);
    var text: u8[>..] = [];
    var seen: i64 = 0;
    for p in pairs {
        if p.key == key {
            if seen == 0 { append_pair(text, key, value); }
            seen += 1;
        } else {
            append_pair(text, p.key, p.value);
        }
    }
    if seen == 0 { append_pair(text, key, value); }
    out.append(text[..]);
    return seen;
}

// drop_pairs writes the pairs that do not match into out and gives the
// count of the pairs that match. A pair matches when its key is key and,
// if by_value is true, its value is value too.
fn drop_pairs(out: u8[>..]&, q: const u8[:], key: const u8[:], value: const u8[:], by_value: bool) -> i64 {
    var pairs: Pair[>..] = [];
    query_pairs(pairs, q);
    var text: u8[>..] = [];
    var gone: i64 = 0;
    for p in pairs {
        if p.key == key && (!by_value || p.value == value) {
            gone += 1;
        } else {
            append_pair(text, p.key, p.value);
        }
    }
    out.append(text[..]);
    return gone;
}

// query_delete removes every pair of the key. It gives the count removed.
fn query_delete(out: u8[>..]&, q: const u8[:], key: const u8[:]) -> i64 {
    return drop_pairs(out, q, key, "", false);
}

// query_delete_pair removes every pair with the key and the value, as
// Node delete(name, value) does. It gives the count removed.
fn query_delete_pair(out: u8[>..]&, q: const u8[:], key: const u8[:], value: const u8[:]) -> i64 {
    return drop_pairs(out, q, key, value, true);
}

// key_order compares two keys by their UTF-16 code units: -1, 0 or 1.
// Node and the URL Standard compare the code units. A code point above
// U+FFFF has two units, and the first of them lies below U+E000. So a
// key with such a code point comes before a key in the range U+E000 to
// U+FFFF. The keys hold valid UTF-8, because the query parser replaces
// an invalid part with the replacement character.
fn key_order(a: const u8[:], b: const u8[:]) -> i64 {
    var ia = 0;
    var ib = 0;
    var pend_a: i64 = -1;
    var pend_b: i64 = -1;
    var more = true;
    while more {
        var ua = -1;
        if pend_a >= 0 {
            ua = pend_a;
            pend_a = -1;
        } else if ia < a.len {
            let cp, len = utf8_next(a, ia);
            ia += len;
            if cp >= 0x10000 {
                ua = 0xD800 + ((cp - 0x10000) >> 10);
                pend_a = 0xDC00 + ((cp - 0x10000) & 0x3FF);
            } else {
                ua = cp;
            }
        }
        var ub = -1;
        if pend_b >= 0 {
            ub = pend_b;
            pend_b = -1;
        } else if ib < b.len {
            let cp, len = utf8_next(b, ib);
            ib += len;
            if cp >= 0x10000 {
                ub = 0xD800 + ((cp - 0x10000) >> 10);
                pend_b = 0xDC00 + ((cp - 0x10000) & 0x3FF);
            } else {
                ub = cp;
            }
        }
        if ua < 0 && ub < 0 {
            more = false;
            continue;
        }
        if ua < 0 { return -1; }
        if ub < 0 { return 1; }
        if ua != ub {
            if ua < ub { return -1; }
            return 1;
        }
    }
    return 0;
}

// utf8_next reads the code point at the byte i of s. It gives the code
// point and the length of the sequence. The text holds valid UTF-8.
fn utf8_next(s: const u8[:], i: i64) -> i64, i64 {
    let c = s[i];
    if c < 0x80 { return c, 1; }
    var cp = 0;
    var len = 1;
    if c >= 0xF0 {
        cp = c & 0x07;
        len = 4;
    } else if c >= 0xE0 {
        cp = c & 0x0F;
        len = 3;
    } else if c >= 0xC0 {
        cp = c & 0x1F;
        len = 2;
    } else {
        return 0xFFFD, 1;
    }
    if i + len > s.len { return 0xFFFD, 1; }
    var k = 1;
    while k < len {
        cp = (cp << 6) | (s[i + k] & 0x3F);
        k += 1;
    }
    return cp, len;
}

// query_sort orders the pairs by key. The sort is stable, so pairs of one
// key keep their order. It is a bottom-up merge sort on indices: n log n,
// no recursion. It gives the count of pairs.
fn query_sort(out: u8[>..]&, q: const u8[:]) -> i64 {
    var pairs: Pair[>..] = [];
    query_pairs(pairs, q);
    // Slices have a fixed size, so these arrays can be indexed.
    var ks: const u8[:][>..] = [];
    var vs: const u8[:][>..] = [];
    for p in pairs {
        ks.push(p.key[..]);
        vs.push(p.value[..]);
    }
    let n = ks.len;
    var src: i64[>..] = [];
    var dst: i64[>..] = [];
    var i = 0;
    while i < n {
        src.push(i);
        dst.push(0);
        i += 1;
    }
    var width = 1;
    while width < n {
        var lo = 0;
        while lo < n {
            var mid = lo + width;
            if mid > n { mid = n; }
            var hi = lo + 2 * width;
            if hi > n { hi = n; }
            var l = lo;
            var r = mid;
            var k = lo;
            while l < mid && r < hi {
                // A tie takes the left run, which keeps the order stable.
                if key_order(ks[src[l]], ks[src[r]]) <= 0 {
                    dst[k] = src[l];
                    l += 1;
                } else {
                    dst[k] = src[r];
                    r += 1;
                }
                k += 1;
            }
            while l < mid { dst[k] = src[l]; l += 1; k += 1; }
            while r < hi { dst[k] = src[r]; r += 1; k += 1; }
            lo += 2 * width;
        }
        var c = 0;
        while c < n { src[c] = dst[c]; c += 1; }
        width *= 2;
    }
    var text: u8[>..] = [];
    for at in src { append_pair(text, ks[at], vs[at]); }
    out.append(text[..]);
    return n;
}
