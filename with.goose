// The URL setters of the url package, on text.
//
// Each with_ function takes one href and one new value for one part. It
// writes the new href into out, as the setter of Node does on a URL
// object. It gives false and leaves out unchanged when WHATWG ignores the
// value, and when the href is not a URL. The value is encoded with the
// encode set of its part. The Url setters of set.goose store the value as
// given, so they check it and never encode it.
namespace url;

import std;

const W_SCHEME: i64 = 0;
const W_USERNAME: i64 = 1;
const W_PASSWORD: i64 = 2;
const W_HOST: i64 = 3;
const W_PORT: i64 = 4;
const W_PATH: i64 = 5;
const W_QUERY: i64 = 6;
const W_FRAGMENT: i64 = 7;

// with_part sets the part named by which. The wrappers below name it.
fn with_part(out: u8[>..]&, href: const u8[:], which: i64, value: const u8[:]) -> bool {
    var n: u8[>..] = [];
    if !normalize(n, href) { return false; }
    let bs = n[..];
    let si = scheme_end(bs);
    let sch = bs[..si];
    let isfile = sch == "file";
    let special = default_port(sch) >= 0 || isfile;
    let has_auth = bs.len >= si + 3 && bs[si + 1] == '/' && bs[si + 2] == '/';
    var aend: i64 = si + 1;
    if has_auth {
        aend = si + 3;
        while aend < bs.len && bs[aend] != '/' && bs[aend] != '?' && bs[aend] != '#' { aend += 1; }
    }
    var pend = aend;
    while pend < bs.len && bs[pend] != '?' && bs[pend] != '#' { pend += 1; }
    var qend = pend;
    while qend < bs.len && bs[qend] != '#' { qend += 1; }
    // The parts of the authority.
    var user: u8[>..] = [];
    var pass: u8[>..] = [];
    var host: u8[>..] = [];
    var port: u8[>..] = [];
    if has_auth {
        let auth = bs[si + 3..aend];
        var at: i64 = -1;
        for c, i in auth { if c == '@' { at = i; } }
        if at >= 0 {
            let ui = auth[..at];
            var k: i64 = ui.len;
            for c, i in ui { if c == ':' { k = i; break; } }
            user.append(ui[..k]);
            if k < ui.len { pass.append(ui[k + 1..]); }
        }
        let hp = auth[at + 1..];
        var he: i64 = hp.len;
        if hp.len > 0 && hp[0] == '[' {
            // he is after the bracket; a port follows after a colon.
            var j: i64 = 0;
            while j < hp.len && hp[j] != ']' { j += 1; }
            he = j + 1;
            host.append(hp[..he]);
            if he < hp.len { port.append(hp[he + 1..]); }
        } else {
            for c, i in hp { if c == ':' { he = i; break; } }
            host.append(hp[..he]);
            if he < hp.len { port.append(hp[he + 1..]); }
        }
    }
    var path: u8[>..] = [];
    path.append(bs[aend..pend]);
    var query: u8[>..] = [];
    query.append(bs[pend..qend]);
    var frag: u8[>..] = [];
    frag.append(bs[qend..]);
    var nsch: u8[>..] = [];
    nsch.append(sch);
    let opaque = !has_auth && !(path.len > 0 && path[0] == '/');
    var auth_new = has_auth;
    let cred = user.len > 0 || pass.len > 0;

    if which == W_SCHEME {
        // The value up to the first colon, in lower case.
        var e: i64 = value.len;
        for c, i in value { if c == ':' { e = i; break; } }
        var v: u8[>..] = [];
        push_lower(v, value[..e]);
        if v.len == 0 || !is_letter(v[0]) { return false; }
        for c in v { if !is_scheme_char(c) { return false; } }
        let nspecial = default_port(v[..]) >= 0 || v[..] == "file";
        if nspecial != special { return false; }
        if v[..] == "file" && (cred || port.len > 0) { return false; }
        if isfile && host.len == 0 { return false; }
        nsch.clear();
        nsch.append(v[..]);
    } else if which == W_USERNAME || which == W_PASSWORD {
        if !has_auth || host.len == 0 || isfile { return false; }
        var enc: u8[>..] = [];
        n_encode(enc, value, if which == W_USERNAME { 3 } else { 4 });
        if which == W_USERNAME { user.clear(); user.append(enc[..]); }
        else { pass.clear(); pass.append(enc[..]); }
    } else if which == W_HOST {
        if opaque { return false; }
        // The host ends at a slash, a ? or a #; a backslash too for a
        // special scheme. A colon outside brackets makes the value void.
        var e: i64 = value.len;
        for c, i in value {
            if c == '/' || c == '?' || c == '#' || (special && c == '\\') { e = i; break; }
        }
        let hv = value[..e];
        // A host holds no @. Node ignores such a value, because the @ would
        // split the userinfo from the host.
        for c in hv { if c == '@' { return false; } }
        if hv.len > 0 && hv[0] != '[' {
            for c in hv { if c == ':' { return false; } }
        }
        if hv.len == 0 && (special && !isfile || cred || port.len > 0 || !has_auth) { return false; }
        host.clear();
        host.append(hv);
        auth_new = true;
    } else if which == W_PORT {
        if !has_auth || host.len == 0 || isfile { return false; }
        var d: i64 = 0;
        while d < value.len && is_digit(value[d]) { d += 1; }
        if value.len > 0 && d == 0 { return false; }
        // Leading zeros count as the same number.
        let pv, ok = n_port(value[..d]);
        if !ok { return false; }
        port.clear();
        if value.len > 0 { format(port, pv); }
    } else if which == W_PATH {
        if opaque { return false; }
        path.clear();
        var tmp: u8[>..] = [];
        for c in value {
            if c == '?' { tmp.append("%3F"); }
            else if c == '#' { tmp.append("%23"); }
            else { tmp.push(c); }
        }
        if tmp.len == 0 && !has_auth { tmp.push('/'); }
        if tmp.len > 0 && !(tmp[0] == '/' || (special && tmp[0] == '\\')) { path.push('/'); }
        path.append(tmp[..]);
    } else if which == W_QUERY {
        query.clear();
        var v: const u8[:] = value;
        if v.len > 0 && v[0] == '?' { v = v[1..]; }
        if value.len > 0 {
            query.push('?');
            for c in v {
                if c == '#' { query.append("%23"); } else { query.push(c); }
            }
        }
    } else {
        frag.clear();
        var v: const u8[:] = value;
        if v.len > 0 && v[0] == '#' { v = v[1..]; }
        if value.len > 0 {
            frag.push('#');
            frag.append(v);
        }
    }

    var text: u8[>..] = [];
    text.append(nsch[..]);
    text.push(':');
    if auth_new {
        text.append("//");
        if user.len > 0 || pass.len > 0 {
            text.append(user[..]);
            if pass.len > 0 {
                text.push(':');
                text.append(pass[..]);
            }
            text.push('@');
        }
        text.append(host[..]);
        if port.len > 0 {
            text.push(':');
            text.append(port[..]);
        }
    }
    // A path of two slashes with no host would read as a host.
    if !auth_new && path.len >= 2 && path[0] == '/' && path[1] == '/' { text.append("/."); }
    text.append(path[..]);
    text.append(query[..]);
    text.append(frag[..]);
    return normalize(out, text[..]);
}

fn with_scheme(out: u8[>..]&, href: const u8[:], v: const u8[:]) -> bool { return with_part(out, href, W_SCHEME, v); }
fn with_username(out: u8[>..]&, href: const u8[:], v: const u8[:]) -> bool { return with_part(out, href, W_USERNAME, v); }
fn with_password(out: u8[>..]&, href: const u8[:], v: const u8[:]) -> bool { return with_part(out, href, W_PASSWORD, v); }
fn with_host(out: u8[>..]&, href: const u8[:], v: const u8[:]) -> bool { return with_part(out, href, W_HOST, v); }
fn with_port(out: u8[>..]&, href: const u8[:], v: const u8[:]) -> bool { return with_part(out, href, W_PORT, v); }
fn with_path(out: u8[>..]&, href: const u8[:], v: const u8[:]) -> bool { return with_part(out, href, W_PATH, v); }
fn with_query(out: u8[>..]&, href: const u8[:], v: const u8[:]) -> bool { return with_part(out, href, W_QUERY, v); }
fn with_fragment(out: u8[>..]&, href: const u8[:], v: const u8[:]) -> bool { return with_part(out, href, W_FRAGMENT, v); }
