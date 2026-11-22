"""Render the README cards (animated SVGs) into docs/cards/. Standard library only. Run: python3 docs/render.py

Night-blue cards with Instrument Serif, Geist and Geist Mono (SIL OFL, docs/fonts/). GitHub shows these through <img>,
so only inline CSS animation and data-URI fonts work. Every element's resting style is its final state and animations
only run *from* hidden, so a viewer that doesn't animate still shows the full card.
"""
import base64
import os
import re
import xml.dom.minidom
from html import escape

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "cards")

BG, BG2, FG = "#030b1a", "#071330", "#ecebe6"
LINE = "rgba(236,235,230,.14)"
ACCENT = "#4f83ff"
W, GAP = 880, 14  # README column width; transparent space under each card

SERIF, SANS, MONO = "'Instrument Serif',Georgia,serif", "Geist,system-ui,sans-serif", "'Geist Mono',ui-monospace,Menlo,monospace"
FONTS = {"serif": ("Instrument Serif", "normal", 400), "serif-italic": ("Instrument Serif", "italic", 400),
         "sans": ("Geist", "normal", 400), "sans-600": ("Geist", "normal", 600), "mono": ("Geist Mono", "normal", 400)}

HERO = {
    "label": "MACOS APP · UNOFFICIAL",
    "first": "WhatsApp+", "last": "in navy",
    "blurb": "WhatsApp Web in a native Mac window: one calm navy theme, up to three numbers, and none of the clutter.",
    "link": "macOS 15+ · Swift · one file",
}
# (file, label, big text, blurb, fill, ink)
TILES = [
    ("tile-numbers", "NUMBERS", "Up to 3", "Each number stays logged in, with its own unread badge in the title bar.", "#0c1d45", FG),
    ("tile-theme", "THEME", "Navy", "WhatsApp's own colors remapped to one quiet navy palette, everywhere.", "#1c3a7c", FG),
    ("tile-alerts", "NOTIFICATIONS", "Every number", "Banners say which number they came from; the Dock shows the total.", FG, BG),
    ("tile-quiet", "LESS NOISE", "Hidden", "No Channels, no Meta AI, no promo cards, no Get WhatsApp for Mac bars.", "#1c3a7c", FG),
    ("tile-glass", "TOOLBAR", "Glass", "A native Liquid Glass switcher, in line with the window buttons.", FG, BG),
    ("tile-safe", "SAFE", "Official", "Runs the real WhatsApp Web. No mods, no unofficial protocols, no tracking.", "#0c1d45", FG),
]
TITLES = [("title-look", "See it", "in action"), ("title-setup", "Set it up", "in a minute"), ("title-use", "Every", "day")]

CSS = """
.u{animation:u 1s cubic-bezier(.16,1,.3,1) backwards}
.f{animation:f 1.2s ease backwards}
.sw{animation:sw 1.8s cubic-bezier(.65,0,.35,1) forwards}
.b{transform-box:fill-box;transform-origin:50% 100%;animation:b 3.2s cubic-bezier(.3,0,.3,1) 1.6s infinite}
@keyframes u{from{opacity:0;transform:translateY(16px)}}
@keyframes f{from{opacity:0}}
@keyframes sw{to{transform:translateX(560px)}}
@keyframes b{0%,30%,100%{transform:translateY(0)}10%{transform:translateY(-16px)}20%{transform:translateY(-4px)}}
@media (prefers-reduced-motion:reduce){*{animation:none!important}}
"""


def b64(path):
    return base64.b64encode(open(os.path.join(ROOT, path), "rb").read()).decode()


def svg(w, h, body, fonts, label):
    faces = "".join(f"@font-face{{font-family:'{FONTS[k][0]}';font-style:{FONTS[k][1]};font-weight:{FONTS[k][2]};"
                    f"src:url(data:font/woff;base64,{b64(f'fonts/{k}.woff')}) format('woff')}}" for k in fonts)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:.3f}" height="{h}" viewBox="0 0 {w:.3f} {h}" '
            f'role="img" aria-label="{escape(label)}"><title>{escape(label)}</title><style>{faces}{CSS}</style>{body}</svg>')


def write(name, content):
    xml.dom.minidom.parseString(content)  # never commit a card that GitHub can't render
    with open(os.path.join(OUT, name), "w") as f:
        f.write(content)


def wrap(text, n):
    lines, cur = [], ""
    for word in text.split():
        if cur and len(cur) + 1 + len(word) > n:
            lines.append(cur)
            cur = word
        else:
            cur = f"{cur} {word}".strip()
    return lines + [cur]


def d(s):
    return f'style="animation-delay:{s:.2f}s"'


def icon(x, y, size, uid):
    """The app icon (icon.svg in the repo root), clipped to a rounded square like macOS draws it."""
    src = open(os.path.join(ROOT, "..", "icon.svg")).read()
    inner = re.sub(r"<!--.*?-->", "", re.search(r"<svg[^>]*>(.*)</svg>", src, re.S).group(1), flags=re.S)
    inner = inner.replace('id="bg"', f'id="{uid}bg"').replace("url(#bg)", f"url(#{uid}bg)") \
                 .replace('id="glyph"', f'id="{uid}gl"').replace("url(#glyph)", f"url(#{uid}gl)")
    s = size / 1024
    return (f'<defs><clipPath id="{uid}c"><rect width="1024" height="1024" rx="230"/></clipPath></defs>'
            f'<g transform="translate({x} {y}) scale({s:.4f})"><g clip-path="url(#{uid}c)">{inner}</g>'
            f'<rect x="2" y="2" width="1020" height="1020" rx="228" fill="none" stroke="#fff" stroke-opacity=".18" stroke-width="4"/></g>')


# ---- cards -----------------------------------------------------------------------
def hero():
    h = 380
    blurb = "".join(f'<tspan x="44" dy="{0 if i == 0 else 26}">{escape(l)}</tspan>' for i, l in enumerate(wrap(HERO["blurb"], 54)))
    body = f"""
<defs>
  <clipPath id="k"><rect width="{W}" height="{h}" rx="16"/></clipPath>
  <linearGradient id="v" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{BG}"/><stop offset="1" stop-color="#0b1d47"/></linearGradient>
  <radialGradient id="glow"><stop offset="0" stop-color="{ACCENT}" stop-opacity=".45"/><stop offset="1" stop-color="{ACCENT}" stop-opacity="0"/></radialGradient>
</defs>
<g clip-path="url(#k)">
  <rect width="{W}" height="{h}" fill="url(#v)"/>
  <circle class="f" {d(.3)} cx="{W - 170}" cy="{h / 2}" r="230" fill="url(#glow)"/>
</g>
<rect x=".5" y=".5" width="{W - 1}" height="{h - 1}" rx="16" fill="none" stroke="{LINE}"/>
<g class="u" {d(.45)}>{icon(W - 300, 60, 260, "h")}</g>
<g class="u" {d(.1)}><circle cx="48" cy="58" r="3.5" fill="{FG}"/>
  <text x="60" y="62" font-family="{MONO}" font-size="12" letter-spacing="1.6" fill="{FG}" fill-opacity=".72">{escape(HERO['label'])}</text></g>
<text class="u" {d(.25)} x="40" y="150" font-family="{SERIF}" font-size="92" fill="{FG}">{escape(HERO['first'])}</text>
<text class="u" {d(.4)} x="52" y="226" font-family="{SERIF}" font-style="italic" font-size="92" fill="{FG}">{escape(HERO['last'])}</text>
<text class="u" {d(.6)} y="272" font-family="{SANS}" font-size="17" fill="{FG}" fill-opacity=".86">{blurb}</text>
<text class="u" {d(.75)} x="44" y="346" font-family="{MONO}" font-size="13" fill="{FG}" fill-opacity=".8">{escape(HERO['link'])}</text>
"""
    write("hero.svg", svg(W, h + GAP, body, ["serif", "serif-italic", "sans", "mono"], f"{HERO['first']} {HERO['last']}. {HERO['blurb']}"))


def tiles():
    tw, th = W / 3, 236
    for n, (name, label, big, blurb, fill, ink) in enumerate(TILES):
        pos = n % 3
        cx, cw = pos * 14 / 3, tw - 28 / 3  # 14px gaps once the three images sit side by side
        lines = "".join(f'<text x="{cx + 24}" y="{168 + i * 20}">{escape(l)}</text>' for i, l in enumerate(wrap(blurb, 32)))
        body = f"""
<defs><clipPath id="k"><rect x="{cx}" width="{cw}" height="{th}" rx="16"/></clipPath>
  <linearGradient id="s" x2="1"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset=".5" stop-color="#fff" stop-opacity=".22"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient></defs>
<g class="u" {d(.1 + n * .1)}>
  <g clip-path="url(#k)">
    <rect x="{cx}" width="{cw}" height="{th}" fill="{fill}"/>
    <circle cx="{cx + cw - 30}" cy="{th - 30}" r="58" fill="none" stroke="{ink}" stroke-opacity=".22" stroke-width="1.5"/>
    <rect class="sw" {d(1.2 + n * .15)} x="{cx - 160}" y="-20" width="110" height="{th + 40}" fill="url(#s)"/>
  </g>
  <rect x="{cx + .5}" y=".5" width="{cw - 1}" height="{th - 1}" rx="16" fill="none" stroke="{LINE}"/>
  <text x="{cx + 24}" y="42" font-family="{MONO}" font-size="12" letter-spacing="1.5" fill="{ink}">{label}</text>
  <text x="{cx + 22}" y="126" font-family="{SERIF}" font-size="{52 if len(big) < 9 else 44}" fill="{ink}">{escape(big)}</text>
  <g font-family="{SANS}" font-size="14" fill="{ink}" fill-opacity=".85">{lines}</g>
</g>
"""
        write(f"{name}.svg", svg(tw, th + GAP, body, ["serif", "sans", "mono"], f"{label}: {big}. {blurb}"))


def notify():
    """A drawn notification banner and the Dock icon with its badge (no screenshots of anyone's screen)."""
    h = 230
    bx, by, bw, bh = 40, 92, 470, 96
    dock_x = 600
    body = f"""
<defs><clipPath id="k"><rect width="{W}" height="{h}" rx="16"/></clipPath>
  <linearGradient id="v" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{BG2}"/><stop offset="1" stop-color="#0b1d47"/></linearGradient></defs>
<g clip-path="url(#k)"><rect width="{W}" height="{h}" fill="url(#v)"/></g>
<rect x=".5" y=".5" width="{W - 1}" height="{h - 1}" rx="16" fill="none" stroke="{LINE}"/>
<text class="u" {d(.05)} x="44" y="56" font-family="{MONO}" font-size="11" letter-spacing="1.5" fill="{FG}" fill-opacity=".6">A NEW MESSAGE ON ANY NUMBER</text>
<g class="u" {d(.25)}>
  <rect x="{bx}" y="{by}" width="{bw}" height="{bh}" rx="22" fill="#fff" fill-opacity=".09" stroke="#fff" stroke-opacity=".16"/>
  {icon(bx + 18, by + 22, 52, "n")}
  <text x="{bx + 86}" y="{by + 34}" font-family="{SANS}" font-weight="600" font-size="15" fill="{FG}">Lumen Studio</text>
  <text x="{bx + bw - 20}" y="{by + 34}" text-anchor="end" font-family="{SANS}" font-size="12" fill="{FG}" fill-opacity=".55">now</text>
  <text x="{bx + 86}" y="{by + 55}" font-family="{SANS}" font-size="13" fill="{FG}" fill-opacity=".7">Studio</text>
  <text x="{bx + 86}" y="{by + 76}" font-family="{SANS}" font-size="14" fill="{FG}" fill-opacity=".9">Can we move the review to 3 pm?</text>
</g>
<g class="u" {d(.45)}>
  <rect x="{dock_x}" y="{by + 4}" width="236" height="88" rx="26" fill="#fff" fill-opacity=".07" stroke="#fff" stroke-opacity=".14"/>
  <rect x="{dock_x + 18}" y="{by + 18}" width="60" height="60" rx="14" fill="#fff" fill-opacity=".1"/>
  <rect x="{dock_x + 158}" y="{by + 18}" width="60" height="60" rx="14" fill="#fff" fill-opacity=".1"/>
  <g class="b">{icon(dock_x + 88, by + 18, 60, "d")}
    <circle cx="{dock_x + 144}" cy="{by + 22}" r="12" fill="#ff3b30"/>
    <text x="{dock_x + 144}" y="{by + 27}" text-anchor="middle" font-family="{SANS}" font-weight="600" font-size="13" fill="#fff">4</text></g>
  <circle cx="{dock_x + 118}" cy="{by + 86}" r="2.2" fill="{FG}" fill-opacity=".7"/>
</g>
<text class="u" {d(.6)} x="{dock_x + 118}" y="{h - 24}" text-anchor="middle" font-family="{SANS}" font-size="13" fill="{FG}" fill-opacity=".6">Dock: total unread, one bounce</text>
<text class="u" {d(.6)} x="{bx + bw / 2}" y="{h - 24}" text-anchor="middle" font-family="{SANS}" font-size="13" fill="{FG}" fill-opacity=".6">Banner: names the number it came from</text>
"""
    write("notify.svg", svg(W, h + GAP, body, ["sans", "sans-600", "mono"],
                            "A notification banner from the Studio number, and the Dock icon with a total unread badge of 4"))


def section_titles():
    for name, text, italic in TITLES:
        for theme, color in (("dark", FG), ("light", BG)):
            body = (f'<text class="u" x="2" y="46" font-family="{SERIF}" font-size="40" fill="{color}">{escape(text)} '
                    f'<tspan font-style="italic">{escape(italic)}</tspan></text>')
            write(f"{name}-{theme}.svg", svg(W, 66, body, ["serif", "serif-italic"], f"{text} {italic}"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    hero()
    tiles()
    notify()
    section_titles()
    print(f"rendered {len(os.listdir(OUT))} cards into {OUT}")
