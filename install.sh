#!/bin/sh
# install.sh — one-command OpenCode v2 installer for Termux / Android
#
# Community installer. OpenCode does not publish an Android build; this script
# uses the official Linux ARM64/x64 release and makes it run under Termux's
# glibc with a patched ELF interpreter and a small launcher.
#
# Usage (from GitHub raw):
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/opencode-termux/main/install.sh | sh
#
# Optional environment variables:
#   OPENCODE_ARCHIVE_URL       Override the CLI tarball URL (for mirrors/pinning)
#   OPENCODE_INSTALL_DIR       Override install dir (default: $HOME/.local/lib/opencode)
#   OPENCODE_TERMUX_INSTALL_URL Override the URL used by `termux-opencode update`

set -eu

REPO_RAW="${OPENCODE_TERMUX_INSTALL_URL:-https://raw.githubusercontent.com/YOUR_USERNAME/opencode-termux/main/install.sh}"
INSTALL_DIR="${OPENCODE_INSTALL_DIR:-$HOME/.local/lib/opencode}"
BIN_DIR="$PREFIX/bin"
LAUNCHER="$BIN_DIR/opencode"
HELPER="$BIN_DIR/termux-opencode"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Environment checks
# ---------------------------------------------------------------------------
[ -n "${PREFIX:-}" ] || die "PREFIX is not set. Run this inside Termux, not a normal Linux shell."
case "$PREFIX" in
  */com.termux/files/usr) ;;
  *) die "This installer is for Termux only (PREFIX=$PREFIX)." ;;
esac

command -v pkg >/dev/null 2>&1 || die "pkg command not found. Are you really inside Termux?"

case "$(uname -m)" in
  aarch64|arm64)
    ARCH=arm64
    LOADER_NAME=ld-linux-aarch64.so.1
    ;;
  x86_64|amd64)
    ARCH=x64
    LOADER_NAME=ld-linux-x86-64.so.2
    warn "x86_64 is detected. Only aarch64 is community-verified so far."
    ;;
  *)
    die "Unsupported architecture: $(uname -m). OpenCode publishes Linux arm64 and x64 builds."
    ;;
esac

# ---------------------------------------------------------------------------
# Dependencies (glibc runtime + patchelf)
# ---------------------------------------------------------------------------
log "Updating Termux packages..."
pkg update -y >/dev/null 2>&1 || die "pkg update failed (check your internet connection)."

log "Installing curl, tar and the glibc repository..."
pkg install -y curl tar glibc-repo >/dev/null 2>&1 || die "Could not install curl/tar/glibc-repo."

log "Refreshing package lists for the glibc repository..."
pkg update -y >/dev/null 2>&1 || die "pkg update after adding glibc-repo failed."

log "Installing the glibc runtime and patchelf..."
pkg install -y glibc-runner patchelf >/dev/null 2>&1 || die "Could not install glibc-runner/patchelf."

command -v curl >/dev/null 2>&1 || die "curl is still missing. Try: pkg install curl"
command -v tar  >/dev/null 2>&1 || die "tar is still missing. Try: pkg install tar"
command -v patchelf >/dev/null 2>&1 || die "patchelf is still missing. Try: pkg install patchelf"

LOADER="$PREFIX/glibc/lib/$LOADER_NAME"
[ -e "$LOADER" ] || die "glibc loader not found at $LOADER. Try: pkg install glibc-repo glibc-runner"

# ---------------------------------------------------------------------------
# Download + patch the official OpenCode CLI
# ---------------------------------------------------------------------------
TMP_DIR="${TMPDIR:-$PREFIX/tmp}/opencode-termux.$$"
mkdir -p "$TMP_DIR" "$INSTALL_DIR" "$BIN_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT
trap 'exit 1' HUP INT TERM

ARCHIVE="${OPENCODE_ARCHIVE_URL:-https://opencode.ai/update/api/latest/cli/opencode/opencode-linux-$ARCH.tar.gz}"
log "Downloading the official OpenCode CLI ($ARCH)..."
curl -fsSL "$ARCHIVE" -o "$TMP_DIR/opencode.tar.gz" || die "Download failed: $ARCHIVE"

log "Extracting..."
tar -xzf "$TMP_DIR/opencode.tar.gz" -C "$TMP_DIR" || die "Could not extract the archive."
[ -f "$TMP_DIR/opencode" ] || die "The archive did not contain an 'opencode' binary."
chmod 755 "$TMP_DIR/opencode"

# IMPORTANT: patch ONLY the interpreter.
# Do NOT use --set-rpath or `grun -c`: rewriting the executable corrupts the
# bundled payload (SIGSEGV / "libc.so: invalid ELF header").
log "Patching ELF interpreter -> $LOADER"
patchelf --set-interpreter "$LOADER" "$TMP_DIR/opencode" || die "patchelf failed."

# The patched binary must be started with Termux's Bionic LD_PRELOAD removed.
env -u LD_PRELOAD "$TMP_DIR/opencode" --version >/dev/null 2>&1 \
  || die "The patched binary did not start. See the Troubleshooting section of README.md."

mv "$TMP_DIR/opencode" "$INSTALL_DIR/opencode.new"
chmod 755 "$INSTALL_DIR/opencode.new"
mv -f "$INSTALL_DIR/opencode.new" "$INSTALL_DIR/opencode"
log "OpenCode binary installed to $INSTALL_DIR/opencode"

# ---------------------------------------------------------------------------
# `opencode` launcher
# ---------------------------------------------------------------------------
cat > "$TMP_DIR/opencode" <<EOF
#!$PREFIX/bin/sh
# OpenCode launcher for Termux.
# Clears Bionic's LD_PRELOAD, then runs the glibc-linked binary directly.
# Do NOT run through grun/ld.so: the background service re-execs /proc/self/exe.
unset LD_PRELOAD
exec "$INSTALL_DIR/opencode" "\$@"
EOF
chmod 755 "$TMP_DIR/opencode"
if [ -e "$LAUNCHER" ]; then
  cp -f "$LAUNCHER" "$LAUNCHER.bak" 2>/dev/null || true
  warn "Existing $LAUNCHER backed up to $LAUNCHER.bak"
fi
mv -f "$TMP_DIR/opencode" "$LAUNCHER"

# ---------------------------------------------------------------------------
# `termux-opencode` helper command
# ---------------------------------------------------------------------------
cat > "$TMP_DIR/termux-opencode" <<'HELPER_EOF'
#!/bin/sh
# termux-opencode — manage OpenCode on Termux
# Generated by install.sh. Values below are substituted at install time.
set -eu

PREFIX="__PREFIX__"
HOME_DIR="__HOME__"
INSTALL_DIR="__INSTALL_DIR__"
OPENCODE_BIN="$INSTALL_DIR/opencode"
INSTALL_URL="__INSTALL_URL__"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

random_password() {
  tr -dc A-Za-z0-9 </dev/urandom 2>/dev/null | head -c 24 || true
}

lan_ip() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 -o addr 2>/dev/null | awk '$2 !~ /^lo$/ {split($4,a,"/"); print a[1]; exit}'
  elif command -v ifconfig >/dev/null 2>&1; then
    ifconfig 2>/dev/null | awk '/inet / && $2 !~ /127\./ {print $2; exit}'
  else
    hostname -I 2>/dev/null | awk '{print $1}'
  fi
}

usage() {
  cat <<'USAGE_EOF'
termux-opencode - OpenCode helper for Termux

Usage:
  termux-opencode <command> [options]

Commands:
  status              Show the background service URL and health info
  pair [options]      Pair this phone with the OpenCode app / web UI (QR code)
  remote [options]    Pair through an end-to-end encrypted remote tunnel
  lan                 Let clients on the same Wi-Fi connect to this phone
  serve [port]        Run a foreground server on 0.0.0.0 (Ctrl+C to stop)
  connect <url>       Connect this phone's CLI to another OpenCode server
  ip                  Print this phone's LAN IP address
  update              Re-run the installer to get the latest OpenCode
  uninstall           Remove launchers and binary (keeps sessions/config)
  help                Show this help

Examples:
  termux-opencode pair
  termux-opencode remote --yes
  termux-opencode lan
  termux-opencode connect http://192.168.1.20:4096
USAGE_EOF
}

cmd_status() {
  "$OPENCODE_BIN" service status
  "$OPENCODE_BIN" api get /api/info || true
}

cmd_pair() {
  exec "$OPENCODE_BIN" pair "$@"
}

cmd_remote() {
  # First use asks for confirmation; pass --yes to accept non-interactively.
  exec "$OPENCODE_BIN" pair --remote "$@"
}

cmd_lan() {
  pass="${OPENCODE_PASSWORD:-$(random_password)}"
  [ -n "$pass" ] || die "Could not generate a password. Set OPENCODE_PASSWORD manually."
  log "Configuring OpenCode to listen on all network interfaces..."
  "$OPENCODE_BIN" service set hostname 0.0.0.0
  "$OPENCODE_BIN" service set password "$pass"
  "$OPENCODE_BIN" service start
  ip="$(lan_ip)"
  status_out="$("$OPENCODE_BIN" service status 2>/dev/null || true)"
  url="$(printf '%s\n' "$status_out" | grep -oE 'http://[^[:space:]]+' | head -1 || true)"
  display_url="$url"
  if [ -n "$ip" ] && [ -n "$display_url" ]; then
    display_url="$(printf '%s' "$display_url" | sed "s|0\\.0\\.0\\.0|$ip|g; s|\\[::\\]|$ip|g")"
  fi
  [ -n "$display_url" ] || display_url="http://${ip:-<phone-ip>}:49374"
  log "LAN address : $display_url"
  log "Username    : opencode"
  log "Password    : $pass"
  log "On your iPhone/desktop (same Wi-Fi), open the address and sign in."
  log "Tip: run 'termux-opencode pair' to print a QR code/link instead."
  printf '%s\n' "$status_out"
}

cmd_serve() {
  if [ "$#" -gt 0 ]; then port="$1"; shift; else port=4096; fi
  pass="${OPENCODE_PASSWORD:-$(random_password)}"
  [ -n "$pass" ] || die "Could not generate a password. Set OPENCODE_PASSWORD manually."
  log "Starting foreground server on 0.0.0.0:$port (Ctrl+C to stop)"
  log "Password: $pass"
  OPENCODE_PASSWORD="$pass" exec "$OPENCODE_BIN" serve --hostname 0.0.0.0 --port "$port" "$@"
}

cmd_connect() {
  [ "$#" -ge 1 ] || die "Usage: termux-opencode connect <url>  (e.g. http://192.168.1.20:4096)"
  url="$1"; shift
  exec "$OPENCODE_BIN" --server "$url" "$@"
}

cmd_update() {
  case "$INSTALL_URL" in
    *YOUR_USERNAME*) die "Edit install.sh and set your GitHub username/repo before using update." ;;
  esac
  log "Re-running the installer from $INSTALL_URL"
  curl -fsSL "$INSTALL_URL" | sh
}

cmd_uninstall() {
  rm -f "$PREFIX/bin/opencode" "$PREFIX/bin/termux-opencode"
  rm -rf "$INSTALL_DIR"
  log "Removed the launchers and binary."
  log "Your sessions/config were kept in ~/.config/opencode and ~/.local/share/opencode."
}

cmd="${1:-help}"
if [ "$#" -gt 0 ]; then shift; fi

case "$cmd" in
  status)               cmd_status "$@" ;;
  pair)                 cmd_pair "$@" ;;
  remote)               cmd_remote "$@" ;;
  lan)                  cmd_lan "$@" ;;
  serve)                cmd_serve "$@" ;;
  connect)              cmd_connect "$@" ;;
  ip)                   lan_ip ;;
  update)               cmd_update "$@" ;;
  uninstall)            cmd_uninstall "$@" ;;
  -h|--help|help)       usage ;;
  -v|--version|version) "$OPENCODE_BIN" --version ;;
  *)
    usage >&2
    die "Unknown command: $cmd"
    ;;
esac
HELPER_EOF

sed \
  -e "s|__PREFIX__|$PREFIX|g" \
  -e "s|__HOME__|$HOME|g" \
  -e "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
  -e "s|__INSTALL_URL__|$REPO_RAW|g" \
  "$TMP_DIR/termux-opencode" > "$TMP_DIR/termux-opencode.out"

chmod 755 "$TMP_DIR/termux-opencode.out"
if [ -e "$HELPER" ]; then
  cp -f "$HELPER" "$HELPER.bak" 2>/dev/null || true
  warn "Existing $HELPER backed up to $HELPER.bak"
fi
mv -f "$TMP_DIR/termux-opencode.out" "$HELPER"

log "Done."
printf '\n'
printf '  opencode --version           verify the CLI\n'
printf '  opencode                     start the TUI in a project folder\n'
printf '  termux-opencode help         see connection commands\n'
printf '\n'

# Keep the service alive on Android when Termux:API is installed (optional).
if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock >/dev/null 2>&1 || true
  log "Acquired a Termux wake lock so the background service is less likely to be killed."
fi
