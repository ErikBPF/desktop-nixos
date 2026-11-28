# Pick the hardware capture source for the NoiseTorch chain.
# Preference: Hollyland wireless > Focusrite Scarlett 2i2 > built-in > highest
# priority.session. Dictation and calls share this chain, so the order is
# explicit instead of implicit in PipeWire priorities.
def n: (.info.props["node.name"] // "");
def d: (.info.props["node.description"] // "");
def ident: ((n + " " + d) | ascii_downcase);
def rank:
  ident
  | if test("hollyland") then 0
    elif test("scarlett|focusrite") then 1
    elif test("built-in") then 2
    else 3 end;

[ .[]
  | select(.info.props["media.class"] == "Audio/Source")
  | select(n | startswith("alsa_input.")) ]
| sort_by(rank, -(.info.props["priority.session"] // 0))
| (.[0] | n) // empty
