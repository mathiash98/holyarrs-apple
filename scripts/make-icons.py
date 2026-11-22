#!/usr/bin/env python3
"""Generates the app icon asset catalog from the HolyArrs brand mark (layered for visionOS and tvOS parallax).
Needs rsvg-convert (brew install librsvg). Run: python3 scripts/make-icons.py"""
import json, os, subprocess, shutil

ROOT = os.path.join(os.path.dirname(__file__), "..", "HolyArrs", "Assets.xcassets")
BG = '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#25272D"/><stop offset="1" stop-color="#101114"/></linearGradient></defs><rect x="{x}" y="{y}" width="{w}" height="{h}" fill="url(#g)"/>'
DIAMOND = ('<defs><clipPath id="nc"><rect x="17.5" y="17.5" width="65" height="65" rx="4" transform="rotate(45 50 50)"/></clipPath></defs>'
           '<g clip-path="url(#nc)"><rect width="100" height="100" fill="#1C1D21"/>'
           '<path d="M50 0 C42 18 46 32 58 41 C70 50 66 70 54 100 L110 100 L110 0 Z" fill="#F23A2E"/>'
           '<path d="M50 0 C42 18 46 32 58 41 C70 50 66 70 54 100 L110 100 L110 0 Z" fill="#55585E" transform="rotate(180 50 50)"/></g>'
           '<rect x="17.5" y="17.5" width="65" height="65" rx="4" transform="rotate(45 50 50)" fill="none" stroke="#3a3d44" stroke-width="1.2"/>')
STAR = '<path d="M50 28 Q54.5 45.5 72 50 Q54.5 54.5 50 72 Q45.5 54.5 28 50 Q45.5 45.5 50 28 Z" fill="#FFFFFF" transform="translate(0 -1.2)"/>'

def svg(w, h, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'

def mark(w, h, scale, inner):
    # Places the 100x100 mark centered in a w x h canvas at `scale` (fraction of the short side).
    s = min(w, h) * scale / 100
    return f'<g transform="translate({(w - 100 * s) / 2} {(h - 100 * s) / 2}) scale({s})">{inner}</g>'

def render(path, w, h, body, opaque=False):
    tmp = path + ".svg"
    open(tmp, "w").write(svg(w, h, body))
    subprocess.run(["rsvg-convert", "-w", str(w), "-h", str(h), "-o", path, tmp], check=True)
    os.remove(tmp)
    if opaque:  # back layers must not have alpha
        subprocess.run(["magick", path, "-background", "#16171B", "-alpha", "remove", "-alpha", "off", path], check=True)

def contents(d, obj):
    os.makedirs(d, exist_ok=True)
    json.dump(obj, open(os.path.join(d, "Contents.json"), "w"), indent=2)

INFO = {"author": "xcode", "version": 1}

def stack(d, w, h, scales, scale_mark, layers):
    """An image stack (tvOS .imagestack or visionOS .solidimagestack) with layers Back/Middle/Front."""
    contents(d, {"info": INFO, "layers": [{"filename": f"{n}.imagestacklayer"} for n, _ in layers]})
    for name, kind in layers:
        ld = os.path.join(d, f"{name}.imagestacklayer")
        contents(ld, {"info": INFO})
        cd = os.path.join(ld, "Content.imageset")
        imgs = []
        for sc in scales:
            fn = f"{name.lower()}{'' if sc == 1 else f'@{sc}x'}.png"
            W, H = w * sc, h * sc
            body = {"back": BG.format(x=0, y=0, w=W, h=H),
                    "middle": mark(W, H, scale_mark, DIAMOND),
                    "front": mark(W, H, scale_mark, STAR)}[kind]
            os.makedirs(cd, exist_ok=True)
            render(os.path.join(cd, fn), W, H, body, opaque=(kind == "back"))
            e = {"filename": fn, "idiom": "tv", "scale": f"{sc}x"} if w != h else {"filename": fn, "idiom": "vision", "scale": "2x"}
            imgs.append(e)
        contents(cd, {"images": imgs, "info": INFO})

if os.path.isdir(ROOT):
    shutil.rmtree(ROOT)
contents(ROOT, {"info": INFO})
L3 = [("Front", "front"), ("Middle", "middle"), ("Back", "back")]

# visionOS: a solid image stack, 1024x1024 per layer; the system masks it to a circle.
stack(os.path.join(ROOT, "AppIcon.solidimagestack"), 1024, 1024, [1], 0.78, L3)

# tvOS brand assets: App Icon (400x240 @1x/@2x), App Store icon (1280x768), Top Shelf (1920x720, 2320x720).
BA = os.path.join(ROOT, "App Icon & Top Shelf Image.brandassets")
contents(BA, {"assets": [
    {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
    {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
    {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
    {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
], "info": INFO})
stack(os.path.join(BA, "App Icon.imagestack"), 400, 240, [1, 2], 0.82, L3)
stack(os.path.join(BA, "App Icon - App Store.imagestack"), 1280, 768, [1], 0.82, L3)
for name, (w, h) in {"Top Shelf Image": (1920, 720), "Top Shelf Image Wide": (2320, 720)}.items():
    d = os.path.join(BA, f"{name}.imageset")
    imgs = []
    for sc in (1, 2):
        fn = f"topshelf{'-wide' if 'Wide' in name else ''}{'' if sc == 1 else '@2x'}.png"
        W, H = w * sc, h * sc
        os.makedirs(d, exist_ok=True)
        render(os.path.join(d, fn), W, H, BG.format(x=0, y=0, w=W, h=H) + mark(W, H, 0.6, DIAMOND + STAR), opaque=True)
        imgs.append({"filename": fn, "idiom": "tv", "scale": f"{sc}x"})
    contents(d, {"images": imgs, "info": INFO})
print("icons written to", os.path.abspath(ROOT))
