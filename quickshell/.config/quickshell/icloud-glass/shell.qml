// shell.qml — entrypoint de la configuración Quickshell `icloud-glass`.
//
// Lanzar con:
//     qs -c icloud-glass          (en primer plano, para ver los logs)
//     qs -c icloud-glass -d       (como daemon; es lo que hace el autostart de Hyprland)
//
// Controlar desde fuera:
//     qs -c icloud-glass ipc call panel toggle
//     qs -c icloud-glass ipc call panel open | close | refresh
//
// Probar contra los fixtures del repo, sin tocar la caché real ni iCloud:
//     ICLOUD_GLASS_CACHE_DIR=$PWD/tests/fixtures qs -c icloud-glass
//
// El blur del fondo NO se hace aquí: lo aplica Hyprland sobre la layer surface
// mediante la regla de `hypr/.config/hypr/lua/icloud-glass.lua`, que hace match
// sobre el namespace `quickshell:icloud-glass`. Sin esa regla el panel funciona
// igual, pero se ve translúcido plano en vez de esmerilado.

import QtQuick
import Quickshell
import "services" as Services
import "components" as Components
import "modules" as Modules

ShellRoot {
    id: shell

    Components.GlassPanel {
        id: panel

        // La única fuente de verdad del estado abierto/cerrado es el singleton Ipc,
        // para que el keybind de Hyprland, el IPC y cualquier clic interno coincidan.
        open: Services.Ipc.panelOpen

        // Cerrar desde dentro (Esc o clic fuera) tiene que propagarse a Ipc, o el
        // siguiente `toggle` haría lo contrario de lo esperado.
        onOpenChanged: if (!open && Services.Ipc.panelOpen) Services.Ipc.panelOpen = false

        Modules.CombinedPanel {
            id: combined

            // Al abrir el panel siempre se vuelve a hoy: si lo dejaste en otro día
            // hace tres horas, no es lo que quieres ver al abrirlo de nuevo.
            Connections {
                target: Services.Ipc
                function onPanelOpened() {
                    combined.selectDate(combined.todayString());
                }
            }
        }
    }

    // `Ipc` solo emite la señal; quien decide actuar es el shell. Así el singleton de
    // IPC no depende de Actions y no hay dependencia circular entre singletons.
    Connections {
        target: Services.Ipc
        function onRefreshRequested() {
            Services.Actions.sync();
        }
    }
}
