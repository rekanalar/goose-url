// Tests for the url package. Run with: goose run test/run.goose
//
// The tests hold the acceptance scenarios of the spec and the normal
// examples of RFC 3986 section 5.3.

import std;
import os;
import url from "..";
import node_cases;
import normalize_cases;
import idna_cases;

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
    var n = 0;
    var ps: url::Pair[>..] = [];
    let ok = url::query_pairs(ps, "a=1&b=x+y%20z&c&&a=2&d=%e2%82%ac");
    assert(ok);
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
    var n = 0;
    var ps: url::Pair[>..] = [];
    let ok = url::query_pairs(ps, "a=%zz&b=1");
    assert(!ok);
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

// Query editing. The expected texts come from Node URLSearchParams.
fn expect_set(q: const u8[:], key: const u8[:], val: const u8[:], want: const u8[:], n: i64) {
    var o: u8[>..] = [];
    assert(url::query_set(o, q, key, val) == n);
    assert(o == want);
}

fn expect_delete(q: const u8[:], key: const u8[:], want: const u8[:], n: i64) {
    var o: u8[>..] = [];
    assert(url::query_delete(o, q, key) == n);
    assert(o == want);
}

fn expect_delete_pair(q: const u8[:], key: const u8[:], val: const u8[:], want: const u8[:], n: i64) {
    var o: u8[>..] = [];
    assert(url::query_delete_pair(o, q, key, val) == n);
    assert(o == want);
}

fn expect_sort(q: const u8[:], want: const u8[:], n: i64) {
    var o: u8[>..] = [];
    assert(url::query_sort(o, q) == n);
    assert(o == want);
}

fn test_query_edit() {
    expect_set("a=1&b=2&a=3", "a", "9", "a=9&b=2", 2);
    expect_set("a=1", "z", "y", "a=1&z=y", 0);
    expect_set("", "a", "1", "a=1", 0);
    expect_delete("a=1&b=2&a=3", "a", "b=2", 2);
    expect_delete("a=1", "z", "a=1", 0);
    expect_delete_pair("a=1&b=2&a=1&c=3", "a", "1", "b=2&c=3", 2);
    expect_delete_pair("a=1&a=2", "a", "3", "a=1&a=2", 0);
    expect_sort("b=2&a=1&b=0&a=3", "a=1&a=3&b=2&b=0", 4);
    expect_sort("", "", 0);
    // A bare key becomes a pair with an empty value.
    expect_sort("b&a", "a=&b=", 2);
    assert(url::query_has("a=1&b=2", "b"));
    assert(!url::query_has("a=1&b=2", "c"));
    assert(url::query_has_pair("a=1&a=2", "a", "2"));
    assert(!url::query_has_pair("a=1&a=2", "a", "3"));
    var ps: url::Pair[>..] = [];
    assert(url::query_get_all(ps, "a=1&b=2&a=3", "a"));
    assert(ps.len == 2);
}

fn test_query_edit_refuse() {
    // Node keeps a broken escape as text. The package refuses it.
    var o: u8[>..] = [];
    assert(url::query_set(o, "a=%zz&b=1", "a", "2") == -1);
    assert(url::query_delete(o, "a=%", "a") == -1);
    assert(url::query_delete_pair(o, "a=%zz", "a", "1") == -1);
    assert(url::query_sort(o, "b=1&a=%zz") == -1);
    assert(o.len == 0);
    assert(url::query_has("a=%zz&b=1", "b"));
    assert(!url::query_has("a=%zz&b=1", "a"));
    var ps: url::Pair[>..] = [];
    assert(!url::query_get_all(ps, "a=%zz&b=1", "b"));
    assert(ps.len == 1);
}

fn test_origin() {
    let u, ok = url::parse("blob:https://a.com/x");
    assert(ok);
    var o: u8[>..] = [];
    assert(!url::origin(o, u));
    assert(o.len == 0);
    let v, vok = url::parse("mailto:a@b.c");
    assert(vok);
    assert(!url::origin(o, v));
    // Node reads a backslash as a slash: its origin is http://evil.com.
    // The null origin is the safe answer.
    let x, xok = url::parse("http://evil.com\\@good.com/");
    assert(xok);
    assert(!url::origin(o, x));
    let y, yok = url::parse("http://evil.com\\.good.com/");
    assert(yok);
    assert(!url::origin(o, y));
    assert(o.len == 0);
    let w, wok = url::parse("http://[::1]:8080/");
    assert(wok);
    assert(url::origin(o, w));
    assert(o == "http://[::1]:8080");
}

fn expect_redacted(text: const u8[:], want: const u8[:]) {
    let u, ok = url::parse(text);
    assert(ok);
    var o: u8[>..] = [];
    url::redacted(o, u);
    assert(o == want);
}

// The rows come from Go 1.27 URL.Redacted.
fn test_redacted() {
    expect_redacted("https://user:secret@example.com/a", "https://user:xxxxx@example.com/a");
    expect_redacted("https://user:@example.com/a", "https://user:xxxxx@example.com/a");
    expect_redacted("https://:pw@example.com/", "https://:xxxxx@example.com/");
    expect_redacted("https://user@example.com/a", "https://user@example.com/a");
    expect_redacted("https://example.com/a?q=1#f", "https://example.com/a?q=1#f");
}

// expect_join_path joins the elements of text, split at spaces.
fn expect_join_path(base: const u8[:], text: const u8[:], want: const u8[:]) {
    let es = words(text);
    var o: u8[>..] = [];
    assert(url::join_path(o, base, es[..]));
    assert(o == want);
}

fn expect_join_empty(base: const u8[:], first: const u8[:], want: const u8[:]) {
    // words cannot make an empty element, so the list is built by hand.
    var es: const u8[:][>..] = [];
    es.push(first);
    es.push("b");
    var o: u8[>..] = [];
    assert(url::join_path(o, base, es[..]));
    assert(o == want);
    var none: const u8[:][>..] = [];
    o = [];
    assert(url::join_path(o, base, none[..]));
    if base == "" { assert(o == "/"); } else { assert(o == "/a"); }
    o = [];
    assert(url::join_path(o, "/a/", none[..]));
    assert(o == "/a/");
}

// The rows come from Go 1.27 URL.JoinPath.
fn test_join_path() {
    expect_join_path("/a/b", "c .. d", "/a/b/d");
    expect_join_path("/a/b/", "c", "/a/b/c");
    expect_join_path("/a/b", "c/", "/a/b/c/");
    expect_join_path("", "x", "/x");
    expect_join_path("/a", "../..", "/");
    expect_join_path("/a/", "b/..", "/a");
    expect_join_path("/a", "b/../", "/a/");
    expect_join_path("/a/b", ".", "/a/b");
    expect_join_path("/a//b", "c", "/a/b/c");
    expect_join_path("/a", "/b", "/a/b");
    expect_join_path("/a", "//b", "/a/b");
    expect_join_path("", ".. a", "/a");
    expect_join_empty("/a", "", "/a/b");
    expect_join_empty("", "", "/b");
    // With no element, Go still cleans the base path.
    var none: const u8[:][>..] = [];
    var c: u8[>..] = [];
    assert(url::join_path(c, "/a//b", none[..]));
    assert(c == "/a/b");
    c = [];
    assert(url::join_path(c, "/a/./b/..", none[..]));
    assert(c == "/a");
    var o: u8[>..] = [];
    let bad1 = words("b?c");
    let bad2 = words("b#c");
    let ok1 = words("b");
    assert(!url::join_path(o, "/a", bad1[..]));
    assert(!url::join_path(o, "/a", bad2[..]));
    assert(!url::join_path(o, "/a?x", ok1[..]));
    assert(o.len == 0);
}

// elapsed_ok checks one hostile call against the time bound of one second.
fn elapsed_ok(start: i64) {
    assert(clock_ns() - start < 1000000000);
}

fn test_edit_hostile() {
    // 10000 pairs with 10000 distinct keys, in reverse order.
    var q: u8[>..] = [];
    var i = 9999;
    while i >= 0 {
        if q.len > 0 { q.push('&'); }
        var key: u8[>..] = [];
        key.append("k");
        // A fixed width keeps the byte order equal to the number order.
        var d = 1000;
        while d > 0 { key.push(('0' + (i / d) % 10) as u8); d = d / 10; }
        q.append(key[..]);
        q.append("=v");
        i -= 1;
    }
    var o: u8[>..] = [];
    var t = clock_ns();
    assert(url::query_sort(o, q[..]) == 10000);
    elapsed_ok(t);
    assert(o.len == q.len);
    assert(o[0] == 'k' && o[1] == '0' && o[4] == '0');
    // The order is right: sorting the sorted text changes nothing.
    var again: u8[>..] = [];
    assert(url::query_sort(again, o[..]) == 10000);
    assert(again[..] == o[..]);
    o = [];
    t = clock_ns();
    assert(url::query_set(o, q[..], "k0000", "x") == 1);
    elapsed_ok(t);
    o = [];
    t = clock_ns();
    assert(url::query_delete(o, q[..], "k0001") == 1);
    elapsed_ok(t);
    o = [];
    t = clock_ns();
    assert(url::query_delete_pair(o, q[..], "k0001", "v") == 1);
    elapsed_ok(t);
    assert(url::query_has(q[..], "k0000"));

    // The read calls are linear too.
    t = clock_ns();
    assert(url::query_has(q[..], "k9999"));
    assert(!url::query_has(q[..], "none"));
    elapsed_ok(t);
    t = clock_ns();
    assert(url::query_has_pair(q[..], "k9999", "v"));
    assert(!url::query_has_pair(q[..], "k9999", "w"));
    elapsed_ok(t);
    var found: url::Pair[>..] = [];
    t = clock_ns();
    assert(url::query_get_all(found, q[..], "k5000"));
    elapsed_ok(t);
    assert(found.len == 1);

    // 10000 equal keys: set keeps one pair.
    var eq: u8[>..] = [];
    i = 0;
    while i < 10000 {
        if eq.len > 0 { eq.push('&'); }
        eq.append("a=1");
        i += 1;
    }
    o = [];
    t = clock_ns();
    assert(url::query_set(o, eq[..], "a", "2") == 10000);
    elapsed_ok(t);
    assert(o == "a=2");
    var every: url::Pair[>..] = [];
    t = clock_ns();
    assert(url::query_get_all(every, eq[..], "a"));
    elapsed_ok(t);
    assert(every.len == 10000);
    o = [];
    assert(url::query_delete(o, eq[..], "a") == 10000);
    assert(o.len == 0);

    // A query of about 1 MB.
    var big: u8[>..] = [];
    while big.len < 1000000 { big.append("abcdefgh=1234567&"); }
    o = [];
    t = clock_ns();
    assert(url::query_sort(o, big[..]) > 0);
    elapsed_ok(t);

    // join_path with 10000 elements, then with 10000 dot-dot elements.
    var views: const u8[:][>..] = [];
    i = 0;
    while i < 10000 { views.push("s"); i += 1; }
    o = [];
    t = clock_ns();
    assert(url::join_path(o, "/", views[..]));
    elapsed_ok(t);
    assert(o.len == 20000);
    var ups: const u8[:][>..] = [];
    i = 0;
    while i < 10000 { ups.push(".."); i += 1; }
    var all: const u8[:][>..] = [];
    for v in views { all.push(v); }
    for v in ups { all.push(v); }
    o = [];
    t = clock_ns();
    assert(url::join_path(o, "/", all[..]));
    elapsed_ok(t);
    assert(o == "/");
}

fn test_node_cases() {
    node_cases::check_queries();
    node_cases::check_origins();
    normalize_cases::check_normalize();
}

// test_normalize holds the hand cases of the spec. One group per user
// story: the canonical text, the host rules and the userinfo rules.
fn test_normalize() {
    var out: u8[>..] = [];

    // US1: the canonical text.
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

    // US2: the host rules.
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

    // US3: the userinfo and the port.
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

// expect_norm checks one normalize result.
fn expect_norm(text: const u8[:], want: const u8[:]) {
    var o: u8[>..] = [];
    assert(url::normalize(o, text));
    assert(o == want);
}

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

fn test_href_helpers() {
    // defrag, as urldefrag of Python: the first # splits.
    let a, f = url::defrag("http://a/b#c#d");
    assert(a == "http://a/b" && f == "c#d");
    let a2, f2 = url::defrag("http://a/b");
    assert(a2 == "http://a/b" && f2 == "");
    // is_abs, as IsAbs of Go: a scheme in front.
    assert(url::is_abs("http://a") && url::is_abs("a:b") && url::is_abs("mailto:x"));
    assert(!url::is_abs("/x") && !url::is_abs("1a:b") && !url::is_abs("") && !url::is_abs(":x"));
    // request_uri, as RequestURI of Go.
    var o: u8[>..] = [];
    let u1, ok1 = url::parse("http://a/p?q=1#f");
    assert(ok1);
    url::request_uri(o, u1);
    assert(o == "/p?q=1");
    o = [];
    let u2, ok2 = url::parse("http://a");
    assert(ok2);
    url::request_uri(o, u2);
    assert(o == "/");
    o = [];
    let u3, ok3 = url::parse("http://a?x");
    assert(ok3);
    url::request_uri(o, u3);
    assert(o == "/?x");
    // path_segments, as path_segments of Rust.
    var segs: const u8[:][>..] = [];
    assert(url::path_segments(segs, "/a/b/"));
    assert(segs.len == 3 && segs[0] == "a" && segs[1] == "b" && segs[2] == "");
    segs = [];
    assert(url::path_segments(segs, "/"));
    assert(segs.len == 1 && segs[0] == "");
    segs = [];
    assert(!url::path_segments(segs, "a/b"));
    assert(!url::path_segments(segs, ""));
    assert(segs.len == 0);
    // can_parse, as URL.canParse of Node.
    assert(url::can_parse("http://a"));
    assert(!url::can_parse("a"));
    assert(url::can_parse_base("b", "http://a/c"));
    assert(!url::can_parse_base("b", "c"));
    // resolve_href.
    o = [];
    assert(url::resolve_href(o, "../g", "http://a/b/c/d?q"));
    assert(o == "http://a/b/g");
    // The setters on text.
    o = [];
    assert(url::with_path(o, "http://a/x", "a b?c"));
    assert(o == "http://a/a%20b%3Fc");
    o = [];
    assert(url::with_username(o, "http://h/", "u:v"));
    assert(o == "http://u%3Av@h/");
    o = [];
    assert(!url::with_username(o, "file:///x", "u"));
    assert(!url::with_port(o, "http://h/", "abc"));
    assert(o.len == 0);
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
    test_query_edit();
    test_query_edit_refuse();
    test_origin();
    test_redacted();
    test_join_path();
    test_edit_hostile();
    test_punycode();
    test_href_helpers();
    test_idna_hostile();
    test_node_cases();
    test_normalize();
    idna_cases::test_idna_cases();
    test_normalize_hostile();
    print("all tests passed");
    return 0;
}
