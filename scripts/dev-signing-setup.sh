#!/usr/bin/env bash
#
# One-time: create a stable self-signed code-signing identity in the login keychain, so builds
# can be signed with a consistent code requirement. This is what lets macOS keep the
# Accessibility permission across rebuilds (ad-hoc signatures change every build and lose it).
#
# It's a LOCAL DEV identity only — not trusted by Gatekeeper, not for distribution.
#
set -euo pipefail
CN="LoudFlow Self-Signed"
KC="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v 2>/dev/null | grep -q "$CN"; then
  echo "Identity '$CN' already present."
  exit 0
fi

TMP=$(mktemp -d)
cat > "$TMP/cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CN
[ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CFG

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -nodes -config "$TMP/cfg" >/dev/null 2>&1
# -legacy: macOS 'security' can't import OpenSSL 3's default PKCS12 MAC algorithm.
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:loudflow -name "$CN" >/dev/null 2>&1 \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:loudflow -name "$CN" -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1
# -A: allow all tools (incl. codesign) to use the key without a keychain prompt.
security import "$TMP/id.p12" -k "$KC" -P loudflow -A
rm -rf "$TMP"
echo "Created '$CN'. Rebuilds signed with it keep their Accessibility grant."
