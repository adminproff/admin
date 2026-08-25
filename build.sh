#!/usr/bin/env bash
set -Eeuo pipefail

PRODUCT="OP-Kiosk-OS"
VERSION="1.0"
ARCH="amd64"
DIST="trixie"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/.build"
OUT="$HERE/output"

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Запустите сборку от root: sudo ./build.sh" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

log "Установка средств сборки"
apt-get update
apt-get install -y --no-install-recommends \
  live-build debootstrap xorriso squashfs-tools dosfstools rsync \
  ca-certificates curl gnupg file isolinux syslinux-common \
  grub-pc-bin grub-efi-amd64-bin mtools fdisk

log "Подготовка проекта"
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"
cd "$WORK"

lb clean --purge || true
lb config noauto \
  --mode debian \
  --distribution "$DIST" \
  --architectures "$ARCH" \
  --binary-images iso-hybrid \
  --archive-areas "main contrib non-free-firmware" \
  --apt-recommends false \
  --apt-indices false \
  --security true \
  --updates true \
  --backports false \
  --firmware-binary true \
  --firmware-chroot true \
  --memtest none \
  --debian-installer none \
  --boot-timeout 1 \
  --checksums sha256 \
  --iso-application "$PRODUCT $VERSION" \
  --iso-publisher "OP Kiosk OS" \
  --iso-volume "OPKIOSK_1_0" \
  --bootappend-live "boot=live components username=kiosk hostname=op-kiosk locales=ru_RU.UTF-8 keyboard-layouts=us quiet loglevel=3 systemd.show_status=false vt.global_cursor_default=0"

mkdir -p \
  config/package-lists \
  config/hooks/live \
  config/includes.chroot/etc/NetworkManager/conf.d \
  config/includes.chroot/etc/chromium/policies/managed \
  config/includes.chroot/etc/op-kiosk \
  config/includes.chroot/etc/openbox \
  config/includes.chroot/etc/polkit-1/rules.d \
  config/includes.chroot/etc/sudoers.d \
  config/includes.chroot/etc/systemd/journald.conf.d \
  config/includes.chroot/etc/systemd/logind.conf.d \
  config/includes.chroot/etc/systemd/system/getty@tty1.service.d \
  config/includes.chroot/etc/systemd/system \
  config/includes.chroot/opt/op-kiosk/html \
  config/includes.chroot/usr/local/sbin \
  config/includes.chroot/var/lib/op-kiosk

cat > config/package-lists/op-kiosk.list.chroot <<'EOF'
live-boot
live-config
linux-image-amd64
systemd-sysv
network-manager
wpasupplicant
iw
rfkill
wireless-regdb
xserver-xorg-core
xserver-xorg-input-libinput
xserver-xorg-video-amdgpu
xserver-xorg-video-vesa
xinit
openbox
x11-xserver-utils
unclutter
chromium
zenity
fonts-dejavu-core
fonts-liberation
fonts-noto-color-emoji
ca-certificates
curl
iproute2
iputils-ping
dnsutils
procps
psmisc
util-linux
pciutils
usbutils
ethtool
rsync
parted
dosfstools
e2fsprogs
grub-efi-amd64-bin
grub-efi-amd64-signed
grub2-common
grub-common
shim-signed
sudo
policykit-1
dbus-x11
xauth
locales
firmware-linux-free
firmware-misc-nonfree
firmware-amd-graphics
firmware-realtek
firmware-iwlwifi
firmware-atheros
firmware-brcm80211
firmware-mediatek
firmware-libertas
EOF

cat > config/includes.chroot/var/lib/op-kiosk/kiosk.conf <<'EOF'
KIOSK_URL=
PROXY_URL=
BROWSER=chromium
EOF

cat > config/includes.chroot/etc/NetworkManager/conf.d/10-op-kiosk.conf <<'EOF'
[main]
plugins=keyfile

[connectivity]
enabled=false

[connection]
wifi.powersave=2
EOF

cat > config/includes.chroot/etc/chromium/policies/managed/op-kiosk.json <<'EOF'
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
  "ShowHomeButton": false
}
EOF

cat > config/includes.chroot/etc/openbox/rc.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <resistance><strength>10</strength><screen_edge_strength>20</screen_edge_strength></resistance>
  <focus><focusNew>yes</focusNew><followMouse>no</followMouse><focusLast>yes</focusLast><underMouse>no</underMouse><focusDelay>200</focusDelay><raiseOnFocus>no</raiseOnFocus></focus>
  <placement><policy>Smart</policy><center>yes</center><monitor>Primary</monitor><primaryMonitor>1</primaryMonitor></placement>
  <theme><name>Clearlooks</name><titleLayout>NLIMC</titleLayout><keepBorder>no</keepBorder><animateIconify>no</animateIconify></theme>
  <desktops><number>1</number><firstdesk>1</firstdesk><names><name>Kiosk</name></names><popupTime>0</popupTime></desktops>
  <keyboard>
    <chainQuitKey>C-g</chainQuitKey>
    <keybind key="C-A-F12"><action name="Execute"><command>/opt/op-kiosk/admin-menu.sh</command></action></keybind>
    <keybind key="A-F4"><action name="None"/></keybind>
    <keybind key="C-A-Delete"><action name="None"/></keybind>
    <keybind key="A-Tab"><action name="None"/></keybind>
    <keybind key="W-r"><action name="None"/></keybind>
  </keyboard>
  <mouse><dragThreshold>8</dragThreshold><doubleClickTime>200</doubleClickTime><screenEdgeWarpTime>0</screenEdgeWarpTime></mouse>
  <applications>
    <application class="*"><decor>no</decor><maximized>yes</maximized></application>
  </applications>
</openbox_config>
EOF

cat > config/includes.chroot/etc/systemd/system/getty@tty1.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin kiosk --noclear %I $TERM
Type=idle
EOF

cat > config/includes.chroot/etc/systemd/logind.conf.d/10-op-kiosk.conf <<'EOF'
[Login]
NAutoVTs=1
ReserveVT=1
HandlePowerKey=poweroff
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
IdleAction=ignore
EOF

cat > config/includes.chroot/etc/systemd/journald.conf.d/10-op-kiosk.conf <<'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=64M
SystemMaxUse=64M
MaxRetentionSec=1day
EOF

cat > config/includes.chroot/etc/polkit-1/rules.d/49-op-kiosk.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if (subject.user == "kiosk") {
        if (action.id.indexOf("org.freedesktop.NetworkManager.") == 0 ||
            action.id == "org.freedesktop.login1.reboot" ||
            action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
            action.id == "org.freedesktop.login1.power-off" ||
            action.id == "org.freedesktop.login1.power-off-multiple-sessions") {
            return polkit.Result.YES;
        }
    }
});
EOF

cat > config/includes.chroot/etc/sudoers.d/op-kiosk <<'EOF'
Defaults:kiosk env_keep += "DISPLAY XAUTHORITY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS"
kiosk ALL=(root) NOPASSWD: /usr/local/sbin/op-kiosk-auth
kiosk ALL=(root) NOPASSWD: /usr/local/sbin/op-kiosk-set-admin-hash
kiosk ALL=(root) NOPASSWD:SETENV: /usr/local/sbin/op-kiosk-install
EOF

cat > config/includes.chroot/usr/local/sbin/op-kiosk-auth <<'EOF'
#!/bin/bash
set -euo pipefail
read -r HASH
[[ "$HASH" =~ ^[0-9a-fA-F]{64}$ ]] || exit 2
EXPECTED=$(tr -d '[:space:]' < /etc/op-kiosk/admin.sha256)
[[ "${HASH,,}" == "${EXPECTED,,}" ]]
EOF

cat > config/includes.chroot/usr/local/sbin/op-kiosk-set-admin-hash <<'EOF'
#!/bin/bash
set -euo pipefail
read -r HASH
[[ "$HASH" =~ ^[0-9a-fA-F]{64}$ ]] || exit 2
printf '%s\n' "${HASH,,}" > /etc/op-kiosk/admin.sha256
chmod 600 /etc/op-kiosk/admin.sha256
EOF

printf '%s\n' 'cac03bc1def5b023ca4dc45d45b74011a4a468e89f30cf70b2b8ff002f1143cc' \
  > config/includes.chroot/etc/op-kiosk/admin.sha256

cat > config/includes.chroot/opt/op-kiosk/network-priority.sh <<'EOF'
#!/bin/bash
set -u

sleep 2

while IFS=: read -r dev type state; do
  [[ "$type" == "ethernet" ]] || continue
  if ! nmcli -t -f NAME,DEVICE con show | awk -F: -v d="$dev" '$2==d{found=1} END{exit !found}'; then
    nmcli con add type ethernet ifname "$dev" con-name "OP-LAN-$dev" \
      connection.autoconnect yes connection.autoconnect-priority 100 \
      ipv4.method auto ipv4.route-metric 100 ipv6.method auto ipv6.route-metric 100 \
      >/dev/null 2>&1 || true
  fi
done < <(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null)

while IFS=: read -r name type; do
  case "$type" in
    802-3-ethernet)
      nmcli con mod "$name" connection.autoconnect yes connection.autoconnect-priority 100 \
        ipv4.route-metric 100 ipv6.route-metric 100 2>/dev/null || true
      ;;
    802-11-wireless)
      nmcli con mod "$name" connection.autoconnect yes connection.autoconnect-priority 50 \
        ipv4.route-metric 600 ipv6.route-metric 600 802-11-wireless.powersave 2 2>/dev/null || true
      ;;
  esac
done < <(nmcli -t -f NAME,TYPE con show 2>/dev/null)
EOF

cat > config/includes.chroot/etc/systemd/system/op-kiosk-network-priority.service <<'EOF'
[Unit]
Description=OP Kiosk OS network priorities
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/opt/op-kiosk/network-priority.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat > config/includes.chroot/etc/systemd/system/op-kiosk-smoke.service <<'EOF'
[Unit]
Description=OP Kiosk OS automated boot smoke marker
ConditionKernelCommandLine=opkiosk.smoketest
After=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo OPKIOSK_BOOT_OK >/dev/ttyS0; sleep 2; systemctl poweroff'

[Install]
WantedBy=multi-user.target
EOF

cat > config/includes.chroot/opt/op-kiosk/xinitrc <<'EOF'
#!/bin/sh
set -eu

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR/op-kiosk-cache" 2>/dev/null || true

setxkbmap -layout 'us,ru' -option 'grp:alt_shift_toggle' || true
xset s off || true
xset -dpms || true
xset s noblank || true
xsetroot -solid '#0b1220' || true
unclutter -idle 3 -root >/dev/null 2>&1 &

openbox --config-file /etc/openbox/rc.xml &

exec /opt/op-kiosk/start-browser.sh
EOF

cat > config/includes.chroot/opt/op-kiosk/start-browser.sh <<'EOF'
#!/bin/bash
set -u

CONF=/var/lib/op-kiosk/kiosk.conf
LOCAL_PAGE='file:///opt/op-kiosk/html/index.html'
PROFILE=/var/lib/op-kiosk/chromium
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
CACHE="$RUNTIME/op-kiosk-cache"
LOG="$RUNTIME/op-kiosk-browser.log"

mkdir -p "$PROFILE" "$CACHE"

while true; do
    KIOSK_URL=''
    PROXY_URL=''
    BROWSER='chromium'
    source "$CONF" 2>/dev/null || true

    URL="${KIOSK_URL:-$LOCAL_PAGE}"
    PROXY="${PROXY_URL:-}"
    BROWSER="${BROWSER:-chromium}"

    ARGS=(
      --kiosk
      --no-first-run
      --no-default-browser-check
      --noerrdialogs
      --disable-session-crashed-bubble
      --disable-infobars
      --disable-notifications
      --disable-component-update
      --disable-background-networking
      --disable-features=TranslateUI,MediaRouter,OptimizationHints
      --overscroll-history-navigation=0
      --disable-pinch
      --autoplay-policy=no-user-gesture-required
      --user-data-dir="$PROFILE"
      --disk-cache-dir="$CACHE"
      --password-store=basic
    )

    if [[ -n "$PROXY" ]]; then
        ARGS+=(--proxy-server="$PROXY")
    fi

    "$BROWSER" "${ARGS[@]}" "$URL" >"$LOG" 2>&1 || true
    sleep 2
done
EOF

cat > config/includes.chroot/opt/op-kiosk/html/index.html <<'EOF'
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>OP Kiosk OS</title>
<style>
  :root{color-scheme:dark;--bg:#07101f;--panel:rgba(17,31,52,.78);--line:rgba(148,185,255,.20);--text:#f4f8ff;--muted:#a8b7cd;--accent:#58a6ff;--ok:#3ddc97}
  *{box-sizing:border-box}
  html,body{height:100%;margin:0;font-family:Inter,Segoe UI,Arial,sans-serif;background:radial-gradient(circle at 18% 18%,#17345d 0,transparent 32%),radial-gradient(circle at 82% 78%,#123c4c 0,transparent 34%),linear-gradient(135deg,#06101e,#0b1727 60%,#07101f);color:var(--text);overflow:hidden}
  body:before{content:"";position:fixed;inset:0;background-image:linear-gradient(rgba(255,255,255,.018) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.018) 1px,transparent 1px);background-size:32px 32px;mask-image:linear-gradient(to bottom,rgba(0,0,0,.8),transparent)}
  .wrap{height:100%;display:grid;place-items:center;padding:32px}
  .card{position:relative;width:min(860px,94vw);padding:56px 60px;border:1px solid var(--line);border-radius:28px;background:var(--panel);backdrop-filter:blur(18px);box-shadow:0 28px 90px rgba(0,0,0,.38)}
  .brand{display:flex;align-items:center;gap:18px;margin-bottom:36px}
  .logo{width:62px;height:62px;border-radius:18px;display:grid;place-items:center;background:linear-gradient(145deg,#58a6ff,#24d1a6);box-shadow:0 12px 34px rgba(62,166,255,.28);font-size:27px;font-weight:800;color:#06101e}
  h1{font-size:48px;line-height:1.05;margin:0;letter-spacing:-1.5px}
  .subtitle{margin:7px 0 0;color:var(--muted);font-size:17px}
  .status{display:flex;align-items:center;gap:12px;margin:6px 0 26px;padding:16px 18px;border-radius:16px;background:rgba(61,220,151,.08);border:1px solid rgba(61,220,151,.20)}
  .dot{width:12px;height:12px;border-radius:50%;background:var(--ok);box-shadow:0 0 0 7px rgba(61,220,151,.12);animation:pulse 2s infinite}
  @keyframes pulse{50%{box-shadow:0 0 0 12px rgba(61,220,151,0)}}
  .status strong{font-size:18px}.status span{color:var(--muted)}
  .message{font-size:23px;line-height:1.5;margin:0 0 30px}
  .hint{display:flex;align-items:center;justify-content:space-between;gap:18px;padding-top:24px;border-top:1px solid var(--line);color:var(--muted);font-size:16px}
  .keys{white-space:nowrap}
  kbd{display:inline-grid;place-items:center;min-width:38px;height:34px;padding:0 10px;margin:0 2px;border-radius:8px;background:#14233a;border:1px solid #2d4568;box-shadow:inset 0 -2px rgba(0,0,0,.28);color:#fff;font:600 14px Segoe UI,Arial}
  @media(max-width:650px){.card{padding:38px 28px}.brand{align-items:flex-start}h1{font-size:36px}.hint{align-items:flex-start;flex-direction:column}.message{font-size:20px}}
</style>
</head>
<body>
<div class="wrap">
  <main class="card">
    <div class="brand">
      <div class="logo">OP</div>
      <div><h1>OP Kiosk OS</h1><p class="subtitle">Минимальная система безопасного доступа к веб-приложению</p></div>
    </div>
    <div class="status"><span class="dot"></span><div><strong>Система готова</strong><br><span>Браузер и сетевые службы запущены</span></div></div>
    <p class="message">Рабочий адрес ещё не задан. Откройте сервисное меню, выберите сеть и укажите URL сайта.</p>
    <div class="hint"><span>Сервисное меню</span><span class="keys"><kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>F12</kbd></span></div>
  </main>
</div>
</body>
</html>
EOF

cat > config/includes.chroot/opt/op-kiosk/admin-menu.sh <<'EOF'
#!/bin/bash
set -u

CONF=/var/lib/op-kiosk/kiosk.conf
TITLE='OP Kiosk OS — сервисное меню'

zinfo(){ zenity --info --title="$TITLE" --width=660 --text="$1"; }
zerr(){ zenity --error --title="$TITLE" --width=660 --text="$1"; }

check_password() {
    local pass hash
    pass=$(zenity --password --title="$TITLE" --text='Пароль администратора:' 2>/dev/null) || exit 0
    hash=$(printf '%s' "$pass" | sha256sum | awk '{print $1}')
    if ! printf '%s\n' "$hash" | sudo /usr/local/sbin/op-kiosk-auth; then
        zerr 'Неверный пароль.'
        exit 1
    fi
}

load_conf(){
    KIOSK_URL=''; PROXY_URL=''; BROWSER='chromium'
    source "$CONF" 2>/dev/null || true
}

save_conf(){
    umask 077
    {
      printf 'KIOSK_URL=%q\n' "$KIOSK_URL"
      printf 'PROXY_URL=%q\n' "$PROXY_URL"
      printf 'BROWSER=%q\n' "$BROWSER"
    } > "$CONF"
}

restart_browser(){ pkill -u "$(id -u)" -f 'chromium.*--kiosk' 2>/dev/null || true; }

network_status(){
    load_conf
    local devices ipv4 routes wifi
    devices=$(nmcli -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null || true)
    ipv4=$(ip -brief -4 addr show 2>/dev/null || true)
    routes=$(ip route show default 2>/dev/null || true)
    wifi=$(nmcli -t -f ACTIVE,SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null | awk -F: '$1=="yes"{printf "SSID: %s\nСигнал: %s%%\nЗащита: %s\n",$2,$3,$4}' || true)
    zenity --text-info --title="$TITLE — состояние" --width=860 --height=560 <<EOT
Рабочий URL: ${KIOSK_URL:-не задан}
Proxy: ${PROXY_URL:-нет}

Активный Wi-Fi:
${wifi:-не подключён}

Устройства:
$devices

IPv4:
$ipv4

Маршрут по умолчанию:
$routes
EOT
}

set_url(){
    load_conf
    local value
    value=$(zenity --entry --title="$TITLE" --width=700 --text='Рабочий URL:' --entry-text="${KIOSK_URL:-https://}" 2>/dev/null) || return
    [[ -z "$value" || "$value" =~ ^(https?|file):// ]] || value="https://$value"
    KIOSK_URL="$value"
    save_conf
    restart_browser
}

set_proxy(){
    load_conf
    local value
    value=$(zenity --entry --title="$TITLE" --width=700 --text='Proxy. Оставьте пустым для прямого подключения. Пример: http://10.0.0.10:3128' --entry-text="${PROXY_URL:-}" 2>/dev/null) || return
    PROXY_URL="$value"
    save_conf
    restart_browser
}

wifi_connect(){
    local dev rows choice ssid security pass hidden=no cname keymgmt
    dev=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}')
    [[ -n "$dev" ]] || { zerr 'Wi-Fi адаптер не найден. Проверьте, установлен ли внутренний модуль или USB-адаптер.'; return; }

    nmcli radio wifi on >/dev/null 2>&1 || true
    nmcli dev wifi rescan ifname "$dev" >/dev/null 2>&1 || true
    sleep 2

    rows=$(nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list ifname "$dev" 2>/dev/null | awk -F: 'length($1)>0 && !seen[$1]++ {printf "%s|%s|%s\n",$1,$2,$3}')

    choice=$( {
      printf '%s|%s|%s\n' '[Скрытая сеть / ввести SSID]' '-' '-'
      printf '%s\n' "$rows"
    } | awk -F'|' '{print $1"\n"$2"\n"$3}' | zenity --list --title="$TITLE — Wi-Fi" --width=820 --height=520 --column='SSID' --column='Сигнал, %' --column='Защита' 2>/dev/null ) || return

    if [[ "$choice" == '[Скрытая сеть / ввести SSID]' ]]; then
        ssid=$(zenity --entry --title="$TITLE — Wi-Fi" --text='Введите SSID скрытой сети:' 2>/dev/null) || return
        hidden=yes
        security=$(printf 'WPA2 / WPA2-WPA3\nWPA3-SAE\nОткрытая сеть\n' | zenity --list --title="$TITLE — Wi-Fi" --column='Защита' 2>/dev/null) || return
    else
        ssid="$choice"
        security=$(nmcli -t -f SSID,SECURITY dev wifi list ifname "$dev" 2>/dev/null | awk -F: -v s="$ssid" '$1==s{print $2; exit}')
    fi

    [[ -n "$ssid" ]] || return

    if [[ "$hidden" == yes ]]; then
        cname="OP-WIFI-$ssid"
        nmcli con delete "$cname" >/dev/null 2>&1 || true
        nmcli con add type wifi ifname "$dev" con-name "$cname" ssid "$ssid" 802-11-wireless.hidden yes connection.autoconnect yes connection.autoconnect-priority 50 ipv4.method auto ipv4.route-metric 600 ipv6.method auto ipv6.route-metric 600 >/dev/null || { zerr 'Не удалось создать профиль Wi-Fi.'; return; }
        if [[ "$security" != 'Открытая сеть' ]]; then
            pass=$(zenity --password --title="$TITLE — Wi-Fi" --text="Пароль сети «$ssid»:" 2>/dev/null) || return
            [[ "$security" == 'WPA3-SAE' ]] && keymgmt=sae || keymgmt=wpa-psk
            nmcli con mod "$cname" wifi-sec.key-mgmt "$keymgmt" wifi-sec.psk "$pass"
        fi
        nmcli con up "$cname" || { zerr 'Не удалось подключиться к Wi-Fi.'; return; }
    else
        if [[ -n "$security" && "$security" != '--' ]]; then
            pass=$(zenity --password --title="$TITLE — Wi-Fi" --text="Пароль сети «$ssid»:" 2>/dev/null) || return
            nmcli dev wifi connect "$ssid" password "$pass" ifname "$dev" || { zerr 'Не удалось подключиться к Wi-Fi. Проверьте пароль.'; return; }
        else
            nmcli dev wifi connect "$ssid" ifname "$dev" || { zerr 'Не удалось подключиться к открытой Wi-Fi сети.'; return; }
        fi
        cname=$(nmcli -t -f NAME,TYPE con show --active 2>/dev/null | awk -F: '$2=="802-11-wireless"{print $1; exit}')
        [[ -n "$cname" ]] && nmcli con mod "$cname" connection.autoconnect yes connection.autoconnect-priority 50 ipv4.route-metric 600 ipv6.route-metric 600 802-11-wireless.powersave 2 || true
    fi
    zinfo "Wi-Fi подключён: $ssid"
}

configure_ipv4(){
    local list con mode addr gateway dns ctype
    list=$(nmcli -t -f NAME,TYPE con show 2>/dev/null | awk -F: '$2=="802-3-ethernet" || $2=="802-11-wireless" {print $1}')
    [[ -n "$list" ]] || { zerr 'Сетевые подключения не найдены.'; return; }
    con=$(printf '%s\n' "$list" | zenity --list --title="$TITLE — IPv4" --width=720 --height=420 --column='Подключение' 2>/dev/null) || return
    mode=$(printf 'DHCP\nСтатический IPv4\n' | zenity --list --title="$TITLE — IPv4" --column='Режим' 2>/dev/null) || return

    if [[ "$mode" == 'DHCP' ]]; then
        nmcli con mod "$con" ipv4.method auto ipv4.addresses '' ipv4.gateway '' ipv4.dns '' ipv4.ignore-auto-dns no
    else
        addr=$(zenity --entry --title="$TITLE" --text='IP/префикс, например 192.168.1.50/24:' 2>/dev/null) || return
        gateway=$(zenity --entry --title="$TITLE" --text='Шлюз, например 192.168.1.1:' 2>/dev/null) || return
        dns=$(zenity --entry --title="$TITLE" --text='DNS через запятую, например 192.168.1.1,1.1.1.1:' 2>/dev/null) || return
        [[ "$addr" =~ ^[0-9.]+/[0-9]{1,2}$ ]] || { zerr 'Некорректный адрес или префикс.'; return; }
        nmcli con mod "$con" ipv4.method manual ipv4.addresses "$addr" ipv4.gateway "$gateway" ipv4.dns "$dns" ipv4.ignore-auto-dns yes
    fi

    ctype=$(nmcli -g connection.type con show "$con" 2>/dev/null || true)
    if [[ "$ctype" == '802-11-wireless' ]]; then
        nmcli con mod "$con" ipv4.route-metric 600
    else
        nmcli con mod "$con" ipv4.route-metric 100
    fi
    nmcli con down "$con" >/dev/null 2>&1 || true
    nmcli con up "$con" >/dev/null 2>&1 || { zerr 'Настройки сохранены, но подключение сейчас не поднялось.'; return; }
    zinfo 'Настройки IPv4 применены.'
}

forget_wifi(){
    local list con
    list=$(nmcli -t -f NAME,TYPE con show 2>/dev/null | awk -F: '$2=="802-11-wireless"{print $1}')
    [[ -n "$list" ]] || { zinfo 'Сохранённых Wi-Fi сетей нет.'; return; }
    con=$(printf '%s\n' "$list" | zenity --list --title="$TITLE — удалить Wi-Fi" --column='Профиль' 2>/dev/null) || return
    nmcli con delete "$con" >/dev/null || { zerr 'Не удалось удалить профиль.'; return; }
    zinfo 'Профиль Wi-Fi удалён.'
}

change_admin_password(){
    local first second hash
    first=$(zenity --password --title="$TITLE" --text='Новый пароль администратора:' 2>/dev/null) || return
    [[ ${#first} -ge 6 ]] || { zerr 'Пароль должен содержать минимум 6 символов.'; return; }
    second=$(zenity --password --title="$TITLE" --text='Повторите новый пароль:' 2>/dev/null) || return
    [[ "$first" == "$second" ]] || { zerr 'Пароли не совпадают.'; return; }
    hash=$(printf '%s' "$first" | sha256sum | awk '{print $1}')
    printf '%s\n' "$hash" | sudo /usr/local/sbin/op-kiosk-set-admin-hash || { zerr 'Не удалось изменить пароль.'; return; }
    zinfo 'Пароль администратора изменён.'
}

install_system(){
    if [[ -d /run/live/medium ]]; then
        sudo -E /usr/local/sbin/op-kiosk-install --gui
    else
        zinfo 'Система уже запущена с внутреннего накопителя.'
    fi
}

check_password

while true; do
    action=$(zenity --list --title="$TITLE" --width=760 --height=620 --column='Действие' 'Состояние сети' 'Подключить Wi-Fi' 'Удалить сохранённую Wi-Fi сеть' 'DHCP / статический IPv4' 'Задать рабочий URL' 'Настроить proxy' 'Перезапустить браузер' 'Сменить пароль администратора' 'Установить OP Kiosk OS на внутренний диск' 'Перезагрузить' 'Выключить' 'Закрыть меню' 2>/dev/null) || exit 0

    case "$action" in
      'Состояние сети') network_status ;;
      'Подключить Wi-Fi') wifi_connect ;;
      'Удалить сохранённую Wi-Fi сеть') forget_wifi ;;
      'DHCP / статический IPv4') configure_ipv4 ;;
      'Задать рабочий URL') set_url ;;
      'Настроить proxy') set_proxy ;;
      'Перезапустить браузер') restart_browser ;;
      'Сменить пароль администратора') change_admin_password ;;
      'Установить OP Kiosk OS на внутренний диск') install_system ;;
      'Перезагрузить') systemctl reboot ;;
      'Выключить') systemctl poweroff ;;
      *) exit 0 ;;
    esac
done
EOF

cat > config/includes.chroot/usr/local/sbin/op-kiosk-install <<'EOF'
#!/bin/bash
set -Eeuo pipefail

GUI=0
[[ "${1:-}" == "--gui" ]] && GUI=1
TITLE='OP Kiosk OS — установка'
TARGET=/mnt/op-kiosk-target

msg(){ if ((GUI)); then zenity --info --title="$TITLE" --width=700 --text="$1"; else echo "$1"; fi; }
err(){ if ((GUI)); then zenity --error --title="$TITLE" --width=700 --text="$1"; else echo "ОШИБКА: $1" >&2; fi; }
fail(){ err "$1"; exit 1; }
cleanup(){
  for path in "$TARGET/run" "$TARGET/sys" "$TARGET/proc" "$TARGET/dev/pts" "$TARGET/dev" "$TARGET/boot/efi" "$TARGET"; do
    mountpoint -q "$path" 2>/dev/null && umount -l "$path" 2>/dev/null || true
  done
}
trap cleanup EXIT

[[ $EUID -eq 0 ]] || fail 'Установщик должен работать от root.'
[[ -d /run/live/medium ]] || fail 'Установка разрешена только из live-режима.'

boot_src=$(findmnt -n -o SOURCE /run/live/medium 2>/dev/null || true)
boot_parent=''
if [[ "$boot_src" == /dev/* ]]; then
  parent=$(lsblk -no PKNAME "$boot_src" 2>/dev/null | head -1 || true)
  [[ -n "$parent" ]] && boot_parent="/dev/$parent"
fi

mapfile -t disks < <(lsblk -dnpo NAME,TYPE | awk '$2=="disk"{print $1}')
choices=()
for dev in "${disks[@]}"; do
  [[ -n "$boot_parent" && "$dev" == "$boot_parent" ]] && continue
  size=$(lsblk -dn -o SIZE "$dev" 2>/dev/null | xargs)
  model=$(lsblk -dn -o MODEL "$dev" 2>/dev/null | xargs)
  tran=$(lsblk -dn -o TRAN "$dev" 2>/dev/null | xargs)
  choices+=("$dev|${size:-?}|${model:-неизвестно}|${tran:-?}")
done
[[ ${#choices[@]} -gt 0 ]] || fail 'Не найден внутренний диск для установки.'

if ((GUI)); then
  table=()
  for row in "${choices[@]}"; do
    IFS='|' read -r dev size model tran <<<"$row"
    table+=("$dev" "$size" "$model" "$tran")
  done
  disk=$(zenity --list --title="$TITLE" --width=920 --height=460 --text='Выберите ВНУТРЕННИЙ накопитель. Он будет ПОЛНОСТЬЮ очищен.' --column='Диск' --column='Размер' --column='Модель' --column='Интерфейс' "${table[@]}") || exit 0
else
  printf '%s\n' "${choices[@]}"
  read -r -p 'Введите устройство диска, например /dev/sda: ' disk
fi

[[ -b "$disk" ]] || fail "Устройство $disk не существует."
[[ "$disk" != "$boot_parent" ]] || fail 'Нельзя устанавливать на загрузочную USB-флешку.'

size_bytes=$(blockdev --getsize64 "$disk")
(( size_bytes >= 3800000000 )) || fail 'Накопитель меньше 3,8 ГБ. Для этой сборки этого недостаточно.'

if ((GUI)); then
  confirm=$(zenity --entry --title="$TITLE" --width=720 --text="ВНИМАНИЕ! Все данные на $disk будут уничтожены.\n\nДля подтверждения введите: УДАЛИТЬ" 2>/dev/null) || exit 0
else
  read -r -p "Все данные на $disk будут уничтожены. Введите УДАЛИТЬ: " confirm
fi
[[ "$confirm" == 'УДАЛИТЬ' ]] || { msg 'Установка отменена.'; exit 0; }

if ((GUI)); then
  exec 3> >(zenity --progress --title="$TITLE" --width=680 --auto-close --no-cancel --percentage=0 --text='Подготовка диска...')
  progress(){ echo "$1" >&3; echo "#$2" >&3; }
else
  progress(){ echo "[$1%] $2"; }
fi

progress 5 'Отключение разделов...'
while read -r part; do umount "$part" 2>/dev/null || true; done < <(lsblk -lnpo NAME "$disk" | tail -n +2)
swapoff -a 2>/dev/null || true
wipefs -a "$disk"

progress 12 'Создание GPT и разделов...'
parted -s "$disk" mklabel gpt
parted -s "$disk" mkpart ESP fat32 1MiB 261MiB
parted -s "$disk" set 1 esp on
parted -s "$disk" mkpart ROOT ext4 261MiB 100%
partprobe "$disk"
sleep 2

if [[ "$disk" =~ (nvme|mmcblk) ]]; then p1="${disk}p1"; p2="${disk}p2"; else p1="${disk}1"; p2="${disk}2"; fi
[[ -b "$p1" && -b "$p2" ]] || fail 'Не удалось создать разделы.'

progress 20 'Форматирование...'
mkfs.vfat -F 32 -n OPBOOT "$p1" >/dev/null
mkfs.ext4 -F -m 0 -L OPROOT "$p2" >/dev/null

progress 28 'Копирование системы...'
rm -rf "$TARGET"
mkdir -p "$TARGET"
mount "$p2" "$TARGET"
mkdir -p "$TARGET/boot/efi"
mount "$p1" "$TARGET/boot/efi"

rsync -aAXH --numeric-ids --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*' --exclude='/run/*' --exclude='/tmp/*' --exclude='/mnt/*' --exclude='/media/*' --exclude='/lost+found' --exclude='/var/lib/op-kiosk/chromium/*' --exclude='/var/cache/apt/archives/*' / "$TARGET/" >/tmp/op-kiosk-rsync.log 2>&1 || { tail -80 /tmp/op-kiosk-rsync.log >&2; fail 'Ошибка копирования системы. Возможно, внутренний накопитель слишком мал.'; }

progress 70 'Создание fstab...'
ROOT_UUID=$(blkid -s UUID -o value "$p2")
EFI_UUID=$(blkid -s UUID -o value "$p1")
cat > "$TARGET/etc/fstab" <<EOT
UUID=$ROOT_UUID / ext4 defaults,noatime,errors=remount-ro 0 1
UUID=$EFI_UUID /boot/efi vfat umask=0077 0 2
tmpfs /tmp tmpfs nosuid,nodev,noatime,mode=1777,size=512M 0 0
tmpfs /var/tmp tmpfs nosuid,nodev,noatime,mode=1777,size=128M 0 0
EOT

progress 76 'Подготовка установленной системы...'
mkdir -p "$TARGET/var/lib/op-kiosk/chromium"
rm -rf "$TARGET/var/lib/op-kiosk/chromium"/*
KUID=$(awk -F: '$1=="kiosk"{print $3}' "$TARGET/etc/passwd" | head -1)
KGID=$(awk -F: '$1=="kiosk"{print $4}' "$TARGET/etc/passwd" | head -1)
[[ -n "$KUID" && -n "$KGID" ]] || fail 'Пользователь kiosk отсутствует в копируемой системе.'
chown -R "$KUID:$KGID" "$TARGET/var/lib/op-kiosk" "$TARGET/home/kiosk"
chmod 600 "$TARGET/etc/op-kiosk/admin.sha256"

cat > "$TARGET/etc/default/grub" <<'EOT'
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR="OP Kiosk OS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 systemd.show_status=false vt.global_cursor_default=0"
GRUB_CMDLINE_LINUX=""
EOT

progress 82 'Установка UEFI-загрузчика...'
for path in dev dev/pts proc sys run; do mount --bind "/$path" "$TARGET/$path"; done
chroot "$TARGET" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=OPKIOSK --removable --no-nvram
chroot "$TARGET" update-initramfs -u -k all
chroot "$TARGET" update-grub

progress 94 'Включение служб...'
chroot "$TARGET" /bin/bash -c '
  systemctl enable NetworkManager.service >/dev/null 2>&1 || true
  systemctl enable op-kiosk-network-priority.service >/dev/null 2>&1 || true
  systemctl enable getty@tty1.service >/dev/null 2>&1 || true
  systemctl set-default multi-user.target >/dev/null 2>&1 || true
'

sync
cleanup
trap - EXIT
progress 100 'Установка завершена.'
if ((GUI)); then exec 3>&-; fi
msg 'OP Kiosk OS установлена. Выньте USB-флешку и перезагрузите терминал.'
EOF

cat > config/hooks/live/0100-op-kiosk.hook.chroot <<'EOF'
#!/bin/bash
set -Eeuo pipefail

sed -i 's/^# *\(ru_RU.UTF-8 UTF-8\)/\1/' /etc/locale.gen || true
sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen || true
locale-gen ru_RU.UTF-8 en_US.UTF-8 || true
update-locale LANG=ru_RU.UTF-8 || true

if ! id kiosk >/dev/null 2>&1; then
  useradd -m -u 1000 -s /bin/bash kiosk
fi
for group in video render input audio netdev plugdev; do
  getent group "$group" >/dev/null 2>&1 && usermod -aG "$group" kiosk || true
done
passwd -l kiosk >/dev/null 2>&1 || true

cat > /home/kiosk/.bash_profile <<'EOT'
if [ -z "${DISPLAY:-}" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
  exec startx /opt/op-kiosk/xinitrc -- :0 vt1 -keeptty -nolisten tcp
fi
EOT
chown kiosk:kiosk /home/kiosk/.bash_profile
chmod 0644 /home/kiosk/.bash_profile

mkdir -p /var/lib/op-kiosk/chromium
chown -R kiosk:kiosk /var/lib/op-kiosk
chmod 0750 /var/lib/op-kiosk
chmod 0600 /var/lib/op-kiosk/kiosk.conf
chmod 0600 /etc/op-kiosk/admin.sha256
chmod 0755 /opt/op-kiosk/*.sh /opt/op-kiosk/xinitrc /usr/local/sbin/op-kiosk-* || true
chmod 0440 /etc/sudoers.d/op-kiosk

systemctl enable NetworkManager.service >/dev/null 2>&1 || true
systemctl enable op-kiosk-network-priority.service >/dev/null 2>&1 || true
systemctl enable op-kiosk-smoke.service >/dev/null 2>&1 || true
systemctl enable getty@tty1.service >/dev/null 2>&1 || true
systemctl set-default multi-user.target >/dev/null 2>&1 || true
systemctl mask ctrl-alt-del.target >/dev/null 2>&1 || true
for n in 2 3 4 5 6; do systemctl mask "getty@tty${n}.service" >/dev/null 2>&1 || true; done

cat > /etc/openbox/menu.xml <<'EOT'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu"><menu id="root-menu" label="OP Kiosk OS"/></openbox_menu>
EOT

apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /tmp/* /var/tmp/*
EOF
chmod +x config/hooks/live/0100-op-kiosk.hook.chroot

log "Статическая проверка скриптов"
while IFS= read -r -d '' script; do bash -n "$script"; done < <(find config -type f \( -name '*.sh' -o -name '*.hook.chroot' \) -print0)

log "Сборка загрузочного ISO"
lb build 2>&1 | tee "$OUT/build.log"

ISO=$(find . -maxdepth 1 -type f \( -name 'live-image-amd64.hybrid.iso' -o -name '*.iso' \) -print -quit)
[[ -n "$ISO" ]] || { echo "ISO не найден. Смотрите $OUT/build.log" >&2; exit 1; }

DEST="$OUT/${PRODUCT}-${VERSION}-${ARCH}.iso"
cp -f "$ISO" "$DEST"
sha256sum "$DEST" > "$DEST.sha256"

log "Проверка структуры ISO"
xorriso -indev "$DEST" -report_el_torito plain > "$OUT/iso-boot-report.txt" 2>&1
xorriso -indev "$DEST" -ls /live > "$OUT/iso-live-files.txt" 2>&1
file "$DEST" > "$OUT/iso-file-info.txt"

printf '\nГотово:\n  %s\n  %s\n' "$DEST" "$DEST.sha256"
