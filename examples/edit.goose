// Edits the query of a URL, reads its origin, hides its password and
// joins a path. Run with: goose run examples/edit.goose
import std;
import url from "..";

fn main() {
    let text = "https://user:secret@Example.com:8443/docs?b=2&a=1&b=0&lang=en";
    let u, ok = url::parse(text);
    assert(ok);

    // set keeps the place of the first pair. delete removes every pair.
    var set_q: u8[>..] = [];
    let old = url::query_set(set_q, u.query, "b", "9");
    print("set b: ", set_q[..], "  (old pairs: ", old, ")");

    var del_q: u8[>..] = [];
    url::query_delete(del_q, u.query, "b");
    print("delete b: ", del_q[..]);

    var sort_q: u8[>..] = [];
    url::query_sort(sort_q, u.query);
    print("sorted: ", sort_q[..]);

    var o: u8[>..] = [];
    if url::origin(o, u) { print("origin: ", o[..]); }

    var r: u8[>..] = [];
    url::redacted(r, u);
    print("redacted: ", r[..]);

    let parts = words("v2 users .. items/");
    var p: u8[>..] = [];
    assert(url::join_path(p, u.path, parts[..]));
    print("path: ", p[..]);
}
