// Prints the normalize result of http://a<cp>b.com/ for every code point
// from the first argument to the second. test/check_idna_data.mjs compares
// the lines with Node. Build with goose build, then run the file.
import std;
import url from "..";

fn main() {
    var lo = 128;
    var hi = 0x10FFFF;
    var cp = lo;
    var buf: u8[>..] = [];
    var text: u8[>..] = [];
    var out: u8[>..] = [];
    while cp <= hi {
        if cp < 0xD800 || cp > 0xDFFF {
            text.clear();
            out.clear();
            text.append("http://a");
            var one: i64[>..] = [];
            one.push(cp);
            url::cps_utf8(text, one[..]);
            text.append("b.com/");
            if url::normalize(out, text[..]) { print(out[..]); } else { print("ERR"); }
        }
        cp += 1;
    }
    return 0;
}
