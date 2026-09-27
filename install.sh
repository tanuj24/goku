#!/bin/sh
# Goku installer for macOS and Linux (formerly Mimir) — https://github.com/tanuj24/mimir
#
#   curl -fsSL https://tanuj24.github.io/mimir/install.sh | sh
#
# Installs the goku CLI, a native binary for macOS and Linux on x86_64 and arm64, verified against the
# release's SHA-256 checksums, to /usr/local/bin (or ~/.local/bin without sudo), plus `mimir`, the
# command's former name (deprecated), as a link to it. An existing goku or mimir install is upgraded in
# place. Platforms without a prebuilt binary get the goku shell script instead.
# (Windows: irm https://tanuj24.github.io/mimir/install.ps1 | iex)
#
#   GOKU_VERSION        install this release (e.g. 0.3.0) instead of the latest
#   GOKU_DOWNLOAD_BASE  where the release files are (goku_<os>_<arch>, checksums.txt); default: the
#                       GitHub release. A file:// URL works too.
#   GOKU_INSTALL_DIR    install into this directory
#   GOKU_CLI_URL        install the file at this URL as goku, as it is (former name: MIMIR_CLI_URL)
set -eu

SITE="https://tanuj24.github.io/mimir"
RELEASES="https://github.com/tanuj24/mimir/releases"
CLI_URL="${GOKU_CLI_URL:-${MIMIR_CLI_URL:-}}"
SYSTEM_DIR=/usr/local/bin
USER_DIR="$HOME/.local/bin"

say() { printf '%s\n' "$*"; }
die() { printf 'install: %s\n' "$*" >&2; exit 1; }

# download URL FILE
download() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    die "curl (or wget) is required"
  fi
}

# sha256 FILE — the hex SHA-256 of the file
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | awk '{ print $NF }'
  else
    die "sha256sum or shasum is required to verify the download"
  fi
}

os=""
arch=""
case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    die "on Windows, install from PowerShell: irm $SITE/install.ps1 | iex" ;;
esac
case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
esac
# An x86_64 shell under Rosetta on Apple silicon: install the native arm64 binary.
if [ "$os" = darwin ] && [ "$arch" = amd64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" = 1 ]; then
  arch=arm64
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/goku-install.XXXXXX") || die "cannot create a temporary directory"
trap 'rm -rf "$tmp"' EXIT
file="$tmp/goku"

if [ -n "$CLI_URL" ]; then
  say "downloading goku CLI from ${CLI_URL}…"
  download "$CLI_URL" "$file" 2>/dev/null || die "download failed ($CLI_URL)"
  kind="from $CLI_URL"
elif [ -n "$os" ] && [ -n "$arch" ]; then
  asset="goku_${os}_${arch}"
  if [ -n "${GOKU_DOWNLOAD_BASE:-}" ]; then
    base=${GOKU_DOWNLOAD_BASE%/}
  elif [ -n "${GOKU_VERSION:-}" ]; then
    base="$RELEASES/download/v${GOKU_VERSION#v}"
  else
    base="$RELEASES/latest/download"
  fi
  say "downloading goku CLI ($asset)…"
  download "$base/$asset" "$file" 2>/dev/null || die "download failed ($base/$asset)"
  download "$base/checksums.txt" "$tmp/checksums.txt" 2>/dev/null || die "download failed ($base/checksums.txt)"
  want=$(awk -v f="$asset" '$2 == f || $2 == "*" f { print $1; exit }' "$tmp/checksums.txt")
  [ -n "$want" ] || die "checksums.txt has no entry for $asset; nothing was installed"
  got=$(sha256 "$file")
  [ "$got" = "$want" ] || die "checksum mismatch for $asset (expected $want, got $got); nothing was installed"
  kind="native binary, $os/$arch"
else
  # No prebuilt binary for this platform: the goku shell script (it needs sh, curl, awk, sed and grep).
  say "no prebuilt goku binary for $(uname -s) $(uname -m); installing the goku shell script…"
  for tool in curl awk sed grep; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required"
  done
  got=false
  # The site serves the script as /goku and, for installers of the former name, as /mimir.
  for url in "$SITE/goku" "$SITE/mimir"; do
    if download "$url" "$file" 2>/dev/null; then got=true; break; fi
  done
  $got || die "download failed ($SITE/goku)"
  head -2 "$file" | grep -q -e goku -e mimir || die "downloaded file doesn't look right; aborting"
  kind="shell script"
fi
chmod 755 "$file"
# The download must run here: its version line proves it is a working goku for this machine.
version=$("$file" version 2>/dev/null | head -1 || true)
case "$version" in
  "goku CLI "*) ;;
  *) die "the downloaded goku does not run on this machine; nothing was installed" ;;
esac

# Where: GOKU_INSTALL_DIR, else where goku or (the former) mimir is already installed, else
# /usr/local/bin when writable (or with sudo), else ~/.local/bin.
dir=${GOKU_INSTALL_DIR:-}
if [ -z "$dir" ]; then
  for c in goku mimir; do
    for d in "$SYSTEM_DIR" "$USER_DIR"; do
      if [ -z "$dir" ] && { [ -e "$d/$c" ] || [ -L "$d/$c" ]; }; then dir=$d; fi
    done
  done
fi
if [ -z "$dir" ]; then
  if [ -w "$SYSTEM_DIR" ] || { command -v sudo >/dev/null 2>&1 && [ -d "$SYSTEM_DIR" ]; }; then
    dir=$SYSTEM_DIR
  else
    dir=$USER_DIR
  fi
fi

# A Homebrew install is upgraded with brew, not here.
for c in goku mimir; do
  if [ -L "$dir/$c" ]; then
    case "$(readlink "$dir/$c")" in
      */Cellar/*) die "$dir/$c was installed with Homebrew — upgrade it with: brew upgrade $c" ;;
    esac
  fi
done

sudo=""
if [ -d "$dir" ] && [ ! -w "$dir" ]; then
  command -v sudo >/dev/null 2>&1 || die "cannot write to $dir (set GOKU_INSTALL_DIR to install elsewhere)"
  sudo=sudo
  say "installing to $dir (sudo may prompt)…"
fi
run() { if [ -n "$sudo" ]; then sudo "$@"; else "$@"; fi; }

upgrading=""
if [ -e "$dir/mimir" ] && [ ! -L "$dir/mimir" ]; then upgrading="$dir/mimir"; fi
replacing_script=""
if [ -f "$dir/goku" ] && head -1 "$dir/goku" 2>/dev/null | grep -q '^#!' && ! head -1 "$file" | grep -q '^#!'; then
  replacing_script="$dir/goku"
fi

run mkdir -p "$dir"
run cp "$file" "$dir/goku.new"
run chmod 755 "$dir/goku.new"
run mv -f "$dir/goku.new" "$dir/goku"
# mimir, the former name (deprecated): a link to goku, so scripts and habits that call mimir keep working.
run rm -f "$dir/mimir"
run ln -s goku "$dir/mimir"
GOKU_NO_DEPRECATION_NOTICE=1 "$dir/mimir" version >/dev/null 2>&1 || die "$dir/mimir does not run"

case ":$PATH:" in
  *":$dir:"*) : ;;
  *) say ""; say "NOTE: add $dir to your PATH:"; say "  export PATH=\"$dir:\$PATH\"" ;;
esac
for c in goku mimir; do
  found=$(command -v "$c" 2>/dev/null || true)
  case "$found" in
    ""|"$dir/$c") : ;;
    /*) say ""; say "NOTE: $found comes first on your PATH — remove it (or put $dir first) to use this install." ;;
  esac
done

say ""
if [ -n "$upgrading" ]; then
  say "upgraded $upgrading: Mimir is now Goku. 'mimir' is now a link to 'goku' and keeps working (deprecated)."
fi
if [ -n "$replacing_script" ]; then
  say "replaced the goku shell script $replacing_script with the native goku binary."
fi
say "Installed goku (and mimir, deprecated) in $dir"
say "  $dir/goku   $version ($kind)"
say "  $dir/mimir  -> goku: the former name; it prints a deprecation note (GOKU_NO_DEPRECATION_NOTICE=1 hides it)"
say ""
say "Get started:"
say "  goku start                  # run the local cloud"
say "  eval \"\$(goku env)\"          # point the AWS CLI / SDKs at it"
say "  goku help                   # snapshots, chaos, iam, lambda debug, logs…"
