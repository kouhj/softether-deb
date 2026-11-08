# Installing from the apt repository

The `.deb` packages are published as a static apt repository on GitHub Pages:

```text
https://kouhj.github.io/softether-deb/
├── dists/<suite>/…     one directory per published suite (see below)
└── softether-deb.asc   signing key
```

Published suites:

| distribution | version | suite |
|---|---|---|
| Debian | 11 (oldoldstable) | `bullseye` |
| Debian | 12 (oldstable) | `bookworm` |
| Debian | 13 (stable) | `trixie` |
| Debian | 14 (testing) | `forky` |
| Debian | 15 (future, built on unstable) | `duke` |
| Ubuntu | 22.04 LTS | `jammy` |
| Ubuntu | 24.04 LTS | `noble` |
| Ubuntu | 26.04 LTS | `resolute` |

All suites are signed with the same key and the indexes use the **DEB822**
format (`.sources`), which every distribution in the table understands. The
legacy one-line format is shown further down for even older systems.

`forky` and `duke` are built on moving targets (Debian testing / unstable), so
those two are best effort: a build can fail after an upstream toolchain change
without the other suites being affected.

Key fingerprint:

```text
F709 BB38 2606 BADE D145  A7EC 8719 B125 AF2E 845D
```

## Quick install (script)

The same steps as below, done in one go — the script detects the distribution,
installs the key, verifies its fingerprint and writes the DEB822 file:

```sh
curl -fsSL https://kouhj.github.io/softether-deb/install.sh | sudo sh
```

Options:

| option | meaning |
|---|---|
| `--install softether-vpnserver` | add the repository and install a package (space separated list works: `"softether-vpnserver softether-vpncmd"`) |
| `--suite <name>` | override the detected suite (needed only on an unsupported release) |
| `--no-update` | do not run `apt-get update` |
| `--dry-run` | print what would happen, change nothing (does not need root) |
| `--remove` | remove the repository and the signing key again |

The script refuses to run on anything but Debian 13 / Ubuntu 26.04 with
`amd64`, and aborts when the downloaded key does not match the expected
fingerprint. Uninstalling the packages is a separate step:

```sh
sudo apt purge 'softether-*'
```

## 1. Install the signing key

```sh
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://kouhj.github.io/softether-deb/softether-deb.asc \
  | sudo tee /etc/apt/keyrings/softether-deb.asc >/dev/null
sudo chmod 0644 /etc/apt/keyrings/softether-deb.asc
```

Check that the key you downloaded is the one above:

```sh
gpg --show-keys --with-fingerprint /etc/apt/keyrings/softether-deb.asc
```

## 2. Add the repository

Write `/etc/apt/sources.list.d/softether.sources`, replacing `<suite>` with the
suite of this machine from the table above (`trixie` on Debian 13, `noble` on
Ubuntu 24.04, …):

```sh
sudo tee /etc/apt/sources.list.d/softether.sources >/dev/null <<'EOF'
Types: deb
URIs: https://kouhj.github.io/softether-deb/
Suites: <suite>
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/softether-deb.asc
EOF
```

Print the codename of this machine with:

```sh
. /etc/os-release && echo "$VERSION_CODENAME"
```

Do not list several suites in one file unless the machine really is one of them:
apt would offer the packages of the other distributions as well.

## 3. Install

```sh
sudo apt update
sudo apt install softether-vpnserver      # or -vpnclient / -vpnbridge / -vpncmd
```

The index declares the dependency that upstream's packaging omits, so
`softether-common` (which ships `libcedar.so` and `libmayaqua.so`) is pulled in
automatically — installing the component package on its own would leave it
without its libraries.

Check what apt resolved:

```sh
apt policy softether-vpnserver
systemctl status softether-vpnserver
```

The service needs to be configured before it is useful; see the upstream
`vpncmd` documentation (`vpncmd /SERVER localhost`).

## Verify the repository

```sh
apt-get update                      # no "NO_PUBKEY" / "not signed" warnings
apt-cache policy softether-vpnserver  # Candidate comes from kouhj.github.io
```

If `apt update` complains about a missing signature, the key is not in place or
`Signed-By:` points at the wrong path — re-check step 1.

## Removing the repository

```sh
sudo rm -f /etc/apt/sources.list.d/softether.sources
sudo rm -f /etc/apt/keyrings/softether-deb.asc
sudo apt update
```

To also remove the packages:

```sh
sudo apt purge 'softether-*'
```

## Older apt with the one-line format

Systems without DEB822 support (Debian 11 and older, Ubuntu 22.04 and older) can
still use the repository:

```sh
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/softether-deb.asc] https://kouhj.github.io/softether-deb/ trixie main" \
  | sudo tee /etc/apt/sources.list.d/softether.list
```

(replace `trixie` with the suite of the machine, see the table above.)

## Without the signing key

If installing the key is not an option, the repository can be used with
`Trusted: yes` (DEB822) or `[trusted=yes]` (one-line). This disables apt's
signature verification for this repository and is not recommended:

```text
Types: deb
URIs: https://kouhj.github.io/softether-deb/
Suites: trixie
Components: main
Architectures: amd64
Trusted: yes
```

## Notes

- GitHub Pages is a CDN, so a freshly published index can be served from cache
  for a few minutes. If a just-released version is missing, wait and run
  `sudo apt update` again.
- The packages are the official upstream release with one local patch (the
  `is_restricted` assignments in `src/Cedar/Server.c` are commented out). See
  the top level `README.md` for the details and for the build logs.
