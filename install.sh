#!/usr/bin/env bash
# install.sh — instalador de los dotfiles de icloud-glass (paquetes GNU Stow).
#
# Idempotente: puede ejecutarse varias veces sin romper nada. Nunca
# sobrescribe en silencio un archivo que ya exista fuera de este repo.
#
# Ver docs/icloud-glass.md para la documentación completa.

set -euo pipefail

# --------------------------------------------------------------------------
# Configuración / constantes
# --------------------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly SCRIPT_DIR

# Paquetes de stow, en el orden en que se enlazan. hypr/ contiene la config
# de Hyprland (Lua + legacy); no incluye "docs", "tests" ni los propios
# archivos de este agente (README.md, install.sh, .stow-local-ignore,
# .gitignore), que .stow-local-ignore ya excluye de cualquier paquete.
readonly PACKAGES=(quickshell icloud-glass vdirsyncer khal todoman systemd hypr)

DRY_RUN=0
FORCE=0
UNINSTALL=0

readonly XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# --------------------------------------------------------------------------
# Utilidades de salida
# --------------------------------------------------------------------------

log()  { printf '%s\n' "$*"; }
info() { printf '  -> %s\n' "$*"; }
warn() { printf '  !! %s\n' "$*" >&2; }
err()  { printf 'ERROR: %s\n' "$*" >&2; }

run() {
    # Ejecuta un comando salvo en --dry-run, donde solo lo imprime.
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '  [dry-run] %s\n' "$*"
        return 0
    fi
    "$@"
}

# --------------------------------------------------------------------------
# --help
# --------------------------------------------------------------------------

usage() {
    cat <<'EOF'
Uso: ./install.sh [opciones]

Instala (o desinstala) los dotfiles de icloud-glass mediante GNU Stow:
detecta e instala dependencias, enlaza los paquetes de este repo en $HOME,
crea el shell.json.example del usuario si no existe, y activa el timer de
sincronización systemd.

Opciones:
  --dry-run      No ejecuta nada; imprime cada paso que haría.
  --force        Sigue adelante aunque no se detecte Arch Linux.
  --uninstall    Desenlaza todos los paquetes de stow, desactiva el timer,
                 e imprime qué datos NO se borran (y cómo borrarlos a mano).
  -h, --help     Muestra esta ayuda.

Pasos que realiza (instalación normal):
  1. Comprueba que el sistema es Arch Linux (o avisa y sigue con --force).
  2. Instala dependencias: stow, quickshell (AUR), vdirsyncer, khal,
     todoman, libsecret, qt6-shadertools (opcional), jq.
  3. Enlaza cada paquete de stow en $HOME (nunca sobrescribe en silencio).
  4. Copia shell.json.example a
     ~/.config/quickshell/icloud-glass/shell.json solo si no existe ya.
  5. Activa `systemctl --user enable --now icloud-glass-sync.timer`.
  6. Comprueba la versión de Hyprland instalada y dice qué config usar
     (Lua >= 0.55, o hypr/legacy/icloud-glass.conf en <= 0.54).
  7. Imprime los pasos siguientes (icloud-glass-setup, require() en
     hyprland.lua, recarga de Hyprland).

Ver docs/icloud-glass.md para más detalle.
EOF
}

# --------------------------------------------------------------------------
# Parseo de argumentos
# --------------------------------------------------------------------------

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --force) FORCE=1 ;;
        --uninstall) UNINSTALL=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            err "Opción desconocida: $arg"
            usage >&2
            exit 1
            ;;
    esac
done

# --------------------------------------------------------------------------
# Paso 1: detección de distro
# --------------------------------------------------------------------------

check_distro() {
    log "==> Comprobando distribución..."
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        if [[ "${ID:-}" == "arch" ]] || [[ "${ID_LIKE:-}" == *arch* ]]; then
            info "Arch Linux detectado (${PRETTY_NAME:-desconocido})."
            return 0
        fi
    fi

    if [[ "$FORCE" -eq 1 ]]; then
        warn "No se detectó Arch Linux, pero se continúa por --force."
        warn "La instalación de dependencias (pacman/paru/yay) probablemente falle;"
        warn "instala manualmente los paquetes listados en 'Dependencias' de docs/icloud-glass.md."
        return 0
    fi

    err "Este instalador está pensado para Arch Linux (usa pacman/paru/yay)."
    err "Si sabes lo que haces, vuelve a ejecutar con --force para continuar de todos modos."
    exit 1
}

# --------------------------------------------------------------------------
# Paso 2: dependencias
# --------------------------------------------------------------------------

# Paquetes de los repos oficiales de Arch.
readonly OFFICIAL_PKGS=(stow vdirsyncer khal todoman libsecret jq)
# Paquetes opcionales de los repos oficiales (recompilar shaders del panel;
# no hace falta para usar el panel, solo para tocar los .qsb).
readonly OPTIONAL_OFFICIAL_PKGS=(qt6-shadertools)
# Solo disponible en AUR.
readonly AUR_PKGS=(quickshell)

detect_aur_helper() {
    if command -v paru &>/dev/null; then
        echo paru
    elif command -v yay &>/dev/null; then
        echo yay
    else
        echo ""
    fi
}

install_dependencies() {
    log "==> Instalando dependencias..."

    if ! command -v pacman &>/dev/null; then
        warn "No se encontró 'pacman'; omito la instalación automática de dependencias."
        warn "Instala manualmente: ${OFFICIAL_PKGS[*]} ${OPTIONAL_OFFICIAL_PKGS[*]} (opcional) y ${AUR_PKGS[*]} (AUR)."
        return 0
    fi

    info "Paquetes oficiales: ${OFFICIAL_PKGS[*]}"
    run sudo pacman -S --needed --noconfirm "${OFFICIAL_PKGS[@]}"

    info "Paquete opcional (recompilar shaders): ${OPTIONAL_OFFICIAL_PKGS[*]}"
    if ! run sudo pacman -S --needed --noconfirm "${OPTIONAL_OFFICIAL_PKGS[@]}"; then
        warn "No se pudo instalar ${OPTIONAL_OFFICIAL_PKGS[*]}; no es necesario salvo que"
        warn "vayas a recompilar los shaders del panel (.qsb). Continúo sin él."
    fi

    local aur_helper
    aur_helper="$(detect_aur_helper)"
    if [[ -n "$aur_helper" ]]; then
        info "Paquetes de AUR (vía $aur_helper): ${AUR_PKGS[*]}"
        run "$aur_helper" -S --needed --noconfirm "${AUR_PKGS[@]}"
    else
        warn "No se encontró 'paru' ni 'yay' (helper de AUR)."
        warn "Instala manualmente los paquetes de AUR: ${AUR_PKGS[*]}"
        warn "  (p.ej.: git clone https://aur.archlinux.org/quickshell.git && cd quickshell && makepkg -si)"
    fi
}

# --------------------------------------------------------------------------
# Paso 3: stow de cada paquete
# --------------------------------------------------------------------------

stow_package() {
    local pkg="$1"

    if [[ ! -d "$SCRIPT_DIR/$pkg" ]]; then
        warn "El paquete '$pkg' no existe en $SCRIPT_DIR; se omite."
        return 0
    fi

    info "Comprobando conflictos de '$pkg'..."
    local conflict_output
    if ! conflict_output="$(cd "$SCRIPT_DIR" && stow -n -v -t "$HOME" "$pkg" 2>&1)"; then
        if printf '%s' "$conflict_output" | grep -qi "existing target is"; then
            err "Stow no puede enlazar '$pkg': ya existen archivos reales (no symlinks) en \$HOME que chocan con este paquete:"
            printf '%s\n' "$conflict_output" | grep -i "existing target is" | sed 's/^/      /' >&2
            err "Resuélvelo a mano: mueve o borra esos archivos (o fusiona su contenido) y vuelve a ejecutar este instalador."
            err "Ejemplo: mv <archivo-en-conflicto> <archivo-en-conflicto>.bak"
            return 1
        fi
        # Otro tipo de error de stow (paquete mal formado, etc.): lo
        # mostramos tal cual y abortamos ese paquete.
        err "stow -n falló para '$pkg':"
        printf '%s\n' "$conflict_output" | sed 's/^/      /' >&2
        return 1
    fi

    info "Enlazando '$pkg' -> \$HOME"
    run bash -c "cd '$SCRIPT_DIR' && stow -R -t '$HOME' '$pkg'"
}

link_packages() {
    log "==> Enlazando paquetes con GNU Stow..."

    if ! command -v stow &>/dev/null; then
        err "'stow' no está instalado. Instálalo (paquete 'stow') y vuelve a ejecutar este script."
        exit 1
    fi

    local failed=0
    for pkg in "${PACKAGES[@]}"; do
        if ! stow_package "$pkg"; then
            failed=1
        fi
    done

    if [[ "$failed" -eq 1 ]]; then
        err "Alguno de los paquetes no se pudo enlazar (ver mensajes arriba). Resuélvelo y repite."
        exit 1
    fi
}

# --------------------------------------------------------------------------
# Paso 4: shell.json del usuario
# --------------------------------------------------------------------------

setup_shell_json() {
    log "==> Configuración del usuario (shell.json)..."

    local example="$SCRIPT_DIR/quickshell/.config/quickshell/icloud-glass/shell.json.example"
    local target="$XDG_CONFIG_HOME/quickshell/icloud-glass/shell.json"

    if [[ ! -f "$example" ]]; then
        warn "No se encontró $example; omito este paso (¿falta el paquete quickshell/ o el .example?)."
        return 0
    fi

    if [[ -e "$target" ]]; then
        info "$target ya existe (es tuyo, no se toca)."
        return 0
    fi

    info "Creando $target a partir de shell.json.example (archivo real, NO symlink)."
    run mkdir -p "$(dirname "$target")"
    run cp "$example" "$target"
}

# --------------------------------------------------------------------------
# Paso 5: systemd --user
# --------------------------------------------------------------------------

enable_timer() {
    log "==> Activando el timer de sincronización..."

    if ! command -v systemctl &>/dev/null; then
        warn "'systemctl' no disponible; activa el timer manualmente cuando puedas:"
        warn "  systemctl --user enable --now icloud-glass-sync.timer"
        return 0
    fi

    run systemctl --user daemon-reload
    if ! run systemctl --user enable --now icloud-glass-sync.timer; then
        warn "No se pudo activar icloud-glass-sync.timer. Compruébalo a mano con:"
        warn "  systemctl --user status icloud-glass-sync.timer"
        warn "  journalctl --user -u icloud-glass-sync.service"
    fi
}

# --------------------------------------------------------------------------
# Paso 6: versión de Hyprland
# --------------------------------------------------------------------------

check_hyprland_version() {
    log "==> Comprobando versión de Hyprland..."

    if ! command -v hyprctl &>/dev/null; then
        warn "No se encontró 'hyprctl' (¿Hyprland no está instalado o no corriendo?)."
        warn "No puedo comprobar la versión; asume que necesitas la config Lua si"
        warn "instalas Hyprland >= 0.55, o la legacy (hyprlang) si es <= 0.54."
        return 0
    fi

    local version_line
    version_line="$(hyprctl version 2>/dev/null | head -n1 || true)"
    if [[ -z "$version_line" ]]; then
        warn "No se pudo leer la versión de Hyprland (¿el compositor no está corriendo ahora mismo?)."
        return 0
    fi

    info "Detectado: $version_line"

    local version
    version="$(printf '%s' "$version_line" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)"

    if [[ -z "$version" ]]; then
        warn "No pude extraer el número de versión de '$version_line'."
        warn "Comprueba a mano si ~/.config/hypr/hyprland.lua existe: si existe, usa la"
        warn "config Lua (hypr/.config/hypr/lua/icloud-glass.lua); si no, la legacy"
        warn "(hypr/legacy/icloud-glass.conf, solo Hyprland <= 0.54)."
        return 0
    fi

    local major minor
    major="$(cut -d. -f1 <<<"$version")"
    minor="$(cut -d. -f2 <<<"$version")"

    if [[ "$major" -gt 0 ]] || { [[ "$major" -eq 0 ]] && [[ "$minor" -ge 55 ]]; }; then
        info "Hyprland >= 0.55: usa la config Lua."
        info "  Añade  require(\"lua.icloud-glass\")  a tu ~/.config/hypr/hyprland.lua"
        info "  (el archivo ya está enlazado en ~/.config/hypr/lua/icloud-glass.lua)."
    else
        info "Hyprland <= 0.54 (hyprlang todavía activo, sin hyprland.lua)."
        info "  Añade  source = $SCRIPT_DIR/hypr/legacy/icloud-glass.conf  a tu"
        info "  ~/.config/hypr/hyprland.conf. Nota: hypr/legacy/ NO se enlaza con"
        info "  stow (a propósito); se referencia directamente desde la ruta del"
        info "  repo. hyprlang se elimina pronto: actualiza Hyprland y migra a la"
        info "  config Lua en cuanto puedas."
    fi
}

# --------------------------------------------------------------------------
# --uninstall
# --------------------------------------------------------------------------

do_uninstall() {
    log "==> Desinstalando icloud-glass..."

    if command -v systemctl &>/dev/null; then
        info "Desactivando el timer de sincronización..."
        run systemctl --user disable --now icloud-glass-sync.timer || \
            warn "No se pudo desactivar icloud-glass-sync.timer (¿ya estaba desactivado?)."
    fi

    if command -v stow &>/dev/null; then
        for pkg in "${PACKAGES[@]}"; do
            if [[ -d "$SCRIPT_DIR/$pkg" ]]; then
                info "Desenlazando '$pkg'..."
                run bash -c "cd '$SCRIPT_DIR' && stow -D -t '$HOME' '$pkg'" || \
                    warn "No se pudo desenlazar '$pkg' del todo (revisa \$HOME a mano)."
            fi
        done
    else
        warn "'stow' no está instalado; no puedo desenlazar los paquetes automáticamente."
        warn "Borra a mano los symlinks que apunten a $SCRIPT_DIR bajo \$HOME."
    fi

    cat <<EOF

Esto NO borra (y no lo hace ningún paso de este instalador):
  - Los datos sincronizados del vdir:      ~/.local/share/icloud-glass/vdir/
  - La caché JSON que lee el panel:        ~/.cache/icloud-glass/
  - El estado interno de vdirsyncer:       ~/.local/share/icloud-glass/vdirsyncer-status/
  - El Apple ID guardado (no es secreto):  ~/.config/icloud-glass/account
  - La app-specific password en el llavero del sistema (Secret Service):
      service=icloud-glass account=<tu-apple-id>
  - Tu shell.json personal (no es un symlink de stow, es tuyo):
      ~/.config/quickshell/icloud-glass/shell.json
  - ~/.config/vdirsyncer/config, si icloud-glass-setup ya lo sobrescribió con
    tu configuración real (deja de ser un symlink de stow en ese momento).

Para borrar todo eso a mano:
  rm -rf ~/.local/share/icloud-glass ~/.cache/icloud-glass \\
         ~/.config/icloud-glass ~/.config/quickshell/icloud-glass/shell.json \\
         ~/.config/vdirsyncer/config
  secret-tool clear service icloud-glass account <tu-apple-id>
EOF
}

# --------------------------------------------------------------------------
# Pasos siguientes (solo instalación)
# --------------------------------------------------------------------------

print_next_steps() {
    cat <<EOF

==> Instalación completa. Pasos siguientes:

  1. Configura tu cuenta de iCloud (Apple ID + app-specific password):
       icloud-glass-setup

  2. Activa la config de Hyprland del panel (ver arriba qué versión toca):
       - Hyprland >= 0.55: añade a ~/.config/hypr/hyprland.lua
             require("lua.icloud-glass")
       - Hyprland <= 0.54 (legacy): añade a ~/.config/hypr/hyprland.conf
             source = $SCRIPT_DIR/hypr/legacy/icloud-glass.conf

  3. Recarga Hyprland:
       hyprctl reload

  Más detalle, troubleshooting y limitaciones conocidas: docs/icloud-glass.md
EOF
}

# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

main() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(--dry-run: no se ejecutará ningún cambio real)"
    fi

    if [[ "$UNINSTALL" -eq 1 ]]; then
        do_uninstall
        exit 0
    fi

    check_distro
    install_dependencies
    link_packages
    setup_shell_json
    enable_timer
    check_hyprland_version
    print_next_steps
}

main "$@"
