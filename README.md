# OpenCode for Termux (one-command installer)

A beginner-friendly installer that puts **OpenCode v2** on your Android phone through Termux, then gives you a small command — `termux-opencode` — for pairing with the OpenCode app, desktop app, web UI, iPhone, or any other client.

> [!IMPORTANT]
> OpenCode does not publish an official Android build. This installer uses the **official Linux release binary** and makes it run under Termux with glibc, `patchelf`, and a tiny launcher. The method is community-verified on Termux aarch64; treat it as community support, not official Android support.

---

## What you get

| Command | What it does |
| --- | --- |
| `opencode` | The real OpenCode CLI/TUI, working in Termux |
| `termux-opencode` | Helper for pairing, remote access, LAN server, connecting to another server, update/uninstall |

The installer:

1. Installs `curl`, `tar`, `glibc-repo`, `glibc-runner`, and `patchelf` with `pkg`.
2. Downloads the latest official CLI from `opencode.ai`.
3. Patches **only** the ELF interpreter to Termux's glibc loader.
4. Writes a launcher that clears Termux's Bionic `LD_PRELOAD` and starts the binary directly.
5. Writes the `termux-opencode` helper command.
6. Verifies the binary starts with `opencode --version`.

Your chats, config, and credentials are **never** deleted by this installer or by `termux-opencode uninstall`. If an older `opencode` or `termux-opencode` launcher already exists, it is backed up to `$PREFIX/bin/<name>.bak` before being replaced.

---

## Requirements

- Android phone or tablet (aarch64 — almost all modern phones). x86_64 is detected but not community-verified yet.
- [Termux](https://github.com/termux/termux-app/releases) installed from **GitHub releases or F-Droid**. The old Play Store version is outdated and will not work.
- Internet connection and about 200 MB free storage.
- Basic familiarity with pasting a command into Termux.

---

## Quick install

> [!WARNING]
> Replace `YOUR_USERNAME` with your GitHub username before publishing. Also replace it in `install.sh` (the `REPO_RAW` variable) so `termux-opencode update` knows where to fetch updates.

Open **Termux** and paste this single line:

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/opencode-termux/main/install.sh | sh
```

Wait for the dependencies and the download to finish. Then check it:

```sh
opencode --version
opencode service status
termux-opencode help
```

Start the TUI inside a project folder:

```sh
cd ~/my-project
opencode
```

Inside OpenCode, use `/connect` to add a model provider (OpenCode Console, Anthropic, OpenAI, etc.).

---

## Connect to other devices

### 1. Phone → desktop / another computer

Run OpenCode on the **desktop** and connect the phone CLI to it.

On the desktop:

```sh
OPENCODE_PASSWORD="a-long-secret" opencode serve --hostname 0.0.0.0 --port 4096
```

On the phone:

```sh
OPENCODE_PASSWORD="a-long-secret" termux-opencode connect http://DESKTOP_IP:4096
```

Find `DESKTOP_IP` with `ip addr` (Linux) or `ipconfig` (Windows) on the desktop. Both devices should be on the same Wi-Fi, or you can use a VPN/tunnel.

Alternatively, on the desktop run `opencode pair` and scan the QR code with the OpenCode app — the app can talk to the desktop directly.

### 2. Phone → iPhone, desktop, or browser (phone is the server)

**Easy way (works from anywhere):**

```sh
termux-opencode remote --yes
```

This prints a link and QR code. Open the link in a browser or scan it with the OpenCode app on your iPhone. Traffic is end-to-end encrypted and still requires your server password. The first time you run it, OpenCode asks before enabling remote access; `--yes` accepts that prompt.

**Same Wi-Fi way (no internet tunnel):**

```sh
termux-opencode lan
```

It sets the service to `0.0.0.0`, generates a password, starts the service, and prints a URL like `http://192.168.1.23:49374`. On your iPhone/desktop, open that URL and sign in with:

- username: `opencode`
- password: the one printed by the command

Keep the Termux screen on while using the LAN server. Android may kill background services when the screen is off; if `termux-tools` is installed, the installer automatically takes a wake lock. You can also take one manually:

```sh
termux-wake-lock
```

**Foreground server instead of a background service:**

```sh
termux-opencode serve 4096
```

Press `Ctrl+C` to stop it.

### 3. Desktop app / OpenCode app pairing

- On any machine, `opencode pair` prints a one-time link and QR code. Links expire after 5 minutes.
- The OpenCode app can scan the QR code or paste the link into its server address field.
- Sessions last 30 days. Changing the server password signs every session out.

---

## `termux-opencode` command reference

```text
termux-opencode status              Show service URL and health info
termux-opencode pair                Pair this phone (local QR/link)
termux-opencode remote --yes        Pair via encrypted remote tunnel
termux-opencode lan                 Allow same-Wi-Fi clients to connect
termux-opencode serve [port]        Foreground server on 0.0.0.0 (default 4096)
termux-opencode connect <url>       Connect this CLI to another server
termux-opencode ip                  Print this phone's LAN IP
termux-opencode update              Download and reinstall the latest OpenCode
termux-opencode uninstall           Remove launchers and binary only
termux-opencode help                Show built-in help
```

Extra arguments are passed through to OpenCode, so things like `termux-opencode pair --remote --yes` work too.

---

## Update and uninstall

Update OpenCode (re-downloads the latest official release):

```sh
termux-opencode update
```

or re-run the curl command from [Quick install](#quick-install).

Remove only the files this project installed:

```sh
termux-opencode uninstall
```

This keeps `~/.config/opencode`, `~/.local/share/opencode`, and your sessions. To fully wipe OpenCode data, use `opencode uninstall` (preview first with `opencode uninstall --dry-run`).

---

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `error while loading shared libraries: ld-linux-aarch64.so.1` | glibc runtime missing | `pkg install glibc-repo glibc-runner`, then re-run the installer |
| `Segmentation fault` on `opencode --version` | Binary was patched with `--set-rpath` or via `grun -c` | Re-run this installer; it patches **only** `--set-interpreter` |
| `libc.so: invalid ELF header` | Same as above, or `LD_PRELOAD` still set | Re-run the installer; make sure you use the generated `opencode` launcher |
| `serve: error while loading shared libraries: serve` | Binary started through `grun`, `ld.so`, or a self-executing wrapper | Run the generated `opencode` launcher directly |
| `opencode: command not found` after install | New shell has not picked up `$PREFIX/bin` | Open a new Termux session, or run `exec $SHELL` |
| Service dies when the screen is off | Android battery optimization | `termux-wake-lock` and disable battery optimization for Termux |
| Cannot reach the LAN URL from iPhone | Wrong IP, different Wi-Fi, or service not listening on `0.0.0.0` | Check `termux-opencode ip`, then `termux-opencode lan` |
| Want to stop listening on all interfaces | Service is still set to `0.0.0.0` | `opencode service set hostname 127.0.0.1 && opencode service start` |
| Proxy/certificate errors | Corporate proxy or HTTPS inspection | See the [OpenCode network docs](https://opencode.ai/docs/network/) |

If you need to reset, `termux-opencode uninstall` then re-run the installer. It is safe to re-run.

---

## Advanced / customization

- Pin a mirror or a specific tarball (export first so the installer's `sh` process sees it):

  ```sh
  export OPENCODE_ARCHIVE_URL="https://your-mirror/opencode-linux-arm64.tar.gz"
  curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/opencode-termux/main/install.sh | sh
  ```

- Change the install directory: `export OPENCODE_INSTALL_DIR="$HOME/.local/share/my-opencode"` before running.
- Change the update URL (forks): `export OPENCODE_TERMUX_INSTALL_URL="https://raw.githubusercontent.com/YOU/REPO/main/install.sh"`.

---

## How it works / credits

- The glibc + `patchelf` method follows the community Termux guidance proposed for the official docs ([PR #62695](https://github.com/anomalyco/opencode/pull/62695)).
- OpenCode itself: <https://opencode.ai> · [docs](https://opencode.ai/docs/) · [GitHub](https://github.com/anomalyco/opencode)
- Pairing / web UI: <https://opencode.ai/docs/cli/web/>
- Termux: <https://termux.dev>

This project is not affiliated with Anomaly or the OpenCode team.

---

## License

MIT — see [LICENSE](LICENSE). Adjust the copyright line with your name before publishing.
