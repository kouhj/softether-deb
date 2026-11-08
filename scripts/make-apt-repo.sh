#!/bin/sh
# Assemble a static apt repository that can be served by GitHub Pages.
#
#   site/
#   ├── index.html                     landing page with the DEB822 snippet
#   ├── softether-deb.asc              signing key (copied from keys/)
#   ├── pool/<suite>/main/s/softether/*.deb + SHA256SUMS
#   └── dists/<suite>/
#       ├── Release, InRelease, Release.gpg          (InRelease/Release.gpg if GPG_KEY)
#       └── main/binary-amd64/{Packages,Packages.gz}
#
# One pool per suite because the packages have identical names and versions in
# both distributions: apt only needs the path in the `Filename:` field, so a
# per-suite pool keeps the upstream package names untouched.
#
# Environment:
#   INPUT_DIR    artefacts, one sub directory per distribution (default artifacts)
#   SITE_DIR     output directory (default site)
#   SUITES       "<suite>:<artifact-dir>" pairs
#                (default "trixie:softether-deb-debian-trixie resolute:softether-deb-ubuntu-26.04")
#   GPG_KEY      key id used to sign the indexes; sign only when it is set
set -eu

INPUT_DIR=${INPUT_DIR:-artifacts}
SITE_DIR=${SITE_DIR:-site}
SUITES=${SUITES:-"trixie:softether-deb-debian-trixie resolute:softether-deb-ubuntu-26.04"}
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPONENTS="softether-vpnserver softether-vpnclient softether-vpnbridge softether-vpncmd"

# The upstream CPack rules never declare that the component packages need the
# libraries from softether-common, so add the dependency to the index (the .deb
# itself is left untouched).
add_common_dependency() {
    awk -v components="$COMPONENTS" '
        BEGIN { n = split(components, list, " "); for (i = 1; i <= n; i++) comp[list[i]] = 1 }
        /^Package: / { inpkg = ($2 in comp) }
        /^Version: / { ver = $2 }
        /^Depends: / && inpkg && index($0, "softether-common") == 0 {
            print $0 ", softether-common (= " ver ")"
            next
        }
        { print }
    ' "$1" >"$1.new"
    mv "$1.new" "$1"
}

sign_index() {
    suite_dir=$1
    gpg --batch --yes --pinentry-mode loopback --passphrase '' \
        --default-key "$GPG_KEY" --clearsign \
        -o "$suite_dir/InRelease" "$suite_dir/Release"
    gpg --batch --yes --pinentry-mode loopback --passphrase '' \
        --default-key "$GPG_KEY" --armor --detach-sign \
        -o "$suite_dir/Release.gpg" "$suite_dir/Release"
}

rm -rf "$SITE_DIR"
mkdir -p "$SITE_DIR"
cp "$REPO_DIR/keys/softether-deb.asc" "$SITE_DIR/"
# the helper script is served next to the repository so it can be piped into sh
install -m 0755 "$REPO_DIR/install.sh" "$SITE_DIR/install.sh"
[ -f "$REPO_DIR/keys/softether-deb.gpg" ] && cp "$REPO_DIR"/keys/softether-deb.gpg "$SITE_DIR/"

for entry in $SUITES; do
    suite=${entry%%:*}
    artifact=${entry#*:}
    src="$INPUT_DIR/$artifact"
    [ -d "$src" ] || { echo "ERROR: missing artifact directory $src" >&2; exit 1; }

    echo "--- $suite"
    pool="$SITE_DIR/pool/$suite/main/s/softether"
    mkdir -p "$pool"
    cp "$src"/*.deb "$pool/"
    ( cd "$pool" && sha256sum ./*.deb >SHA256SUMS )

    index_dir="$SITE_DIR/dists/$suite/main/binary-amd64"
    mkdir -p "$index_dir"
    ( cd "$SITE_DIR" && apt-ftparchive packages "pool/$suite" >"dists/$suite/main/binary-amd64/Packages" )
    add_common_dependency "$index_dir/Packages"
    gzip -9 -kf "$index_dir/Packages"

    ( cd "$SITE_DIR" && apt-ftparchive \
        -o APT::FTPArchive::Release::Origin="SoftEther deb repository" \
        -o APT::FTPArchive::Release::Label="SoftEther VPN (patched)" \
        -o APT::FTPArchive::Release::Suite="$suite" \
        -o APT::FTPArchive::Release::Codename="$suite" \
        -o APT::FTPArchive::Release::Architectures="amd64" \
        -o APT::FTPArchive::Release::Components="main" \
        -o APT::FTPArchive::Release::Description="SoftEther VPN ${suite} packages built from the official release" \
        release "dists/$suite" >"dists/$suite/Release.tmp" )
    mv "$SITE_DIR/dists/$suite/Release.tmp" "$SITE_DIR/dists/$suite/Release"

    if [ -n "${GPG_KEY:-}" ]; then
        sign_index "$SITE_DIR/dists/$suite"
        echo "    signed with $GPG_KEY"
    else
        echo "    WARNING: GPG_KEY not set, the index is unsigned"
    fi
    echo "    $(grep -c '^Package: ' "$index_dir/Packages") package(s)"
done

cat >"$SITE_DIR/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>SoftEther VPN deb repository</title>
<style>
  body { font-family: sans-serif; max-width: 46rem; margin: 3rem auto; padding: 0 1rem; line-height: 1.5; }
  pre { background: #f4f4f4; padding: .8rem; overflow-x: auto; }
  code { font-family: monospace; }
</style>
</head>
<body>
<h1>SoftEther VPN deb repository</h1>
<p>SoftEther VPN packages built from the official upstream release for
Debian 13 (trixie) and Ubuntu 26.04 (resolute), with one local patch: the
enterprise feature restrictions of the open source build are disabled.</p>

<h2>Add the repository (DEB822)</h2>
<p><code>/etc/apt/sources.list.d/softether.sources</code>:</p>
<pre>Types: deb
URIs: https://__REPO_HOST__/
Suites: __SUITES__
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/softether-deb.asc</pre>
<p>The signing key:</p>
<pre>sudo install -d /etc/apt/keyrings
curl -fsSL https://__REPO_HOST__/softether-deb.asc \
  | sudo tee /etc/apt/keyrings/softether-deb.asc &gt;/dev/null</pre>
<p>Then <code>sudo apt update &amp;&amp; sudo apt install softether-vpnserver</code>.</p>
<p><a href="https://github.com/__REPO__">Source, build logs and releases</a></p>
</body>
</html>
HTML

# fill in the host/suites placeholders of the landing page
REPO_SLUG=${GITHUB_REPOSITORY:-}
if [ -n "$REPO_SLUG" ]; then
    owner=${REPO_SLUG%%/*}
    repo=${REPO_SLUG#*/}
    host="${owner}.github.io/${repo}"
else
    host="example.github.io/softether-deb"
fi
suite_list=$(for entry in $SUITES; do printf '%s ' "${entry%%:*}"; done)
sed -i "s|__REPO_HOST__|$host|g; s|__SUITES__|$suite_list|g; s|__REPO__|${REPO_SLUG:-owner/repo}|g" \
    "$SITE_DIR/index.html"

echo "--- site layout"
find "$SITE_DIR" -type f | sed "s|^$SITE_DIR/|    |" | sort
