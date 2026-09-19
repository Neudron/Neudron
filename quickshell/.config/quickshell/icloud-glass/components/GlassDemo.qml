// GlassDemo.qml — página autónoma para juzgar el material Liquid Glass sin el resto
// del panel: tres fondos (foto clara, foto oscura, degradado saturado), sliders de
// refraction/tintAlpha/elevation y un interruptor claro/oscuro.
//
// No se descarga ninguna imagen: los tres fondos son gradientes QML generados en el
// propio archivo (Canvas para las dos "fotos" con ruido procedural barato + un
// LinearGradient/Gradient normal para el degradado saturado).
//
// CÓMO LANZARLA
// --------------
// Como ventana de escritorio normal (no layer-shell), con Quickshell:
//
//   qs -p quickshell/.config/quickshell/icloud-glass/components/GlassDemo.qml
//
// o, si se prefiere un QML puro sin Quickshell (solo para ver el material en sí,
// aunque entonces `import "../services"` fallará si Config no está disponible — el
// propio GlassSurface degrada a sus valores por defecto en ese caso):
//
//   qml quickshell/.config/quickshell/icloud-glass/components/GlassDemo.qml
//
// Los sliders actúan directamente sobre las tres tarjetas GlassSurface a la vez, para
// comparar el efecto sobre los tres fondos en paralelo.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Window {
    id: demoWindow
    width: 1400
    height: 820
    visible: true
    title: "icloud-glass — GlassDemo"
    color: darkMode ? "#000000" : "#E5E5EA"

    property bool darkMode: true
    property real demoRefraction: 1.0
    property real demoTintAlpha: 0.38
    property int demoElevation: 2
    readonly property color labelColor: darkMode ? "#F5F5F7" : "#1C1C1E"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 20

        // --- controles ---------------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: controlsRow.implicitHeight + 24
            radius: 16
            color: demoWindow.darkMode ? "#1C1C1E" : "#FFFFFF"
            border.width: 1
            border.color: demoWindow.darkMode ? "#3A3A3C" : "#D1D1D6"

            RowLayout {
                id: controlsRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 28

                ColumnLayout {
                    spacing: 2
                    Text { text: "refraction: " + demoWindow.demoRefraction.toFixed(2); color: demoWindow.labelColor; font.pixelSize: 13 }
                    Slider {
                        from: 0; to: 1.5; value: demoWindow.demoRefraction; stepSize: 0.05
                        Layout.preferredWidth: 220
                        onMoved: demoWindow.demoRefraction = value
                    }
                }
                ColumnLayout {
                    spacing: 2
                    Text { text: "tintAlpha: " + demoWindow.demoTintAlpha.toFixed(2); color: demoWindow.labelColor; font.pixelSize: 13 }
                    Slider {
                        from: 0; to: 1; value: demoWindow.demoTintAlpha; stepSize: 0.02
                        Layout.preferredWidth: 220
                        onMoved: demoWindow.demoTintAlpha = value
                    }
                }
                ColumnLayout {
                    spacing: 2
                    Text { text: "elevation: " + demoWindow.demoElevation; color: demoWindow.labelColor; font.pixelSize: 13 }
                    Slider {
                        from: 0; to: 3; value: demoWindow.demoElevation; stepSize: 1; snapMode: Slider.SnapAlways
                        Layout.preferredWidth: 220
                        onMoved: demoWindow.demoElevation = value
                    }
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    spacing: 8
                    Text { text: "Claro"; color: demoWindow.labelColor; font.pixelSize: 13 }
                    Switch { checked: demoWindow.darkMode; onToggled: demoWindow.darkMode = checked }
                    Text { text: "Oscuro"; color: demoWindow.labelColor; font.pixelSize: 13 }
                }
            }
        }

        // --- tres fondos en paralelo ---------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 20

            // Fondo 1: "foto clara" — cielo/nube generado con Canvas + ruido barato.
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 20
                clip: true
                color: "#000000"

                Canvas {
                    id: lightPhoto
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d");
                        const g = ctx.createLinearGradient(0, 0, 0, height);
                        g.addColorStop(0, "#BFE3FF");
                        g.addColorStop(0.55, "#E9F4FF");
                        g.addColorStop(1, "#FFFFFF");
                        ctx.fillStyle = g;
                        ctx.fillRect(0, 0, width, height);
                        // "nubes": manchas suaves semi-transparentes
                        ctx.fillStyle = "rgba(255,255,255,0.55)";
                        for (let i = 0; i < 14; i++) {
                            const cx = (i * 97 % width);
                            const cy = (i * 53 % (height * 0.6)) + height * 0.1;
                            const r = 40 + (i * 31 % 60);
                            ctx.beginPath();
                            ctx.ellipse(cx, cy, r * 1.6, r * 0.7, 0, 0, Math.PI * 2);
                            ctx.fill();
                        }
                    }
                }

                GlassSurface {
                    anchors.centerIn: parent
                    width: 260; height: 160
                    radius: 20
                    refraction: demoWindow.demoRefraction
                    tintAlpha: demoWindow.demoTintAlpha
                    elevation: demoWindow.demoElevation
                    interactive: true
                    Text {
                        anchors.centerIn: parent
                        text: "Fondo claro"
                        color: "#1C1C1E"
                        font.pixelSize: 17
                    }
                }
            }

            // Fondo 2: "foto oscura" — noche/luces de ciudad con ruido procedural.
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 20
                clip: true
                color: "#000000"

                Canvas {
                    id: darkPhoto
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d");
                        const g = ctx.createLinearGradient(0, 0, 0, height);
                        g.addColorStop(0, "#05070F");
                        g.addColorStop(0.6, "#0E1524");
                        g.addColorStop(1, "#1A2438");
                        ctx.fillStyle = g;
                        ctx.fillRect(0, 0, width, height);
                        // "luces" puntuales
                        for (let i = 0; i < 60; i++) {
                            const px = (i * 137) % width;
                            const py = height * 0.5 + (i * 83 % (height * 0.45));
                            const r = 1 + (i % 3);
                            ctx.fillStyle = i % 5 === 0 ? "rgba(255,190,120,0.9)" : "rgba(200,220,255,0.7)";
                            ctx.beginPath();
                            ctx.ellipse(px, py, r, r, 0, 0, Math.PI * 2);
                            ctx.fill();
                        }
                    }
                }

                GlassSurface {
                    anchors.centerIn: parent
                    width: 260; height: 160
                    radius: 20
                    refraction: demoWindow.demoRefraction
                    tintAlpha: demoWindow.demoTintAlpha
                    elevation: demoWindow.demoElevation
                    interactive: true
                    Text {
                        anchors.centerIn: parent
                        text: "Fondo oscuro"
                        color: "#F5F5F7"
                        font.pixelSize: 17
                    }
                }
            }

            // Fondo 3: degradado saturado (sin Canvas, Gradient QML puro).
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 20
                clip: true
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "#FF3B6F" }
                    GradientStop { position: 0.45; color: "#7B2FFF" }
                    GradientStop { position: 1.0; color: "#00C2FF" }
                }

                GlassSurface {
                    anchors.centerIn: parent
                    width: 260; height: 160
                    radius: 20
                    refraction: demoWindow.demoRefraction
                    tintAlpha: demoWindow.demoTintAlpha
                    elevation: demoWindow.demoElevation
                    interactive: true
                    Text {
                        anchors.centerIn: parent
                        text: "Degradado"
                        color: "#FFFFFF"
                        font.pixelSize: 17
                    }
                }
            }
        }

        // --- fila extra: mismo material con refraction: 0 para comparar el fallback ---
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            spacing: 20

            Text {
                text: "Camino de fallback (refraction: 0, sin shader) →"
                color: demoWindow.labelColor
                font.pixelSize: 13
                Layout.alignment: Qt.AlignVCenter
            }

            GlassSurface {
                Layout.preferredWidth: 220
                Layout.preferredHeight: 90
                radius: 20
                refraction: 0
                tintAlpha: demoWindow.demoTintAlpha
                elevation: demoWindow.demoElevation
                Text {
                    anchors.centerIn: parent
                    text: "Sin shader"
                    color: demoWindow.darkMode ? "#F5F5F7" : "#1C1C1E"
                    font.pixelSize: 15
                }
            }
        }
    }
}
