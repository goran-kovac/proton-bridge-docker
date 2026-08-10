# Minimal, self-contained Proton Mail Bridge image.
# Base: the official, signed .deb package from Proton (proton.me/download/bridge),
# pulled at build time. This keeps you independent from maintaining a
# community Docker wrapper - just bump BRIDGE_VERSION and rebuild.
#
# Check the current version: https://proton.me/download/bridge/stable_releases.html

# ---- Stage 1: fetch the signed .deb ----
# wget is only needed to download the package, not at runtime, so it's kept
# out of the final image (also keeps its own CVEs out of image scans).
FROM debian:bookworm-slim AS fetch

ARG BRIDGE_VERSION=3.25.0
ARG BRIDGE_DEB=protonmail-bridge_${BRIDGE_VERSION}-1_amd64.deb

RUN apt-get update && apt-get install -y --no-install-recommends \
        wget \
        ca-certificates \
    && wget -q https://proton.me/download/bridge/${BRIDGE_DEB} -O /tmp/bridge.deb

# ---- Stage 2: runtime image ----
FROM debian:bookworm-slim

COPY --from=fetch /tmp/bridge.deb /tmp/bridge.deb

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        gnupg \
        pass \
        socat \
        dbus-x11 \
        libfido2-1 \
    && ( apt-get install -y /tmp/bridge.deb || \
         ( apt-get install -y -f && apt-get install -y /tmp/bridge.deb ) ) \
    && rm -f /tmp/bridge.deb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/root"]

# Bridge only binds internally to 127.0.0.1 - see entrypoint.sh (socat forwarding)
EXPOSE 143 25

ENTRYPOINT ["/entrypoint.sh"]
