# softether-deb

Build the **official** SoftEther VPN `.deb` packages for Debian 13 (trixie) and
Ubuntu 26.04, with a single local patch applied, using GitHub Actions.

## The patch

`patches/0001-comment-out-is_restricted-assignments.patch` comments out the two
assignments of `is_restricted` in `src/Cedar/Server.c`:

```c
bool is_restricted = false;                                          /* unchanged */
// is_restricted = SiIsEnterpriseFunctionsRestrictedOnOpenSource(s->Cedar);
```

`is_restricted` stays `false`, so the global flags that disable the "enterprise"
features of the open source build are never set:

| flag | feature |
|---|---|
| `GSF_DISABLE_PUSH_ROUTE` | pushing routes to clients |
| `GSF_DISABLE_RADIUS_AUTH` | RADIUS authentication |
| `GSF_DISABLE_CERT_AUTH` | client certificate authentication |
| `GSF_DISABLE_DEEP_LOGGING` | deep packet logging |
| `GSF_DISABLE_AC` | access control list / traffic shaping |
| `GSF_DISABLE_SYSLOG` | syslog output |

The declarations of the variable are kept on purpose: commenting them out would
not compile, and the rest of the function reads the variable.

## How the packages are built

The workflow runs `scripts/build-deb.sh` inside the target distribution's
container:

1. download the official source release `SoftEtherVPN-<version>.tar.xz`;
2. apply the patch with `patch -p1` and verify that no assignment of
   `is_restricted` is left;
3. `cmake -DCMAKE_BUILD_TYPE=Release` + `cmake --build`;
4. `cpack -G DEB` — the upstream project ships CPack packaging, so the packages
   are the same components the project itself defines:

   `softether-vpnserver`, `softether-vpnclient`, `softether-vpnbridge`,
   `softether-vpncmd`, `softether-common`.

Nothing else is changed: no source edits besides the patch, no repacking of the
upstream packaging rules.

## Using the artifacts

Every workflow run uploads one artifact per distribution, e.g.
`softether-deb-debian-trixie` and `softether-deb-ubuntu-26.04`, each containing
the `.deb` files plus `SHA256SUMS`:

```sh
gh run download --repo <owner>/softether-deb --name softether-deb-debian-trixie
sudo apt install ./softether-common_*.deb ./softether-vpnserver_*.deb
```

The packages carry the distribution they were built on in the artifact name
only — the `.deb` file names stay the upstream ones, so do not mix artifacts of
two distributions in one directory (the checksum file would collide).

### Upstream packaging quirk

The CPack rules in the upstream project split the packages into components but
never declare that `softether-vpnserver` (and `-vpnclient`, `-vpnbridge`,
`-vpncmd`) depend on `softether-common`, which is where `libcedar.so` and
`libmayaqua.so` live. Installing a component on its own therefore leaves it
without its libraries — always install `softether-common` in the same command
(as above). This is upstream behaviour and is left untouched here, because the
only local change to the source is the patch.

## Bumping the version

SoftEther changes `src/Cedar/Server.c` from time to time, so when a new tag
appears:

1. set `SOFTETHER_VERSION` in `.github/workflows/build-deb.yml`;
2. regenerate the patch against the new tag and check that it still applies
   (the workflow fails if the assignment is still present, and `patch` fails if
   the context does not match).

```sh
curl -fsSLO https://github.com/softethervpn/softethervpn/releases/download/<tag>/SoftEtherVPN-<tag>.tar.xz
tar -xJf SoftEtherVPN-<tag>.tar.xz && cd SoftEtherVPN-<tag>
cp src/Cedar/Server.c /tmp/Server.c.orig
sed -i 's@^\(\s*\)is_restricted = SiIsEnterpriseFunctionsRestrictedOnOpenSource(s->Cedar);@\1// [patch] enterprise restrictions disabled: is_restricted = SiIsEnterpriseFunctionsRestrictedOnOpenSource(s->Cedar);@' src/Cedar/Server.c
diff -u --label a/src/Cedar/Server.c --label b/src/Cedar/Server.c /tmp/Server.c.orig src/Cedar/Server.c > 0001.patch
```

## Releases

Pushing a tag runs the same build and then publishes a GitHub release with every
package attached:

```sh
git tag 5.2.5189
git push origin 5.2.5189
```

- the asset names carry the distribution they were built on, because the `.deb`
  file names are otherwise identical:
  `softether-vpnserver_5.2.5189_amd64.debian-trixie.deb` and
  `softether-vpnserver_5.2.5189_amd64.ubuntu-26.04.deb`;
- one `SHA256SUMS` covers all of them;
- pushing the tag again (or re-running the workflow for it) uploads the packages
  with `--clobber`, so the release is updated instead of duplicated.

## apt repository (GitHub Pages)

Tag pushes also assemble a static apt repository and publish it to GitHub Pages:

```text
https://kouhj.github.io/softether-deb/
```

- `dists/trixie/` (Debian 13) and `dists/resolute/` (Ubuntu 26.04), each with a
  signed `InRelease`, a `Release.gpg` and the `main/binary-amd64` indexes;
- one pool per suite (`pool/<suite>/main/s/softether/`) because the packages have
  the same name and version in both distributions — apt only needs the path from
  the `Filename:` field;
- the `Packages` index adds the `softether-common` dependency that upstream's
  CPack rules omit, so a component package pulls its libraries in;
- `softether-deb.asc` is the signing key. The private key is stored in the
  repository secret `GPG_PRIVATE_KEY`; when the secret is missing the index is
  published unsigned and the job says so in the log.

Add it with the helper (detects the distribution, installs and verifies the key,
writes the DEB822 file):

```sh
curl -fsSL https://kouhj.github.io/softether-deb/install.sh | sudo sh
sudo sh install.sh --install softether-vpnserver   # or: --remove / --dry-run
```

Installing by hand — **DEB822** `.sources` files for Debian 13 and Ubuntu 26.04,
key installation, verification and removal: see
[docs/apt-repo.md](docs/apt-repo.md). The helper is published next to the
repository as `install.sh`.

## Notes

- SoftEther's sources use CRLF line endings; `.gitattributes` disables any line
  ending normalisation so the patch keeps matching byte for byte.
- The packages are built from the unmodified upstream release; the only change
  is the patch above. SoftEther VPN is licensed under the Apache License 2.0 —
  see the upstream repository for the full license and disclaimer.
- This repository is not affiliated with the SoftEther project.
