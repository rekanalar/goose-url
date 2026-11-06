// The builder for the url package.
//
// build writes the text of one Url into a buffer the caller owns. A
// separator appears only when its part is not empty. The port text goes
// in as the caller holds it; a caller that wants the default port gone
// clears port_text before the call.
namespace url;

import std;

// build writes the URL text into out.
fn build(out: u8[>..]&, u: Url&) {
    out.append(u.scheme);
    if u.has_scheme {
        out.append(":");
    }
    if u.host.len > 0 {
        out.append("//");
        if u.userinfo.len > 0 {
            out.append(u.userinfo);
            out.append("@");
        }
        // The host slice of an IPv6 address holds ':', so the brackets
        // go back around it.
        var v6 = false;
        for c in u.host {
            if c == ':' { v6 = true; }
        }
        if v6 {
            out.append("[");
            out.append(u.host);
            out.append("]");
        } else {
            out.append(u.host);
        }
        if u.port_text.len > 0 {
            out.append(":");
            out.append(u.port_text);
        }
    }
    out.append(u.path);
    if u.has_query {
        out.append("?");
        out.append(u.query);
    }
    if u.fragment.len > 0 {
        out.append("#");
        out.append(u.fragment);
    }
}
