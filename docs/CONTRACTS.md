# CONTRACTS.md — contratos congelados de icloud-glass

> **Congelado en la Ola 0.** Ningún agente puede añadir, renombrar ni reinterpretar campos de este
> documento. Si algo falta, el agente **para y lo reporta al orquestador**; no improvisa.

## 0. Rutas canónicas

| Qué | Ruta |
|---|---|
| vdir (datos sincronizados) | `~/.local/share/icloud-glass/vdir/` |
| Caché JSON (lo que lee el QML) | `~/.cache/icloud-glass/` |
| Config de usuario del shell | `~/.config/quickshell/icloud-glass/shell.json` |
| Apple ID (no secreto) | `~/.config/icloud-glass/account` |
| App-specific password | Secret Service: `service=icloud-glass account=<appleid>` |

Variables de entorno respetadas: `XDG_DATA_HOME`, `XDG_CACHE_HOME`, `XDG_CONFIG_HOME`.
Override para tests: `ICLOUD_GLASS_CACHE_DIR`, `ICLOUD_GLASS_VDIR`.

---

## 1. `events.json`

Escrito por `icloud-glass-sync` / `icloud-glass-refresh`. Siempre **write + rename** (atómico).

```jsonc
{
  "schema": 1,
  "generated": "2026-09-19T12:00:00+02:00",   // ISO 8601 con offset, hora local
  "range": { "start": "2026-09-19", "end": "2026-11-18" },
  "calendars": [                                // todos los calendarios conocidos, aunque estén vacíos
    { "name": "Personal", "color": "#FF9F0A" }
  ],
  "events": [
    {
      "uid": "6F3A...@icloud.com",  // string, NO único entre ocurrencias de un recurrente
      "key": "6F3A...@icloud.com|2026-09-19T14:30:00+02:00", // string ÚNICO por ocurrencia. Clave de lista.
      "title": "Reunión de equipo",
      "calendar": "Personal",
      "color": "#FF9F0A",           // hex #RRGGBB, siempre presente (fallback del Config)
      "allDay": false,
      "start": "2026-09-19T14:30:00+02:00",  // null SI Y SOLO SI allDay
      "end":   "2026-09-19T15:30:00+02:00",  // null SI Y SOLO SI allDay
      "startDate": "2026-09-19",    // siempre presente; fecha local de inicio
      "endDate":   "2026-09-19",    // siempre presente; fecha local del último día INCLUSIVE
      "durationMinutes": 60,        // null si allDay
      "location": null,
      "description": null,
      "recurring": false,
      "status": "CONFIRMED",        // CONFIRMED | TENTATIVE | CANCELLED | null
      "cancelled": false,
      "url": null,
      "categories": []
    }
  ]
}
```

Reglas duras:
- `events` viene **ordenado** por `startDate`, luego all-day primero, luego `start`, luego `title`.
- Un evento multi-día genera **una sola entrada** con `startDate != endDate`. El QML lo expande.
- Un recurrente genera **una entrada por ocurrencia** dentro de `range`, cada una con su propia `key`.
- Los campos nunca se omiten: si no hay valor, es `null` (o `[]` en listas).

## 2. `todos.json`

```jsonc
{
  "schema": 1,
  "generated": "2026-09-19T12:00:00+02:00",
  "lists": [
    { "name": "Recordatorios", "color": "#0A84FF", "pending": 3, "completed": 12 }
  ],
  "todos": [
    {
      "uid": "A1B2...",           // string ÚNICO. Clave de lista y argumento de las acciones.
      "summary": "Entregar trabajo",
      "list": "Recordatorios",
      "color": "#0A84FF",
      "completed": false,
      "completedAt": null,        // ISO 8601 o null
      "due": "2026-09-20T09:00:00+02:00",  // null si no tiene hora; null si no tiene due
      "dueDate": "2026-09-20",    // null si no tiene due
      "dueAllDay": false,         // true = solo fecha, sin hora
      "overdue": false,           // calculado por el backend contra `generated`
      "priority": 0,              // 0 = ninguna, 1-4 = alta, 5 = media, 6-9 = baja (RFC 5545)
      "priorityLabel": "none",    // none | low | medium | high  (derivado, para no repetir lógica)
      "percent": 0,               // 0-100
      "description": null,
      "categories": [],
      "created": "2026-09-01T10:00:00+02:00"
    }
  ]
}
```

Reglas duras:
- `todos` ordenado por: pendientes antes que completados → vencidos primero → `due` ascendente
  (los sin `due` al final) → `priority` ascendente tratando 0 como 10 → `summary`.
- `lists` incluye listas vacías (para poder mostrar el estado "Todo hecho" por lista).

## 3. `status.json`

```jsonc
{
  "schema": 1,
  "state": "ok",             // ok | syncing | stale | error
  "lastSync": "2026-09-19T12:00:00+02:00",   // último intento
  "lastSyncOk": "2026-09-19T12:00:00+02:00", // último ÉXITO; null si nunca
  "durationMs": 1840,
  "error": null,             // mensaje humano, una frase, en español
  "errorKind": null,         // network | auth | server | config | tool | unknown
  "counts": { "events": 42, "todos": 15, "calendars": 3, "lists": 2 }
}
```

`state`:
- `ok` — último sync bien y hace <30 min.
- `stale` — hay caché válida pero el último sync falló o fue hace >30 min. **El QML sigue mostrando datos.**
- `error` — no hay caché utilizable.
- `syncing` — escrito al empezar; el QML muestra el indicador sin borrar los datos.

## 4. `shell.json` (config de usuario) — tokens

```jsonc
{
  "schema": 1,
  "theme": "auto",                 // auto | light | dark
  "accentFromWallpaper": true,
  "monitor": null,                 // null = monitor enfocado; o el nombre ("DP-1")
  "position": "center",            // center | top-right | top-left | bottom-right | bottom-left
  "hiddenCalendars": [],
  "hiddenLists": [],
  "defaultList": null,             // lista destino de QuickAdd; null = la primera
  "syncIntervalMinutes": 15,
  "upcomingCount": 5,
  "reducedMotion": "auto",         // auto | on | off
  "colors": {
    "dark":  { "surface": "#0E0E11", "surfaceAlpha": 0.38, "surfaceRaised": "#1A1A1F",
               "onSurface": "#F5F5F7", "onSurfaceMuted": "#A1A1AA", "accent": "#0A84FF",
               "stroke": "#FFFFFF", "strokeAlpha": 0.14, "danger": "#FF453A", "success": "#30D158" },
    "light": { "surface": "#FFFFFF", "surfaceAlpha": 0.55, "surfaceRaised": "#F2F2F7",
               "onSurface": "#1C1C1E", "onSurfaceMuted": "#6E6E73", "accent": "#0071E3",
               "stroke": "#000000", "strokeAlpha": 0.08, "danger": "#D70015", "success": "#248A3D" }
  },
  "calendarColors": {},            // { "Personal": "#FF9F0A" } — override manual
  "font": { "family": "Inter", "scale": 1.0 }
}
```

Escala de espaciado fija (no configurable): `4, 8, 12, 16, 24, 32`.
Radios fijos: chip `12`, tarjeta `20`, panel `28`.
Escala tipográfica fija: `11, 13, 15, 17, 22, 28`.

---

## 5. API de `GlassSurface.qml`

```qml
GlassSurface {
    radius: 20            // real, por defecto 20
    tint: "#0E0E11"       // color base; por defecto Config.c.surface
    tintAlpha: 0.38       // real 0..1
    elevation: 1          // int 0..3 → intensidad de sombra y borde
    refraction: 1.0       // real 0..1.5; 0 desactiva el shader (reduced motion / fallback)
    specular: true        // bool; highlight superior
    interactive: false    // bool; si true, el specular sigue al ratón
    // default property alias content → los hijos se colocan dentro, con clip al radio
}
```
Debe funcionar sin shader (si `qsb` falla o `refraction === 0`) degradando a color plano + borde.

## 6. API de los singletons

```qml
// services/Config.qml   (Singleton)
readonly property var raw          // shell.json ya parseado y fusionado con los defaults
readonly property var c            // paleta activa ya resuelta (theme auto → light/dark)
readonly property bool dark
readonly property bool reducedMotion
function calendarColor(name) -> string
function listColor(name) -> string
signal reloaded()

// services/DataStore.qml   (Singleton)
readonly property var events              // array, tal cual el contrato (ya filtrado por hiddenCalendars)
readonly property var todos               // array, idem con hiddenLists
readonly property var calendars           // array de {name, color}
readonly property var lists               // array de {name, color, pending, completed}
readonly property var status              // objeto status.json
readonly property bool ready              // true cuando hay datos utilizables (aunque sean stale)
function eventsOn(dateString) -> array    // "YYYY-MM-DD"
function upcoming(n) -> array             // desde ahora, ignora los ya terminados
function hasEventsOn(dateString) -> bool
function colorsOn(dateString) -> array    // colores únicos, para los puntos del mes
function todosFor(listName) -> array

// services/Actions.qml   (Singleton)
function completeTodo(uid, completed)     // completed: bool (permite deshacer)
function newTodo(listName, summary, dueIso /*o null*/)
function newEvent(calendarName, title, startIso, endIso, allDay)
function sync()                           // dispara icloud-glass-sync
signal actionFailed(string what, string message)
signal actionSucceeded(string what)
readonly property bool busy

// services/Ipc.qml  → IpcHandler target "panel": toggle() open() close() refresh()
```

`Actions` es **optimista**: emite el cambio local al instante, y si el `Process` sale != 0 revierte y
emite `actionFailed`. Nunca bloquea la UI.

---

## 7. Mapa de propiedad de archivos

| Agente | Dueño exclusivo de |
|---|---|
| A1 | `icloud-glass/**`, `vdirsyncer/**`, `khal/**`, `todoman/**`, `systemd/**` |
| A2 | `quickshell/.config/quickshell/icloud-glass/services/**` |
| A3 | `quickshell/.config/quickshell/icloud-glass/components/**`, `.../shaders/**` |
| B1 | `.../modules/CalendarWidget.qml`, `.../modules/EventList.qml` |
| B2 | `.../modules/RemindersWidget.qml`, `.../modules/QuickAdd.qml` |
| B3 | `install.sh`, `.stow-local-ignore`, `.gitignore`, `hypr/**`, `README.md`, `docs/icloud-glass.md` |
| Orquestador | `docs/CONTRACTS.md`, `tests/**`, `.../shell.qml`, `.../modules/CombinedPanel.qml` |

Nadie escribe fuera de su columna. `docs/CONTRACTS.md` es de solo lectura para todos menos el orquestador.

## 8. Fixtures

`tests/fixtures/{events,todos,status}.json` — casos duros incluidos: evento recurrente semanal,
evento de todo el día, evento multi-día que cruza cambio de hora (DST del 25-10-2026),
evento cancelado, reminder vencido, reminder con prioridad alta, reminder completado,
lista de reminders vacía.

Variantes de estado para probar la UI:
`tests/fixtures/status-error-network.json`, `status-error-auth.json`, `status-stale.json`,
`tests/fixtures/events-empty.json`, `todos-empty.json`.

Los QML se prueban con `ICLOUD_GLASS_CACHE_DIR=$PWD/tests/fixtures qs -p quickshell/.config/quickshell/icloud-glass/shell.qml`.

---

## 9. CLI de escritura — `icloud-glass-write` (añadido en Ola C, tras integrar A1+A2)

**Por qué existe.** A2 asumió que el QML podía llamar a `todo done <uid>`. A1 comprobó contra todoman 4.7.0
real que `todo` identifica las tareas por un **entero secuencial inestable**, no por UID, y que
`--porcelain` ni siquiera expone el UID. Usar ese entero rompería la unicidad y la estabilidad que exige
la sección 2. Por eso la escritura de VTODO no pasa por todoman: un binario propio edita el `.ics` del vdir
(que es exactamente para lo que sirve un vdir) y `vdirsyncer` lo empuja a iCloud en el siguiente sync.

**Los eventos sí siguen pasando por `khal new`**, que escribe correctamente en el vdir.

```
icloud-glass-write todo-done  <uid> [--undo]
icloud-glass-write todo-new   --list <nombre> --summary <texto> [--due <iso8601>] [--all-day]
icloud-glass-write event-new  --calendar <nombre> --title <texto> --start <iso> [--end <iso>] [--all-day]
```

Contrato de comportamiento:
- Salida 0 = hecho. Salida != 0 = **una sola línea en stderr, en español, diciendo la causa**
  (`No existe ninguna tarea con ese UID.`, `La lista «Compra» no existe.`, …). Nada de tracebacks.
- `todo-new` y `event-new` imprimen en stdout el `uid` (todo) o la `key` (evento) creados, y nada más.
- Toda escritura actualiza `LAST-MODIFIED`, incrementa `SEQUENCE` y escribe con write+`os.replace`.
- `todo-done` marca `STATUS:COMPLETED`, `PERCENT-COMPLETE:100` y `COMPLETED:<ahora UTC>`; `--undo`
  revierte a `STATUS:NEEDS-ACTION` y borra `COMPLETED`/`PERCENT-COMPLETE`.
- Es idempotente: completar algo ya completado sale 0 sin tocar el archivo.
- Respeta `ICLOUD_GLASS_VDIR`.

`Actions.qml` llama a `icloud-glass-write …` y después a `icloud-glass-refresh`, y lanza
`icloud-glass-sync` en segundo plano. La firma pública de `Actions` (sección 6) **no cambia**.

---

## 10. Política de color y contraste (medida, no supuesta — Ola D)

`tests/contrast.py` la comprueba y **falla el build si se incumple**. Sustituye a la tabla informal de
tokens: lo de aquí es lo que manda.

### El problema que resuelve
El panel es translúcido sobre un wallpaper arbitrario. Con un alpha fijo el contraste no tiene solución:
para garantizar 4.5:1 sobre cualquier fondo haría falta `surfaceAlpha` ≥ 0.93, es decir, opaco, lo que
elimina el efecto Liquid Glass. Medido: con la configuración inicial (0.38 / 0.55), el texto principal
sobre un wallpaper blanco daba **2.31:1**. Ilegible.

### Las tres reglas

1. **Los tokens de texto cumplen AA sobre su superficie opaca.** Si un token no llega, está mal elegido y
   ningún alpha lo arregla. Medido: `onSurface` 17.7:1 (oscuro) y 17.0:1 (claro).

2. **Alpha adaptativo con elección automática de tema.** `Config.qml` calcula
   `alphaEfectivo = max(surfaceAlpha configurado, mínimo exigido por el wallpaper)` y elige el tema que
   menos alpha necesite para la luminancia media del wallpaper. Con eso el alpha **nunca pasa de 0.48**
   (peor caso: wallpaper de luminancia 144) y baja a **0.00** en wallpapers muy oscuros o muy claros. El
   techo aceptado es 0.55; por encima el panel deja de parecer cristal y el test falla.

   | Luminancia del wallpaper | 0 | 64 | 128 | 160 | 192 | 255 |
   |---|---|---|---|---|---|---|
   | Tema elegido | oscuro | oscuro | oscuro | claro | claro | claro |
   | Alpha mínimo | 0.00 | 0.00 | 0.40 | 0.42 | 0.12 | 0.00 |

3. **`accent`, `danger` y `success` son MARCAS, no texto**, y **solo se pintan sobre `surfaceRaised`**.
   Son puntos de calendario, barras de color, círculos de check e iconos, así que les aplica WCAG 1.4.11
   (3:1), no 4.5:1 — precisamente porque el contrato ya prohíbe transmitir estado solo con color: la marca
   siempre va acompañada de texto o icono en `onSurface`.
   **Sobre el cristal desnudo estos colores caen a 1.0–1.7:1, o sea invisibles.** De ahí la regla.

### Tokens corregidos

| Token | Antes | Ahora | Por qué |
|---|---|---|---|
| `dark.surfaceRaised` | `#1A1A1F` | `#22222A` | separación con el cristal era 1.03:1 |
| `light.surfaceRaised` | `#F2F2F7` | `#E8E8F0` | separación era 1.06:1 |
| `light.accent` | `#0071E3` | `#0062C4` | no llegaba a 3:1 como marca |
| `light.success` | `#248A3D` | `#1E7A34` | 3.94:1 sobre superficie opaca |
| `surfaceRaisedAlpha` | — | `0.92` (ambos temas) | **token nuevo**: las filas son más sólidas que el cristal |

Comprobar siempre con `python3 tests/contrast.py` tras tocar cualquier color.
