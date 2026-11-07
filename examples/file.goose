// file: URLs round-trip between href text and a file path.
// Run with: goose run examples/file.goose
import std;
import url from "..";

fn main() {
    var href: u8[>..] = [];
    url::path_to_file_url(href, "/home/ada/a b.txt", false);
    print("posix href: ", href);

    href = [];
    url::path_to_file_url(href, "C:\\Users\\ada\\a b.txt", true);
    print("windows href: ", href);

    var p: u8[>..] = [];
    let ok1 = url::file_url_to_path(p, "file:///home/ada/a%20b.txt", false);
    print("posix path: ", ok1, " ", p);

    p = [];
    let ok2 = url::file_url_to_path(p, "file:///c:/Users/ada/x.txt", true);
    print("windows path: ", ok2, " ", p);

    p = [];
    let ok3 = url::file_url_to_path(p, "file://server/share/a.txt", true);
    print("unc path: ", ok3, " ", p);

    p = [];
    let ok4 = url::file_url_to_path(p, "http://a/b", false);
    print("not a file URL: ", ok4);
    return 0;
}
