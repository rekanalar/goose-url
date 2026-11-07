// An example for the url package.
//
// It reads the query pairs of a URL, builds a new query, and changes
// the URL with checked setters.
//
// Run with: goose run examples/query.goose
import std;
import url from "..";

fn main() {
    let u, ok = url::parse("http://example.com/search?q=goose+lang&tag=a%26b");
    assert(ok);
    print("port: ", url::port_or_default(u));

    var pairs: url::Pair[>..] = [];
    url::query_pairs(pairs, u.query);
    for p in pairs { print(p.key, " = ", p.value); }

    var q: u8[>..] = [];
    url::append_pair(q, "name", "a b&c");
    url::append_pair(q, "page", "2");
    print("query: ", q);

    var v = u;
    if !url::set_scheme(v, "https") { return 1; }
    if !url::set_query(v, q[..]) { return 1; }
    if url::set_host(v, "bad host") { return 1; }
    var out: u8[>..] = [];
    url::build(out, v);
    print("url: ", out);
    return 0;
}
