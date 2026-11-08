#!/bin/sh
# Add the SoftEther VPN apt repository to a Debian 13 or Ubuntu 26.04 host.
#
#   curl -fsSL https://kouhj.github.io/softether-deb/install.sh | sudo sh
#   sudo sh install.sh --install softether-vpnserver
#   sudo sh install.sh --remove
#
# Options:
#   --suite <name>     use this suite instead of the one detected (trixie,
#                      resolute); only needed for an unsupported release
#   --install <pkg>    also install a package (repeatable argument is not
#                      supported: pass "softether-vpnserver softether-vpncmd")
#   --remove           remove the repository and the signing key again
#   --no-update        do not run "apt-get update"
#   --dry-run          print what would be executed
#   -h, --help         this help
#
# Environment overrides (mainly for testing):
#   BASE      repository base URL      (default https://kouhj.github.io/softether-deb)
#   KEYRING   where the key is written (default /etc/apt/keyrings/softether-deb.asc)
#   SOURCES   the .sources file        (default /etc/apt/sources.list.d/softether.sources)

set -eu

BASE=${BASE:-https://kouhj.github.io/softether-deb}
KEYRING=${KEYRING:-/etc/apt/keyrings/softether-deb.asc}
SOURCES=${SOURCES:-/etc/apt/sources.list.d/softether.sources}
FINGERPRINT='F709BB382606BADED145A7EC8719B125AF2E845D'
SUPPORTED='bullseye bookworm trixie forky duke jammy noble resolute'

suite=
install_pkgs=
remove=0
update=1
dry=0

usage() {
    cat <<'EOF'
Add the SoftEther VPN apt repository (Debian 13 / Ubuntu 26.04).

  sh install.sh [options]

Options:
  --suite <name>     override the detected suite (trixie, resolute)
  --install <pkg>    also install a package, e.g. softether-vpnserver
  --remove           remove the repository and the signing key
  --no-update        do not run "apt-get update"
  --dry-run          print the actions without changing anything
  -h, --help         show this help

Examples:
  curl -fsSL https://kouhj.github.io/softether-deb/install.sh | sudo sh
  sudo sh install.sh --install softether-vpnserver
  sudo sh install.sh --remove
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --suite)    suite=${2:?--suite needs a value}; shift 2 ;;
        --install)  install_pkgs=${2:?--install needs a package name}; shift 2 ;;
        --remove)   remove=1; shift ;;
        --no-update) update=0; shift ;;
        --dry-run)  dry=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        *)          echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

say()  { printf '%s\n' "$*"; }
run()  {
    if [ "$dry" = 1 ]; then
        printf '  would run: %s\n' "$*"
    else
        "$@"
    fi
}

# --------------------------------------------------------------------- helpers
fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$1"
    else
        echo "ERROR: curl or wget is required" >&2
        exit 1
    fi
}

if [ "$dry" != 1 ] && [ "$(id -u)" != 0 ]; then
    echo "ERROR: run this as root (sudo), or use --dry-run to preview" >&2
    exit 1
fi

# ---------------------------------------------------------------- remove mode
if [ "$remove" = 1 ]; then
    say "removing the repository ..."
    run rm -f "$SOURCES" "$KEYRING"
    [ "$update" = 1 ] && run apt-get update
    say "done (installed packages are left alone, use: apt purge 'softether-*')"
    exit 0
fi

# ------------------------------------------------------------ distribution
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
else
    echo "ERROR: /etc/os-release not found" >&2
    exit 1
fi

detected=${VERSION_CODENAME:-}
if [ -n "$suite" ]; then
    if [ "$suite" != "$detected" ]; then
        say "WARNING: forcing suite '$suite' on ${PRETTY_NAME:-this system} (detected '$detected')"
    fi
else
    case " $SUPPORTED " in
        *" $detected "*) suite=$detected ;;
        *)
            echo "ERROR: ${PRETTY_NAME:-unknown system} is not supported." >&2
            echo "       Published suites: $SUPPORTED" >&2
            echo "       (Debian 11/12/13/14/15 and Ubuntu 22.04/24.04/26.04)" >&2
            echo "       Use --suite <name> to override at your own risk." >&2
            exit 1
            ;;
    esac
fi

arch=$(dpkg --print-architecture 2>/dev/null || echo unknown)
if [ "$arch" != amd64 ]; then
    echo "ERROR: only amd64 packages are published (detected '$arch')" >&2
    exit 1
fi

say "repository : $BASE  (suite $suite, $arch)"
say "keyring    : $KEYRING"
say "sources    : $SOURCES"

# ------------------------------------------------------------------ add mode
say "installing the signing key ..."
run sh -c "install -d -m 0755 '$(dirname "$KEYRING")'"

if [ "$dry" = 1 ]; then
    say "  would fetch: $BASE/softether-deb.asc"
else
    tmp=$(mktemp)
    fetch "$BASE/softether-deb.asc" >"$tmp"
    if command -v gpg >/dev/null 2>&1; then
        # a private GNUPGHOME: root has none, and gpg aborts without one
        ghome=$(mktemp -d)
        got=$(GNUPGHOME=$ghome gpg --with-colons --import-options show-only --import --dry-run \
                   "$tmp" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')
        rm -rf "$ghome"
        if [ "$got" != "$FINGERPRINT" ]; then
            echo "ERROR: unexpected key fingerprint: ${got:-<none>}" >&2
            echo "       expected $FINGERPRINT" >&2
            rm -f "$tmp"
            exit 1
        fi
        say "  key fingerprint verified: $got"
    else
        say "  WARNING: gpg is not installed, the key fingerprint was not verified"
    fi
    install -m 0644 "$tmp" "$KEYRING"
    rm -f "$tmp"
fi

say "writing the DEB822 sources file ..."
if [ "$dry" = 1 ]; then
    cat <<EOF
  would write $SOURCES:
    Types: deb
    URIs: $BASE/
    Suites: $suite
    Components: main
    Architectures: $arch
    Signed-By: $KEYRING
EOF
else
    cat >"$SOURCES" <<EOF
Types: deb
URIs: $BASE/
Suites: $suite
Components: main
Architectures: $arch
Signed-By: $KEYRING
EOF
    chmod 0644 "$SOURCES"
fi

[ "$update" = 1 ] && run apt-get update

if [ -n "$install_pkgs" ]; then
    say "installing: $install_pkgs"
    # shellcheck disable=SC2086
    run apt-get install -y $install_pkgs
fi

if [ "$dry" = 1 ]; then
    say "dry run finished, nothing was changed"
else
    say "done. available versions:"
    apt-cache policy softether-vpnserver 2>/dev/null | sed -n '1,4p' | sed 's/^/  /'
fi
