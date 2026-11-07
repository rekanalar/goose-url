// normalize writes the canonical text of a URL, as Node new URL(text).href.
// Run with: goose run examples/normalize.goose
import std;
import url from "..";

fn show(s: const u8[:]) {
    var out: u8[>..] = [];
    if url::normalize(out, s) {
        print(s, " -> ", out);
    } else {
        print(s, " -> refused");
    }
}

fn main() {
    show("HTTP://Example.COM:80/a/./b/../c");
    show("http://0x7f.1/a b?q=1 2#top");
    show("http://[0:0:0:0:0:0:0:1]:8080/");
    show("http://user@name:p w@host/");
    show("http://example.com:99999/");
    return 0;
}
