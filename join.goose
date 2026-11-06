// The joiner for the url package. RFC 3986 section 5.
//
// join resolves a reference against a base URL. The rules come from
// RFC 3986 section 5.2.2, the merged path from section 5.2.3, and the
// dot segments from section 5.2.4.
//
// The dot segment loop follows the strict left-to-right piece algorithm
// of section 5.2.4. One output buffer and one loop hold no recursion and
// no backtracking.
namespace url;

import std;

// remove_dot_segments writes path without its dot segments into out. A
// ".." at the root stays at the root. The scan uses an index, so it never
// rebinds a slice.
fn remove_dot_segments(out: u8[>..]&, path: const u8[:]) {
    var output: u8[>..] = [];
    var pos = 0;
    // A reference path that ends in a dot segment gives a path that
    // ends in a slash, per the section 5.3 examples.
    var add_slash = false;
    if path.len > 0 && path[path.len - 1] == '.' { add_slash = true; }
    if path.len > 1 && path[path.len - 2] == '.' && path[path.len - 1] == '/' { add_slash = true; }
    while pos < path.len {
        let left = path.len - pos;
        // Rule 2A: a leading "../" or "./" moves the input forward.
        if left >= 3 && path[pos] == '.' && path[pos + 1] == '.' && path[pos + 2] == '/' { pos += 3; continue; }
        if left >= 2 && path[pos] == '.' && path[pos + 1] == '/' { pos += 2; continue; }
        // Rule 2B: a leading "/./" drops the "./". A lone "/." gives "/".
        if left >= 3 && path[pos] == '/' && path[pos + 1] == '.' && path[pos + 2] == '/' { pos += 2; continue; }
        if left == 2 && path[pos] == '/' && path[pos + 1] == '.' {
            output.append("/");
            pos += 2;
            continue;
        }
        // Rule 2C: a lone "/" or "/..".
        if left == 1 && path[pos] == '/' {
            output.append("/");
            pos += 1;
            continue;
        }
        if left == 3 && path[pos] == '/' && path[pos + 1] == '.' && path[pos + 2] == '.' {
            drop_last_segment(output);
            output.append("/");
            pos += 3;
            continue;
        }
        // Rule 2D: a leading "/../" moves one segment up.
        if left >= 4 && path[pos] == '/' && path[pos + 1] == '.' && path[pos + 2] == '.' && path[pos + 3] == '/' {
            pos += 3;
            drop_last_segment(output);
            continue;
        }
        // Rule 2E: a lone "." or "..".
        if left == 1 && path[pos] == '.' { pos += 1; continue; }
        if left == 2 && path[pos] == '.' && path[pos + 1] == '.' {
            pos += 2;
            drop_last_segment(output);
            continue;
        }
        // Rule 2F: move one segment, the first through the next slash or
        // the end, from the input to the output.
        var end = pos;
        if path[pos] == '/' { end = pos + 1; }
        while end < path.len && path[end] != '/' { end += 1; }
        output.append(path[pos..end]);
        pos = end;
    }
    if add_slash && (output.len == 0 || output[output.len - 1] != '/') {
        output.append("/");
    }
    out.append(output[..]);
}

// drop_last_segment removes the last segment of the output. A ".." at
// the root leaves the root.
fn drop_last_segment(output: u8[>..]&) {
    var cut = -1;
    var k = 0;
    while k < output.len {
        if output[k] == '/' { cut = k; }
        k += 1;
    }
    if cut >= 0 {
        output.resize(cut);
    } else {
        output.clear();
    }
}

// merge_paths gives the path of a reference against the path of the
// base. The rules are RFC 3986 section 5.2.3.
fn merge_paths(out: u8[>..]&, base_path: const u8[:], ref_path: const u8[:]) {
    // An empty base path, or one with no slash, gets a "/" in front.
    var cut = -1;
    var i = 0;
    while i < base_path.len {
        if base_path[i] == '/' { cut = i; }
        i += 1;
    }
    if cut < 0 {
        out.append("/");
        out.append(ref_path);
        return;
    }
    out.append(base_path[..cut + 1]);
    out.append(ref_path);
}

// join resolves the reference against the base and writes the result
// into out. It returns false when the base is not an absolute URL or the
// reference is not valid.
fn join(out: u8[>..]&, base_text: const u8[:], ref_text: const u8[:]) -> bool {
    let base, ok = parse(base_text);
    if !ok { return false; }
    let ref, rok = parse_ref(ref_text);
    if !rok { return false; }

    // The path buffers come first, so they outlive the target.
    var path_buf: u8[>..] = [];
    var merged_buf: u8[>..] = [];
    var clean_buf: u8[>..] = [];
    var target = Url { scheme: "", userinfo: "", host: "", port: -1, port_text: "", path: "", query: "", fragment: "", has_scheme: false, has_authority: false, has_query: false };

    if ref.has_scheme {
        target = ref;
        // Rule 5.2.2: a strict parser drops the dot segments of an
        // absolute reference path too.
        if target.path.len > 0 {
            remove_dot_segments(clean_buf, target.path);
            target.path = clean_buf[..];
        }
    } else if ref.has_authority {
        target.scheme = base.scheme;
        target.has_scheme = true;
        target.userinfo = ref.userinfo;
        target.host = ref.host;
        target.port = ref.port;
        target.port_text = ref.port_text;
        remove_dot_segments(clean_buf, ref.path);
        target.path = clean_buf[..];
        target.query = ref.query;
        target.has_query = ref.has_query;
        target.fragment = ref.fragment;
    } else if ref.path.len == 0 {
        target.scheme = base.scheme;
        target.has_scheme = true;
        target.userinfo = base.userinfo;
        target.host = base.host;
        target.port = base.port;
        target.port_text = base.port_text;
        target.path = base.path;
        if ref.has_query {
            target.query = ref.query;
            target.has_query = true;
        } else {
            target.query = base.query;
            target.has_query = base.has_query;
        }
        target.fragment = ref.fragment;
    } else {
        target.scheme = base.scheme;
        target.has_scheme = true;
        target.userinfo = base.userinfo;
        target.host = base.host;
        target.port = base.port;
        target.port_text = base.port_text;
        if ref.path[0] == '/' {
            remove_dot_segments(clean_buf, ref.path);
        } else {
            merge_paths(merged_buf, base.path, ref.path);
            remove_dot_segments(clean_buf, merged_buf[..]);
        }
        target.path = clean_buf[..];
        target.query = ref.query;
        target.has_query = ref.has_query;
        target.fragment = ref.fragment;
    }
    build(out, target);
    return true;
}
