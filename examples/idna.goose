// IDNA maps a Unicode host to Punycode, as Node new URL(text).href.
// Run with: goose run examples/idna.goose
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
    show("http://münchen.de/");
    show("http://български.иком.museum/");
    show("http://faß.de/");
    show("http://xn--fa-hya.de/");
    show("http://áb.de/");
    show("http://ex­ample.com/");
    return 0;
}
