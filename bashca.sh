#!/bin/bash

set -e  # Exit if any command fails

CERT_DIR="$HOME/Downloads"
CERT_NAME="my-cert.pem"  # Change this if your cert has a different name
CRT_PATH="/usr/local/share/ca-certificates/my-cert.crt"
NSS_CERT_NAME="My Custom CA"

echo "🔍 Looking for CA certificate in $CERT_DIR..."
if [ ! -f "$CERT_DIR/$CERT_NAME" ]; then
    echo "❌ ERROR: Certificate not found in $CERT_DIR!"
    exit 1
fi

echo "🔄 Converting PEM to CRT format (if needed)..."
openssl x509 -in "$CERT_DIR/$CERT_NAME" -inform PEM -out "$CERT_DIR/my-cert.crt"

echo "🔑 Copying CA certificate to system trust store..."
sudo cp "$CERT_DIR/my-cert.crt" "$CRT_PATH"
sudo chmod 644 "$CRT_PATH"

echo "🔄 Updating system CA certificates..."
sudo update-ca-certificates --fresh

echo "✅ System-wide CA installation complete!"

# Chrome & Firefox trust store setup
echo "🌐 Configuring Chrome & Firefox to trust the CA..."

# For Chrome & Chromium-based browsers
echo "🛠️ Adding certificate to Chrome trust store..."
mkdir -p "$HOME/.pki/nssdb"
certutil -d sql:"$HOME/.pki/nssdb" -A -t "C,," -n "$NSS_CERT_NAME" -i "$CRT_PATH" || true

# For Firefox (all profiles)
echo "🛠️ Adding certificate to Firefox trust store..."
for profile in "$HOME/.mozilla/firefox/"*.default-release; do
    if [ -d "$profile" ]; then
        certutil -d sql:"$profile" -A -t "C,," -n "$NSS_CERT_NAME" -i "$CRT_PATH" || true
    fi
done

echo "✅ Browser CA installation complete!"

# Final verification
echo "🔍 Verifying installation..."
openssl verify "$CRT_PATH"

echo "🎉 Certificate installed successfully! Restart your browsers to apply changes."
