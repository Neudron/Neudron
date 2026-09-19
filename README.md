![GitHub Snake](https://github.com/OfficialCodeVoyage/OfficialCodeVoyage/blob/6df7b29dd8219f717a53420721b40af395f5e4b0/github-snake-dark.svg)

# Neudron — dotfiles

Dotfiles personales, organizados en paquetes de [GNU Stow](https://www.gnu.org/software/stow/):
cada carpeta de primer nivel espeja la ruta real bajo `$HOME`.

## icloud-glass

Panel de calendario y recordatorios de iCloud para Hyprland + Quickshell, con estética
"Liquid Glass". La documentación completa (arquitectura, instalación, configuración de
iCloud, atajos, troubleshooting y limitaciones conocidas) está en
**[`docs/icloud-glass.md`](docs/icloud-glass.md)**.

## Paquetes

| Paquete | Qué contiene | Se instala en |
|---|---|---|
| `quickshell/` | El shell QML de icloud-glass (panel, componentes, shaders, servicios) | `~/.config/quickshell/` |
| `icloud-glass/` | Binarios propios: `icloud-glass-sync`, `icloud-glass-refresh`, `icloud-glass-setup` | `~/.local/bin/` |
| `vdirsyncer/` | Plantilla de configuración para sincronizar iCloud (CalDAV) a un vdir local | `~/.config/vdirsyncer/` |
| `khal/` | Configuración de `khal` (lectura de calendarios desde el vdir) | `~/.config/khal/` |
| `todoman/` | Configuración de `todoman` (lectura de recordatorios desde el vdir) | `~/.config/todoman/` |
| `systemd/` | Servicio y timer `--user` que sincronizan periódicamente | `~/.config/systemd/user/` |
| `hypr/` | Reglas de Hyprland para el panel: blur de capa, keybind, autostart (Lua para >= 0.55; legacy hyprlang para <= 0.54, sin enlazar por stow — ver `docs/icloud-glass.md`) | `~/.config/hypr/` |

## Instalación

```sh
./install.sh
```

Detecta dependencias (Arch Linux: `pacman` + `paru`/`yay` para AUR), enlaza los paquetes con
`stow` sin sobrescribir nada en silencio, crea tu `shell.json` personal si no existe, y activa
el timer de sincronización. Opciones: `--dry-run`, `--force`, `--uninstall`, `--help`.

Para instalar (o reinstalar) un paquete suelto a mano:

```sh
stow -R -t "$HOME" quickshell
```

Ver **[`docs/icloud-glass.md`](docs/icloud-glass.md)** para la guía completa, incluida la
configuración de la cuenta de iCloud y las limitaciones conocidas.
