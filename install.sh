#!/bin/sh
# Eagle installer for macOS and Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/joeyrobert/eagle.cr/main/install.sh | sh
#   wget -qO- https://raw.githubusercontent.com/joeyrobert/eagle.cr/main/install.sh | sh
#   sh install.sh --help
#
# Installs the `eagle` CLI into $EAGLE_HOME/bin (default ~/.eagle/bin) and the engine
# source into $EAGLE_HOME/src. Safe to re-run: it replaces the previous install.
set -eu

REPO_SLUG="joeyrobert/eagle.cr"
EAGLE_REPO="${EAGLE_REPO:-https://github.com/$REPO_SLUG}"
EAGLE_RELEASES="${EAGLE_RELEASES:-https://github.com/$REPO_SLUG/releases}"
EAGLE_HOME="${EAGLE_HOME:-$HOME/.eagle}"
EAGLE_VERSION="${EAGLE_VERSION:-latest}"
MIN_CRYSTAL="1.21.0"

WITH_DEPS=0
FROM_SOURCE=0
YES=0
MODIFY_PATH=ask
UNINSTALL=0

usage() {
  cat <<EOF
Eagle installer

Usage: install.sh [options]

Options:
  --with-deps        install missing prerequisites (Crystal, SDL2, git) with your
                     package manager; may use sudo (apt, dnf, pacman)
  --from-source      skip the prebuilt binary; clone and build with shards
  --version VERSION  install a specific release tag, e.g. v0.1.0 (or set EAGLE_VERSION)
  --yes, -y          answer yes to every prompt (PATH setup; deps only with --with-deps)
  --no-modify-path   never edit shell startup files
  --uninstall        remove \$EAGLE_HOME (default ~/.eagle)
  --help, -h         show this help

Environment:
  EAGLE_HOME      install location (default ~/.eagle)
  EAGLE_VERSION   release tag to install (default latest)
  EAGLE_REPO      git URL to build from (default $EAGLE_REPO; file:// works)
  EAGLE_RELEASES  base URL for release downloads (default $EAGLE_RELEASES)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --with-deps) WITH_DEPS=1 ;;
    --from-source) FROM_SOURCE=1 ;;
    --version) [ $# -ge 2 ] || { echo "--version needs a value" >&2; exit 2; }; EAGLE_VERSION="$2"; shift ;;
    --version=*) EAGLE_VERSION="${1#*=}" ;;
    --yes|-y) YES=1 ;;
    --no-modify-path) MODIFY_PATH=no ;;
    --uninstall) UNINSTALL=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
info() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }

# Prompts read from /dev/tty so they work under `curl | sh`, where stdin is the script.
can_prompt() { [ "$YES" -eq 0 ] && (true </dev/tty) 2>/dev/null && [ -t 2 ]; }

# confirm "question" default(y|n): --yes answers y; no terminal answers the default.
confirm() {
  if [ "$YES" -eq 1 ]; then return 0; fi
  if ! can_prompt; then [ "$2" = y ]; return; fi
  if [ "$2" = y ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  printf '%s %s ' "$1" "$hint" >&2
  read -r answer </dev/tty || answer=""
  case "$answer" in
    [yY]*) return 0 ;;
    [nN]*) return 1 ;;
    *) [ "$2" = y ] ;;
  esac
}

# version_ge A B: true when A >= B (numeric major.minor.patch).
version_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
    exit 0 }'
}

download() {
  if has curl; then curl -fsSL "$1" -o "$2"
  elif has wget; then wget -q "$1" -O "$2"
  else die "need curl or wget to download $1"
  fi
}

if [ "$UNINSTALL" -eq 1 ]; then
  if [ -x "$EAGLE_HOME/bin/eagle" ] || [ -d "$EAGLE_HOME/src" ]; then
    # Only remove what the installer created, in case EAGLE_HOME points somewhere shared.
    rm -rf "$EAGLE_HOME/src" "$EAGLE_HOME/src.new" "$EAGLE_HOME/wasm-toolchain"
    rm -f "$EAGLE_HOME/bin/eagle" "$EAGLE_HOME/bin/eagle.new"
    rmdir "$EAGLE_HOME/bin" "$EAGLE_HOME" 2>/dev/null || true
    say "Removed Eagle from $EAGLE_HOME."
  else
    say "Nothing to remove: $EAGLE_HOME doesn't look like an Eagle install."
  fi
  say "If you added it to PATH, delete the line marked '# eagle' from your shell startup file (~/.zshrc, ~/.bashrc, ~/.profile or ~/.config/fish/config.fish)."
  exit 0
fi

# ---- platform ---------------------------------------------------------------
case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux) OS=linux ;;
  MINGW*|MSYS*|CYGWIN*) die "on Windows use PowerShell: irm https://raw.githubusercontent.com/$REPO_SLUG/main/install.ps1 | iex" ;;
  *) die "unsupported OS $(uname -s); Eagle supports macOS, Linux and Windows" ;;
esac
case "$(uname -m)" in
  x86_64|amd64) ARCH=x86_64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *) die "unsupported CPU $(uname -m)" ;;
esac
info "Platform: $OS-$ARCH"

# Package manager commands for the prerequisites, per platform.
PM=""
if [ "$OS" = macos ]; then
  has brew && PM=brew
else
  if has apt-get; then PM=apt; elif has dnf; then PM=dnf; elif has pacman; then PM=pacman; fi
fi
SUDO=""
if [ "$OS" = linux ] && [ "$(id -u)" -ne 0 ]; then SUDO="sudo "; fi
CRYSTAL_SCRIPT="curl -fsSL https://crystal-lang.org/install.sh | ${SUDO}bash"
case "$PM" in
  brew) DEPS_CMDS="brew install crystal sdl2 git" ;;
  apt) DEPS_CMDS="${SUDO}apt-get update && ${SUDO}apt-get install -y git build-essential pkg-config libsdl2-dev curl
$CRYSTAL_SCRIPT" ;;
  dnf) DEPS_CMDS="${SUDO}dnf install -y git gcc pkgconf-pkg-config SDL2-devel curl
$CRYSTAL_SCRIPT" ;;
  pacman) DEPS_CMDS="${SUDO}pacman -S --needed --noconfirm crystal shards sdl2 git base-devel pkgconf" ;;
  *) if [ "$OS" = macos ]; then DEPS_CMDS="# install Homebrew from https://brew.sh, then:
brew install crystal sdl2 git"; else DEPS_CMDS="# install Crystal: https://crystal-lang.org/install/
# install SDL2 development files (libSDL2.so and headers) and git with your package manager"; fi ;;
esac

# ---- prerequisites ----------------------------------------------------------
sdl2_found() {
  if has pkg-config && pkg-config --exists sdl2 2>/dev/null; then return 0; fi
  if has sdl2-config; then return 0; fi
  for d in /opt/homebrew/lib /usr/local/lib /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu /usr/lib/aarch64-linux-gnu; do
    if [ -e "$d/libSDL2.dylib" ] || [ -e "$d/libSDL2.so" ]; then return 0; fi
  done
  return 1
}

check_prereqs() {
  MISSING=""
  if has crystal; then
    CRYSTAL_VERSION="$(crystal --version 2>/dev/null | awk 'NR == 1 { print $2 }')"
    if version_ge "$CRYSTAL_VERSION" "$MIN_CRYSTAL"; then
      say "  crystal $CRYSTAL_VERSION: ok"
    else
      say "  crystal $CRYSTAL_VERSION: too old (need >= $MIN_CRYSTAL)"
      MISSING="$MISSING crystal"
    fi
  else
    say "  crystal: missing (need >= $MIN_CRYSTAL)"
    MISSING="$MISSING crystal"
  fi
  if has shards; then say "  shards: ok"; else say "  shards: missing"; MISSING="$MISSING shards"; fi
  if sdl2_found; then say "  SDL2: ok"; else say "  SDL2: missing"; MISSING="$MISSING sdl2"; fi
  if has git; then say "  git: ok"; else say "  git: missing"; MISSING="$MISSING git"; fi
}

info "Checking prerequisites"
check_prereqs
if [ -n "$MISSING" ]; then
  say ""
  say "Missing:$MISSING. Install them with:"
  say ""
  say "$DEPS_CMDS" | sed 's/^/  /'
  say ""
  if [ -n "$PM" ] && { [ "$WITH_DEPS" -eq 1 ] || { can_prompt && confirm "Run these commands now?" n; }; }; then
    info "Installing prerequisites"
    sh -ec "$DEPS_CMDS"
    info "Re-checking prerequisites"
    check_prereqs
  fi
  [ -z "$MISSING" ] || warn "still missing:$MISSING. eagle needs Crystal and SDL2 to build games; install them and re-run this script."
fi

# ---- install ----------------------------------------------------------------
TMP="$(mktemp -d "${TMPDIR:-/tmp}/eagle-install.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$EAGLE_HOME/bin"

case "$EAGLE_VERSION" in
  latest) TAG="" ;;
  v*) TAG="$EAGLE_VERSION" ;;
  *) TAG="v$EAGLE_VERSION" ;;
esac

# Replaces $EAGLE_HOME/src and $EAGLE_HOME/bin/eagle with the ones in $1 (a dir with bin/eagle and src/).
put_in_place() {
  rm -rf "$EAGLE_HOME/src.new"
  mv "$1/src" "$EAGLE_HOME/src.new"
  rm -rf "$EAGLE_HOME/src"
  mv "$EAGLE_HOME/src.new" "$EAGLE_HOME/src"
  cp "$1/bin/eagle" "$EAGLE_HOME/bin/eagle.new"
  chmod 755 "$EAGLE_HOME/bin/eagle.new"
  mv "$EAGLE_HOME/bin/eagle.new" "$EAGLE_HOME/bin/eagle"
}

# Downloads and checks the release tarball into $TMP/release. Returns 1 if there is none or it doesn't run here.
fetch_prebuilt() {
  asset="eagle-$OS-$ARCH.tar.gz"
  if [ -n "$TAG" ]; then url="$EAGLE_RELEASES/download/$TAG/$asset"; else url="$EAGLE_RELEASES/latest/download/$asset"; fi
  info "Downloading $url"
  if ! download "$url" "$TMP/$asset" 2>/dev/null; then
    say "  no prebuilt binary for $OS-$ARCH${TAG:+ at $TAG}"
    return 1
  fi
  mkdir -p "$TMP/release"
  if ! tar xzf "$TMP/$asset" -C "$TMP/release"; then
    warn "could not unpack $asset"
    return 1
  fi
  if [ ! -x "$TMP/release/bin/eagle" ] || [ ! -d "$TMP/release/src" ]; then
    warn "$asset has an unexpected layout"
    return 1
  fi
  if ! "$TMP/release/bin/eagle" version >/dev/null 2>&1; then
    warn "the prebuilt binary doesn't run here (usually a missing Crystal or SDL2 library)"
    return 1
  fi
}

install_from_source() {
  has git || die "building from source needs git"
  if ! has crystal || ! has shards; then die "building from source needs Crystal >= $MIN_CRYSTAL and shards (see above)"; fi
  info "Cloning $EAGLE_REPO${TAG:+ at $TAG}"
  if [ -n "$TAG" ]; then
    git clone --quiet --depth 1 --branch "$TAG" "$EAGLE_REPO" "$TMP/src" || die "no release $TAG in $EAGLE_REPO; see $EAGLE_RELEASES"
  else
    git clone --quiet --depth 1 "$EAGLE_REPO" "$TMP/src"
  fi
  # Build in the final location so the binary finds its source (examples, web build script).
  rm -rf "$EAGLE_HOME/src.new"
  mv "$TMP/src" "$EAGLE_HOME/src.new"
  rm -rf "$EAGLE_HOME/src"
  mv "$EAGLE_HOME/src.new" "$EAGLE_HOME/src"
  info "Building eagle (shards build --release; this takes a minute or two)"
  (cd "$EAGLE_HOME/src" && shards build --release --no-debug eagle)
  cp "$EAGLE_HOME/src/bin/eagle" "$EAGLE_HOME/bin/eagle.new"
  chmod 755 "$EAGLE_HOME/bin/eagle.new"
  mv "$EAGLE_HOME/bin/eagle.new" "$EAGLE_HOME/bin/eagle"
}

if [ "$FROM_SOURCE" -eq 0 ] && fetch_prebuilt; then
  put_in_place "$TMP/release"
else
  [ "$FROM_SOURCE" -eq 1 ] || info "Falling back to building from source"
  install_from_source
fi

"$EAGLE_HOME/bin/eagle" version >/dev/null 2>&1 || die "installed $EAGLE_HOME/bin/eagle but it doesn't run"
info "Installed $("$EAGLE_HOME/bin/eagle" version) to $EAGLE_HOME/bin/eagle"

# ---- PATH -------------------------------------------------------------------
BIN="$EAGLE_HOME/bin"
case ":$PATH:" in
  *":$BIN:"*) ON_PATH=1 ;;
  *) ON_PATH=0 ;;
esac
if [ "$ON_PATH" -eq 0 ]; then
  SHELL_NAME="$(basename "${SHELL:-sh}")"
  case "$SHELL_NAME" in
    zsh) RC="${ZDOTDIR:-$HOME}/.zshrc"; LINE="export PATH=\"$BIN:\$PATH\" # eagle" ;;
    bash) if [ "$OS" = macos ]; then RC="$HOME/.bash_profile"; else RC="$HOME/.bashrc"; fi; LINE="export PATH=\"$BIN:\$PATH\" # eagle" ;;
    fish) RC="$HOME/.config/fish/config.fish"; LINE="fish_add_path \"$BIN\" # eagle" ;;
    *) RC="$HOME/.profile"; LINE="export PATH=\"$BIN:\$PATH\" # eagle" ;;
  esac
  if [ -f "$RC" ] && grep -F "$BIN" "$RC" >/dev/null 2>&1; then
    say "$RC already adds $BIN to PATH; open a new terminal to pick it up."
  elif [ "$MODIFY_PATH" = ask ] && { [ "$YES" -eq 1 ] || can_prompt; } && confirm "Add $BIN to PATH in $RC?" y; then
    mkdir -p "$(dirname "$RC")"
    printf '\n%s\n' "$LINE" >> "$RC"
    say "Added to $RC. Open a new terminal, or run: $LINE"
  else
    say "Add eagle to your PATH:"
    say "  $LINE"
    say "(put that line in $RC to make it permanent)"
  fi
fi

say ""
say "Get started:"
say "  eagle init mygame     # answer a few questions, or add --yes for defaults"
say "  cd mygame && eagle run"
say ""
say "Update: re-run this installer. Uninstall:"
say "  curl -fsSL https://raw.githubusercontent.com/$REPO_SLUG/main/install.sh | sh -s -- --uninstall"
