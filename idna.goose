// IDNA host processing for the url package.
//
// idna_to_ascii applies UTS 46 as Node applies it: non-transitional
// processing, no STD3 rules, no hyphen rule and no length rule, with the
// bidi and the joiner checks on. The tables come from Unicode 17.0.
//
// Each step runs in time of n log n of the host length.
namespace url;

import std;

// bs_last gives the last index i with a[i] <= v, or -1 when none.
fn bs_last(a: const i64[:], v: i64) -> i64 {
    var lo: i64 = 0;
    var hi: i64 = a.len;
    while lo < hi {
        let mid = (lo + hi) / 2;
        if a[mid] <= v { lo = mid + 1; } else { hi = mid; }
    }
    return lo - 1;
}

// uts_kind gives the UTS 46 kind of a code point: 0 valid, 1 ignored,
// 2 mapped, 3 disallowed. For a mapped code point, off is the place of
// the mapping in UTS_POOL.
fn uts_kind(cp: i64) -> i64, i64 {
    let i = bs_last(UTS_START[..], cp);
    return UTS_KIND[i], UTS_MAP[i];
}

fn ccc_of(cp: i64) -> i64 {
    let i = bs_last(CCC_START[..], cp);
    if i >= 0 && cp <= CCC_END[i] { return CCC_VAL[i]; }
    return 0;
}

fn is_mark(cp: i64) -> bool {
    let i = bs_last(MARK_START[..], cp);
    return i >= 0 && cp <= MARK_END[i];
}

fn bidi_of(cp: i64) -> i64 {
    let i = bs_last(BIDI_START[..], cp);
    if i >= 0 && cp <= BIDI_END[i] { return BIDI_CLASS[i]; }
    return 23;
}

fn in_virama(cp: i64) -> bool {
    let i = bs_last(VIRAMA[..], cp);
    return i >= 0 && VIRAMA[i] == cp;
}

// join_of gives the joining type: 1 L, 2 R, 3 D, 0 none.
fn join_of(cp: i64) -> i64 {
    let i = bs_last(JT_CP[..], cp);
    if i >= 0 && JT_CP[i] == cp { return JT_TYPE[i]; }
    return 0;
}

// uts_map writes the UTS 46 mapping of the code points into out. It gives
// false when a code point is disallowed.
fn uts_map(out: i64[>..]&, cps: const i64[:]) -> bool {
    for cp in cps {
        let kind, off = uts_kind(cp);
        if kind == 0 { out.push(cp); }
        else if kind == 2 {
            var n = UTS_POOL[off];
            var k: i64 = 1;
            while k <= n { out.push(UTS_POOL[off + k]); k += 1; }
        } else if kind == 3 { return false; }
    }
    return true;
}

// nfc_decompose appends the full canonical decomposition of cp to out.
fn nfc_decompose(out: i64[>..]&, cp: i64) {
    if cp < 0xC0 { out.push(cp); return; }
    if cp >= 0xAC00 && cp <= 0xD7A3 {
        let s = cp - 0xAC00;
        out.push(0x1100 + s / 588);
        out.push(0x1161 + (s % 588) / 28);
        if s % 28 != 0 { out.push(0x11A7 + s % 28); }
        return;
    }
    let i = bs_last(DEC_CP[..], cp);
    if i >= 0 && DEC_CP[i] == cp {
        let off = DEC_OFF[i];
        var k: i64 = 1;
        while k <= DEC_POOL[off] { out.push(DEC_POOL[off + k]); k += 1; }
        return;
    }
    out.push(cp);
}

// nfc_pair gives the composite of a starter and a following code point,
// or -1.
fn nfc_pair(a: i64, b: i64) -> i64 {
    if a < 0x80 && b < 0x80 { return -1; }
    if a >= 0x1100 && a < 0x1113 && b >= 0x1161 && b < 0x1176 {
        return 0xAC00 + ((a - 0x1100) * 21 + (b - 0x1161)) * 28;
    }
    if a >= 0xAC00 && a <= 0xD7A3 && (a - 0xAC00) % 28 == 0 && b > 0x11A7 && b < 0x11C3 {
        return a + (b - 0x11A7);
    }
    let key = a * 0x200000 + b;
    let i = bs_last(COMP_KEY[..], key);
    if i >= 0 && COMP_KEY[i] == key { return COMP_VAL[i]; }
    return -1;
}

// nfc writes the NFC form of the code points into out.
fn nfc(out: i64[>..]&, cps: const i64[:]) {
    var d: i64[>..] = [];
    for cp in cps { nfc_decompose(d, cp); }
    // Put each run of marks in the order of the combining class. The sort
    // keeps equal classes in place, because the key holds the place.
    var i: i64 = 0;
    while i < d.len {
        if ccc_of(d[i]) == 0 { i += 1; continue; }
        var j = i;
        var sorted = true;
        var prev: i64 = 0;
        while j < d.len {
            let c = ccc_of(d[j]);
            if c == 0 { break; }
            if c < prev { sorted = false; }
            prev = c;
            j += 1;
        }
        if !sorted {
            var keys: i64[>..] = [];
            var k = i;
            while k < j { keys.push(ccc_of(d[k]) * 0x100000000 + (k - i)); k += 1; }
            sort(keys[..]);
            var run: i64[>..] = [];
            k = i;
            while k < j { run.push(d[k]); k += 1; }
            k = 0;
            while k < keys.len { d[i + k] = run[keys[k] & 0xFFFFFFFF]; k += 1; }
        }
        i = j;
    }
    // Compose each mark or jamo into the last starter when nothing blocks it.
    var start: i64 = -1;
    var last: i64 = 0;
    for cp in d[..] {
        let c = ccc_of(cp);
        if start >= 0 && (last < c || (last == 0 && out.len == start + 1)) {
            let m = nfc_pair(out[start], cp);
            if m >= 0 { out[start] = m; continue; }
        }
        if c == 0 { start = out.len; }
        last = c;
        out.push(cp);
    }
}

// label_valid is is_label_valid of ada 3.3.0, the URL parser of Node, with
// its tables. It keeps the faults of ada on purpose, because the package
// follows Node: a joiner ends the check with its own answer, a joiner
// context looks for any joining letter before and after, and an LTR label
// skips its last character. The bidi class numbers: L0 R1 AL2 EN3 ES4 ET5
// AN6 CS7 NSM8 BN9 ON13 and NONE 23.
fn label_valid(l: const i64[:]) -> bool {
    if l.len == 0 { return true; }
    if is_mark(l[0]) { return false; }
    var i: i64 = 0;
    while i < l.len {
        let c = l[i];
        if c == 0x200C {
            if i > 0 && in_virama(l[i - 1]) { return true; }
            if i == 0 || i + 1 >= l.len { return false; }
            var left = false;
            var k: i64 = 0;
            while k < i { let j = join_of(l[k]); if j == 1 || j == 3 { left = true; break; } k += 1; }
            var right = false;
            k = i + 1;
            while k < l.len { let j = join_of(l[k]); if j == 2 || j == 3 { right = true; break; } k += 1; }
            return left && right;
        }
        if c == 0x200D { return i > 0 && in_virama(l[i - 1]); }
        i += 1;
    }
    var last: i64 = l.len - 1;
    while last >= 0 && bidi_of(l[last]) == 8 { last -= 1; }
    if last < 0 { return false; }
    var rtl = false;
    for c in l {
        let b = bidi_of(c);
        if b == 1 || b == 2 || b == 6 { rtl = true; break; }
    }
    if !rtl { return true; }
    var n: i64 = 0;
    if bidi_of(l[0]) == 0 {
        while n < last {
            let b = bidi_of(l[n]);
            if !(b == 0 || b == 3 || b == 4 || b == 7 || b == 5 || b == 13 || b == 9 || b == 8) { return false; }
            n += 1;
        }
        return true;
    }
    var en = false;
    var an = false;
    while n <= last {
        let b = bidi_of(l[n]);
        if b == 3 { en = true; if an { return false; } }
        if b == 6 { an = true; if en { return false; } }
        if !(b == 1 || b == 2 || b == 6 || b == 3 || b == 4 || b == 7 || b == 5 || b == 13 || b == 9 || b == 8) { return false; }
        if n == last && !(b == 1 || b == 2 || b == 6 || b == 3) { return false; }
        n += 1;
    }
    return true;
}

// idna_to_ascii writes the ASCII form of the UTF-8 host s into out. It
// gives false for a host that UTS 46 refuses.
fn idna_to_ascii(out: u8[>..]&, s: const u8[:]) -> bool {
    var cps: i64[>..] = [];
    if !utf8_cps(cps, s) { return false; }
    var mapped: i64[>..] = [];
    if !uts_map(mapped, cps[..]) { return false; }
    var norm: i64[>..] = [];
    nfc(norm, mapped[..]);
    // Split into labels. A label with the xn-- prefix is decoded.
    var lab: i64[>..] = [];
    var ends: i64[>..] = [];
    var isx: bool[>..] = [];
    var ns: i64[>..] = [];
    var ne: i64[>..] = [];
    var i: i64 = 0;
    while i <= norm.len {
        var j = i;
        while j < norm.len && norm[j] != 0x2E { j += 1; }
        var x = false;
        if j - i >= 4 && norm[i] == 'x' && norm[i + 1] == 'n' && norm[i + 2] == '-' && norm[i + 3] == '-' {
            x = true;
            var a: u8[>..] = [];
            var k = i + 4;
            while k < j {
                if norm[k] >= 0x80 { return false; }
                a.push(norm[k] as u8);
                k += 1;
            }
            // The part after the prefix must not hold another xn--. Ada
            // refuses it, as WHATWG issue 803 says.
            if a.len >= 4 && a[0] == 'x' && a[1] == 'n' && a[2] == '-' && a[3] == '-' { return false; }
            var dec: i64[>..] = [];
            if a.len == 0 || !pc_decode(dec, a[..]) { return false; }
            var wide = false;
            for c in dec { if c >= 0x80 { wide = true; } }
            if !wide { return false; }
            var again: i64[>..] = [];
            nfc(again, dec[..]);
            if again.len != dec.len { return false; }
            k = 0;
            while k < dec.len {
                if again[k] != dec[k] { return false; }
                let kind, off = uts_kind(dec[k]);
                if kind != 0 { return false; }
                k += 1;
            }
            lab.append(dec[..]);
        } else {
            var k = i;
            while k < j { lab.push(norm[k]); k += 1; }
        }
        isx.push(x);
        ns.push(i);
        ne.push(j);
        ends.push(lab.len);
        i = j + 1;
    }
    var at: i64 = 0;
    var n: i64 = 0;
    while n < ends.len {
        let l = lab[at..ends[n]];
        var ascii = true;
        for c in l { if c >= 0x80 { ascii = false; } }
        // Ada checks a label that holds a code point of 128 and up, and a
        // label that came from Punycode. It leaves a plain ASCII label.
        if (isx[n] || !ascii) && !label_valid(l) { return false; }
        at = ends[n];
        n += 1;
    }
    // Write the labels.
    var tmp: u8[>..] = [];
    at = 0;
    n = 0;
    while n < ends.len {
        let l = lab[at..ends[n]];
        if n > 0 { tmp.push('.'); }
        var ascii = true;
        for c in l { if c >= 0x80 { ascii = false; } }
        if isx[n] {
            // The label keeps its own Punycode text.
            var k = ns[n];
            while k < ne[n] { tmp.push(norm[k] as u8); k += 1; }
        } else if ascii {
            for c in l { tmp.push(c as u8); }
        } else {
            tmp.append("xn--");
            if !pc_encode(tmp, l) { return false; }
        }
        at = ends[n];
        n += 1;
    }
    if tmp.len == 0 { return false; }
    out.append(tmp[..]);
    return true;
}

// domain_to_ascii writes the host of Node url.domainToASCII into out: the
// text is percent-decoded, mapped, checked and put in Punycode. It gives
// false where Node gives an empty text.
fn domain_to_ascii(out: u8[>..]&, s: const u8[:]) -> bool {
    var h: u8[>..] = [];
    if !n_host(h, s, true) || h.len == 0 { return false; }
    out.append(h[..]);
    return true;
}

// domain_to_unicode writes the host of Node url.domainToUnicode into out:
// the ASCII form with each xn-- label decoded.
fn domain_to_unicode(out: u8[>..]&, s: const u8[:]) -> bool {
    var a: u8[>..] = [];
    if !domain_to_ascii(a, s) { return false; }
    var tmp: u8[>..] = [];
    var i: i64 = 0;
    while i <= a.len {
        var j = i;
        while j < a.len && a[j] != '.' { j += 1; }
        if i > 0 { tmp.push('.'); }
        if j - i > 4 && a[i] == 'x' && a[i + 1] == 'n' && a[i + 2] == '-' && a[i + 3] == '-' {
            var dec: i64[>..] = [];
            if !pc_decode(dec, a[i + 4..j]) { return false; }
            cps_utf8(tmp, dec[..]);
        } else {
            tmp.append(a[i..j]);
        }
        i = j + 1;
    }
    out.append(tmp[..]);
    return true;
}
