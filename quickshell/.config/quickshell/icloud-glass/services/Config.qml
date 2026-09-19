pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Config: lee ~/.config/quickshell/icloud-glass/shell.json y lo fusiona sobre
// unos defaults completos definidos aquí mismo. Si el archivo no existe o está
// corrupto, el shell sigue funcionando con los defaults, sin excepciones.
//
// API pública (congelada, ver docs/CONTRACTS.md §6):
//   raw, c, dark, reducedMotion, calendarColor(name), listColor(name), reloaded()
Singleton {
    id: root

    // --- Defaults completos (mismo esquema que shell.json.example) ---
    readonly property var defaults: ({
        schema: 1,
        theme: "auto",
        accentFromWallpaper: true,
        monitor: null,
        position: "center",
        hiddenCalendars: [],
        hiddenLists: [],
        defaultList: null,
        syncIntervalMinutes: 15,
        upcomingCount: 5,
        reducedMotion: "auto",
        colors: {
            dark: {
                surface: "#0E0E11", surfaceAlpha: 0.38, surfaceRaised: "#1A1A1F",
                onSurface: "#F5F5F7", onSurfaceMuted: "#A1A1AA", accent: "#0A84FF",
                stroke: "#FFFFFF", strokeAlpha: 0.14, danger: "#FF453A", success: "#30D158"
            },
            light: {
                surface: "#FFFFFF", surfaceAlpha: 0.55, surfaceRaised: "#F2F2F7",
                onSurface: "#1C1C1E", onSurfaceMuted: "#6E6E73", accent: "#0071E3",
                stroke: "#000000", strokeAlpha: 0.08, danger: "#D70015", success: "#248A3D"
            }
        },
        calendarColors: ({}),
        font: { family: "Inter", scale: 1.0 }
    })

    // Config fusionada (defaults + shell.json del usuario). Nunca es null.
    readonly property var raw: mergeConfig(defaults, parsedUserConfig)

    // Se incrementa cada vez que toca reevaluar el tema por hora (ver
    // scheduleNextThemeCheck). `dark` lo lee para que su binding se
    // reevalúe aunque `raw.theme` no haya cambiado.
    property int themeTick: 0

    // true si, según `raw.theme` (o la hora si es "auto"), toca tema oscuro.
    readonly property bool dark: {
        themeTick; // dependencia intencional: fuerza reevaluación periódica
        return computeDark();
    }

    // Paleta ya resuelta según el tema activo.
    readonly property var c: dark ? raw.colors.dark : raw.colors.light

    // reducedMotion: "auto" | "on" | "off". En "auto" intentamos leer la
    // preferencia de accesibilidad de Qt; si la plataforma no la expone,
    // asumimos false (sin animación reducida) en vez de fallar.
    readonly property bool reducedMotion: computeReducedMotion()

    signal reloaded()

    function calendarColor(name) {
        if (raw.calendarColors && raw.calendarColors[name])
            return raw.calendarColors[name];
        return c.accent;
    }

    function listColor(name) {
        if (raw.calendarColors && raw.calendarColors[name])
            return raw.calendarColors[name];
        return c.accent;
    }

    // --- Internals ---

    property var parsedUserConfig: ({})

    function mergeConfig(base, override) {
        // Fusión superficial recursiva de objetos planos; los arrays y valores
        // escalares del override sustituyen por completo a los del base.
        var out = {};
        for (var k in base) {
            var bv = base[k];
            var ov = (override && override.hasOwnProperty(k)) ? override[k] : undefined;
            if (ov === undefined) {
                out[k] = bv;
            } else if (bv !== null && typeof bv === "object" && !Array.isArray(bv)
                       && ov !== null && typeof ov === "object" && !Array.isArray(ov)) {
                out[k] = mergeConfig(bv, ov);
            } else {
                out[k] = ov;
            }
        }
        // Campos que el usuario añadió y que no están en defaults (por si acaso).
        if (override) {
            for (var k2 in override) {
                if (!out.hasOwnProperty(k2))
                    out[k2] = override[k2];
            }
        }
        return out;
    }

    function computeDark() {
        var theme = raw.theme;
        if (theme === "dark") return true;
        if (theme === "light") return false;
        // "auto": claro de 07:00 a 19:00, oscuro fuera de ese rango.
        var h = new Date().getHours();
        return !(h >= 7 && h < 19);
    }

    function computeReducedMotion() {
        var mode = raw.reducedMotion;
        if (mode === "on") return true;
        if (mode === "off") return false;
        // "auto": Qt no expone de forma estable y multiplataforma una
        // preferencia de "reduce motion" en QML puro (a diferencia de
        // prefers-reduced-motion en la web). Si en el futuro Quickshell
        // expone algo como Quickshell.systemPreferences.reducedMotion,
        // se debería consultar aquí. Por ahora, false.
        return false;
    }

    // --- Carga de shell.json ---

    FileView {
        id: userConfigFile
        path: Quickshell.env("ICLOUD_GLASS_SHELL_CONFIG")
              || (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
                 + "/quickshell/icloud-glass/shell.json"
        watchChanges: true

        onLoaded: root.reparseUserConfig()
        onFileChanged: root.reparseUserConfig()
        onLoadFailed: function (error) {
            // Archivo ausente o ilegible: seguimos con los defaults.
            root.parsedUserConfig = {};
            root.reloaded();
        }
    }

    function reparseUserConfig() {
        try {
            var text = userConfigFile.text();
            if (!text || text.trim().length === 0) {
                parsedUserConfig = {};
            } else {
                var parsed = JSON.parse(text);
                parsedUserConfig = (parsed && typeof parsed === "object") ? parsed : {};
            }
        } catch (e) {
            // JSON corrupto: mantenemos la config anterior (o vacía si es la
            // primera carga) y no propagamos la excepción.
            console.warn("Config: shell.json inválido, usando defaults/última config válida:", e);
            if (parsedUserConfig === undefined)
                parsedUserConfig = {};
        }
        reloaded();
    }

    // --- Timer único para el cambio automático claro/oscuro ---
    // En vez de sondear cada minuto, calculamos los ms que faltan hasta las
    // 07:00 o las 19:00 (lo que toque a continuación) y disparamos una vez.
    Timer {
        id: themeTimer
        repeat: false
        onTriggered: {
            // Forzamos la reevaluación de `dark` (propiedad calculada) y
            // reprogramamos el siguiente disparo.
            root.themeTick = root.themeTick + 1;
            root.reloaded();
            scheduleNextThemeCheck();
        }
    }

    Component.onCompleted: scheduleNextThemeCheck()

    function scheduleNextThemeCheck() {
        if (raw.theme !== "auto") return;
        var now = new Date();
        var next = new Date(now);
        if (now.getHours() < 7) {
            next.setHours(7, 0, 5, 0);
        } else if (now.getHours() < 19) {
            next.setHours(19, 0, 5, 0);
        } else {
            next.setDate(next.getDate() + 1);
            next.setHours(7, 0, 5, 0);
        }
        var ms = next.getTime() - now.getTime();
        // Límite defensivo: nunca más de 24h+1min, nunca menos de 1s.
        themeTimer.interval = Math.max(1000, Math.min(ms, 24 * 60 * 60 * 1000 + 60000));
        themeTimer.start();
    }
}
