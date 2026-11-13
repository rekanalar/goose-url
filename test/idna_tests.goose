// Tests of Punycode and of the IDNA host mapping.
//
namespace idna_tests;

import std;
import url from "..";

// expect_puny checks one RFC 3492 sample in both directions.
fn expect_puny(text: const u8[:], code: const u8[:]) {
    var a: u8[>..] = [];
    assert(url::punycode_encode(a, text));
    assert(a == code);
    var b: u8[>..] = [];
    assert(url::punycode_decode(b, code));
    assert(b == text);
}

fn test_punycode() {
    expect_puny("ليهمابتكلموشعربي؟", "egbpdaj6bu4bxfgehfvwxn");
    expect_puny("他们为什么不说中文", "ihqwcrb4cv8a8dqg056pqjye");
    expect_puny("他們爲什麽不說中文", "ihqwctvzc91f659drss3x8bo0yb");
    expect_puny("Pročprostěnemluvíčesky", "Proprostnemluvesky-uyb24dma41a");
    expect_puny("למההםפשוטלאמדבריםעברית", "4dbcagdahymbxekheh6e0a7fei0b");
    expect_puny("なぜみんな日本語を話してくれないのか", "n8jok5ay5dzabd5bym9f0cm5685rrjetr6pdxa");
    expect_puny("3年B組金八先生", "3B-ww4c5e180e575a65lsy2b");
    expect_puny("安室奈美恵-with-SUPER-MONKEYS", "-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n");
    expect_puny("Hello-Another-Way-それぞれの場所", "Hello-Another-Way--fc4qua05auwb3674vfr0b");
    expect_puny("ひとつ屋根の下2", "2-u9tlzr9756bt3uc0v");
    expect_puny("MajiでKoiする5秒前", "MajiKoi5-783gue6qz075azm5e");
    expect_puny("パフィーdeルンバ", "de-jg4avhby1noc0d");
    expect_puny("そのスピードで", "d9juau41awczczp");
    // All-basic text encodes to itself and gets no delimiter.
    var o: u8[>..] = [];
    assert(url::punycode_encode(o, "abc"));
    assert(o == "abc");
    // Faults: bad digit, truncated number, overflow, bad UTF-8.
    var d: u8[>..] = [];
    assert(!url::punycode_decode(d, "a-!"));
    assert(!url::punycode_decode(d, "a-9"));
    assert(!url::punycode_decode(d, "99999999999999"));
    assert(!url::punycode_decode(d, "\xC3\xBC-abc"));
    var e: u8[>..] = [];
    assert(!url::punycode_encode(e, "\xC3"));
    assert(!url::punycode_encode(e, "\xED\xA0\x80"));
    assert(e.len == 0);
}

fn test_idna_hostile() {
    // A host of 50000 labels, one of them Punycode.
    var many: u8[>..] = [];
    many.append("http://xn--tda.");
    for i in 0..50000 { many.append("a."); }
    many.append("b/");
    var t = clock_ns();
    var o: u8[>..] = [];
    assert(url::normalize(o, many[..]));
    assert(clock_ns() - t < 1000000000);
    // A label of 100000 digits after xn--, which decodes to disallowed points.
    var longx: u8[>..] = [];
    longx.append("http://xn--");
    for i in 0..100000 { longx.push('a'); }
    longx.append("/");
    t = clock_ns();
    o = [];
    assert(!url::normalize(o, longx[..]));
    assert(clock_ns() - t < 1000000000);
    // A label of 100000 non-ASCII code points.
    var wide: u8[>..] = [];
    wide.append("http://");
    for i in 0..100000 { wide.append("\xc3\xa9"); }
    wide.append("/");
    t = clock_ns();
    o = [];
    assert(url::normalize(o, wide[..]));
    assert(clock_ns() - t < 1000000000);
    // A run of 100000 combining marks after a letter.
    var marks: u8[>..] = [];
    marks.append("http://a");
    for i in 0..100000 { marks.append("\xcc\x81"); }
    marks.append("/");
    t = clock_ns();
    o = [];
    let mok = url::normalize(o, marks[..]);
    assert(clock_ns() - t < 1000000000);
    // Marks in descending class order force the sort.
    var rev: u8[>..] = [];
    rev.append("http://a");
    for i in 0..50000 { rev.append("\xcc\xa7\xcc\x81"); }
    rev.append("/");
    t = clock_ns();
    o = [];
    let rok = url::normalize(o, rev[..]);
    assert(clock_ns() - t < 1000000000);
    // The same for the host of a file: URL and for a long hostile path.
    t = clock_ns();
    o = [];
    var fh: u8[>..] = [];
    fh.append("file://");
    fh.append(wide[7..]);
    let fok = url::normalize(o, fh[..]);
    assert(clock_ns() - t < 1000000000);
}
