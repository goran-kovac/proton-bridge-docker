# proton-bridge-docker

[![Build and publish Docker image](https://github.com/goran-kovac/proton-bridge-docker/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/goran-kovac/proton-bridge-docker/actions/workflows/docker-publish.yml)

A minimal, self-contained Docker image for [Proton Mail Bridge](https://proton.me/mail/bridge), built directly from Proton's official signed `.deb` package instead of relying on the maintenance of a community wrapper.

Bridge exposes your Proton Mail account as a standard IMAP/SMTP mailbox, so any regular email client (Outlook, Thunderbird, Apple Mail, generic IMAP tools, ...) can connect to it - no Proton-specific plugin required.

> **Status:** early, community-maintained project. Works, but hasn't been battle-tested across every setup. Issues and PRs welcome.

## Why this image

- Built from Proton's own signed release package (`proton.me/download/bridge`), so you're not depending on a third party keeping a Dockerfile in sync with new Bridge releases.
- Uses [`pass`](https://www.passwordstore.org/) (GPG-based) as the credential store instead of requiring a full desktop keyring/D-Bus session - works fine headless.
- Small footprint: `debian:bookworm-slim` base, no GUI/Qt dependencies.
- Bridge binds internally to `127.0.0.1`; the entrypoint mirrors ports `143` (IMAP) and `25` (SMTP) to `0.0.0.0` via `socat` so other containers/hosts on the network can reach it.

## Requirements

- Docker and Docker Compose
- A Proton Mail account (Bridge requires a paid plan; it's not available on the free tier)

## Quick start

### 1. Get the image

Either use the prebuilt image, published automatically by GitHub Actions on every push to `main` and on version tags:

```bash
docker pull ghcr.io/goran-kovac/proton-bridge-docker:latest
```

...or build it yourself:

```bash
docker compose build
```

`docker-compose.yml` builds locally by default (`build: .`). To use the prebuilt image instead, replace `build: .` with `image: ghcr.io/goran-kovac/proton-bridge-docker:latest`.

### 2. One-time interactive login

Bridge stores its session/credentials in a named volume (`protonmail_data`, mounted at `/root`), so this login step only needs to run once.

```bash
docker compose run --rm protonmail-bridge init
```

This drops you into Bridge's interactive CLI. From there:

```
login
# enter your Proton Mail address, password, and 2FA code if enabled
info
# shows the generated Bridge credentials (NOT your Proton password!)
# and the actual IMAP/SMTP ports Bridge is using internally
exit
```

Note the username/password and ports shown by `info` - you'll need them for your email client and possibly for adjusting the port mapping below.

### 3. Start it for real

```bash
docker compose up -d
```

### 4. Connect your email client

Point your IMAP/SMTP client at the host running this container:

- **Host:** the Docker host's address (or the service name `protonmail-bridge` if connecting from another container on the same network)
- **IMAP port:** 143
- **SMTP port:** 25
- **Username/password:** from the `info` output in step 2 (not your regular Proton password)
- **Encryption:** Bridge uses a self-signed certificate for IMAP/SMTP TLS - if your client refuses it, look for an "allow self-signed certificates" option

## Configuration

### Ports

Bridge's internal default ports are `1143` (IMAP) and `1025` (SMTP), forwarded by `entrypoint.sh` to the standard `143`/`25`. These can differ depending on your Bridge version/setup - always confirm with `info` after logging in, and adjust the `socat` lines in `entrypoint.sh` plus the port mapping in `docker-compose.yml` if they don't match.

### Updating Bridge

```bash
# edit ARG BRIDGE_VERSION in the Dockerfile, then:
docker compose build
docker compose up -d
```

### CI: building and publishing the image

`.github/workflows/docker-publish.yml` builds and pushes the image to GHCR (`ghcr.io/goran-kovac/proton-bridge-docker`) automatically:

- every push to `main` → tagged `latest`
- every tag matching `v*.*.*` (e.g. `v1.0.0`) → tagged with that version plus `1.0`

No extra secrets needed - it authenticates with the repo's built-in `GITHUB_TOKEN`. After the first run, make the package public under the repo's **Packages** tab if you want anyone to `docker pull` it without logging in.

Check [proton.me/download/bridge/stable_releases.html](https://proton.me/download/bridge/stable_releases.html) for the latest version. Bridge also silently self-updates at runtime; pinning `BRIDGE_VERSION` close to the latest release avoids the self-update pulling in a binary that needs a shared library not present in the image (see Troubleshooting).

### Staying up to date

Two things can go stale here, and they're kept current differently:

- **GitHub Actions and the Debian base image** - handled by [Dependabot](.github/dependabot.yml), which opens PRs weekly when `actions/checkout`, `docker/build-push-action`, etc. or `debian:bookworm-slim` get updates.
- **`BRIDGE_VERSION`** - not a registry tag, so Dependabot can't see it. `.github/workflows/check-bridge-version.yml` checks Proton's release notes weekly and opens a PR bumping it when a new stable version is out. Review these PRs before merging - a new Bridge version can add runtime dependencies the Dockerfile doesn't have yet (that's exactly what happened with `libfido2` in 3.22.0).

### Security hardening in CI

- **Image vulnerability scanning.** After every build, [Trivy](https://github.com/aquasecurity/trivy) scans the pushed image for known CVEs (CRITICAL/HIGH) in the Debian base and installed packages, with `ignore-unfixed: true` so it only reports CVEs that actually have an available patch (otherwise the Bridge `.deb`'s own transitive dependencies generate a lot of noise nobody can currently fix). Results show up under the repo's **Security → Code scanning** tab rather than failing the build - flip `exit-code` in `docker-publish.yml` to a non-zero value if you'd rather have the build fail on findings.
- **Weekly rebuild.** `docker-publish.yml` also runs on a weekly schedule (Mondays), not just on push, so newly released Debian security patches for otherwise-unchanged packages get pulled in and rescanned even if nobody touched the repo that week.
- **`wget` kept out of the runtime image.** The Dockerfile is a two-stage build - `wget`/`ca-certificates` fetch the Bridge `.deb` in a throwaway build stage, and only `ca-certificates` (needed at runtime for TLS to Proton's servers) makes it into the final image. Smaller image, one less thing to scan and patch.
- **Actions pinned to commit SHA.** All third-party GitHub Actions (`actions/checkout`, `docker/*`, `peter-evans/create-pull-request`, `aquasecurity/trivy-action`, `github/codeql-action`) are pinned to a full commit SHA rather than a floating tag like `@v7`, with the version as a trailing comment. This is the [supply-chain hardening GitHub itself recommends](https://docs.github.com/actions/security-guides/security-hardening-for-github-actions#using-third-party-actions) - a tag can be moved, a SHA can't. Dependabot still tracks and updates these SHAs automatically when a new version is released.

## Security notes

- Don't expose ports 143/25 publicly - only bind them within a trusted internal network or via `127.0.0.1`/an internal Docker network, e.g. through a reverse proxy or VPN if remote access is needed.
- The `protonmail_data` volume contains your session, local vault, and GPG key for `pass`. Treat it like a credentials store.

## Troubleshooting

**`error while loading shared libraries: libfido2.so.1: cannot open shared object file`**
Bridge auto-updated itself at runtime to a version newer than what was installed at build time, and that newer version needs `libfido2` (added as a dependency from Bridge 3.22 onward). Make sure `libfido2-1` is installed in the Dockerfile (already included here) and that `BRIDGE_VERSION` is reasonably current, then rebuild.

**`dbus[8]: Failed to start message bus: Failed to open "/usr/share/dbus-1/system.conf"`**
Harmless. Bridge doesn't rely on a system D-Bus for its credential store in this setup - see the comments in `entrypoint.sh`.

**`WARN ... Failed to add test credentials to keychain ... SecretServiceDBusHelper`**
Also harmless. Bridge always probes the D-Bus secret-service backend first; without a keyring/session bus that probe is expected to fail, and Bridge automatically falls back to `pass`.

**`Failed to create lock file; another instance is running`**
You tried to run a second Bridge process (e.g. via `docker exec` into the already-running container) while the main service container is still up. Stop the running container first (`docker compose stop`) before running `docker compose run --rm protonmail-bridge init`.

**Login/`init` won't start**
Make sure you rebuilt the image after changing the Dockerfile - `docker compose run` does not rebuild automatically.

## Known limitations

- Only tested on `linux/amd64`.
- No health check yet.
- The `.deb` install occasionally needs an extra dependency added to the Dockerfile if Proton changes what the package requires - if the build fails, check the log for the missing package.

## AI disclosure

Large parts of this project - the Dockerfile, entrypoint script, CI workflow, and this README - were written with the help of an AI coding assistant (Claude), based on my own debugging of real errors from running Bridge in a container. I reviewed and tested the changes, but treat this as a community project maintained with AI assistance, not hand-crafted line by line. Issues and corrections are very welcome.

## License

MIT, see [LICENSE](LICENSE).
