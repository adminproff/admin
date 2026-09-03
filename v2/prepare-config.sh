#!/usr/bin/env bash
set -Eeuo pipefail

WORK_DIR=""
VERSION=""
DEFAULT_URL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --default-url)
            DEFAULT_URL="$2"
            shift 2
            ;;
        *)
            printf 'Неизвестный аргумент: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

[[ -n "$WORK_DIR" ]] || { echo 'Не задан --work-dir' >&2; exit 2; }
[[ -n "$VERSION" ]] || { echo 'Не задан --version' >&2; exit 2; }
[[ -n "$DEFAULT_URL" ]] || { echo 'Не задан --default-url' >&2; exit 2; }

CONFIG="$WORK_DIR/config"

mkdir -p \
    "$CONFIG/package-lists" \
    "$CONFIG/hooks/live" \
    "$CONFIG/includes.chroot/etc/chromium/policies/managed" \
    "$CONFIG/includes.chroot/etc/lightdm/lightdm.conf.d" \
    "$CONFIG/includes.chroot/etc/live/config.conf.d" \
    "$CONFIG/includes.chroot/etc/NetworkManager/conf.d" \
    "$CONFIG/includes.chroot/etc/openbox" \
    "$CONFIG/includes.chroot/etc/xdg/openbox" \
    "$CONFIG/includes.chroot/etc/op-kiosk" \
    "$CONFIG/includes.chroot/etc/polkit-1/rules.d" \
    "$CONFIG/includes.chroot/etc/sudoers.d" \
    "$CONFIG/includes.chroot/etc/systemd/journald.conf.d" \
    "$CONFIG/includes.chroot/etc/systemd/logind.conf.d" \
    "$CONFIG/includes.chroot/etc/systemd/system/lightdm.service.d" \
    "$CONFIG/includes.chroot/etc/systemd/system" \
    "$CONFIG/includes.chroot/etc/tmpfiles.d" \
    "$CONFIG/includes.chroot/opt/op-kiosk/html" \
    "$CONFIG/includes.chroot/usr/local/sbin" \
    "$CONFIG/includes.chroot/usr/share/xsessions" \
    "$CONFIG/includes.chroot/var/lib/op-kiosk" \
    "$CONFIG/includes.installer/usr/lib/finish-install.d" \
    "$CONFIG/binary_debian-installer" \
    "$CONFIG/includes.binary"

cat >"$CONFIG/package-lists/op-kiosk.list.chroot" <<'EOF'
live-boot
live-config
linux-image-amd64
systemd-sysv
network-manager
wpasupplicant
iw
rfkill
wireless-regdb
lightdm
lightdm-gtk-greeter
openbox
xserver-xorg-core
xserver-xorg-input-libinput
xserver-xorg-video-amdgpu
xserver-xorg-video-ati
xserver-xorg-video-vesa
x11-xserver-utils
x11-utils
xdotool
xterm
unclutter
chromium
zenity
fonts-dejavu-core
fonts-liberation
fonts-noto-core
fonts-noto-color-emoji
ca-certificates
curl
jq
python3-minimal
iproute2
iputils-ping
dnsutils
procps
psmisc
util-linux
pciutils
usbutils
ethtool
sudo
polkitd
pkexec
dbus-x11
xauth
locales
firmware-linux-free
firmware-linux-nonfree
firmware-misc-nonfree
firmware-amd-graphics
firmware-realtek
firmware-iwlwifi
firmware-atheros
firmware-brcm80211
firmware-mediatek
firmware-libertas
grub-pc-bin
grub-efi-amd64-bin
grub-efi-amd64-signed
shim-signed
EOF

cat >"$CONFIG/includes.chroot/etc/live/config.conf.d/10-op-kiosk.conf" <<'EOF'
LIVE_USERNAME="kiosk"
LIVE_USER_FULLNAME="OP Kiosk"
LIVE_HOSTNAME="op-kiosk"
LIVE_USER_DEFAULT_GROUPS="audio cdrom video render input netdev plugdev"
EOF

cat >"$CONFIG/includes.chroot/etc/NetworkManager/conf.d/10-op-kiosk.conf" <<'EOF'
[main]
plugins=keyfile

[connectivity]
enabled=false

[connection]
wifi.powersave=2
EOF

{
    printf 'KIOSK_URL=%q\n' "$DEFAULT_URL"
    printf 'PROXY_URL=\n'
    printf 'IGNORE_CERT_ERRORS=no\n'
    printf 'BROWSER=chromium\n'
} >"$CONFIG/includes.chroot/var/lib/op-kiosk/kiosk.conf"

cat >"$CONFIG/includes.chroot/etc/op-kiosk/release-info" <<EOF
PRODUCT=OP Kiosk OS
VERSION=$VERSION
TARGET=HP t530 amd64
BASE=Debian 13 trixie
INSTALLER=Debian Installer live-installer
SESSION=systemd -> LightDM -> Openbox -> Chromium
DEFAULT_URL=$DEFAULT_URL
STATUS=EXPERIMENTAL until complete install-and-cold-boot CI passes
EOF

# SHA-256 строки "opkiosk" без перевода строки.
printf '%s\n' 'cac03bc1def5b023ca4dc45d45b74011a4a468e89f30cf70b2b8ff002f1143cc' \
    >"$CONFIG/includes.chroot/etc/op-kiosk/admin.sha256"

cat >"$CONFIG/includes.chroot/etc/lightdm/lightdm.conf.d/50-op-kiosk.conf" <<'EOF'
[LightDM]
run-directory=/run/lightdm

[Seat:*]
autologin-user=kiosk
autologin-user-timeout=0
autologin-session=op-kiosk
user-session=op-kiosk
greeter-session=lightdm-gtk-greeter
greeter-hide-users=true
greeter-show-manual-login=false
allow-guest=false
xserver-command=X -core -nolisten tcp -s 0 -dpms
EOF

cat >"$CONFIG/includes.chroot/etc/systemd/system/lightdm.service.d/10-op-kiosk.conf" <<'EOF'
[Unit]
After=live-config.service NetworkManager.service op-kiosk-firstboot.service
Wants=NetworkManager.service
EOF

cat >"$CONFIG/includes.chroot/usr/share/xsessions/op-kiosk.desktop" <<'EOF'
[Desktop Entry]
Name=OP Kiosk Session
Comment=OP Kiosk OS controlled browser session
Exec=/opt/op-kiosk/session.sh
TryExec=/opt/op-kiosk/session.sh
Type=Application
DesktopNames=OPKIOSK
EOF

cat >"$CONFIG/includes.chroot/etc/xdg/openbox/rc.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <focusLast>yes</focusLast>
    <underMouse>no</underMouse>
    <focusDelay>150</focusDelay>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>
  <placement>
    <policy>Smart</policy>
    <center>yes</center>
    <monitor>Primary</monitor>
    <primaryMonitor>1</primaryMonitor>
  </placement>
  <theme>
    <name>Clearlooks</name>
    <titleLayout>NLIMC</titleLayout>
    <keepBorder>yes</keepBorder>
    <animateIconify>no</animateIconify>
  </theme>
  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
    <names><name>OP Kiosk</name></names>
    <popupTime>0</popupTime>
  </desktops>
  <keyboard>
    <chainQuitKey>C-g</chainQuitKey>
    <keybind key="C-A-m">
      <action name="Execute"><command>/opt/op-kiosk/admin-menu.sh</command></action>
    </keybind>
    <keybind key="C-A-t">
      <action name="Execute"><command>/opt/op-kiosk/admin-terminal.sh</command></action>
    </keybind>
    <keybind key="C-S-F12">
      <action name="Execute"><command>/opt/op-kiosk/admin-menu.sh</command></action>
    </keybind>
    <keybind key="C-S-F11">
      <action name="Execute"><command>/opt/op-kiosk/admin-terminal.sh</command></action>
    </keybind>
    <keybind key="A-F4">
      <action name="Execute"><command>/bin/true</command></action>
    </keybind>
    <keybind key="C-A-Delete">
      <action name="Execute"><command>/bin/true</command></action>
    </keybind>
    <keybind key="A-Tab">
      <action name="Execute"><command>/bin/true</command></action>
    </keybind>
    <keybind key="W-r">
      <action name="Execute"><command>/bin/true</command></action>
    </keybind>
  </keyboard>
  <mouse>
    <dragThreshold>8</dragThreshold>
    <doubleClickTime>200</doubleClickTime>
    <screenEdgeWarpTime>0</screenEdgeWarpTime>
    <context name="Root">
      <mousebind button="Right" action="Press">
        <action name="Execute"><command>/bin/true</command></action>
      </mousebind>
      <mousebind button="Middle" action="Press">
        <action name="Execute"><command>/bin/true</command></action>
      </mousebind>
    </context>
  </mouse>
  <applications>
    <application class="Chromium-browser">
      <decor>no</decor>
      <maximized>yes</maximized>
      <fullscreen>yes</fullscreen>
    </application>
    <application class="chromium">
      <decor>no</decor>
      <maximized>yes</maximized>
      <fullscreen>yes</fullscreen>
    </application>
  </applications>
  <menu>
    <file>/etc/xdg/openbox/menu.xml</file>
    <hideDelay>200</hideDelay>
    <middle>no</middle>
    <submenuShowDelay>200</submenuShowDelay>
    <applicationIcons>no</applicationIcons>
    <manageDesktops>no</manageDesktops>
  </menu>
</openbox_config>
EOF

cat >"$CONFIG/includes.chroot/etc/xdg/openbox/menu.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="OP Kiosk OS" />
</openbox_menu>
EOF

cat >"$CONFIG/includes.chroot/opt/op-kiosk/session.sh" <<'EOF'
#!/bin/bash
set -Eeuo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LOG_DIR=/var/log/op-kiosk
SESSION_LOG="$LOG_DIR/session.log"
OPENBOX_LOG="$LOG_DIR/openbox.log"

mkdir -p "$LOG_DIR" "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
touch "$SESSION_LOG" "$OPENBOX_LOG"
exec >>"$SESSION_LOG" 2>&1

printf '\n[%s] OP Kiosk Session: uid=%s display=%s\n' \
    "$(date -Is)" "$(id -u)" "${DISPLAY:-unset}"

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] \
   && [[ "${1:-}" != "--inside-dbus" ]] \
   && command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session -- "$0" --inside-dbus
fi

export HOME="${HOME:-/home/kiosk}"
export USER=kiosk
export LOGNAME=kiosk
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${XDG_RUNTIME_DIR:-/tmp}/cache}"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

setxkbmap -layout 'us,ru' -option 'grp:alt_shift_toggle' >/dev/null 2>&1 || true
xset s off >/dev/null 2>&1 || true
xset -dpms >/dev/null 2>&1 || true
xset s noblank >/dev/null 2>&1 || true
xsetroot -solid '#07101f' >/dev/null 2>&1 || true

unclutter -idle 3 -root >/dev/null 2>&1 &
UNCLUTTER_PID=$!

: >"$OPENBOX_LOG"
openbox --config-file /etc/xdg/openbox/rc.xml >>"$OPENBOX_LOG" 2>&1 &
OPENBOX_PID=$!

cleanup() {
    kill -TERM "${BROWSER_PID:-}" "${OPENBOX_PID:-}" "${UNCLUTTER_PID:-}" \
        2>/dev/null || true
    wait "${BROWSER_PID:-}" "${OPENBOX_PID:-}" "${UNCLUTTER_PID:-}" \
        2>/dev/null || true
}
trap 'cleanup; exit 0' INT TERM HUP
trap cleanup EXIT

for _ in $(seq 1 100); do
    kill -0 "$OPENBOX_PID" 2>/dev/null || {
        echo "[$(date -Is)] Openbox завершился до готовности"
        tail -n 80 "$OPENBOX_LOG" 2>/dev/null || true
        exit 40
    }
    pgrep -u "$(id -u)" -x openbox >/dev/null 2>&1 && break
    sleep 0.1
done
sleep 0.5

/opt/op-kiosk/browser-supervisor.sh &
BROWSER_PID=$!

while true; do
    if ! kill -0 "$OPENBOX_PID" 2>/dev/null; then
        echo "[$(date -Is)] Openbox завершился; LightDM перезапустит сессию"
        exit 41
    fi
    if ! kill -0 "$BROWSER_PID" 2>/dev/null; then
        rc=0
        wait "$BROWSER_PID" || rc=$?
        echo "[$(date -Is)] Диспетчер Chromium завершился, rc=$rc"
        exit 42
    fi
    sleep 1
done
EOF

cat >"$CONFIG/includes.chroot/opt/op-kiosk/browser-supervisor.sh" <<'EOF'
#!/bin/bash
set -u

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
CONF=/var/lib/op-kiosk/kiosk.conf
LOG_DIR=/var/log/op-kiosk
LOG="$LOG_DIR/browser.log"
PROFILE=/var/lib/op-kiosk/chromium
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
CACHE="${XDG_CACHE_HOME:-$RUNTIME/cache}/chromium"
LOCAL_PORT=8099
LOCAL_ROOT=/opt/op-kiosk/html
HTTP_LOG="$LOG_DIR/local-http.log"
BROWSER_PID=""
HTTP_PID=""

mkdir -p "$LOG_DIR" "$PROFILE" "$CACHE" "$RUNTIME"
touch "$LOG" "$HTTP_LOG"
chmod 0700 "$PROFILE" "$CACHE" "$RUNTIME" 2>/dev/null || true
exec >>"$LOG" 2>&1

serial() {
    printf '%s\n' "$*" >/dev/ttyS0 2>/dev/null || true
    printf '%s\n' "$*"
}

ci_mode() {
    [[ -e /etc/op-kiosk/ci-mode ]] \
        || grep -qw 'opkiosk.ci=1' /proc/cmdline 2>/dev/null
}

load_conf() {
    KIOSK_URL=''
    PROXY_URL=''
    IGNORE_CERT_ERRORS='no'
    BROWSER='chromium'
    # shellcheck disable=SC1090
    source "$CONF" 2>/dev/null || true
}

resolve_browser() {
    local configured="${1:-chromium}"
    local candidate
    for candidate in \
        "$configured" \
        /usr/bin/chromium \
        /usr/lib/chromium/chromium \
        chromium chromium-browser google-chrome-stable google-chrome; do
        if [[ "$candidate" == */* ]]; then
            [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
        elif command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done
    return 1
}

target_reachable() {
    local url="$1"
    local ignore_cert="$2"
    [[ -n "$url" ]] || return 1
    case "$url" in
        file://*)
            [[ -e "${url#file://}" ]]
            return
            ;;
        http://*|https://*)
            local -a curl_args
            curl_args=(-fsS -o /dev/null --connect-timeout 3 --max-time 5)
            [[ "$ignore_cert" == yes ]] && curl_args+=(-k)
            curl "${curl_args[@]}" "$url"
            return
            ;;
        *)
            return 1
            ;;
    esac
}

urlencode() {
    python3 - "$1" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=''))
PY
}

start_local_server() {
    python3 -m http.server "$LOCAL_PORT" \
        --bind 127.0.0.1 \
        --directory "$LOCAL_ROOT" \
        >>"$HTTP_LOG" 2>&1 &
    HTTP_PID=$!
    for _ in $(seq 1 50); do
        curl -fsS "http://127.0.0.1:$LOCAL_PORT/offline.html" \
            >/dev/null 2>&1 && return 0
        kill -0 "$HTTP_PID" 2>/dev/null || return 1
        sleep 0.1
    done
    return 1
}

stop_browser() {
    local pid="${BROWSER_PID:-}"
    [[ -n "$pid" ]] || return 0
    kill -TERM "$pid" 2>/dev/null || true
    pkill -TERM -u "$(id -u)" -f -- "--user-data-dir=$PROFILE" \
        2>/dev/null || true
    for _ in $(seq 1 40); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    kill -KILL "$pid" 2>/dev/null || true
    pkill -KILL -u "$(id -u)" -f -- "--user-data-dir=$PROFILE" \
        2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    BROWSER_PID=""
}

cleanup() {
    stop_browser
    if [[ -n "${HTTP_PID:-}" ]]; then
        kill -TERM "$HTTP_PID" 2>/dev/null || true
        wait "$HTTP_PID" 2>/dev/null || true
    fi
}
trap 'cleanup; exit 0' INT TERM HUP
trap cleanup EXIT

run_browser() {
    local browser="$1"
    local launch_url="$2"
    local target_url="$3"
    local proxy_url="$4"
    local ignore_cert="$5"
    local mode="$6"
    local safe_mode="$7"
    local -a args

    rm -f "$PROFILE"/SingletonLock "$PROFILE"/SingletonSocket \
        "$PROFILE"/SingletonCookie 2>/dev/null || true

    args=(
        --kiosk
        --start-fullscreen
        --ozone-platform=x11
        --no-first-run
        --no-default-browser-check
        --noerrdialogs
        --disable-session-crashed-bubble
        --disable-infobars
        --disable-notifications
        --disable-component-update
        --disable-background-networking
        --disable-features=TranslateUI,MediaRouter,OptimizationHints,GlobalMediaControls
        --disable-dev-shm-usage
        --disable-breakpad
        --disable-crash-reporter
        --overscroll-history-navigation=0
        --disable-pinch
        --autoplay-policy=no-user-gesture-required
        --user-data-dir="$PROFILE"
        --disk-cache-dir="$CACHE"
        --password-store=basic
    )

    [[ -n "$proxy_url" ]] && args+=(--proxy-server="$proxy_url")
    [[ "$ignore_cert" == yes ]] && args+=(--ignore-certificate-errors)

    if [[ "$safe_mode" == yes ]]; then
        args+=(--disable-gpu --disable-gpu-compositing --no-sandbox)
    fi

    if ci_mode; then
        args+=(
            --remote-debugging-address=127.0.0.1
            --remote-debugging-port=9222
            --remote-allow-origins=http://127.0.0.1:9222
        )
    fi

    printf '\n[%s] Chromium: mode=%s safe=%s URL=%s\n' \
        "$(date -Is)" "$mode" "$safe_mode" "$launch_url"
    printf '[%s] Команда: %q' "$(date -Is)" "$browser"
    printf ' %q' "${args[@]}" "$launch_url"
    printf '\n'

    local started elapsed rc failures
    started="$(date +%s)"
    failures=0
    "$browser" "${args[@]}" "$launch_url" &
    BROWSER_PID=$!
    serial "OPKIOSK_BROWSER_STARTED mode=$mode pid=$BROWSER_PID"

    while kill -0 "$BROWSER_PID" 2>/dev/null; do
        sleep 5

        if [[ "$mode" == offline ]]; then
            if target_reachable "$target_url" "$ignore_cert"; then
                serial OPKIOSK_TARGET_RECOVERED
                stop_browser
                return 20
            fi
        elif [[ "$mode" == online ]]; then
            if target_reachable "$target_url" "$ignore_cert"; then
                failures=0
            else
                failures=$((failures + 1))
                if (( failures >= 3 )); then
                    serial OPKIOSK_TARGET_LOST
                    stop_browser
                    return 21
                fi
            fi
        fi
    done

    rc=0
    wait "$BROWSER_PID" || rc=$?
    BROWSER_PID=""
    elapsed=$(( $(date +%s) - started ))
    printf '[%s] Chromium завершился: rc=%s, время=%ss\n' \
        "$(date -Is)" "$rc" "$elapsed"

    if (( elapsed < 8 )) && [[ "$safe_mode" == no ]]; then
        return 111
    fi
    return "$rc"
}

: >"$LOG"
: >"$HTTP_LOG"

if ! start_local_server; then
    serial OPKIOSK_LOCAL_HTTP_FAILED
fi

while true; do
    load_conf

    if ! BROWSER_PATH="$(resolve_browser "${BROWSER:-chromium}")"; then
        serial OPKIOSK_BROWSER_BINARY_NOT_FOUND
        sleep 10
        continue
    fi

    TARGET_URL="${KIOSK_URL:-}"
    PROXY="${PROXY_URL:-}"
    IGNORE_CERT="${IGNORE_CERT_ERRORS:-no}"

    if target_reachable "$TARGET_URL" "$IGNORE_CERT"; then
        MODE=online
        LAUNCH_URL="$TARGET_URL"
    else
        MODE=offline
        ENCODED_TARGET="$(urlencode "$TARGET_URL")"
        LAUNCH_URL="http://127.0.0.1:$LOCAL_PORT/offline.html?target=$ENCODED_TARGET"
    fi

    run_browser "$BROWSER_PATH" "$LAUNCH_URL" "$TARGET_URL" \
        "$PROXY" "$IGNORE_CERT" "$MODE" no
    rc=$?

    if [[ $rc -eq 111 ]]; then
        serial OPKIOSK_BROWSER_EARLY_FAILURE_SAFE_RETRY
        run_browser "$BROWSER_PATH" "$LAUNCH_URL" "$TARGET_URL" \
            "$PROXY" "$IGNORE_CERT" "$MODE" yes
        rc=$?
    fi

    sleep 2
done
EOF

cat >"$CONFIG/includes.chroot/opt/op-kiosk/html/offline.html" <<'EOF'
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>OP Kiosk OS — ожидание сервера</title>
<style>
:root{color-scheme:dark;--bg:#07101f;--panel:rgba(16,29,49,.88);--line:rgba(143,184,255,.22);--text:#f6f9ff;--muted:#9fb0c8;--accent:#58a6ff;--ok:#35d39a;--warn:#ffbd59}
*{box-sizing:border-box}
html,body{height:100%;margin:0;font-family:Inter,"Segoe UI",Arial,sans-serif;background:radial-gradient(circle at 18% 16%,#183c6e 0,transparent 34%),radial-gradient(circle at 82% 84%,#124754 0,transparent 36%),linear-gradient(145deg,#050b15,#0a1728 58%,#07101f);color:var(--text);overflow:hidden}
body:before{content:"";position:fixed;inset:0;background-image:linear-gradient(rgba(255,255,255,.018) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.018) 1px,transparent 1px);background-size:34px 34px;mask-image:linear-gradient(to bottom,rgba(0,0,0,.85),transparent)}
.wrap{height:100%;display:grid;place-items:center;padding:36px}
.card{position:relative;width:min(920px,95vw);padding:56px 62px;border:1px solid var(--line);border-radius:30px;background:var(--panel);backdrop-filter:blur(18px);box-shadow:0 34px 100px rgba(0,0,0,.42)}
.brand{display:flex;align-items:center;gap:20px;margin-bottom:38px}.logo{width:68px;height:68px;border-radius:20px;display:grid;place-items:center;background:linear-gradient(145deg,#62adff,#30d5a6);box-shadow:0 14px 38px rgba(79,165,255,.28);font-size:29px;font-weight:900;color:#06101e}
h1{font-size:48px;line-height:1.06;margin:0;letter-spacing:-1.5px}.subtitle{margin:8px 0 0;color:var(--muted);font-size:17px}
.status{display:flex;align-items:center;gap:15px;margin:10px 0 30px;padding:18px 20px;border-radius:18px;background:rgba(255,189,89,.08);border:1px solid rgba(255,189,89,.22)}
.dot{width:13px;height:13px;border-radius:50%;background:var(--warn);box-shadow:0 0 0 7px rgba(255,189,89,.12);animation:pulse 2s infinite}@keyframes pulse{50%{box-shadow:0 0 0 13px rgba(255,189,89,0)}}
.status strong{font-size:19px}.status span{color:var(--muted)}.message{font-size:23px;line-height:1.5;margin:0 0 26px}.url{padding:17px 19px;border:1px solid var(--line);border-radius:15px;background:rgba(0,0,0,.18);font:600 17px/1.45 Consolas,monospace;overflow-wrap:anywhere;color:#cfe5ff}
.hint{display:flex;align-items:center;justify-content:space-between;gap:20px;padding-top:27px;margin-top:28px;border-top:1px solid var(--line);color:var(--muted);font-size:16px}.keys{white-space:nowrap}kbd{display:inline-grid;place-items:center;min-width:38px;height:34px;padding:0 10px;margin:0 2px;border-radius:8px;background:#14233a;border:1px solid #2c466b;box-shadow:inset 0 -2px rgba(0,0,0,.32);color:#fff;font:700 14px "Segoe UI",Arial}
@media(max-width:680px){.card{padding:40px 28px}h1{font-size:36px}.hint{align-items:flex-start;flex-direction:column}.message{font-size:20px}}
</style>
</head>
<body>
<div class="wrap"><main class="card">
<div class="brand"><div class="logo">OP</div><div><h1>OP Kiosk OS</h1><p class="subtitle">Защищённый доступ к веб-приложению</p></div></div>
<div class="status"><span class="dot"></span><div><strong>Ожидание рабочего сервера</strong><br><span>Сеть и Chromium запущены; подключение проверяется автоматически</span></div></div>
<p class="message">Система продолжает попытки подключения. После восстановления связи браузер сам откроет рабочий адрес.</p>
<div class="url" id="target">Рабочий адрес не задан</div>
<div class="hint"><span>Настройка сети и адреса</span><span class="keys"><kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>M</kbd></span></div>
</main></div>
<script>
const p=new URLSearchParams(location.search);const target=p.get('target')||'';
document.getElementById('target').textContent=target||'Рабочий адрес не задан';
</script>
</body>
</html>
EOF

cat >"$CONFIG/includes.chroot/opt/op-kiosk/admin-menu.sh" <<'EOF'
#!/bin/bash
set -u

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
CONF=/var/lib/op-kiosk/kiosk.conf
TITLE='OP Kiosk OS — сервисное меню'
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
LOCK_FILE="$RUNTIME/op-kiosk-admin-menu.lock"
mkdir -p "$RUNTIME" 2>/dev/null || true
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

serial() {
    printf '%s\n' "$*" >/dev/ttyS0 2>/dev/null || true
}

ci_mode() {
    [[ -e /etc/op-kiosk/ci-mode ]] \
        || grep -qw 'opkiosk.ci=1' /proc/cmdline 2>/dev/null
}

zinfo() {
    zenity --info --title="$TITLE" --width=700 --text="$1" 2>/dev/null
}

zerr() {
    zenity --error --title="$TITLE" --width=700 --text="$1" 2>/dev/null
}

check_password() {
    ci_mode && return 0
    local pass hash
    pass=$(zenity --password --title="$TITLE" \
        --text='Пароль администратора:' 2>/dev/null) || exit 0
    hash=$(printf '%s' "$pass" | sha256sum | awk '{print $1}')
    if ! printf '%s\n' "$hash" | sudo /usr/local/sbin/op-kiosk-auth; then
        zerr 'Неверный пароль.'
        exit 1
    fi
}

load_conf() {
    KIOSK_URL=''
    PROXY_URL=''
    IGNORE_CERT_ERRORS='no'
    BROWSER='chromium'
    # shellcheck disable=SC1090
    source "$CONF" 2>/dev/null || true
}

save_conf() {
    local tmp="$CONF.tmp.$$"
    umask 077
    {
        printf 'KIOSK_URL=%q\n' "$KIOSK_URL"
        printf 'PROXY_URL=%q\n' "$PROXY_URL"
        printf 'IGNORE_CERT_ERRORS=%q\n' "$IGNORE_CERT_ERRORS"
        printf 'BROWSER=%q\n' "$BROWSER"
    } >"$tmp"
    mv -f "$tmp" "$CONF"
}

restart_browser() {
    pkill -TERM -u "$(id -u)" -f -- '--user-data-dir=/var/lib/op-kiosk/chromium' \
        2>/dev/null || true
}

network_status() {
    load_conf
    local tmp
    tmp=$(mktemp)
    {
        printf 'OP Kiosk OS\n'
        printf '============\n\n'
        printf 'Рабочий URL: %s\n' "${KIOSK_URL:-не задан}"
        printf 'Proxy: %s\n' "${PROXY_URL:-нет}"
        printf 'Игнорирование ошибок сертификата: %s\n\n' "$IGNORE_CERT_ERRORS"
        printf 'Сетевые устройства:\n'
        nmcli -f DEVICE,TYPE,STATE,CONNECTION device status 2>&1 || true
        printf '\nIPv4-адреса:\n'
        ip -brief -4 address show 2>&1 || true
        printf '\nМаршруты:\n'
        ip -4 route show 2>&1 || true
        printf '\nDNS:\n'
        nmcli -f GENERAL.DEVICE,IP4.DNS device show 2>&1 || true
        printf '\nСлужбы:\n'
        systemctl --no-pager --plain is-active \
            NetworkManager.service lightdm.service op-kiosk-health.service \
            2>&1 || true
    } >"$tmp"
    zenity --text-info --title="$TITLE — состояние" \
        --width=920 --height=650 --filename="$tmp" 2>/dev/null || true
    rm -f "$tmp"
}

wifi_connect() {
    local dev rows choice ssid security pass hidden cname keymgmt
    hidden=no
    dev=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null \
        | awk -F: '$2=="wifi"{print $1; exit}')
    [[ -n "$dev" ]] || {
        zerr 'Wi-Fi адаптер не найден. Проверьте внутренний модуль или USB-адаптер.'
        return
    }

    nmcli radio wifi on >/dev/null 2>&1 || true
    nmcli dev wifi rescan ifname "$dev" >/dev/null 2>&1 || true
    sleep 2

    rows=$(nmcli -t -e no -f SSID,SIGNAL,SECURITY \
        dev wifi list ifname "$dev" 2>/dev/null \
        | awk -F: 'length($1)>0 && !seen[$1]++ {printf "%s|%s|%s\n",$1,$2,$3}')

    choice=$({
        printf '%s|%s|%s\n' '[Скрытая сеть / ввести SSID]' '-' '-'
        printf '%s\n' "$rows"
    } | awk -F'|' '{print $1"\n"$2"\n"$3}' \
      | zenity --list --title="$TITLE — Wi-Fi" \
            --width=860 --height=540 \
            --column='SSID' --column='Сигнал, %' --column='Защита' \
            2>/dev/null) || return

    if [[ "$choice" == '[Скрытая сеть / ввести SSID]' ]]; then
        ssid=$(zenity --entry --title="$TITLE — Wi-Fi" \
            --text='Введите SSID скрытой сети:' 2>/dev/null) || return
        hidden=yes
        security=$(printf 'WPA2 / WPA2-WPA3\nWPA3-SAE\nОткрытая сеть\n' \
            | zenity --list --title="$TITLE — Wi-Fi" \
                --column='Защита' 2>/dev/null) || return
    else
        ssid="$choice"
        security=$(nmcli -t -e no -f SSID,SECURITY \
            dev wifi list ifname "$dev" 2>/dev/null \
            | awk -F: -v s="$ssid" '$1==s{print $2; exit}')
    fi

    [[ -n "$ssid" ]] || return
    cname="OP-WIFI-$ssid"

    if [[ "$hidden" == yes ]]; then
        nmcli con delete "$cname" >/dev/null 2>&1 || true
        nmcli con add type wifi ifname "$dev" con-name "$cname" ssid "$ssid" \
            802-11-wireless.hidden yes \
            connection.autoconnect yes connection.autoconnect-priority 50 \
            ipv4.method auto ipv4.route-metric 600 \
            ipv6.method auto ipv6.route-metric 600 \
            >/dev/null || { zerr 'Не удалось создать профиль Wi-Fi.'; return; }
        if [[ "$security" != 'Открытая сеть' ]]; then
            pass=$(zenity --password --title="$TITLE — Wi-Fi" \
                --text="Пароль сети «$ssid»:" 2>/dev/null) || return
            [[ "$security" == 'WPA3-SAE' ]] && keymgmt=sae || keymgmt=wpa-psk
            nmcli con mod "$cname" wifi-sec.key-mgmt "$keymgmt" wifi-sec.psk "$pass"
        fi
        nmcli con up "$cname" >/dev/null \
            || { zerr 'Не удалось подключиться к Wi-Fi.'; return; }
    else
        if [[ -n "$security" && "$security" != '--' ]]; then
            pass=$(zenity --password --title="$TITLE — Wi-Fi" \
                --text="Пароль сети «$ssid»:" 2>/dev/null) || return
            nmcli dev wifi connect "$ssid" password "$pass" ifname "$dev" \
                >/dev/null || {
                    zerr 'Не удалось подключиться к Wi-Fi. Проверьте пароль.'
                    return
                }
        else
            nmcli dev wifi connect "$ssid" ifname "$dev" >/dev/null \
                || { zerr 'Не удалось подключиться к открытой сети.'; return; }
        fi
        cname=$(nmcli -t -f NAME,TYPE con show --active 2>/dev/null \
            | awk -F: '$2=="802-11-wireless"{print $1; exit}')
    fi

    if [[ -n "$cname" ]]; then
        nmcli con mod "$cname" \
            connection.autoconnect yes connection.autoconnect-priority 50 \
            ipv4.route-metric 600 ipv6.route-metric 600 \
            802-11-wireless.powersave 2 2>/dev/null || true
    fi
    zinfo "Wi-Fi подключён: $ssid"
}

forget_wifi() {
    local list con
    list=$(nmcli -t -f NAME,TYPE con show 2>/dev/null \
        | awk -F: '$2=="802-11-wireless"{print $1}')
    [[ -n "$list" ]] || { zinfo 'Сохранённых Wi-Fi сетей нет.'; return; }
    con=$(printf '%s\n' "$list" \
        | zenity --list --title="$TITLE — удалить Wi-Fi" \
            --width=700 --height=420 --column='Профиль' 2>/dev/null) || return
    nmcli con delete "$con" >/dev/null \
        || { zerr 'Не удалось удалить профиль.'; return; }
    zinfo 'Профиль Wi-Fi удалён.'
}

configure_ipv4() {
    local list con mode addr gateway dns ctype
    list=$(nmcli -t -f NAME,TYPE con show 2>/dev/null \
        | awk -F: '$2=="802-3-ethernet" || $2=="802-11-wireless" {print $1}')
    [[ -n "$list" ]] || { zerr 'Сетевые подключения не найдены.'; return; }

    con=$(printf '%s\n' "$list" \
        | zenity --list --title="$TITLE — IPv4" \
            --width=760 --height=450 --column='Подключение' 2>/dev/null) || return
    mode=$(printf 'DHCP\nСтатический IPv4\n' \
        | zenity --list --title="$TITLE — IPv4" \
            --width=500 --height=260 --column='Режим' 2>/dev/null) || return

    if [[ "$mode" == DHCP ]]; then
        nmcli con mod "$con" \
            ipv4.method auto ipv4.addresses '' ipv4.gateway '' ipv4.dns '' \
            ipv4.ignore-auto-dns no
    else
        addr=$(zenity --entry --title="$TITLE" --width=700 \
            --text='IP/префикс, например 192.168.1.50/24:' 2>/dev/null) || return
        gateway=$(zenity --entry --title="$TITLE" --width=700 \
            --text='Шлюз. Можно оставить пустым:' 2>/dev/null) || return
        dns=$(zenity --entry --title="$TITLE" --width=700 \
            --text='DNS через запятую, например 192.168.1.10,192.168.1.11:' \
            2>/dev/null) || return
        [[ "$addr" =~ ^[0-9.]+/[0-9]{1,2}$ ]] \
            || { zerr 'Некорректный адрес или префикс.'; return; }
        nmcli con mod "$con" \
            ipv4.method manual ipv4.addresses "$addr" \
            ipv4.gateway "$gateway" ipv4.dns "$dns" ipv4.ignore-auto-dns yes
    fi

    ctype=$(nmcli -g connection.type con show "$con" 2>/dev/null || true)
    if [[ "$ctype" == '802-11-wireless' ]]; then
        nmcli con mod "$con" connection.autoconnect-priority 50 \
            ipv4.route-metric 600 ipv6.route-metric 600
    else
        nmcli con mod "$con" connection.autoconnect-priority 100 \
            ipv4.route-metric 100 ipv6.route-metric 100
    fi

    nmcli con down "$con" >/dev/null 2>&1 || true
    nmcli con up "$con" >/dev/null 2>&1 \
        || { zerr 'Параметры сохранены, но подключение сейчас не поднялось.'; return; }
    zinfo 'Настройки IPv4 применены.'
}

set_url() {
    load_conf
    local value
    value=$(zenity --entry --title="$TITLE" --width=760 \
        --text='Рабочий URL:' \
        --entry-text="${KIOSK_URL:-http://}" 2>/dev/null) || return
    if [[ -n "$value" && ! "$value" =~ ^(https?|file):// ]]; then
        value="http://$value"
    fi
    KIOSK_URL="$value"
    save_conf
    restart_browser
    zinfo 'Рабочий URL сохранён. Chromium перезапускается.'
}

set_proxy() {
    load_conf
    local value
    value=$(zenity --entry --title="$TITLE" --width=760 \
        --text='Proxy. Оставьте пустым для прямого подключения. Пример: http://10.0.0.10:3128' \
        --entry-text="${PROXY_URL:-}" 2>/dev/null) || return
    PROXY_URL="$value"
    save_conf
    restart_browser
    zinfo 'Настройка proxy сохранена.'
}

toggle_cert_errors() {
    load_conf
    local value
    value=$(printf 'no — проверять сертификаты\nyes — разрешить внутренний недоверенный сертификат\n' \
        | zenity --list --title="$TITLE — HTTPS" --width=700 --height=280 \
            --column='Режим' 2>/dev/null) || return
    case "$value" in
        no*) IGNORE_CERT_ERRORS=no ;;
        yes*) IGNORE_CERT_ERRORS=yes ;;
        *) return ;;
    esac
    save_conf
    restart_browser
    zinfo 'Настройка проверки сертификата сохранена.'
}

show_diagnostics() {
    local tmp
    tmp=$(mktemp)
    {
        printf '=== OP Kiosk OS diagnostics ===\n'
        date -Is
        printf '\n--- release ---\n'
        cat /etc/op-kiosk/release-info 2>&1 || true
        printf '\n--- boot ---\n'
        cat /proc/cmdline 2>&1 || true
        printf '\n--- systemd ---\n'
        systemctl --no-pager --plain status \
            NetworkManager.service lightdm.service \
            op-kiosk-network-priority.service op-kiosk-health.service \
            2>&1 || true
        printf '\n--- network ---\n'
        nmcli device status 2>&1 || true
        ip address 2>&1 || true
        ip route 2>&1 || true
        printf '\n--- processes ---\n'
        ps auxww 2>&1 | grep -E 'lightdm|openbox|chromium|op-kiosk' || true
        printf '\n--- browser log ---\n'
        tail -n 120 /var/log/op-kiosk/browser.log 2>&1 || true
        printf '\n--- session log ---\n'
        tail -n 120 /var/log/op-kiosk/session.log 2>&1 || true
        printf '\n--- lightdm journal ---\n'
        journalctl -b -u lightdm.service --no-pager -n 120 2>&1 || true
    } >"$tmp"
    zenity --text-info --title="$TITLE — диагностика" \
        --width=1050 --height=720 --filename="$tmp" 2>/dev/null || true
    rm -f "$tmp"
}

change_admin_password() {
    local first second hash
    first=$(zenity --password --title="$TITLE" \
        --text='Новый пароль администратора:' 2>/dev/null) || return
    [[ ${#first} -ge 6 ]] \
        || { zerr 'Пароль должен содержать минимум 6 символов.'; return; }
    second=$(zenity --password --title="$TITLE" \
        --text='Повторите новый пароль:' 2>/dev/null) || return
    [[ "$first" == "$second" ]] \
        || { zerr 'Пароли не совпадают.'; return; }
    hash=$(printf '%s' "$first" | sha256sum | awk '{print $1}')
    printf '%s\n' "$hash" | sudo /usr/local/sbin/op-kiosk-set-admin-hash \
        || { zerr 'Не удалось изменить пароль.'; return; }
    zinfo 'Пароль администратора изменён.'
}

check_password
serial OPKIOSK_MENU_OPENED

while true; do
    action=$(zenity --list --title="$TITLE" \
        --width=820 --height=690 --column='Действие' \
        'Состояние сети' \
        'Подключить Wi-Fi' \
        'Удалить сохранённую Wi-Fi сеть' \
        'DHCP / статический IPv4' \
        'Задать рабочий URL' \
        'Настроить proxy' \
        'Проверка HTTPS-сертификата' \
        'Перезапустить Chromium' \
        'Показать диагностику' \
        'Сменить пароль администратора' \
        'Перезагрузить' \
        'Выключить' \
        'Закрыть меню' 2>/dev/null) || exit 0

    case "$action" in
        'Состояние сети') network_status ;;
        'Подключить Wi-Fi') wifi_connect ;;
        'Удалить сохранённую Wi-Fi сеть') forget_wifi ;;
        'DHCP / статический IPv4') configure_ipv4 ;;
        'Задать рабочий URL') set_url ;;
        'Настроить proxy') set_proxy ;;
        'Проверка HTTPS-сертификата') toggle_cert_errors ;;
        'Перезапустить Chromium') restart_browser ;;
        'Показать диагностику') show_diagnostics ;;
        'Сменить пароль администратора') change_admin_password ;;
        'Перезагрузить') systemctl reboot ;;
        'Выключить') systemctl poweroff ;;
        *) exit 0 ;;
    esac
done
EOF

cat >"$CONFIG/includes.chroot/opt/op-kiosk/admin-terminal.sh" <<'EOF'
#!/bin/bash
set -u

TITLE='OP Kiosk OS — диагностический терминал'

ci_mode() {
    [[ -e /etc/op-kiosk/ci-mode ]] \
        || grep -qw 'opkiosk.ci=1' /proc/cmdline 2>/dev/null
}

if ! ci_mode; then
    pass=$(zenity --password --title="$TITLE" \
        --text='Пароль администратора:' 2>/dev/null) || exit 0
    hash=$(printf '%s' "$pass" | sha256sum | awk '{print $1}')
    if ! printf '%s\n' "$hash" | sudo /usr/local/sbin/op-kiosk-auth; then
        zenity --error --title="$TITLE" --text='Неверный пароль.' \
            2>/dev/null || true
        exit 1
    fi
fi

printf '%s\n' OPKIOSK_TERMINAL_OPENED >/dev/ttyS0 2>/dev/null || true

exec xterm \
    -T "$TITLE" \
    -fa 'DejaVu Sans Mono' \
    -fs 12 \
    -geometry 120x36 \
    -bg '#07101f' \
    -fg '#f4f8ff' \
    -e /opt/op-kiosk/terminal-shell.sh
EOF

cat >"$CONFIG/includes.chroot/opt/op-kiosk/terminal-shell.sh" <<'EOF'
#!/bin/bash
export LANG=ru_RU.UTF-8
export LC_ALL=ru_RU.UTF-8
export TERM=xterm-256color
export PS1='kiosk@op-kiosk:\w\$ '
clear
cat <<'EOT'
OP Kiosk OS — диагностический терминал
=======================================

Полезные команды:
  nmcli device status
  ip -4 address
  ip route
  systemctl status lightdm
  tail -n 100 /var/log/op-kiosk/browser.log
  tail -n 100 /var/log/op-kiosk/session.log

Терминал работает от непривилегированного пользователя kiosk.
Для выхода: exit
EOT
printf '\n'
exec /bin/bash --noprofile --norc
EOF

cat >"$CONFIG/includes.chroot/usr/local/sbin/op-kiosk-auth" <<'EOF'
#!/bin/bash
set -euo pipefail
read -r HASH
[[ "$HASH" =~ ^[0-9a-fA-F]{64}$ ]] || exit 2
EXPECTED=$(tr -d '[:space:]' </etc/op-kiosk/admin.sha256)
[[ "${HASH,,}" == "${EXPECTED,,}" ]]
EOF

cat >"$CONFIG/includes.chroot/usr/local/sbin/op-kiosk-set-admin-hash" <<'EOF'
#!/bin/bash
set -euo pipefail
read -r HASH
[[ "$HASH" =~ ^[0-9a-fA-F]{64}$ ]] || exit 2
printf '%s\n' "${HASH,,}" >/etc/op-kiosk/admin.sha256
chown root:root /etc/op-kiosk/admin.sha256
chmod 0600 /etc/op-kiosk/admin.sha256
EOF

cat >"$CONFIG/includes.chroot/etc/sudoers.d/op-kiosk" <<'EOF'
Defaults:kiosk !requiretty
kiosk ALL=(root) NOPASSWD: /usr/local/sbin/op-kiosk-auth
kiosk ALL=(root) NOPASSWD: /usr/local/sbin/op-kiosk-set-admin-hash
EOF

cat >"$CONFIG/includes.chroot/etc/polkit-1/rules.d/49-op-kiosk.rules" <<'EOF'
polkit.addRule(function(action, subject) {
    if (subject.user !== "kiosk") {
        return polkit.Result.NOT_HANDLED;
    }

    if (action.id.indexOf("org.freedesktop.NetworkManager.") === 0 ||
        action.id === "org.freedesktop.login1.reboot" ||
        action.id === "org.freedesktop.login1.reboot-multiple-sessions" ||
        action.id === "org.freedesktop.login1.power-off" ||
        action.id === "org.freedesktop.login1.power-off-multiple-sessions") {
        return polkit.Result.YES;
    }

    return polkit.Result.NOT_HANDLED;
});
EOF

cat >"$CONFIG/includes.chroot/etc/chromium/policies/managed/op-kiosk.json" <<'EOF'
{
  "DeveloperToolsAvailability": 2,
  "BrowserAddPersonEnabled": false,
  "GuestModeEnabled": false,
  "IncognitoModeAvailability": 1,
  "DefaultBrowserSettingEnabled": false,
  "TranslateEnabled": false,
  "AutofillAddressEnabled": false,
  "AutofillCreditCardEnabled": false,
  "PasswordManagerEnabled": false,
  "BackgroundModeEnabled": false,
  "BrowserSignin": 0,
  "MetricsReportingEnabled": false,
  "PromotionalTabsEnabled": false,
  "ShowHomeButton": false,
  "RestoreOnStartup": 4,
  "AllowDeletingBrowserHistory": false
}
EOF

cat >"$CONFIG/includes.chroot/opt/op-kiosk/network-priority.sh" <<'EOF'
#!/bin/bash
set -u

sleep 2

while IFS=: read -r dev type state; do
    [[ "$type" == ethernet ]] || continue
    [[ -n "$dev" && "$dev" != lo ]] || continue
    if ! nmcli -t -f NAME,DEVICE con show 2>/dev/null \
        | awk -F: -v d="$dev" '$2==d{found=1} END{exit !found}'; then
        nmcli con add type ethernet ifname "$dev" con-name "OP-LAN-$dev" \
            connection.autoconnect yes connection.autoconnect-priority 100 \
            ipv4.method auto ipv4.route-metric 100 \
            ipv6.method auto ipv6.route-metric 100 \
            >/dev/null 2>&1 || true
    fi
done < <(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null)

while IFS=: read -r name type; do
    case "$type" in
        802-3-ethernet)
            nmcli con mod "$name" \
                connection.autoconnect yes connection.autoconnect-priority 100 \
                ipv4.route-metric 100 ipv6.route-metric 100 \
                2>/dev/null || true
            ;;
        802-11-wireless)
            nmcli con mod "$name" \
                connection.autoconnect yes connection.autoconnect-priority 50 \
                ipv4.route-metric 600 ipv6.route-metric 600 \
                802-11-wireless.powersave 2 \
                2>/dev/null || true
            ;;
    esac
done < <(nmcli -t -f NAME,TYPE con show 2>/dev/null)
EOF

cat >"$CONFIG/includes.chroot/etc/systemd/system/op-kiosk-network-priority.service" <<'EOF'
[Unit]
Description=OP Kiosk OS network connection priorities
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/opt/op-kiosk/network-priority.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat >"$CONFIG/includes.chroot/opt/op-kiosk/health-check.sh" <<'EOF'
#!/bin/bash
set -u

serial() {
    printf '%s\n' "$*" >/dev/ttyS0 2>/dev/null || true
    printf '%s\n' "$*"
}

ci_mode() {
    [[ -e /etc/op-kiosk/ci-mode ]] \
        || grep -qw 'opkiosk.ci=1' /proc/cmdline 2>/dev/null
}

serial OPKIOSK_HEALTH_STARTED

for _ in $(seq 1 240); do
    lightdm_ok=0
    x_ok=0
    openbox_ok=0
    chromium_ok=0
    page_ok=1

    systemctl is-active --quiet lightdm.service && lightdm_ok=1
    [[ -S /tmp/.X11-unix/X0 ]] && x_ok=1
    pgrep -u kiosk -x openbox >/dev/null 2>&1 && openbox_ok=1
    pgrep -u kiosk -f '/chromium.*--kiosk' >/dev/null 2>&1 && chromium_ok=1

    if ci_mode; then
        page_ok=0
        json=$(curl -fsS --max-time 2 http://127.0.0.1:9222/json/list \
            2>/dev/null || true)
        if printf '%s' "$json" | grep -q 'OP Kiosk CI Ready'; then
            page_ok=1
        fi
    fi

    if (( lightdm_ok && x_ok && openbox_ok && chromium_ok && page_ok )); then
        mkdir -p /run/op-kiosk
        printf '%s\n' PASS >/run/op-kiosk/ready
        if ci_mode; then
            serial OPKIOSK_RUNTIME_READY_CI
        else
            serial OPKIOSK_RUNTIME_READY
        fi
        exit 0
    fi
    sleep 1
done

serial OPKIOSK_RUNTIME_FAILED
systemctl --no-pager --plain status lightdm.service 2>/dev/null \
    >/dev/ttyS0 || true
ps auxww >/dev/ttyS0 2>/dev/null || true
tail -n 160 /var/log/op-kiosk/session.log >/dev/ttyS0 2>/dev/null || true
tail -n 160 /var/log/op-kiosk/browser.log >/dev/ttyS0 2>/dev/null || true
exit 1
EOF

cat >"$CONFIG/includes.chroot/etc/systemd/system/op-kiosk-health.service" <<'EOF'
[Unit]
Description=OP Kiosk OS graphical runtime verification
After=lightdm.service NetworkManager.service
Wants=lightdm.service NetworkManager.service

[Service]
Type=oneshot
ExecStart=/opt/op-kiosk/health-check.sh
TimeoutStartSec=300

[Install]
WantedBy=graphical.target
EOF

cat >"$CONFIG/includes.chroot/usr/local/sbin/op-kiosk-finalize" <<'EOF'
#!/bin/bash
set -Eeuo pipefail

MODE="${1:---firstboot}"
REPORT=/var/lib/op-kiosk/install-verification.txt

log() {
    printf '[%s] %s\n' "$(date -Is)" "$*"
}

ensure_kiosk_user() {
    if ! getent group kiosk >/dev/null 2>&1; then
        groupadd --gid 1000 kiosk 2>/dev/null || groupadd kiosk
    fi

    if ! id kiosk >/dev/null 2>&1; then
        if ! getent passwd 1000 >/dev/null 2>&1; then
            useradd --uid 1000 --gid kiosk --create-home \
                --shell /bin/bash --comment 'OP Kiosk' kiosk
        else
            useradd --gid kiosk --create-home \
                --shell /bin/bash --comment 'OP Kiosk' kiosk
        fi
    fi

    local group
    for group in audio cdrom video render input netdev plugdev; do
        getent group "$group" >/dev/null 2>&1 \
            && usermod -aG "$group" kiosk || true
    done
    for group in autologin nopasswdlogin; do
        getent group "$group" >/dev/null 2>&1 \
            && usermod -aG "$group" kiosk || true
    done

    gpasswd -d kiosk sudo >/dev/null 2>&1 || true
    passwd -l kiosk >/dev/null 2>&1 || true
}

if [[ "$MODE" != --build ]]; then
    ensure_kiosk_user
fi

mkdir -p \
    /var/lib/op-kiosk/chromium \
    /var/log/op-kiosk \
    /etc/op-kiosk \
    /home/kiosk 2>/dev/null || true

if id kiosk >/dev/null 2>&1; then
    chown -R kiosk:kiosk /var/lib/op-kiosk /home/kiosk
    chown kiosk:kiosk /var/log/op-kiosk
else
    chown -R 1000:1000 /var/lib/op-kiosk /home/kiosk 2>/dev/null || true
    chown 1000:1000 /var/log/op-kiosk 2>/dev/null || true
fi
chmod 0750 /var/lib/op-kiosk
chmod 0755 /var/log/op-kiosk
chmod 0600 /var/lib/op-kiosk/kiosk.conf
chown root:root /etc/op-kiosk/admin.sha256
chmod 0600 /etc/op-kiosk/admin.sha256
chmod 0440 /etc/sudoers.d/op-kiosk

rm -f /home/kiosk/.bash_profile /home/kiosk/.xinitrc 2>/dev/null || true
printf '%s\n' '/usr/sbin/lightdm' >/etc/X11/default-display-manager

systemctl enable NetworkManager.service >/dev/null 2>&1
systemctl enable lightdm.service >/dev/null 2>&1
systemctl enable op-kiosk-network-priority.service >/dev/null 2>&1
systemctl enable op-kiosk-health.service >/dev/null 2>&1
systemctl enable op-kiosk-firstboot.service >/dev/null 2>&1
systemctl set-default graphical.target >/dev/null 2>&1
systemctl mask ctrl-alt-del.target >/dev/null 2>&1 || true

if [[ "$MODE" == --firstboot ]]; then
    touch /var/lib/op-kiosk/.firstboot-complete
    systemctl disable op-kiosk-firstboot.service >/dev/null 2>&1 || true
fi

if [[ "$MODE" == --installer || "$MODE" == --installer-ci ]]; then
    touch /var/lib/op-kiosk/.installer-finalized
fi

{
    printf 'OP Kiosk OS installation verification\n'
    printf '====================================\n'
    printf 'Timestamp: %s\n' "$(date -Is)"
    printf 'Mode: %s\n' "$MODE"
    printf 'Default target: %s\n' "$(readlink -f /etc/systemd/system/default.target 2>/dev/null || true)"
    printf 'LightDM enabled: %s\n' "$(systemctl is-enabled lightdm.service 2>/dev/null || true)"
    printf 'NetworkManager enabled: %s\n' "$(systemctl is-enabled NetworkManager.service 2>/dev/null || true)"
    printf 'Kiosk health enabled: %s\n' "$(systemctl is-enabled op-kiosk-health.service 2>/dev/null || true)"
    printf 'Kiosk user: %s\n' "$(getent passwd kiosk 2>/dev/null || echo missing)"
} >"$REPORT"

failures=0
check() {
    local description="$1"
    shift
    if "$@"; then
        printf 'PASS: %s\n' "$description" >>"$REPORT"
    else
        printf 'FAIL: %s\n' "$description" >>"$REPORT"
        failures=$((failures + 1))
    fi
}

check 'graphical.target is default' \
    test "$(readlink -f /etc/systemd/system/default.target 2>/dev/null)" \
        = /lib/systemd/system/graphical.target
check 'LightDM is enabled' systemctl is-enabled --quiet lightdm.service
check 'NetworkManager is enabled' systemctl is-enabled --quiet NetworkManager.service
check 'network priority service is enabled' \
    systemctl is-enabled --quiet op-kiosk-network-priority.service
check 'health service is enabled' \
    systemctl is-enabled --quiet op-kiosk-health.service
check 'LightDM configuration exists' \
    test -s /etc/lightdm/lightdm.conf.d/50-op-kiosk.conf
check 'OP Kiosk XSession exists' \
    test -x /opt/op-kiosk/session.sh
check 'Chromium launcher exists' \
    test -x /opt/op-kiosk/browser-supervisor.sh
check 'service menu exists' \
    test -x /opt/op-kiosk/admin-menu.sh
check 'kiosk configuration exists' \
    test -s /var/lib/op-kiosk/kiosk.conf

if [[ "$MODE" != --build ]]; then
    check 'kiosk user exists' id kiosk
fi

if [[ "$MODE" == --installer || "$MODE" == --installer-ci || "$MODE" == --firstboot ]]; then
    check 'fstab exists' test -s /etc/fstab
    check 'installed kernel exists' bash -c 'compgen -G "/boot/vmlinuz-*" >/dev/null'
    check 'installed initramfs exists' bash -c 'compgen -G "/boot/initrd.img-*" >/dev/null'
    check 'GRUB configuration exists' test -s /boot/grub/grub.cfg
    if [[ -d /boot/efi/EFI ]]; then
        check 'UEFI loader exists' bash -c \
            'find /boot/efi/EFI -type f -iname "*.efi" -print -quit | grep -q .'
    fi
fi

cat "$REPORT"

if (( failures > 0 )); then
    log "Проверка завершилась с ошибками: $failures"
    exit 1
fi

log 'OP Kiosk OS finalization PASS'
exit 0
EOF

cat >"$CONFIG/includes.chroot/etc/systemd/system/op-kiosk-firstboot.service" <<'EOF'
[Unit]
Description=OP Kiosk OS installed-system first boot finalizer
After=local-fs.target systemd-remount-fs.service
Before=lightdm.service display-manager.service
ConditionPathExists=!/run/live/medium
ConditionPathExists=!/var/lib/op-kiosk/.firstboot-complete

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/op-kiosk-finalize --firstboot
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target
EOF

cat >"$CONFIG/includes.chroot/etc/systemd/logind.conf.d/10-op-kiosk.conf" <<'EOF'
[Login]
HandlePowerKey=poweroff
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
IdleAction=ignore
EOF

cat >"$CONFIG/includes.chroot/etc/systemd/journald.conf.d/10-op-kiosk.conf" <<'EOF'
[Journal]
Storage=auto
RuntimeMaxUse=64M
SystemMaxUse=128M
MaxRetentionSec=7day
EOF

cat >"$CONFIG/includes.chroot/etc/tmpfiles.d/op-kiosk.conf" <<'EOF'
d /var/lib/op-kiosk 0750 1000 1000 -
d /var/lib/op-kiosk/chromium 0700 1000 1000 -
d /var/log/op-kiosk 0755 1000 1000 -
EOF

cat >"$CONFIG/includes.installer/usr/lib/finish-install.d/90op-kiosk" <<'EOF'
#!/bin/sh
set -e

if [ ! -x /target/usr/local/sbin/op-kiosk-finalize ]; then
    echo 'OP Kiosk OS: finalizer is missing in /target' >&2
    exit 1
fi

in-target /usr/local/sbin/op-kiosk-finalize --installer
printf '%s\n' OPKIOSK_INSTALL_FINALIZE_PASS >/dev/ttyS0 2>/dev/null || true
exit 0
EOF

cat >"$CONFIG/hooks/live/0100-op-kiosk.hook.chroot" <<'EOF'
#!/bin/bash
set -Eeuo pipefail

sed -i 's/^# *\(ru_RU.UTF-8 UTF-8\)/\1/' /etc/locale.gen || true
sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen || true
locale-gen ru_RU.UTF-8 en_US.UTF-8
update-locale LANG=ru_RU.UTF-8

chmod 0755 /opt/op-kiosk/*.sh /usr/local/sbin/op-kiosk-*
chmod 0755 /usr/local/sbin/op-kiosk-finalize
chmod 0440 /etc/sudoers.d/op-kiosk
chmod 0600 /etc/op-kiosk/admin.sha256
chmod 0600 /var/lib/op-kiosk/kiosk.conf

/usr/local/sbin/op-kiosk-finalize --build

apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /tmp/* /var/tmp/*
EOF

cat >"$CONFIG/binary_debian-installer/preseed.cfg" <<'EOF'
### OP Kiosk OS 2.0 — безопасные значения Debian Installer.
### Выбор целевого диска и окончательное подтверждение удаления данных
### намеренно НЕ автоматизированы.

d-i debian-installer/locale string ru_RU.UTF-8
d-i localechooser/supported-locales multiselect ru_RU.UTF-8, en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us

d-i netcfg/enable boolean false
d-i netcfg/get_hostname string op-kiosk
d-i netcfg/get_domain string local

d-i passwd/root-login boolean false
d-i passwd/root-password-crypted password !
d-i passwd/make-user boolean false

d-i clock-setup/utc boolean true
d-i time/zone string Europe/Moscow
d-i clock-setup/ntp boolean false

d-i apt-setup/use_mirror boolean false
d-i base-installer/install-recommends boolean false
d-i pkgsel/upgrade select none
popularity-contest popularity-contest/participate boolean false

d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-md/device_remove_md boolean true

d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean false
d-i grub-installer/bootdev string default

d-i finish-install/reboot_in_progress note
d-i cdrom-detect/eject boolean false
EOF

cp -f "$CONFIG/binary_debian-installer/preseed.cfg" \
    "$CONFIG/includes.installer/preseed.cfg"

cat >"$CONFIG/includes.binary/README-OP-KIOSK.txt" <<EOF
OP Kiosk OS $VERSION
====================

Режим Live запускает Chromium без изменения внутреннего накопителя.
Для установки используйте отдельный пункт Debian Installer в загрузочном меню.

Установка из Chromium и сервисного меню намеренно отсутствует.

Сервисное меню: Ctrl+Alt+M
Диагностический терминал: Ctrl+Alt+T
Пароль по умолчанию: opkiosk

Рабочий URL по умолчанию:
$DEFAULT_URL

Статус этой сборки: экспериментальная до прохождения полного CI-цикла
ISO -> установка -> отключение ISO -> холодная загрузка внутреннего диска.
EOF

chmod 0755 \
    "$CONFIG/hooks/live/0100-op-kiosk.hook.chroot" \
    "$CONFIG/includes.installer/usr/lib/finish-install.d/90op-kiosk"

printf 'Конфигурация OP Kiosk OS %s подготовлена в %s\n' "$VERSION" "$CONFIG"
