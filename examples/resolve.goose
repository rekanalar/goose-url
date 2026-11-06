// An example for the url package.
//
// It parses a URL, prints its parts, and joins two relative links
// against it.
//
// Run with: goose run examples/resolve.goose
import std;
import url from "..";

fn main() {
    let base_text = "https://www.example.com/docs/index.html?page=1";
    let u, ok = url::parse(base_text);
    assert(ok);
    print("scheme: ", u.scheme);
    print("host: ", u.host);
    print("port: ", u.port);
    print("path: ", u.path);
    print("query: ", u.query);

    var out: u8[>..] = [];
    url::join(out, base_text, "guide/intro.html");
    print("link 1 -> ", out);

    out = [];
    url::join(out, base_text, "../assets/style.css");
    print("link 2 -> ", out);
    return 0;
}
