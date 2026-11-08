// Query pairs and form encoding for the url package.
//
// query_pairs splits a query or a form body into decoded key and value
// pairs. append_pair writes one pair, as the Rust form_urlencoded
// Serializer does. The pairs keep their order.
namespace url;

import std;

// Pair holds one decoded key and one decoded value.
struct Pair {
    key: u8[],
    value: u8[],
}

// query_pairs decodes every key=value pair of q into out. Pairs split at
// &. An empty piece is skipped. A key without = gets an empty value, as
// in Go ParseQuery and the Rust query_pairs. A + is a space. A pair with a
// broken escape keeps the text, as Node and Python do. The call gives
// true.
fn query_pairs(out: Pair[>..]&, q: const u8[:]) -> bool {
    var pos = 0;
    while pos <= q.len {
        var end = pos;
        while end < q.len && q[end] != '&' { end += 1; }
        let piece = q[pos..end];
        pos = end + 1;
        if piece.len == 0 { continue; }
        var eq = piece.len;
        for c, i in piece {
            if c == '=' { eq = i; break; }
        }
        var k: u8[>..] = [];
        var v: u8[>..] = [];
        decode_form(k, piece[..eq]);
        if eq < piece.len {
            decode_form(v, piece[eq + 1..]);
        }
        out.push(Pair { key: k[..], value: v[..] });
    }
    return true;
}

// query_get decodes the first value of key in q into out. It gives false
// when the key is absent. Go Get.
fn query_get(out: u8[>..]&, q: const u8[:], key: const u8[:]) -> bool {
    var pairs: Pair[>..] = [];
    query_pairs(pairs, q);
    for p in pairs {
        if p.key == key {
            out.append(p.value);
            return true;
        }
    }
    return false;
}

// append_pair writes one pair into out in form encoding. It puts an & in
// front when out holds text already. Python urlencode, Go Values.Encode.
fn append_pair(out: u8[>..]&, key: const u8[:], value: const u8[:]) {
    if out.len > 0 { out.push('&'); }
    form_encode(out, key);
    out.push('=');
    form_encode(out, value);
}

// encode_pairs writes all pairs into out in form encoding.
fn encode_pairs(out: u8[>..]&, pairs: const Pair[:]) {
    for p in pairs { append_pair(out, p.key, p.value); }
}
