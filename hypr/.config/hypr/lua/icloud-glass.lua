-- icloud-glass.lua — reglas de Hyprland (Lua, API `hl.*`) para el panel
-- icloud-glass (Quickshell).
--
-- IMPORTANTE: Hyprland >= 0.55 (mayo 2026) migró su configuración de
-- hyprlang a Lua. La config principal vive en `~/.config/hypr/hyprland.lua`
-- y hyprlang se retira en 1-2 releases más. Este archivo usa exclusivamente
-- la API Lua (`hl.bind`, `hl.layer_rule`, `hl.on`), NO hyprlang. Si tu
-- Hyprland es <= 0.54 (sin `hyprland.lua`), usa en su lugar
-- `hypr/legacy/icloud-glass.conf` (hyprlang, deprecado).
--
-- Cómo activarlo:
--   Este archivo se instala (vía GNU Stow) en `~/.config/hypr/lua/icloud-glass.lua`.
--   Desde tu `~/.config/hypr/hyprland.lua` añade:
--
--       require("lua.icloud-glass")
--
--   Esto sigue la convención de módulos de Lua: un `require("a.b")` busca
--   `a/b.lua` relativo a los directorios de `package.path`, y Hyprland
--   añade el propio directorio de config (`~/.config/hypr/`) a esa ruta de
--   búsqueda — por eso basta con `lua.icloud-glass` teniendo el archivo en
--   `~/.config/hypr/lua/icloud-glass.lua`. NO hemos podido verificar contra
--   una instancia real de Hyprland que `package.path` incluya el directorio
--   de config por defecto en toda configuración; si `require` falla con
--   "module not found", añade antes de la línea de arriba:
--
--       package.path = package.path .. ";" .. os.getenv("HOME") .. "/.config/hypr/?.lua"
--
-- Fuentes verificadas (2026-09-19):
--   - Ejemplo oficial: https://raw.githubusercontent.com/hyprwm/Hyprland/main/example/hyprland.lua
--     (confirma `hl.bind`, `hl.dsp.exec_cmd`, `hl.window_rule`, `hl.layer_rule`,
--     el comentario de autostart con `hl.on("hyprland.start", ...)`, y el
--     patrón `require("archivo")` para dividir la config).
--   - https://wiki.hypr.land/configuring/core/rules/layer-rules/ (tabla de
--     props/efectos exacta de `hl.layer_rule`: `match.namespace` es regex;
--     efectos `blur` (bool), `blur_popups` (bool), `ignore_alpha` (float
--     0.0-1.0), `no_anim` (bool), `xray` (bool), `dim_around` (bool),
--     `no_screen_share` (bool), `above_lock` (int), `animation` (string),
--     `order` (int). Todo en snake_case, confirmado con los ejemplos de esa
--     misma página, p.ej. `hl.layer_rule({ match = { namespace = "rofi" },
--     blur = true, ignore_alpha = 0.5 })`).
--   - https://wiki.hypr.land/configuring/core/autostart/ (confirma
--     `hl.on("hyprland.start", function() hl.exec_cmd(...) end)`).
--   - https://wiki.hypr.land/configuring/core/advanced-configuration/lua-utilities/
--     (confirma `hl.exec_cmd()` como spawn asíncrono, sin necesitar `& disown`).
--
-- Namespace real del panel:
-- `quickshell/.config/quickshell/icloud-glass/components/GlassPanel.qml` fija
-- `WlrLayershell.namespace: "icloud-glass" + namespaceSuffix`. Quickshell
-- antepone su propio prefijo, así que el namespace EFECTIVO que ve Hyprland
-- empieza por `quickshell:icloud-glass` (con el sufijo opcional al final si
-- se usan varios paneles). Por eso la regex de abajo es `^quickshell:icloud-glass`.
-- Si ese componente cambia el namespace base, A1/A3 deben avisar para
-- actualizar esta regla (ver comentario en GlassPanel.qml).

local iCloudGlassLayerRule = hl.layer_rule({
    name  = "icloud-glass-panel-blur",
    match = { namespace = "^quickshell:icloud-glass" },

    -- Activa el blur del compositor detrás del panel. El shader de
    -- GlassSurface.qml (refracción/tinte/especular) se pinta ENCIMA de ese
    -- blur; si `ignore_alpha` fuera 0 (o no estuviera puesto), Hyprland
    -- consideraría "vacíos" (no-blureados) los píxeles casi transparentes
    -- del shader y el blur se vería recortado/con agujeros. Con ~0.15,
    -- Hyprland sigue blureando detrás de los píxeles con opacidad baja pero
    -- no nula que produce el shader.
    blur         = true,
    ignore_alpha = 0.15,

    -- La animación de apertura/cierre (escala 0.96→1 + opacidad + offset,
    -- ver el comentario en GlassPanel.qml) la hace el propio QML. Si el
    -- compositor animase también la capa, se sumarían ambas animaciones y
    -- se vería doble/con tirones. Por eso se desactiva aquí.
    no_anim = true,
})

-- SUPER + C: abre/cierra el panel. Llama al IPC handler `panel` que expone
-- services/Ipc.qml (ver docs/CONTRACTS.md, sección 6):
--   IpcHandler target "panel": toggle() open() close() refresh()
-- `-c icloud-glass` selecciona la config de Quickshell instalada en
-- `~/.config/quickshell/icloud-glass/`.
hl.bind("SUPER + C", hl.dsp.exec_cmd("qs -c icloud-glass ipc call panel toggle"))

-- Autostart: lanza el shell de Quickshell como daemon en segundo plano al
-- arrancar Hyprland (una única instancia, con la layer surface del panel
-- oculta hasta el primer toggle — ver GlassPanel.qml, `visible: false`
-- mientras `open == false`).
hl.on("hyprland.start", function()
    hl.exec_cmd("qs -c icloud-glass -d")
end)

return {
    layer_rule = iCloudGlassLayerRule,
}
