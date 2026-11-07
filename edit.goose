// Query editing for the url package.
//
// The functions read a query text, or a form body, and write an edited
// query text into a buffer of the caller. The rules are the rules of Node
// URLSearchParams. The text goes out in form encoding, as append_pair
// writes it.
//
// An edit gives a count, or -1 when the query holds a broken escape. Node
// keeps a broken escape as text. This package refuses it, as query_pairs
// does, and writes nothing. The output appends to out, so give an empty
// buffer for a fresh text.
namespace url;

import std;

// query_has says whether a pair has the key. A pair with a broken escape
// does not count.
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
// It gives false after a broken escape, as query_pairs does.
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
    if !query_pairs(pairs, q) { return -1; }
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
    if !query_pairs(pairs, q) { return -1; }
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

// key_order compares two keys by their bytes: -1, 0 or 1. Node compares
// UTF-16 code units. The two orders differ only for code points above
// U+FFFF against U+E000 to U+FFFF.
fn key_order(a: const u8[:], b: const u8[:]) -> i64 {
    var i = 0;
    while i < a.len && i < b.len {
        if a[i] != b[i] {
            if a[i] < b[i] { return -1; }
            return 1;
        }
        i += 1;
    }
    if a.len == b.len { return 0; }
    if a.len < b.len { return -1; }
    return 1;
}

// query_sort orders the pairs by key. The sort is stable, so pairs of one
// key keep their order. It is a bottom-up merge sort on indices: n log n,
// no recursion. It gives the count of pairs.
fn query_sort(out: u8[>..]&, q: const u8[:]) -> i64 {
    var pairs: Pair[>..] = [];
    if !query_pairs(pairs, q) { return -1; }
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
