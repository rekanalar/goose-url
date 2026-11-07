// Tests for the url package. Run with: goose run test/run.goose
//
// The tests hold the acceptance scenarios of the spec and the normal
// examples of RFC 3986 section 5.3.

import std;
import url from "..";

// expect_parse checks the parts of one URL.
fn expect_parse(s: const u8[:], scheme: const u8[:], userinfo: const u8[:], host: const u8[:], port: i32, path: const u8[:], query: const u8[:], fragment: const u8[:]) {
    let u, ok = url::parse(s);
    assert(ok);
    assert(u.scheme == scheme);
    assert(u.userinfo == userinfo);
    assert(u.host == host);
    assert(u.port == port);
    assert(u.path == path);
    assert(u.query == query);
    assert(u.fragment == fragment);
}

// expect_fault checks that the text is not a valid absolute URL.
fn expect_fault(s: const u8[:]) {
    let u, ok = url::parse(s);
    assert(!ok);
}

// expect_join checks the result of a join.
fn expect_join(base: const u8[:], ref: const u8[:], want: const u8[:]) {
    var out: u8[>..] = [];
    let ok = url::join(out, base, ref);
    assert(ok);
    assert(out == want);
}

fn test_parse_full() {
    expect_parse("https://jim:pw@example.com:8443/a/b?q=1#top",
        "https", "jim:pw", "example.com", 8443, "/a/b", "q=1", "top");
}

fn test_parse_simple() {
    expect_parse("http://example.com", "http", "", "example.com", -1, "", "", "");
    expect_parse("http://example.com/", "http", "", "example.com", -1, "/", "", "");
    expect_parse("http://example.com/p", "http", "", "example.com", -1, "/p", "", "");
    expect_parse("https://example.com:443/", "https", "", "example.com", 443, "/", "", "");
    expect_parse("mailto:jim@example.com", "mailto", "", "", -1, "jim@example.com", "", "");
}

fn test_parse_faults() {
    expect_fault("");
    expect_fault("::::");
    expect_fault("http://");
    expect_fault("example.com/path");
    expect_fault("1http://example.com");
    expect_fault("http://exa mple.com/");
    expect_fault("http://example.com:port/");
    expect_fault("http://example.com:99999/");
    expect_fault("http://[::1/");
    expect_fault("//example.com/");
}

fn test_parse_ipv6() {
    expect_parse("http://[::1]:8080/x", "http", "", "::1", 8080, "/x", "", "");
    expect_parse("http://[2001:db8::1]/", "http", "", "2001:db8::1", -1, "/", "", "");
}

fn test_parse_escapes() {
    // An escaped # does not split the query.
    expect_parse("http://example.com/p%23q?a=b", "http", "", "example.com", -1, "/p%23q", "a=b", "");
}

fn test_build() {
    var out: u8[>..] = [];
    let u, ok = url::parse("https://jim:pw@example.com:8443/a/b?q=1#top");
    assert(ok);
    url::build(out, u);
    assert(out == "https://jim:pw@example.com:8443/a/b?q=1#top");
}

fn test_build_ipv6() {
    var out: u8[>..] = [];
    let u, ok = url::parse("http://[::1]:8080/x");
    assert(ok);
    url::build(out, u);
    assert(out == "http://[::1]:8080/x");
}

// The round trip holds for many URLs.
fn test_round_trip() {
    const urls = [
        "http://example.com",
        "http://example.com/",
        "https://example.com/path",
        "https://example.com/path/to/file.txt",
        "http://user@example.com/",
        "http://user:pass@example.com/",
        "http://user:pass@example.com:8080/path?query=value",
        "https://example.com/?a=1&b=2",
        "https://example.com/#fragment",
        "https://example.com/path?query#fragment",
        "http://[::1]/",
        "http://[::1]:8080/path",
        "http://[2001:db8::1]:443/x?y",
        "ftp://files.example.com/pub/file.txt",
        "mailto:jim@example.com",
        "https://sub.domain.example.co.uk/a",
        "https://example.com/a%20b",
        "https://example.com/a?x=%2F",
        "https://example.com:8443/",
        "http://example.com/~user/",
        "https://example.com/a/b/../c",
    ];
    for s in urls {
        var out: u8[>..] = [];
        let u, ok = url::parse(s);
        assert(ok);
        url::build(out, u);
        assert(out == s);
    }
}

fn test_encode() {
    var out: u8[>..] = [];
    url::encode(out, "a b&c=d", "");
    assert(out == "a%20b%26c%3Dd");
}

fn test_encode_safe() {
    // A slash in the safe set stays.
    var out: u8[>..] = [];
    url::encode(out, "a/b c", "/");
    assert(out == "a/b%20c");
}

fn test_decode() {
    var out: u8[>..] = [];
    let ok = url::decode(out, "a%20b%26c", false);
    assert(ok);
    assert(out == "a b&c");
}

fn test_decode_form() {
    // In form mode a plus is a space.
    var out: u8[>..] = [];
    let ok = url::decode(out, "a+b%20c", true);
    assert(ok);
    assert(out == "a b c");
}

fn test_decode_faults() {
    var out: u8[>..] = [];
    let ok1 = url::decode(out, "%2", false);
    assert(!ok1);
    let ok2 = url::decode(out, "%zz", false);
    assert(!ok2);
    let ok3 = url::decode(out, "abc%", false);
    assert(!ok3);
}

fn expect_esc(got: const u8[:], want: const u8[:]) { assert(got == want); }

// The expected texts come from Python 3 urllib.parse and Go 1.2x net/url
// for the input "a b/c&d=e~é$@:,;?+*".
fn test_escape_sets() {
    const s = "a b/c&d=e~é$@:,;?+*";
    var a: u8[>..] = [];
    url::quote(a, s);
    assert(a == "a%20b/c%26d%3De~%C3%A9%24%40%3A%2C%3B%3F%2B%2A");
    var b: u8[>..] = [];
    url::quote_plus(b, s);
    assert(b == "a+b%2Fc%26d%3De~%C3%A9%24%40%3A%2C%3B%3F%2B%2A");
    var c: u8[>..] = [];
    url::query_escape(c, s);
    assert(c == b[..]);
    var d: u8[>..] = [];
    url::path_escape(d, s);
    assert(d == "a%20b%2Fc&d=e~%C3%A9$@:%2C%3B%3F+%2A");
}

// The Rust form_urlencoded byte_serialize keeps *-._ and escapes ~.
fn test_form_encode() {
    var a: u8[>..] = [];
    url::form_encode(a, "k y/~*-._");
    assert(a == "k+y%2F%7E*-._");
}

fn test_query_pairs() {
    // Python parse_qsl with keep_blank_values and Go ParseQuery agree.
    var ps: url::Pair[>..] = [];
    let ok = url::query_pairs(ps, "a=1&b=x+y%20z&c&&a=2&d=%e2%82%ac");
    assert(ok);
    var n = 0;
    for p in ps {
        if n == 0 { assert(p.key == "a"); assert(p.value == "1"); }
        if n == 1 { assert(p.key == "b"); assert(p.value == "x y z"); }
        if n == 2 { assert(p.key == "c"); assert(p.value == ""); }
        if n == 3 { assert(p.key == "a"); assert(p.value == "2"); }
        if n == 4 { assert(p.key == "d"); assert(p.value == "€"); }
        n += 1;
    }
    assert(n == 5);
}

fn test_query_pairs_fault() {
    // Go ParseQuery skips the bad pair, reports the fault, and goes on.
    var ps: url::Pair[>..] = [];
    let ok = url::query_pairs(ps, "a=%zz&b=1");
    assert(!ok);
    var n = 0;
    for p in ps { assert(p.key == "b"); n += 1; }
    assert(n == 1);
}

fn test_query_get() {
    var out: u8[>..] = [];
    assert(url::query_get(out, "a=1&a=2&b=%41", "a"));
    assert(out == "1");
    out = [];
    assert(url::query_get(out, "a=1&a=2&b=%41", "b"));
    assert(out == "A");
    assert(!url::query_get(out, "a=1", "z"));
}

fn test_append_pair() {
    // Python urlencode([("k y","v/~*"),("é","")]) is
    // k+y=v%2F~%2A&%C3%A9= ; the form set here escapes ~ as the Rust
    // Serializer does.
    var out: u8[>..] = [];
    url::append_pair(out, "k y", "v/~*");
    url::append_pair(out, "é", "");
    assert(out == "k+y=v%2F%7E*&%C3%A9=");
    var ps: url::Pair[>..] = [];
    assert(url::query_pairs(ps, out[..]));
}

fn test_default_port() {
    // The Rust port_or_known_default list.
    assert(url::default_port("http") == 80);
    assert(url::default_port("HTTPS") == 443);
    assert(url::default_port("ws") == 80);
    assert(url::default_port("wss") == 443);
    assert(url::default_port("ftp") == 21);
    assert(url::default_port("gopher") == -1);
    let u, ok = url::parse("https://example.com/");
    assert(ok);
    assert(url::port_or_default(u) == 443);
    let v, ok2 = url::parse("https://example.com:8443/");
    assert(ok2);
    assert(url::port_or_default(v) == 8443);
}

fn test_setters() {
    var u, ok = url::parse("http://example.com/a?q=1#f");
    assert(ok);
    assert(url::set_scheme(u, "https"));
    assert(url::set_host(u, "example.org"));
    assert(url::set_port(u, "8443"));
    assert(url::set_userinfo(u, "jim:pw"));
    assert(url::set_path(u, "/x/y"));
    assert(url::set_query(u, "a=b"));
    assert(url::set_fragment(u, "top"));
    var out: u8[>..] = [];
    url::build(out, u);
    assert(out == "https://jim:pw@example.org:8443/x/y?a=b#top");
    assert(url::set_port(u, ""));
    assert(url::set_query(u, ""));
    assert(url::set_fragment(u, ""));
    out = [];
    url::build(out, u);
    assert(out == "https://jim:pw@example.org/x/y");
    assert(url::set_host(u, "::1"));
    out = [];
    url::build(out, u);
    assert(out == "https://jim:pw@[::1]/x/y");
}

// Each bad value gives false and leaves the Url as it was.
fn test_setter_faults() {
    var u, ok = url::parse("http://example.com/a");
    assert(ok);
    assert(!url::set_scheme(u, "ht tp"));
    assert(!url::set_scheme(u, "1http"));
    assert(!url::set_scheme(u, ""));
    assert(!url::set_host(u, "exa mple.com"));
    assert(!url::set_host(u, "a/b"));
    assert(!url::set_host(u, ""));
    assert(!url::set_host(u, "a::zz"));
    assert(!url::set_port(u, "99999"));
    assert(!url::set_port(u, "80x"));
    assert(!url::set_userinfo(u, "a@b"));
    assert(!url::set_path(u, "/a?b"));
    assert(!url::set_path(u, "rel"));
    assert(!url::set_query(u, "a#b"));
    assert(!url::set_fragment(u, "a b"));
    var out: u8[>..] = [];
    url::build(out, u);
    assert(out == "http://example.com/a");
}

fn test_join_base() {
    expect_join("http://a/b/c/d;p?q", "../g", "http://a/b/g");
    expect_join("http://a/b/c/d;p?q", "../../g", "http://a/g");
    expect_join("http://a/b/c/d;p?q", "../../../g", "http://a/g");
    expect_join("http://a/b/c/d;p?q", "/./g", "http://a/g");
    expect_join("http://a/b/c/d;p?q", "g", "http://a/b/c/g");
    expect_join("http://a/b/c/d;p?q", "./g", "http://a/b/c/g");
    expect_join("http://a/b/c/d;p?q", "g/", "http://a/b/c/g/");
    expect_join("http://a/b/c/d;p?q", "/g", "http://a/g");
    expect_join("http://a/b/c/d;p?q", "?y", "http://a/b/c/d;p?y");
    expect_join("http://a/b/c/d;p?q", "g?y", "http://a/b/c/g?y");
    expect_join("http://a/b/c/d;p?q", "#s", "http://a/b/c/d;p?q#s");
    expect_join("http://a/b/c/d;p?q", "g#s", "http://a/b/c/g#s");
    expect_join("http://a/b/c/d;p?q", "g?y#s", "http://a/b/c/g?y#s");
    expect_join("http://a/b/c/d;p?q", ";x", "http://a/b/c/;x");
    expect_join("http://a/b/c/d;p?q", "g;x", "http://a/b/c/g;x");
    expect_join("http://a/b/c/d;p?q", "g;x?y#s", "http://a/b/c/g;x?y#s");
    expect_join("http://a/b/c/d;p?q", "", "http://a/b/c/d;p?q");
    expect_join("http://a/b/c/d;p?q", ".", "http://a/b/c/");
    expect_join("http://a/b/c/d;p?q", "./", "http://a/b/c/");
    expect_join("http://a/b/c/d;p?q", "..", "http://a/b/");
    expect_join("http://a/b/c/d;p?q", "../", "http://a/b/");
    expect_join("http://a/b/c/d;p?q", "../g", "http://a/b/g");
    expect_join("http://a/b/c/d;p?q", "../..", "http://a/");
    expect_join("http://a/b/c/d;p?q", "../../", "http://a/");
    expect_join("http://a/b/c/d;p?q", "../../g", "http://a/g");
    expect_join("http://a/b/c/d;p?q", "http://x/y", "http://x/y");
    expect_join("http://a/b/c/d;p?q", "//x/y", "http://x/y");
}

fn test_join_absolute_base() {
    expect_join("http://a/b/c/d;p?q", "https://x/y", "https://x/y");
}

fn test_join_faults() {
    var out: u8[>..] = [];
    let ok = url::join(out, "not a url", "x");
    assert(!ok);
}

fn test_large_url() {
    // A long URL parses in bounded time. The test checks the parts.
    var text: u8[>..] = [];
    text.append("https://example.com/");
    var i = 0;
    while i < 60000 {
        text.append("a");
        i += 1;
    }
    let u, ok = url::parse(text[..]);
    assert(ok);
    assert(u.host == "example.com");
    assert(u.path.len == 60001);
}

fn main() {
    test_parse_full();
    test_parse_simple();
    test_parse_faults();
    test_parse_ipv6();
    test_parse_escapes();
    test_build();
    test_build_ipv6();
    test_round_trip();
    test_encode();
    test_encode_safe();
    test_decode();
    test_decode_form();
    test_decode_faults();
    test_escape_sets();
    test_form_encode();
    test_query_pairs();
    test_query_pairs_fault();
    test_query_get();
    test_append_pair();
    test_default_port();
    test_setters();
    test_setter_faults();
    test_join_base();
    test_join_absolute_base();
    test_join_faults();
    test_large_url();
    print("all tests passed");
    return 0;
}
