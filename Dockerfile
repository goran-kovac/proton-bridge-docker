# Minimal, self-contained Proton Mail Bridge image.
# Base: the official, signed .deb package from Proton (proton.me/download/bridge),
# pulled at build time. This keeps you independent from maintaining a
# community Docker wrapper - just bump BRIDGE_VERSION and rebuild.
#
# Check the current version: https://proton.me/download/bridge/stable_releases.html

FROM debian:bookworm-slim

ARG BRIDGE_VERSION=3.25.0
ARG BRIDGE_DEB=protonmail-bridge_${BRIDGE_VERSION}-1_amd64.deb

RUN apt-get update && apt-get install -y --no-install-recommends \
        wget \
        ca-certificates \
        gnupg \
        pass \
        socat \
        dbus-x11 \
        libfido2-1 \
    && wget -q https://proton.me/download/bridge/${BRIDGE_DEB} \
    && ( apt-get install -y ./${BRIDGE_DEB} || \
         ( apt-get install -y -f && apt-get install -y ./${BRIDGE_DEB} ) ) \
    && rm -f ./${BRIDGE_DEB} \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/root"]

# Bridge only binds internally to 127.0.0.1 - see entrypoint.sh (socat forwarding)
EXPOSE 143 25

ENTRYPOINT ["/entrypoint.sh"]
