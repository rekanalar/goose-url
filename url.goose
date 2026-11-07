// url - URL parsing and building for Goose.
//
// The package parses an absolute URL into its seven parts, rebuilds the
// text from the parts, encodes and decodes percent escapes, and joins a
// relative reference against a base URL. The rules are RFC 3986.
//
// The parts are slices over the input text. The input text must outlive
// the Url value.
//
// The repository is goose-url. The import name is "url".
namespace url;

import std;
import parse;
import build;
import percent;
import join;
import query;
import set;
import edit;
import redact;
import normalize;
import punycode;
import idna_data;
import idna;
import fileurl;
import href;
import with;
