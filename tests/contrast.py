#!/usr/bin/env python3
"""Verifica la política de contraste de icloud-glass.

El panel es translúcido sobre un wallpaper arbitrario, así que medir el texto contra
el color de `surface` no demuestra nada: lo que ve el ojo es `surface` compuesto con
su alpha sobre el wallpaper. Con un alpha fijo el problema no tiene solución — para
garantizar 4.5:1 sobre cualquier fondo haría falta alpha >= 0.93, o sea opaco, y eso
elimina el efecto Liquid Glass.

La política que sí funciona, y que este script comprueba, tiene tres partes:

  1. Los colores de texto deben cumplir AA sobre su superficie OPACA. Si no lo hacen,
     el token está mal elegido y ningún alpha lo arregla.
  2. El tema se elige según la luminancia del wallpaper (oscuro sobre fondos oscuros,
     claro sobre fondos claros). Con esa elección el alpha necesario para mantener
     legible el texto nunca pasa de ~0.42, y es 0 en los extremos.
  3. Los colores semánticos (accent/danger/success) son MARCAS, no texto: puntos de
     calendario, barras de color, círculos de check, iconos. WCAG 1.4.11 les pide 3:1,
     no 4.5:1, porque el texto que los acompaña nunca depende del color (el contrato
     ya exige icono + texto). Y **solo pueden pintarse sobre `surfaceRaised`**: sobre
     el cristal desnudo bajan a 1.0-1.7:1, que es invisible. El cristal es el
     contenedor; todo lo que lleva color va en una fila sólida.

`Config.qml` implementa (2) calculando el alpha efectivo como
`max(surfaceAlpha configurado, alpha mínimo exigido por el wallpaper)`.
"""

import json
import re
import sys
from pathlib import Path

MIN_PRIMARY = 4.5    # texto principal, AA
MIN_MUTED = 3.0      # texto secundario
MIN_SEMANTIC = 3.0   # accent/danger/success: son MARCAS, no texto (WCAG 1.4.11)
MIN_RAISED_SEPARATION = 1.1  # surfaceRaised debe distinguirse de surface

# Techo de alpha que aceptamos con la elección automática de tema. Por encima de
# esto el panel deja de parecer cristal, que es justo lo que se quería evitar.
MAX_ADAPTIVE_ALPHA = 0.55

SEMANTIC_TOKENS = ("accent", "danger", "success")


def hex_to_rgb(value):
    m = re.fullmatch(r"#([0-9A-Fa-f]{6})", value.strip())
    if not m:
        raise ValueError(f"color no válido: {value!r}")
    h = m.group(1)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def composite(fg_rgb, alpha, bg_rgb):
    return tuple(round(f * alpha + b * (1 - alpha)) for f, b in zip(fg_rgb, bg_rgb))


def relative_luminance(rgb):
    ch = []
    for c in rgb:
        s = c / 255
        ch.append(s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4)
    return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]


def contrast_ratio(a, b):
    la, lb = relative_luminance(a), relative_luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def min_alpha_for(surface_rgb, requirements, backdrop_rgb):
    """Alpha mínimo (0..1, paso 0.01) para cumplir todas las parejas (color, umbral)."""
    alpha = 0.0
    while alpha <= 1.0:
        eff = composite(surface_rgb, alpha, backdrop_rgb)
        if all(contrast_ratio(fg, thr_fg) >= thr
               for fg, thr in requirements
               for thr_fg in [eff]):
            return round(alpha, 2)
        alpha += 0.01
    return 1.0


def load_tokens(repo_root):
    path = repo_root / "quickshell/.config/quickshell/icloud-glass/shell.json.example"
    colors = json.loads(path.read_text()).get("colors")
    if not colors or not {"dark", "light"} <= set(colors):
        raise SystemExit(f"{path} no tiene colors.dark y colors.light")
    return colors


def check_opaque_colors(colors, failures):
    """(1) Los colores deben cumplir AA sobre su superficie opaca."""
    print("1. Colores sobre la superficie OPACA (si esto falla, el token está mal)")
    print(f"   {'tema':6} {'token':16} {'ratio':>8}  {'mín':>5}")
    for theme in ("dark", "light"):
        t = colors[theme]
        surface = hex_to_rgb(t["surface"])
        raised = hex_to_rgb(t.get("surfaceRaised", t["surface"]))
        raised_alpha = float(t.get("surfaceRaisedAlpha", 1.0))
        checks = [("onSurface", surface, MIN_PRIMARY),
                  ("onSurfaceMuted", surface, MIN_MUTED)]
        # Los semánticos se miden sobre surfaceRaised ya compuesta sobre el peor
        # wallpaper, que es la situación real en la que se ven.
        worst_raised = min(
            (composite(raised, raised_alpha, b) for b in [(0, 0, 0), (255, 255, 255)]),
            key=lambda eff: min(contrast_ratio(hex_to_rgb(t[tok]), eff)
                                for tok in SEMANTIC_TOKENS if tok in t))
        checks += [(tok, worst_raised, MIN_SEMANTIC) for tok in SEMANTIC_TOKENS]
        for token, bg, threshold in checks:
            if token not in t:
                failures.append(f"[{theme}] falta el token '{token}'")
                continue
            ratio = contrast_ratio(hex_to_rgb(t[token]), bg)
            ok = ratio >= threshold
            print(f"   {theme:6} {token:16} {ratio:6.2f}:1  {threshold:4.1f}  "
                  f"{'OK' if ok else 'FALLA'}")
            if not ok:
                failures.append(
                    f"[{theme}] {token} solo da {ratio:.2f}:1 sobre su superficie "
                    f"opaca (mínimo {threshold}:1). Ningún alpha arregla esto: "
                    f"hay que oscurecer o aclarar el token.")


def check_adaptive_alpha(colors, failures):
    """(2) Con elección automática de tema, el alpha necesario debe seguir siendo bajo."""
    print()
    print("2. Alpha mínimo según la luminancia del wallpaper, eligiendo tema")
    print(f"   {'L':>4} {'α oscuro':>9} {'α claro':>8}   {'tema':7} {'α final':>8}")
    peak, peak_lum = 0.0, None
    for lum in range(0, 256, 16):
        backdrop = (lum, lum, lum)
        per_theme = {}
        for theme in ("dark", "light"):
            t = colors[theme]
            reqs = [(hex_to_rgb(t["onSurface"]), MIN_PRIMARY),
                    (hex_to_rgb(t["onSurfaceMuted"]), MIN_MUTED)]
            per_theme[theme] = min_alpha_for(hex_to_rgb(t["surface"]), reqs, backdrop)
        chosen = "oscuro" if per_theme["dark"] <= per_theme["light"] else "claro"
        final = min(per_theme["dark"], per_theme["light"])
        if final > peak:
            peak, peak_lum = final, lum
        if lum % 32 == 0:
            print(f"   {lum:4} {per_theme['dark']:9.2f} {per_theme['light']:8.2f}   "
                  f"{chosen:7} {final:8.2f}")
    print(f"   peor caso: alpha {peak:.2f} con un wallpaper de luminancia {peak_lum}")
    if peak > MAX_ADAPTIVE_ALPHA:
        failures.append(
            f"El alpha adaptativo llega a {peak:.2f} (luminancia {peak_lum}), por "
            f"encima del techo {MAX_ADAPTIVE_ALPHA}: el panel dejaría de parecer "
            f"cristal. Hay que subir el contraste de los tokens de texto.")
    return peak


def check_raised(colors, failures):
    """(3) surfaceRaised se distingue del cristal, y las marcas NO valen sobre el cristal."""
    print()
    print("3. surfaceRaised: separación del cristal, y por qué las marcas van encima")
    for theme in ("dark", "light"):
        t = colors[theme]
        if "surfaceRaised" not in t:
            failures.append(f"[{theme}] falta surfaceRaised")
            continue
        alpha = float(t.get("surfaceAlpha", 1.0))
        raised_alpha = float(t.get("surfaceRaisedAlpha", alpha))
        surface, raised = hex_to_rgb(t["surface"]), hex_to_rgb(t["surfaceRaised"])
        backdrops = [(0, 0, 0), (255, 255, 255)]

        worst_sep = min(
            contrast_ratio(composite(raised, raised_alpha, b),
                           composite(surface, alpha, b))
            for b in backdrops)
        # Lo mismo medido sobre el cristal desnudo, para dejar constancia de por qué
        # existe la regla: aquí las marcas son invisibles.
        on_glass = min(
            contrast_ratio(hex_to_rgb(t[tok]), composite(surface, alpha, b))
            for tok in SEMANTIC_TOKENS if tok in t for b in backdrops)
        print(f"   {theme:6} separación raised/cristal {worst_sep:.2f}:1 "
              f"(mín {MIN_RAISED_SEPARATION}) · marca sobre cristal desnudo: "
              f"{on_glass:.2f}:1 → por eso va sobre raised")
        if worst_sep < MIN_RAISED_SEPARATION:
            failures.append(
                f"[{theme}] surfaceRaised no se distingue de surface "
                f"({worst_sep:.2f}:1): las filas se pierden en el cristal.")


def main():
    repo_root = Path(__file__).resolve().parent.parent
    colors = load_tokens(repo_root)
    failures = []

    check_opaque_colors(colors, failures)
    check_adaptive_alpha(colors, failures)
    check_raised(colors, failures)

    if failures:
        print("\nIncumplimientos:", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1
    print("\nLa política de contraste se cumple en ambos temas.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
