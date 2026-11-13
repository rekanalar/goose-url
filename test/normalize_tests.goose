// Tests of the normalize call against Node and the hostile inputs.
//
namespace normalize_tests;

import std;
import url from "..";
import node_cases;

// expect_norm checks one normalize result.
fn expect_norm(text: const u8[:], want: const u8[:]) {
    var o: u8[>..] = [];
    assert(url::normalize(o, text));
    assert(o == want);
}

fn test_node_cases() {
    node_cases::check_queries();
    node_cases::check_origins();
    url_cases::check_queries();
    url_cases::check_origins();
    normalize_cases::check_normalize();
}

// test_normalize holds the hand cases of the spec. One group per user
// story: the canonical text, the host rules and the userinfo rules.
fn test_normalize() {
    var out: u8[>..] = [];

    // The canonical text.
    assert(url::normalize(out, "HTTP://Example.COM:80/a/../b/./c"));
    assert(out == "http://example.com/b/c");
    out = [];
    assert(url::normalize(out, "http:\\\\example.com\\a\\b"));
    assert(out == "http://example.com/a/b");
    out = [];
    assert(url::normalize(out, "http:example.com"));
    assert(out == "http://example.com/");
    out = [];
    assert(url::normalize(out, "  http://example.com  "));
    assert(out == "http://example.com/");
    out = [];
    assert(url::normalize(out, "http://example.com"));
    assert(out == "http://example.com/");
    // A failure leaves out unchanged.
    assert(!url::normalize(out, "no-scheme"));
    assert(out == "http://example.com/");
    out = [];
    assert(!url::normalize(out, ""));
    assert(!url::normalize(out, "ftp"));
    expect_norm("mailto:a@b", "mailto:a@b");
    expect_norm("file:///x", "file:///x");
    expect_norm("foo://A.b/x", "foo://A.b/x");
    // file: and non-special schemes.
    expect_norm("file:c:\\x\\y", "file:///c:/x/y");
    expect_norm("file://localhost/a", "file:///a");
    expect_norm("file://host/a", "file://host/a");
    expect_norm("file:///c|/x/../..", "file:///c:/");
    expect_norm("foo://Host/a/../b", "foo://Host/b");
    expect_norm("foo:a/../b", "foo:a/../b");
    expect_norm("a:b c ?x", "a:b c%20?x");
    expect_norm("foo:/..//x", "foo:/.//x");
    assert(!url::normalize(out, "foo://:80/"));
    assert(!url::normalize(out, "foo://u@/x"));
    assert(!url::normalize(out, "http://"));
    assert(!url::normalize(out, "http://////"));
    assert(!url::normalize(out, "http://?x"));
    // Percent sets: encoded bytes, kept escapes, bare %.
    assert(url::normalize(out, "http://example.com/a b/c^d"));
    assert(out == "http://example.com/a%20b/c%5Ed");
    out = [];
    assert(url::normalize(out, "http://example.com/%41%2F%%zzx"));
    assert(out == "http://example.com/%41%2F%%zzx");
    out = [];
    assert(url::normalize(out, "http://example.com/?a b'a|b{b"));
    assert(out == "http://example.com/?a%20b%27a|b{b");
    out = [];
    assert(url::normalize(out, "http://example.com/?#"));
    assert(out == "http://example.com/?#");
    out = [];
    assert(url::normalize(out, "http://example.com/#a b`c<d"));
    assert(out == "http://example.com/#a%20b%60c%3Cd");
    out = [];
    // Dot segments, including the percent forms.
    assert(url::normalize(out, "http://example.com/a/b/../../c"));
    assert(out == "http://example.com/c");
    out = [];
    assert(url::normalize(out, "http://example.com/%2e/x/%2e%2e/y"));
    assert(out == "http://example.com/y");
    out = [];
    assert(url::normalize(out, "http://example.com/%2e%2e%2e/.."));
    assert(out == "http://example.com/");
    out = [];

    // The host rules.
    assert(url::normalize(out, "HTTP://A.B:80/X"));
    assert(out == "http://a.b/X");
    out = [];
    assert(url::normalize(out, "http://0x7F.1/"));
    assert(out == "http://127.0.0.1/");
    out = [];
    assert(url::normalize(out, "http://0177.0.0.1/"));
    assert(out == "http://127.0.0.1/");
    out = [];
    assert(url::normalize(out, "http://127.1/"));
    assert(out == "http://127.0.0.1/");
    out = [];
    assert(url::normalize(out, "http://1.2.3/"));
    assert(out == "http://1.2.0.3/");
    out = [];
    assert(url::normalize(out, "http://4294967295/"));
    assert(out == "http://255.255.255.255/");
    out = [];
    assert(url::normalize(out, "http://1.2.3.4./"));
    assert(out == "http://1.2.3.4/");
    out = [];
    assert(url::normalize(out, "http://%41.com/"));
    assert(out == "http://a.com/");
    out = [];
    assert(url::normalize(out, "http://A_b!c~/"));
    assert(out == "http://a_b!c~/");
    out = [];
    // Host faults.
    assert(!url::normalize(out, "http://1.2.3.4.5/"));
    assert(!url::normalize(out, "http://1.2.3.256/"));
    assert(!url::normalize(out, "http://4294967296/"));
    assert(!url::normalize(out, "http://08/"));
    assert(!url::normalize(out, "http://a%25b/"));
    assert(!url::normalize(out, "http://a%2Fb/"));
    assert(!url::normalize(out, "http://a%00b/"));
    assert(!url::normalize(out, "http://a|b/"));
    assert(!url::normalize(out, "http://a[2]b/"));
    // IDNA faults: bare xn--, bad Punycode, bidi, joiner, space.
    assert(!url::normalize(out, "http://xn--/"));
    assert(!url::normalize(out, "http://xn--a.com/"));
    assert(!url::normalize(out, "http://\xd7\x90a.com/"));
    assert(!url::normalize(out, "http://a\xe2\x80\x8db.com/"));
    assert(!url::normalize(out, "http://a b\xc3\xbc.com/"));
    assert(!url::normalize(out, "http://\xc3/"));
    assert(out.len == 0);
    // IDNA hosts.
    expect_norm("http://m\xc3\xbcnchen.de/", "http://xn--mnchen-3ya.de/");
    expect_norm("http://xn--mnchen-3ya.de/", "http://xn--mnchen-3ya.de/");
    expect_norm("http://XN--TDA.com/", "http://xn--tda.com/");
    expect_norm("http://\xc3\x9f.de/", "http://xn--zca.de/");
    expect_norm("http://a\xc2\xad.com/", "http://a.com/");
    expect_norm("http://\xef\xbc\xa1.com/", "http://a.com/");
    expect_norm("http://%C3%BC.com/", "http://xn--tda.com/");
    // IPv6 canonical form.
    assert(url::normalize(out, "http://[0:0:1:0:0:0:0:1]/"));
    assert(out == "http://[0:0:1::1]/");
    out = [];
    assert(url::normalize(out, "http://[1:0:0:1:0:0:0:1]/"));
    assert(out == "http://[1:0:0:1::1]/");
    out = [];
    assert(url::normalize(out, "http://[FE80:0:0:0:200:5EFF:FE00:5213]/"));
    assert(out == "http://[fe80::200:5eff:fe00:5213]/");
    out = [];
    assert(url::normalize(out, "http://[::ffff:1.2.3.4]/"));
    assert(out == "http://[::ffff:102:304]/");
    out = [];
    assert(!url::normalize(out, "http://[1::2::3]/"));
    assert(!url::normalize(out, "http://[::ffff:1.2.3.256]/"));
    assert(!url::normalize(out, "http://[::ffff:01.2.3.4]/"));
    assert(!url::normalize(out, "http://[::ffff:0x1.2.3.4]/"));
    assert(!url::normalize(out, "http://[1:2:3:4:5:6:7]/"));
    assert(!url::normalize(out, "http://[1:2:3:4:5:6:7:8::]/"));

    // The userinfo and the port.
    assert(url::normalize(out, "http://a@b@c.d/"));
    assert(out == "http://a%40b@c.d/");
    out = [];
    assert(url::normalize(out, "http://a:b@c@d/"));
    assert(out == "http://a:b%40c@d/");
    out = [];
    assert(url::normalize(out, "http://:@example.com/"));
    assert(out == "http://example.com/");
    out = [];
    assert(url::normalize(out, "http://u:@example.com/"));
    assert(out == "http://u@example.com/");
    out = [];
    assert(url::normalize(out, "http://:p@example.com/"));
    assert(out == "http://:p@example.com/");
    out = [];
    assert(url::normalize(out, "http://user:pa:ss@example.com/"));
    assert(out == "http://user:pa%3Ass@example.com/");
    out = [];
    assert(url::normalize(out, "http://a b^c@example.com/"));
    assert(out == "http://a%20b%5Ec@example.com/");
    out = [];
    assert(url::normalize(out, "http://example.com:80/"));
    assert(out == "http://example.com/");
    out = [];
    assert(url::normalize(out, "http://example.com:080/"));
    assert(out == "http://example.com/");
    out = [];
    assert(url::normalize(out, "http://example.com:/"));
    assert(out == "http://example.com/");
    out = [];
    assert(url::normalize(out, "http://example.com:443/"));
    assert(out == "http://example.com:443/");
    out = [];
    assert(url::normalize(out, "https://example.com:443/"));
    assert(out == "https://example.com/");
    out = [];
    assert(url::normalize(out, "ftp://example.com:21/x"));
    assert(out == "ftp://example.com/x");
    out = [];
    assert(url::normalize(out, "http://[::1]:80/x"));
    assert(out == "http://[::1]/x");
    out = [];
    assert(!url::normalize(out, "http://example.com:65536/"));
    assert(!url::normalize(out, "http://example.com:a/"));
    assert(!url::normalize(out, "http://example.com:-1/"));
    assert(!url::normalize(out, "http://a:b:c/"));
}

// test_normalize_hostile proves that a hostile input costs one pass. The
// ten texts are each 100000 bytes. All of them must finish in under one
// second in total.
fn test_normalize_hostile() {
    var big: u8[>..] = [];
    for i in 0..50000 {
        big.append("1.");
    }
    let t0 = clock_ns();
    var out: u8[>..] = [];

    var texts: u8[:][>..] = [];
    var a: u8[>..] = [];
    for i in 0..100000 { a.push('%'); }
    texts.push(a[..]);
    var b: u8[>..] = [];
    for i in 0..100000 { b.push('.'); }
    texts.push(b[..]);
    var c: u8[>..] = [];
    for i in 0..50000 { c.append(".."); }
    texts.push(c[..]);
    var d: u8[>..] = [];
    for i in 0..100000 { d.push('['); }
    texts.push(d[..]);
    var e: u8[>..] = [];
    for i in 0..100000 { e.push('@'); }
    texts.push(e[..]);
    var f: u8[>..] = [];
    for i in 0..100000 { f.push('7'); }
    texts.push(f[..]);
    var g: u8[>..] = [];
    for i in 0..100000 { g.push('x'); }
    texts.push(g[..]);
    var h: u8[>..] = [];
    for i in 0..50000 { h.append("1:"); }
    texts.push(h[..]);
    var k: u8[>..] = [];
    for i in 0..50000 { k.append("[1:"); }
    texts.push(k[..]);
    var m: u8[>..] = [];
    m.append("http://");
    for i in 0..100000 { m.push('a'); }
    texts.push(m[..]);

    for s in texts {
        if !url::normalize(out, s) { out = []; }
    }
    if !url::normalize(out, big[..]) { out = []; }
    assert(clock_ns() - t0 < 1000000000);
}
