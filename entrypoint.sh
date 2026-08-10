#!/usr/bin/env bash
set -euo pipefail

export GNUPGHOME=/root/.gnupg
export PASSWORD_STORE_DIR=/root/.password-store

# Bridge needs a secret-service backend for its vault. In this headless
# container we use "pass" (GPG-based) instead of GNOME Keyring. On startup,
# Bridge always probes secret-service-dbus first; without a session bus or a
# real keyring provider that probe is expected to fail with just a WARN, not
# an error. Bridge then automatically falls back to "pass" once it finds the
# `pass` binary and an initialized store. A system D-Bus doesn't help here
# (Bridge doesn't use it for this), so we don't start one.

if [ ! -d "$PASSWORD_STORE_DIR" ]; then
    echo ">> Generating GPG key for pass (one-time)..."
    cat >/tmp/gpg-gen <<EOF
%no-protection
Key-Type: RSA
Key-Length: 3072
Name-Real: ProtonBridge
Name-Email: bridge@localhost
Expire-Date: 0
%commit
EOF
    gpg --batch --gen-key /tmp/gpg-gen
    KEY_ID=$(gpg --list-keys --with-colons | awk -F: '/^pub/ {print $5; exit}')
    pass init "$KEY_ID"
fi

# One-time interactive login: docker compose run --rm protonmail-bridge init
if [ "${1:-}" = "init" ]; then
    exec protonmail-bridge --cli
fi

# Normal operation: Bridge only binds to 127.0.0.1, so we mirror it to
# 0.0.0.0 via socat, allowing other containers on the same Docker network
# (or the host) to reach it. 1143/1025 are Bridge's default ports - check
# with "info" in the CLI after logging in and adjust here if needed.
socat TCP-LISTEN:143,fork,reuseaddr TCP:127.0.0.1:1143 &
socat TCP-LISTEN:25,fork,reuseaddr TCP:127.0.0.1:1025 &

exec protonmail-bridge --noninteractive
