#!/bin/bash
# Despliegue local: compila, firma con una identidad ESTABLE (para que macOS recuerde los
# permisos de micrófono/accesibilidad entre actualizaciones), instala y relanza.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Klip"
SRC_BUNDLE="$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"
SIGN_IDENTITY_NAME="Klip Code Signing"

# Crea (una sola vez) un certificado de firma autofirmado y lo marca como de confianza, para que la
# firma sea estable entre builds → TCC (micrófono, etc.) NO vuelve a preguntar.
# Imprime el nombre de la identidad en stdout; falla (return 1) si no se pudo preparar.
ensure_identity() {
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY_NAME"; then
        echo "$SIGN_IDENTITY_NAME"; return 0
    fi
    command -v openssl >/dev/null 2>&1 || return 1
    local kc tmp legacy
    kc="$(security default-keychain | tr -d ' \t"')"
    tmp="$(mktemp -d)"
    legacy=""; openssl version 2>/dev/null | grep -q "OpenSSL 3" && legacy="-legacy" || true
    cat > "$tmp/req.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $SIGN_IDENTITY_NAME
[v3]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
    if openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/k.pem" -out "$tmp/c.pem" \
            -days 3650 -config "$tmp/req.cnf" -extensions v3 >/dev/null 2>&1 \
       && openssl pkcs12 -export $legacy -inkey "$tmp/k.pem" -in "$tmp/c.pem" -out "$tmp/c.p12" \
            -passout pass:klip -name "$SIGN_IDENTITY_NAME" >/dev/null 2>&1 \
       && security import "$tmp/c.p12" -k "$kc" -P klip -T /usr/bin/codesign -A >/dev/null 2>&1; then
        security add-trusted-cert -r trustRoot -p codeSign -k "$kc" "$tmp/c.pem" >/dev/null 2>&1 || true
        rm -rf "$tmp"
        if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY_NAME"; then
            echo "$SIGN_IDENTITY_NAME"; return 0
        fi
    fi
    rm -rf "$tmp"; return 1
}

echo "==> 1) Compilando la .app (release)…"
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

# Identidad de firma: estable si es posible (sin sudo, para poder usar el llavero del usuario).
SIGN_ID="-"
if [ -z "$SUDO" ]; then
    if ID="$(ensure_identity)"; then SIGN_ID="$ID"; fi
fi

echo "==> 3.5) Firmando en /Applications (ubicación estable, sin metadatos re-añadidos)…"
$SUDO xattr -cr "$DEST" 2>/dev/null || true
if ! $SUDO codesign --force --sign "$SIGN_ID" --identifier com.proper.klip \
        --entitlements Resources/Klip.entitlements "$DEST" 2>/tmp/klip_sign_err; then
    if [ "$SIGN_ID" != "-" ]; then
        echo "  ⚠ la firma con '$SIGN_ID' falló; usando ad-hoc"
        SIGN_ID="-"
        $SUDO codesign --force --sign - --identifier com.proper.klip \
            --entitlements Resources/Klip.entitlements "$DEST"
    else
        cat /tmp/klip_sign_err; rm -f /tmp/klip_sign_err; exit 1
    fi
fi
rm -f /tmp/klip_sign_err
$SUDO codesign --verify --strict "$DEST" && echo "  ✓ firma válida en /Applications"
if [ "$SIGN_ID" = "-" ]; then
    echo "  (firma ad-hoc: macOS volverá a pedir los permisos tras cada reinstalación)"
else
    echo "  (firma estable '$SIGN_ID': el permiso de micrófono se recuerda entre actualizaciones)"
fi

# Idioma local por defecto (UI + transcripción de audio). Solo en una instalación NUEVA (respeta una elección posterior).
# Se puede forzar con KLIP_DEFAULT_LANG=en ./install.sh
KLIP_LANG="${KLIP_DEFAULT_LANG:-es}"
defaults read com.proper.klip uiLanguage            >/dev/null 2>&1 || defaults write com.proper.klip uiLanguage            -string "$KLIP_LANG"
defaults read com.proper.klip transcriptionLanguage >/dev/null 2>&1 || defaults write com.proper.klip transcriptionLanguage -string "$KLIP_LANG"

echo "==> 4) Abriendo…"
open "$DEST"

echo ""
echo "✓ Instalado en $DEST"
echo "  · Atajos por defecto:  Historial ⌥⇧E · Voz ⌥⇧R · Anotar ⌥⇧D · Texto OCR ⌥⇧F · Subir ⌥⇧O"
echo "    (los exactos se ven en el menú de Klip y se cambian en Preferencias › Atajos)"
echo "  · Abrir al iniciar sesión: se registra automáticamente la primera vez."
echo "    Si Configuración › General › Ítems de inicio pide aprobación, actívalo ahí."
echo "  · Auto-pegado: actívalo desde el menú de Klip → 'Activar auto-pegado…'"
echo "    (concede Accesibilidad cuando el sistema lo pida)."
