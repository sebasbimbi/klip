#!/bin/bash
# Despliegue local: compila, firma, instala en /Applications y relanza limpio.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Klip"
SRC_BUNDLE="$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

echo "==> 1) Compilando y armando el .app (release)…"
./build.sh release

echo "==> 2) Cerrando instancias previas (si las hay)…"
/usr/bin/pkill -x "$APP_NAME" 2>/dev/null || true
/usr/bin/pkill -x Pasta 2>/dev/null || true   # nombre anterior
perl -e 'select(undef,undef,undef,0.4)'

echo "==> 3) Instalando en /Applications…"
SUDO=""
if [ ! -w /Applications ]; then SUDO="sudo"; fi
$SUDO rm -rf "$DEST"
$SUDO cp -R "$SRC_BUNDLE" "$DEST"
$SUDO xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> 3.5) Firmando en /Applications (ubicación estable, sin re-añadido de metadatos)…"
$SUDO xattr -cr "$DEST" 2>/dev/null || true
$SUDO codesign --force --sign - --identifier com.proper.klip --entitlements Resources/Klip.entitlements "$DEST" 2>&1
$SUDO codesign --verify --strict "$DEST" && echo "  ✓ firma válida en /Applications"

echo "==> 4) Lanzando…"
open "$DEST"

echo ""
echo "✓ Instalado en $DEST"
echo "  · Mostrar historial: ⌘⇧E   ·   Grabar nota de voz: ⌘⇧I"
echo "  · Arranque al iniciar sesión: se registra automáticamente la primera vez."
echo "    Si Ajustes › General › Ítems de inicio de sesión pide aprobación, actívalo ahí."
echo "  · Pegado automático: actívalo desde el menú de Klip → 'Activar pegado automático…'"
echo "    (concede Accesibilidad cuando el sistema lo pida)."
