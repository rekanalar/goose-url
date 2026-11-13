// Tests of the href helpers: defrag, request URI and the with calls.
//
namespace href_tests;

import std;
import url from "..";

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
