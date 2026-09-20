#!/usr/bin/env bash
# tests/run.sh — arnés de verificación de icloud-glass, de extremo a extremo.
#
# Encadena, en este orden, y falla en el primer paso que falle:
#   1. python3 tests/validate.py tests/fixtures   (los fixtures cumplen el contrato)
#   2. qmllint sobre los 17 QML de producción      (análisis estático; aviso, no bloquea
#                                                    — ver la nota que imprime este script)
#   3. los tests QML offscreen (QtQuick.Test vía qmltestrunner, QT_QPA_PLATFORM=offscreen)
#   4. hueco documentado para tests/contrast.py (otro agente); si no existe, se
#      avisa y se continúa, no se falla.
#
# Ver docs/CONTRACTS.md y el informe de la tarea D1 para el porqué de cada pieza.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

FIXTURES="$REPO_ROOT/tests/fixtures"
QML_DIR="$REPO_ROOT/quickshell/.config/quickshell/icloud-glass"
STUBS="$REPO_ROOT/tests/qml/stubs"
SCEN="$REPO_ROOT/tests/qml/.tmp"
TESTS_QML_DIR="$REPO_ROOT/tests/qml"

step() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }
bad()  { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; }

overall_status=0

# ---------------------------------------------------------------------------
# 1. validate.py sobre los fixtures del contrato
# ---------------------------------------------------------------------------
step "1/4 · python3 tests/validate.py tests/fixtures"
if python3 "$REPO_ROOT/tests/validate.py" "$FIXTURES"; then
    ok "validate.py: los fixtures cumplen docs/CONTRACTS.md"
else
    bad "validate.py encontró incumplimientos del contrato en tests/fixtures"
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. qmllint sobre los 17 QML de producción
# ---------------------------------------------------------------------------
step "2/4 · qmllint sobre quickshell/.config/quickshell/icloud-glass"
QMLLINT_BIN="$(command -v qmllint 2>/dev/null || echo /usr/lib/qt6/bin/qmllint)"
if [ ! -x "$QMLLINT_BIN" ]; then
    bad "no se encontró el binario qmllint; instala qt6-declarative-dev-tools"
    exit 1
fi

mapfile -t QML_FILES < <(find "$QML_DIR" -name '*.qml' | sort)
echo "Analizando ${#QML_FILES[@]} archivos QML..."
lint_had_output=0
for f in "${QML_FILES[@]}"; do
    out="$("$QMLLINT_BIN" -I "$STUBS" "$f" 2>&1)"
    if [ -n "$out" ]; then
        lint_had_output=1
        echo "--- ${f#"$REPO_ROOT"/} ---"
        echo "$out"
    fi
done
if [ "$lint_had_output" -eq 0 ]; then
    ok "qmllint no reportó nada sobre los 17 archivos"
else
    # NO se trata como fallo duro del pipeline: qmllint, en este contenedor,
    # no tiene los qmltypes reales de Quickshell (solo nuestros stubs de
    # tests/qml/stubs, pensados para EJECUTAR QML, no para satisfacer al
    # linter estático) y ni siquiera resuelve QtQuick por completo — así lo
    # advierte el propio encargo de esta tarea. Los avisos de arriba son
    # una señal complementaria, no una verificación fiable por sí sola.
    echo
    echo "(qmllint reportó avisos arriba. Se registran como diagnóstico, NO hacen"
    echo " fallar run.sh: en este contenedor qmllint no resuelve el módulo Quickshell"
    echo " real —solo nuestros stubs QML, pensados para ejecutar, no para lint— y ya se"
    echo " advirtió en el encargo que ni siquiera resuelve QtQuick del todo. La prueba"
    echo " de verdad son los tests offscreen del paso 3/4.)"
fi

# ---------------------------------------------------------------------------
# 3. tests QML offscreen (QtQuick.Test)
# ---------------------------------------------------------------------------
step "3/4 · tests QML offscreen (qmltestrunner, QT_QPA_PLATFORM=offscreen)"
RUNNER_BIN="$(command -v qmltestrunner 2>/dev/null || echo /usr/lib/qt6/bin/qmltestrunner)"
if [ ! -x "$RUNNER_BIN" ]; then
    bad "no se encontró qmltestrunner; instala qml6-module-qttest (ver informe de la tarea)"
    exit 1
fi

echo "Preparando escenarios de caché combinados en ${SCEN#"$REPO_ROOT"/}/ ..."
rm -rf "$SCEN"
mkdir -p "$SCEN"

make_scenario() {
    local name="$1" events="$2" todos="$3" status="$4"
    local dir="$SCEN/cache-$name"
    mkdir -p "$dir"
    cp "$FIXTURES/$events" "$dir/events.json"
    cp "$FIXTURES/$todos" "$dir/todos.json"
    cp "$FIXTURES/$status" "$dir/status.json"
}

# Los 6 estados que pide el encargo, con los fixtures que ya existen en
# tests/fixtures (no se duplican, se combinan bajo los nombres fijos que
# DataStore.qml espera: events.json / todos.json / status.json).
make_scenario ok            events.json       todos.json       status.json
make_scenario error-network events.json       todos.json       status-error-network.json
make_scenario error-auth    events-empty.json todos-empty.json status-error-auth.json
make_scenario syncing       events.json       todos.json       status-syncing.json
make_scenario events-empty  events-empty.json todos.json       status.json
make_scenario todos-empty   events.json       todos-empty.json status.json
# Copia privada y escribible para el test de "JSON corrupto a mitad de carga".
make_scenario corrupt       events.json       todos.json       status.json

export QT_QPA_PLATFORM=offscreen
export QML_XHR_ALLOW_FILE_READ=1
export QML_XHR_ALLOW_FILE_WRITE=1
export QML2_IMPORT_PATH="$STUBS"
export QML_IMPORT_PATH="$STUBS"

TEST_LOG="$(mktemp)"
"$RUNNER_BIN" -input "$TESTS_QML_DIR" 2>&1 | tee "$TEST_LOG"
runner_status=${PIPESTATUS[0]}

echo
echo "--- comprobando que la salida no contenga warnings/errores de QML ---"
# Requisito explícito del encargo: CERO binding loops, y en general ningún
# warning de motor QML, incluso si QtTest considera que todo "PASS" (QtTest
# solo juzga las aserciones explícitas, no los warnings de binding sueltos).
if grep -Eiq 'binding loop|TypeError|ReferenceError|Cannot read propert|is not a function|Cannot assign to non-existent|Non-existent attached|produced [1-9][0-9]* error' "$TEST_LOG"; then
    bad "la salida de qmltestrunner contiene warnings/errores de QML (ver arriba)"
    runner_status=1
else
    ok "sin binding loops ni otros warnings de motor QML en la salida"
fi
rm -f "$TEST_LOG"

if [ "$runner_status" -ne 0 ]; then
    bad "los tests QML offscreen fallaron"
    exit 1
fi
ok "tests QML offscreen: todo verde"

# ---------------------------------------------------------------------------
# 4. hueco documentado para tests/contrast.py
# ---------------------------------------------------------------------------
step "4/4 · tests/contrast.py (hueco para otro agente)"
if [ -f "$REPO_ROOT/tests/contrast.py" ]; then
    if python3 "$REPO_ROOT/tests/contrast.py"; then
        ok "tests/contrast.py: OK"
    else
        bad "tests/contrast.py falló"
        exit 1
    fi
else
    echo "tests/contrast.py todavía no existe (lo añadirá otro agente) — se salta, no falla."
fi

echo
ok "tests/run.sh: todo OK"
exit 0
