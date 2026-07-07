#!/bin/bash
# Compila Klip y arma el bundle .app (sin Xcode, solo Command Line Tools).
set -e

APP_NAME="Klip"
BUNDLE="$APP_NAME.app"
CONFIG="${1:-release}"
BUILD_DIR=".build/$CONFIG"
BUNDLE_ID="com.proper.klip"
ENTITLEMENTS="Resources/Klip.entitlements"

cd "$(dirname "$0")"

echo "→ Compilando ($CONFIG)…"
swift build -c "$CONFIG"

echo "→ Armando $BUNDLE…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$BUNDLE/Contents/Info.plist"

# Icono .icns desde Resources/AppIcon.png vía iconutil/sips (sin Xcode).
if [ -f "Resources/AppIcon.png" ]; then
    echo "→ Generando icono…"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s             Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png"      >/dev/null
        sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png"   >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "→ Firmando ad-hoc (reintentos para carpetas sincronizadas que re-añaden metadatos)…"
SIGNED=0
for attempt in 1 2 3; do
    xattr -cr "$BUNDLE" 2>/dev/null || true
    find "$BUNDLE" -name '._*' -delete 2>/dev/null || true
    if codesign --force --sign - --identifier "$BUNDLE_ID" --entitlements "$ENTITLEMENTS" "$BUNDLE" 2>/dev/null; then
        SIGNED=1; break
    fi
done
if [ "$SIGNED" = "1" ] && codesign --verify --strict "$BUNDLE" 2>/dev/null; then
    echo "  firma válida ✓"
else
    echo "  ⚠ firma local inválida (carpeta sincronizada). Usa ./install.sh: firma en /Applications."
fi

echo ""
echo "✓ Listo: $BUNDLE   (ejecutar:  open $BUNDLE)"
echo "  Atajos: ⌥⇧E (historial) · ⌥⇧R (voz) · ⌥⇧D (anotar) · ⌥⇧F (OCR) · ⌥⇧O (subir)   ·   Instalar: ./install.sh"
