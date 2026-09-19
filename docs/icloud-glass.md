# icloud-glass

Panel de calendario y recordatorios de iCloud para Hyprland, construido con
[Quickshell](https://quickshell.outfoxxed.me/) y una estética "Liquid Glass" (blur del
compositor + refracción/tinte por shader).

> Contratos de datos y API congelados: [`CONTRACTS.md`](CONTRACTS.md). Este documento es la
> guía de uso; para el formato exacto de `events.json`, `todos.json`, `status.json`,
> `shell.json` y las señales de los singletons QML, la fuente de verdad es ese archivo.

## Arquitectura

```
iCloud (CalDAV: caldav.icloud.com)
        │
        │  vdirsyncer  (autenticación: Apple ID + app-specific password,
        │               vía Secret Service / libsecret)
        ▼
  vdir local (.ics)                         ~/.local/share/icloud-glass/vdir/
   ├── calendars/   (VEVENT)
   └── reminders/   (VTODO)
        │
        │  khal (lee calendarios)  +  icloud-glass-sync (parsea .ics directamente)
        ▼
  icloud-glass-sync
        │  genera / regenera, siempre con write+rename (atómico):
        ▼
  Caché JSON                                 ~/.cache/icloud-glass/
   ├── events.json
   ├── todos.json
   └── status.json
        │
        │  leído por
        ▼
  Quickshell (QML)                           ~/.config/quickshell/icloud-glass/
   services/DataStore.qml  →  modules/*  →  components/GlassPanel.qml (capa wlr-layer-shell)
        │
        │  namespace efectivo "quickshell:icloud-glass..."
        ▼
  Hyprland: hl.layer_rule → blur del compositor detrás del panel
```

Escritura (completar un recordatorio, crear un evento o un recordatorio nuevo) sigue un
camino separado, sin pasar por `todoman` (ver el porqué en `CONTRACTS.md`, sección 9):

```
Actions.qml (QML)  →  icloud-glass-write <subcomando>  →  edita el .ics del vdir directamente
                                                          → icloud-glass-refresh (regenera caché)
                                                          → icloud-glass-sync en segundo plano
                                                            (empuja el cambio a iCloud)
```

Los eventos nuevos sí se crean con `khal new` (que sabe escribir bien en el vdir); solo la
escritura de VTODO evita todoman.

## Dependencias

Instaladas automáticamente por `install.sh` en Arch Linux:

| Paquete | Repo | Para qué |
|---|---|---|
| `stow` | oficial | enlazar los dotfiles |
| `quickshell` | AUR | el shell/panel |
| `vdirsyncer` | oficial | sincronizar iCloud ↔ vdir local |
| `khal` | oficial | leer calendarios del vdir; también usado por `khal new` al crear eventos |
| `todoman` | oficial | comprobación de salud de `icloud-glass-setup`; NO se usa para leer/escribir recordatorios (ver `CONTRACTS.md` §9) |
| `libsecret` (`secret-tool`) | oficial | guardar la app-specific password en el llavero del sistema |
| `qt6-shadertools` | oficial, **opcional** | solo si vas a recompilar los shaders (`.qsb`) del panel |
| `jq` | oficial | utilidades de scripting |

Python 3.9+ (con `zoneinfo`) es requisito de `icloud-glass-sync`; en Arch viene con el
sistema.

## Instalación

```sh
git clone <este-repo>
cd icloud-glass   # o como se llame tu checkout
./install.sh
```

`install.sh` es idempotente y **nunca sobrescribe en silencio** un archivo real que ya exista
en `$HOME`: si `stow` detecta un conflicto, lo lista y explica cómo resolverlo (mover o
renombrar el archivo existente y reejecutar). Pasos que hace:

1. Comprueba que es Arch Linux (con `--force` continúa avisando en otras distros).
2. Instala las dependencias de la tabla de arriba (`pacman` para las oficiales, `paru`/`yay`
   para `quickshell`; si no hay ninguno instalado, imprime qué instalar a mano en vez de
   fallar).
3. Enlaza cada paquete de stow (`quickshell`, `icloud-glass`, `vdirsyncer`, `khal`,
   `todoman`, `systemd`, `hypr`) en `$HOME`.
4. Copia `shell.json.example` a `~/.config/quickshell/icloud-glass/shell.json` **solo si no
   existe ya** — ese archivo es tuyo, no un symlink del repo, así que tus cambios sobreviven
   a una reinstalación.
5. Activa `systemctl --user enable --now icloud-glass-sync.timer`.
6. Detecta la versión de Hyprland instalada y te dice si toca activar la config Lua o la
   legacy (ver más abajo).
7. Imprime los pasos siguientes.

Opciones: `--dry-run` (no toca nada, solo imprime), `--force` (ignora la comprobación de
distro), `--uninstall` (ver [Desinstalación](#desinstalación)), `-h`/`--help`.

## Configuración de iCloud

1. Genera una **app-specific password** en <https://appleid.apple.com/> (Inicio de sesión y
   seguridad → Contraseñas específicas de app). No uses tu contraseña normal de Apple ID: no
   funcionaría con autenticación en dos pasos, y una contraseña específica de app se puede
   revocar sin tocar el resto de la cuenta.
2. Ejecuta:

   ```sh
   icloud-glass-setup
   ```

   Te pide el Apple ID y esa contraseña (nunca se escribe a disco ni se pasa por `argv`: se
   guarda en el llavero del sistema vía `secret-tool`, Secret Service — clave
   `service=icloud-glass account=<tu-apple-id>`). Genera
   `~/.config/vdirsyncer/config` a partir de la plantilla del repo sustituyendo el Apple ID,
   y lanza el primer `vdirsyncer discover` + `sync` + `icloud-glass-refresh`.
3. **Comprueba el resumen que imprime `icloud-glass-setup` tras el `discover`.** Es la única
   forma real de saber qué calendarios y qué listas de Recordatorios expone tu cuenta por
   CalDAV — ver [Limitaciones](#limitaciones) sobre por qué esto no se puede dar por
   garantizado de antemano.

## Referencia de `shell.json`

Vive en `~/.config/quickshell/icloud-glass/shell.json` (creado por `install.sh` a partir de
`shell.json.example` la primera vez; después es tuyo). Formato completo y valores por
defecto: `CONTRACTS.md`, sección 4. Resumen de los campos que probablemente quieras tocar:

| Campo | Qué hace |
|---|---|
| `theme` | `auto` (sigue el sistema) / `light` / `dark` |
| `monitor` | `null` = monitor enfocado, o el nombre exacto (p.ej. `"DP-1"`) |
| `position` | `center` / `top-right` / `top-left` / `bottom-right` / `bottom-left` |
| `hiddenCalendars` / `hiddenLists` | nombres a ocultar del panel sin dejar de sincronizarlos |
| `defaultList` | lista destino por defecto al crear un recordatorio nuevo |
| `syncIntervalMinutes` | informativo para la UI; el intervalo real lo fija el timer systemd |
| `reducedMotion` | `auto` / `on` / `off` — desactiva las animaciones de apertura/cierre y del shader |
| `colors` / `calendarColors` / `font` | paleta y tipografía |

## Atajos de teclado

| Atajo | Acción |
|---|---|
| `SUPER + C` | Abre/cierra el panel (`qs -c icloud-glass ipc call panel toggle`) |
| `Esc` (con el panel abierto) | Cierra el panel |
| Clic fuera del panel | Cierra el panel |

Definido en `hypr/.config/hypr/lua/icloud-glass.lua` (o en la legacy `.conf`). Si ya tienes
`SUPER + C` asignado a otra cosa en tu propio `hyprland.lua`, cambia el bind en ese archivo
antes de activarlo.

### Activar la config de Hyprland

**Hyprland >= 0.55** usa Lua (`~/.config/hypr/hyprland.lua`); hyprlang (`.conf`) solo se
carga si `hyprland.lua` NO existe, y se elimina del proyecto en 1-2 releases tras la
migración. Añade a tu `hyprland.lua`:

```lua
require("lua.icloud-glass")
```

(El archivo se instala en `~/.config/hypr/lua/icloud-glass.lua`; `require("lua.icloud-glass")`
sigue la convención estándar de módulos de Lua — un `require("a.b")` busca `a/b.lua` en
`package.path` — asumiendo que el directorio de config de Hyprland está en esa ruta de
búsqueda. Si `require` falla con "module not found", añade antes:
`package.path = package.path .. ";" .. os.getenv("HOME") .. "/.config/hypr/?.lua"`.)

**Hyprland <= 0.54** (sin `hyprland.lua`, hyprlang todavía activo): usa
`hypr/legacy/icloud-glass.conf`. Este archivo **no se enlaza con stow a propósito** (no es un
dotfile, es la config en sí); añade a tu `~/.config/hypr/hyprland.conf`:

```
source = /ruta/a/tu/checkout/del/repo/hypr/legacy/icloud-glass.conf
```

`install.sh` imprime esa ruta ya resuelta al final de la instalación. Actualiza a Hyprland
>= 0.55 y migra a la config Lua en cuanto puedas: hyprlang desaparece pronto.

Tras activar cualquiera de las dos: `hyprctl reload`.

La regla de blur hace match sobre el namespace efectivo del panel,
`^quickshell:icloud-glass` (Quickshell antepone su propio prefijo al namespace que fija
`GlassPanel.qml`). Usa `blur = true` e `ignore_alpha = 0.15` para que el shader de
`GlassSurface.qml` (refracción/tinte/especular, ver `CONTRACTS.md` §5) no le recorte el blur
al compositor, y `no_anim = true` porque la animación de apertura/cierre la hace el propio
QML.

## Actualización

```sh
cd <tu-checkout-del-repo>
git pull
./install.sh
```

`stow -R` vuelve a enlazar todo (re-stow); es seguro repetirlo. Tu `shell.json` y tus datos
de iCloud no se tocan. Si cambiaste algo a mano en un archivo que stow gestiona, `install.sh`
te avisará del conflicto en vez de pisarlo.

## Desinstalación

```sh
./install.sh --uninstall
```

Desenlaza todos los paquetes de stow y desactiva el timer. **No borra**:

- Los datos sincronizados del vdir: `~/.local/share/icloud-glass/vdir/`
- La caché JSON: `~/.cache/icloud-glass/`
- El estado interno de vdirsyncer: `~/.local/share/icloud-glass/vdirsyncer-status/`
- El Apple ID guardado (no es secreto): `~/.config/icloud-glass/account`
- La app-specific password en el llavero del sistema (Secret Service)
- Tu `shell.json` (no es un symlink de stow)
- `~/.config/vdirsyncer/config`, una vez que `icloud-glass-setup` lo sobrescribió con tu
  configuración real (deja de ser un symlink de stow en ese momento)

Para borrar todo eso a mano, `./install.sh --uninstall` imprime los comandos exactos
(`rm -rf` de esas rutas + `secret-tool clear ...`).

## Troubleshooting

**El panel no aparece con `SUPER + C`.**
- Comprueba que `hyprland.lua` tiene el `require("lua.icloud-glass")` (o que la legacy
  `.conf` está `source`ada) y que hiciste `hyprctl reload`.
- Comprueba que el shell de Quickshell está corriendo: `pgrep -af "qs -c icloud-glass"`. Si
  no, lánzalo a mano: `qs -c icloud-glass -d`.
- Revisa que `SUPER + C` no esté ya bindeado a otra cosa en tu propio `hyprland.lua` (un
  bind posterior puede pisar al primero).

**No hay blur detrás del panel (se ve el shader pero sin desenfoque del fondo).**
- Comprueba que tu Hyprland tiene el blur global activado
  (`hl.config({ decoration = { blur = { enabled = true } } })`).
- Comprueba que la regla de capa está cargada: `hyprctl layers` debería listar una capa con
  namespace que empiece por `quickshell:icloud-glass`, y esa es la que debe hacer match la
  regla `hl.layer_rule` (o `layerrule` en la legacy).
- Si ves el blur "con agujeros" (recortado donde el shader es casi transparente), es el
  motivo de `ignore_alpha = 0.15`: comprueba que no se ha quedado en 0 ni se ha eliminado.

**No baja nada (calendarios/recordatorios vacíos).**
- Ejecuta `icloud-glass-sync` a mano (sin `--quiet`) y lee el error en stderr.
- Comprueba el estado del timer: `systemctl --user status icloud-glass-sync.timer` y
  `journalctl --user -u icloud-glass-sync.service`.
- Comprueba `~/.cache/icloud-glass/status.json`: el campo `error`/`errorKind` (sección 3 de
  `CONTRACTS.md`) da la causa en una frase, en español.
- Si `errorKind` es `auth`: repite `icloud-glass-setup` (puede que la app-specific password
  haya caducado o se haya revocado desde appleid.apple.com).

**Credenciales / "no se pudo guardar la contraseña en el llavero".**
- Asegúrate de tener un Secret Service corriendo (GNOME Keyring, KWallet con el módulo de
  compatibilidad, o similar) y desbloqueado en tu sesión de Hyprland.
- Prueba `secret-tool store --label=test service icloud-glass-test account test` a mano; si
  falla igual, el problema es el Secret Service, no `icloud-glass-setup`.

## Limitaciones

- **iCloud Reminders viaja por CalDAV como `VTODO`, pero hay incertidumbre real sobre si
  todas tus listas se exponen así.** No hay forma de comprobarlo sin una cuenta real de
  iCloud (listas compartidas o "inteligentes" podrían no aparecer). Por eso
  `icloud-glass-setup` imprime el resumen del `discover` justo después de configurarse: es
  la única verificación de verdad, y hay que mirarla.
- **No hay push.** La sincronización es por el timer systemd (cada 15 minutos por defecto,
  `OnUnitActiveSec=15min` en `systemd/.config/systemd/user/icloud-glass-sync.timer`) más el
  refresco manual desde el panel (`Actions.sync()`). Un cambio hecho en el iPhone/Mac puede
  tardar hasta ese intervalo en aparecer aquí.
- **No se soportan adjuntos, subtareas anidadas ni recordatorios por ubicación.** El contrato
  de datos (`CONTRACTS.md` §1-2) no tiene campos para ninguno de los tres; si tu cuenta los
  usa, simplemente no se muestran ni se sincronizan.
- **No existe una API pública de Apple para Calendar/Reminders.** Este proyecto usa
  exclusivamente CalDAV estándar (`vdirsyncer`, `khal`) contra `caldav.icloud.com` con
  autenticación por app-specific password. No se usa ninguna API privada de Apple, ni
  scraping, ni nada fuera de ese protocolo estándar.
- **Conflictos de edición simultánea:** `vdirsyncer` está configurado con
  `conflict_resolution = "b wins"` (iCloud gana) en ambos pares (calendarios y
  recordatorios) — ver el comentario en `vdirsyncer/.config/vdirsyncer/config`. Un cambio
  hecho aquí y no sincronizado todavía, si choca con un cambio hecho en otro dispositivo
  antes del siguiente sync, se pierde. Es una decisión de producto (iCloud como fuente de
  verdad), no un límite técnico, pero conviene saberlo.
