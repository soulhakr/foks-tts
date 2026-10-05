"""Builds brand/palette.json: anchors -> ramps (OKLab interpolation), themes, and a WCAG contrast report.
Run with any Python 3:  python3 build_palette.py   (writes palette.json and prints the report)."""
import colorsys, json, math, pathlib

def hex2rgb(h): h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
def rgb2hex(c): return "#%02X%02X%02X" % tuple(max(0, min(255, round(v))) for v in c)
def lin(v): v /= 255; return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
def unlin(v): v = 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055; return v * 255
def to_oklab(c):
    r, g, b = (lin(x) for x in c)
    l = 0.4122214708*r + 0.5363325363*g + 0.0514459929*b
    m = 0.2119034982*r + 0.6806995451*g + 0.1073969566*b
    s = 0.0883024619*r + 0.2817188376*g + 0.6299787005*b
    l, m, s = (x ** (1/3) for x in (l, m, s))
    return (0.2104542553*l + 0.7936177850*m - 0.0040720468*s,
            1.9779984951*l - 2.4285922050*m + 0.4505937099*s,
            0.0259040371*l + 0.7827717662*m - 0.8086757660*s)
def from_oklab(L, a, b):
    l = (L + 0.3963377774*a + 0.2158037573*b) ** 3
    m = (L - 0.1055613458*a - 0.0638541728*b) ** 3
    s = (L - 0.0894841775*a - 1.2914855480*b) ** 3
    r = 4.0767416621*l - 3.3077115913*m + 0.2309699292*s
    g = -1.2684380046*l + 2.6097574011*m - 0.3413193965*s
    bb = -0.0041960863*l - 0.7034186147*m + 1.7076147010*s
    return tuple(unlin(max(0, min(1, v))) for v in (r, g, bb))
def mix(h1, h2, t):
    a, b = to_oklab(hex2rgb(h1)), to_oklab(hex2rgb(h2))
    return rgb2hex(from_oklab(*(a[i] + (b[i] - a[i]) * t for i in range(3))))
def ramp(anchors):
    """anchors: {step: hex} for some steps; fill the rest of 50..900 by OKLab interpolation between neighbours."""
    steps = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900]
    known = sorted(anchors)
    out = {}
    for s in steps:
        if s in anchors: out[s] = anchors[s]; continue
        lo = max(k for k in known if k < s); hi = min(k for k in known if k > s)
        out[s] = mix(anchors[lo], anchors[hi], (s - lo) / (hi - lo))
    return {str(k): v for k, v in out.items()}

# --- anchors (the first four are the exact colours already used by the icon)
rust   = ramp({50: "#FDF0E6", 500: "#DE6226", 600: "#B84016", 800: "#5C200E", 900: "#22100A"})
forest = ramp({50: "#EAF3EE", 600: "#24664C", 900: "#0A241B"})
sand   = ramp({50: "#FFFAF2", 100: "#FFF3E4", 300: "#EED6BA", 800: "#3B1F14", 900: "#22100A"})

def lum(h):
    r, g, b = (lin(x) for x in hex2rgb(h)); return 0.2126*r + 0.7152*g + 0.0722*b
def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True); return (la + 0.05) / (lb + 0.05)

themes = {
  "dark":  {"background": forest["900"], "surface": forest["600"], "text": sand["50"], "text-muted": sand["300"],
            "accent": rust["500"], "on-accent": rust["900"], "border": forest["600"], "highlight": rust["500"]},
  "light": {"background": sand["50"], "surface": sand["100"], "text": rust["900"], "text-muted": sand["800"],
            "accent": rust["600"], "on-accent": sand["50"], "border": sand["300"], "highlight": rust["500"]},
}
def hsl(h):
    r, g, b = (x / 255 for x in hex2rgb(h)); hh, ll, ss = colorsys.rgb_to_hls(r, g, b); return round(hh * 360), round(ss * 100), round(ll * 100)

pairs = []
for name, t in themes.items():
    for fg, bg, kind in [("text", "background", "body text"), ("text-muted", "background", "secondary text"), ("text", "surface", "text on surface"),
                         ("accent", "background", "accent / links / icons"), ("on-accent", "accent", "button label")]:
        c = contrast(t[fg], t[bg])
        pairs.append({"theme": name, "pair": f"{fg} on {bg}", "use": kind, "fg": t[fg], "bg": t[bg], "ratio": round(c, 2),
                      "AA text (4.5)": c >= 4.5, "AA large/UI (3.0)": c >= 3.0})
out = {"name": "FOKS TTS", "rule": "60% neutrals (forest or sand), 30% secondary, 10% rust accent. Never blue, violet, or yellow-orange.",
       "tokens": {"rust": rust, "forest": forest, "sand": sand}, "themes": themes, "contrast": pairs,
       "hues_hsl_deg": {"rust-500": hsl(rust["500"]), "forest-600": hsl(forest["600"]), "sand-100": hsl(sand["100"])}}
pathlib.Path(__file__).with_name("palette.json").write_text(json.dumps(out, indent=2) + "\n")
hr, hf, hs = hsl(rust["500"])[0], hsl(forest["600"])[0], hsl(sand["100"])[0]
print(f"hues: rust {hr} deg, forest {hf} deg, sand {hs} deg; complement of rust = {(hr+180)%360} deg; forest is {abs(hf-(hr+180)%360)} deg from it (split-complement)")
for p in pairs: print(f"{p['theme']:5} {p['pair']:26} {p['ratio']:5}  AA text:{'yes' if p['AA text (4.5)'] else 'NO ':3}  AA large/UI:{'yes' if p['AA large/UI (3.0)'] else 'NO'}")
for fam, r in (("rust", rust), ("forest", forest), ("sand", sand)): print(fam, " ".join(r.values()))
