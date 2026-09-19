#!/usr/bin/env bash
# build-shaders.sh — compila los .frag de icloud-glass a .qsb (Qt Shader Baker).
#
# Idempotente: se puede ejecutar tantas veces como se quiera; solo recompila si el
# .frag es más nuevo que el .qsb existente (o si falta el .qsb), a menos que se pase
# --force. Los .qsb generados se commitean al repo para que instalar icloud-glass
# no requiera tener Qt de desarrollo instalado en la máquina destino.
#
# Uso:
#   ./build-shaders.sh            # compila lo que haga falta
#   ./build-shaders.sh --force    # recompila todo
#
# Requiere `qsb` (Qt Shader Baker), del paquete Arch `qt6-shadertools`
# (pacman -S qt6-shadertools). En Ubuntu/Debian de desarrollo: `qt6-shader-baker`.
#
# Targets generados (cubren el runtime RHI de Quickshell/Qt Quick en Linux+Vulkan/GL,
# y de paso Windows/macOS si algún día hiciera falta):
#   SPIR-V 100, GLSL "300 es,140", HLSL 50, MSL 12

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        *) echo "Uso: $0 [--force]" >&2; exit 2 ;;
    esac
done

# Localiza qsb: puede estar en PATH directamente, o (en Debian/Ubuntu con paquetes
# qt6-*) bajo /usr/lib/qt6/bin, que no siempre está en PATH.
QSB_BIN=""
if command -v qsb >/dev/null 2>&1; then
    QSB_BIN="qsb"
elif [ -x /usr/lib/qt6/bin/qsb ]; then
    QSB_BIN="/usr/lib/qt6/bin/qsb"
else
    for candidate in /usr/lib/qt6*/bin/qsb /opt/qt6*/bin/qsb; do
        if [ -x "$candidate" ]; then
            QSB_BIN="$candidate"
            break
        fi
    done
fi

if [ -z "$QSB_BIN" ]; then
    cat >&2 <<'EOF'
ERROR: no se encuentra `qsb` (Qt Shader Baker).

Instálalo con:
  Arch Linux : sudo pacman -S qt6-shadertools
  Ubuntu/Deb : sudo apt-get install qt6-shader-baker qt6-shadertools-dev

Si ya tienes Qt6 instalado pero `qsb` no está en el PATH, prueba a añadir el
directorio de binarios de Qt6 (p.ej. /usr/lib/qt6/bin) a tu PATH.

Los .qsb ya compilados se commitean al repo, así que si no vas a modificar el
shader no necesitas ejecutar este script: basta con instalar icloud-glass tal cual.
EOF
    exit 1
fi

echo "Usando qsb: $QSB_BIN ($("$QSB_BIN" --version 2>&1 | head -1))"

compiled=0
skipped=0
for frag in "$SCRIPT_DIR"/*.frag; do
    [ -e "$frag" ] || continue
    out="${frag}.qsb"
    if [ "$FORCE" -eq 0 ] && [ -e "$out" ] && [ "$out" -nt "$frag" ]; then
        echo "  = $(basename "$frag") -> $(basename "$out") (sin cambios, omitido)"
        skipped=$((skipped + 1))
        continue
    fi
    echo "  > $(basename "$frag") -> $(basename "$out")"
    "$QSB_BIN" \
        --glsl "300 es,140" \
        --hlsl 50 \
        --msl 12 \
        -o "$out" \
        "$frag"
    compiled=$((compiled + 1))
done

echo "Listo: $compiled compilado(s), $skipped sin cambios."
