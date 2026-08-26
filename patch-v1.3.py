#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

BUILD = Path("build.sh")
text = BUILD.read_text(encoding="utf-8")


def replace_once(old: str, new: str, description: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f"{description}: ожидалось одно совпадение, найдено {count}"
        )
    text = text.replace(old, new, 1)


def replace_heredoc(target: str, body: str) -> None:
    global text
    pattern = re.compile(
        rf"(cat > {re.escape(target)} <<'EOF'\n).*?(\nEOF)",
        flags=re.DOTALL,
    )
    text, count = pattern.subn(
        lambda match: match.group(1) + body.rstrip("\n") + match.group(2),
        text,
        count=1,
    )
    if count != 1:
        raise RuntimeError(f"Не найден heredoc для {target}")


def insert_before(anchor: str, block: str, description: str) -> None:
    global text
    count = text.count(anchor)
    if count != 1:
        raise RuntimeError(
            f"{description}: ожидалось одно совпадение, найдено {count}"
        )
    text = text.replace(anchor, block.rstrip("\n") + "\n\n" + anchor, 1)


# patch-v1.3.py запускается после patch-v1.1.py.
replace_once('VERSION="1.1"', 'VERSION="1.3"', "номер версии")
replace_once('--iso-volume "OPKIOSK_1_1"', '--iso-volume "OPKIOSK_1_3"', "метка ISO")

# LightDM берёт на себя создание X11-сессии и автологин. Это устраняет
# зависимость от .bash_profile, getty и момента запуска live-config.
replace_once(
    "xvfb\n",
    "xvfb\nlightdm\nlightdm-gtk-greeter\nxserver-xorg-legacy\nxterm\n",
    "пакеты LightDM и терминала",
)

replace_heredoc(
    "config/includes.chroot/var/lib/op-kiosk/kiosk.conf",
    r'''KIOSK_URL=https://op.arkhbum.local
PROXY_URL=
BROWSER=chromium''',
)

replace_heredoc(
    "config/includes.chroot/etc/openbox/rc.xml",
    r'''<?xml version="1.0" encoding="UTF-8"?>
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
    <keepBorder>no</keepBorder>
    <animateIconify>no</animateIconify>
  </theme>
  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
    <names><name>Kiosk</name></names>
    <popupTime>0</popupTime>
  </desktops>
  <keyboard>
    <chainQuitKey>C-g</chainQuitKey>
    <keybind key="C-A-F12">
      <action name="Execute"><command>/opt/op-kiosk/admin-menu.sh</command></action>
    </keybind>
    <keybind key="C-A-F11">
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
    <application class="*">
      <decor>no</decor>
      <maximized>yes</maximized>
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
</openbox_config>''',
)

replace_heredoc(
    "config/includes.chroot/etc/systemd/system/getty@tty1.service.d/autologin.conf",
    r'''[Service]
ExecStart=
ExecStart=-/sbin/agetty --noclear %I $TERM
Type=idle''',
)

replace_heredoc(
    "config/includes.chroot/opt/op-kiosk/xinitrc",
    r'''#!/bin/bash
set -u

export HOME="${HOME:-/home/kiosk}"
export USER="${USER:-kiosk}"
export LOGNAME="${LOGNAME:-kiosk}"
export DISPLAY="${DISPLAY:-:0}"

LOG_DIR=/var/log/op-kiosk
mkdir -p "$LOG_DIR" 2>/dev/null || true
SESSION_LOG="$LOG_DIR/session.log"
if ! touch "$SESSION_LOG" 2>/dev/null; then
    SESSION_LOG=/tmp/op-kiosk-session.log
fi
exec >>"$SESSION_LOG" 2>&1
printf '\n[%s] Запуск графической сессии OP Kiosk OS 1.3, DISPLAY=%s, UID=%s\n' \
    "$(date -Is)" "$DISPLAY" "$(id -u)"

UID_NOW="$(id -u)"
SYSTEM_RUNTIME="/run/user/$UID_NOW"
FALLBACK_RUNTIME="/tmp/op-kiosk-runtime-$UID_NOW"
if [[ -d "$SYSTEM_RUNTIME" && -w "$SYSTEM_RUNTIME" ]]; then
    export XDG_RUNTIME_DIR="$SYSTEM_RUNTIME"
else
    export XDG_RUNTIME_DIR="$FALLBACK_RUNTIME"
    install -d -m 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
fi

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$XDG_RUNTIME_DIR/cache}"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" 2>/dev/null || true

setxkbmap -layout 'us,ru' -option 'grp:alt_shift_toggle' >/dev/null 2>&1 || true
xset s off >/dev/null 2>&1 || true
xset -dpms >/dev/null 2>&1 || true
xset s noblank >/dev/null 2>&1 || true
xsetroot -solid '#0b1220' >/dev/null 2>&1 || true
unclutter -idle 3 -root >/dev/null 2>&1 &

# Openbox перезапускается независимо от Chromium, чтобы сервисные горячие
# клавиши сохранялись даже после аварии оконного менеджера.
(
  while true; do
    openbox --config-file /etc/openbox/rc.xml >>"$LOG_DIR/openbox.log" 2>&1 || true
    sleep 1
  done
) &

for _ in $(seq 1 50); do
    pgrep -x openbox >/dev/null 2>&1 && break
    sleep 0.1
done
sleep 0.5

exec /opt/op-kiosk/start-browser.sh''',
)

replace_heredoc(
    "config/includes.chroot/opt/op-kiosk/start-browser.sh",
    r'''#!/bin/bash
set -u

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
CONF=/var/lib/op-kiosk/kiosk.conf
LOCAL_PAGE='file:///opt/op-kiosk/html/index.html'
LOG_DIR=/var/log/op-kiosk

mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG="$LOG_DIR/browser.log"
if ! touch "$LOG" 2>/dev/null; then
    LOG=/tmp/op-kiosk-browser.log
fi
: >"$LOG" 2>/dev/null || true
exec >>"$LOG" 2>&1

printf '[%s] OP Kiosk OS 1.3: launcher запущен, UID=%s, DISPLAY=%s\n' \
    "$(date -Is)" "$(id -u)" "${DISPLAY:-не задан}"

export HOME="${HOME:-/home/kiosk}"
export USER="${USER:-kiosk}"
export LOGNAME="${LOGNAME:-kiosk}"
export DISPLAY="${DISPLAY:-:0}"

UID_NOW="$(id -u)"
SYSTEM_RUNTIME="/run/user/$UID_NOW"
FALLBACK_RUNTIME="/tmp/op-kiosk-runtime-$UID_NOW"
if [[ -d "$SYSTEM_RUNTIME" && -w "$SYSTEM_RUNTIME" ]]; then
    export XDG_RUNTIME_DIR="$SYSTEM_RUNTIME"
else
    export XDG_RUNTIME_DIR="$FALLBACK_RUNTIME"
    install -d -m 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
fi

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$XDG_RUNTIME_DIR/cache}"
export TMPDIR="$XDG_RUNTIME_DIR/tmp"
PROFILE=/var/lib/op-kiosk/chromium
CACHE="$XDG_CACHE_HOME/chromium"
CRASH="$XDG_CONFIG_HOME/chromium/Crash Reports"
HOME_CRASH="$HOME/.config/chromium/Crash Reports"

mkdir -p \
    "$PROFILE" \
    "$CACHE" \
    "$CRASH/pending" \
    "$HOME_CRASH/pending" \
    "$TMPDIR" 2>/dev/null || true
chmod 0700 "$PROFILE" "$CACHE" "$XDG_RUNTIME_DIR" "$TMPDIR" 2>/dev/null || true

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

show_error_once() {
    local marker=/tmp/op-kiosk-browser-error-shown
    [[ -e "$marker" ]] && return 0
    : >"$marker"
    local tail_text
    tail_text="$(tail -n 25 "$LOG" 2>/dev/null || true)"
    if command -v zenity >/dev/null 2>&1; then
        zenity --error \
          --title='OP Kiosk OS — ошибка запуска браузера' \
          --width=780 \
          --text="Chromium не запустился. Повторные попытки продолжаются.\n\nЖурнал: $LOG\n\n$tail_text" \
          >/dev/null 2>&1 &
    fi
}

launch_browser() {
    local browser="$1"
    local url="$2"
    local proxy="$3"
    local safe_mode="$4"
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
      --disable-crash-reporter
      --disable-breakpad
      --crash-dumps-dir="$CRASH"
      --disable-gpu
      --use-gl=swiftshader
      --overscroll-history-navigation=0
      --disable-pinch
      --autoplay-policy=no-user-gesture-required
      --user-data-dir="$PROFILE"
      --disk-cache-dir="$CACHE"
      --password-store=basic
    )

    [[ -n "$proxy" ]] && args+=(--proxy-server="$proxy")
    [[ "$safe_mode" == yes ]] && args+=(--no-sandbox --disable-gpu-compositing)

    if grep -qw 'opkiosk.smoketest' /proc/cmdline 2>/dev/null; then
        args+=(--remote-debugging-address=127.0.0.1 --remote-debugging-port=9222)
    fi

    printf '\n[%s] Запуск браузера: %q' "$(date -Is)" "$browser"
    printf ' %q' "${args[@]}" "$url"
    printf '\n'

    local started pid rc elapsed
    started="$(date +%s)"
    "$browser" "${args[@]}" "$url" &
    pid=$!
    wait "$pid"
    rc=$?
    elapsed=$(( $(date +%s) - started ))
    printf '[%s] Chromium завершился: rc=%s, время=%ss\n' \
        "$(date -Is)" "$rc" "$elapsed"

    (( elapsed < 8 )) && return 111
    return "$rc"
}

rm -f /tmp/op-kiosk-browser-error-shown 2>/dev/null || true

while true; do
    KIOSK_URL='https://op.arkhbum.local'
    PROXY_URL=''
    BROWSER='chromium'
    source "$CONF" 2>/dev/null || true

    if grep -qw 'opkiosk.smoketest' /proc/cmdline 2>/dev/null; then
        URL="$LOCAL_PAGE"
    else
        URL="${KIOSK_URL:-$LOCAL_PAGE}"
    fi
    PROXY="${PROXY_URL:-}"

    if ! BROWSER_PATH="$(resolve_browser "${BROWSER:-chromium}")"; then
        printf '[%s] Chromium не найден. PATH=%s\n' "$(date -Is)" "$PATH"
        show_error_once
        sleep 5
        continue
    fi

    launch_browser "$BROWSER_PATH" "$URL" "$PROXY" no
    rc=$?

    if [[ $rc -eq 111 ]]; then
        printf '[%s] Раннее завершение. Повтор с --no-sandbox.\n' "$(date -Is)"
        launch_browser "$BROWSER_PATH" "$URL" "$PROXY" yes
        rc=$?
    fi

    [[ $rc -eq 111 ]] && show_error_once
    sleep 2
done''',
)

replace_heredoc(
    "config/includes.chroot/etc/systemd/system/op-kiosk-smoke.service",
    r'''[Unit]
Description=OP Kiosk OS full boot browser smoke test
ConditionKernelCommandLine=opkiosk.smoketest
After=lightdm.service NetworkManager.service
Wants=lightdm.service NetworkManager.service

[Service]
Type=oneshot
ExecStart=/opt/op-kiosk/smoke-test.sh
TimeoutStartSec=240

[Install]
WantedBy=graphical.target''',
)

replace_heredoc(
    "config/includes.chroot/opt/op-kiosk/smoke-test.sh",
    r'''#!/bin/bash
set -u

serial() {
    printf '%s\n' "$*" >/dev/ttyS0 2>/dev/null || true
}

serial OPKIOSK_SMOKE_STARTED
for _ in $(seq 1 180); do
    if curl -fsS --max-time 2 http://127.0.0.1:9222/json/list 2>/dev/null \
       | grep -q 'OP Kiosk OS'; then
        serial OPKIOSK_BROWSER_OK
        sleep 2
        systemctl poweroff
        exit 0
    fi
    sleep 1
done

serial OPKIOSK_BROWSER_FAILED
serial '--- lightdm ---'
tail -n 80 /var/log/lightdm/lightdm.log >/dev/ttyS0 2>/dev/null || true
serial '--- session ---'
tail -n 80 /var/log/op-kiosk/session.log >/dev/ttyS0 2>/dev/null || true
serial '--- browser ---'
tail -n 120 /var/log/op-kiosk/browser.log >/dev/ttyS0 2>/dev/null || true
systemctl poweroff
exit 1''',
)

# Дополнительные файлы LightDM и диагностического терминала.
insert_before(
    "cat > config/hooks/live/0100-op-kiosk.hook.chroot <<'EOF'",
    r'''mkdir -p \
  config/includes.chroot/etc/lightdm/lightdm.conf.d \
  config/includes.chroot/etc/systemd/system/lightdm.service.d \
  config/includes.chroot/etc/tmpfiles.d \
  config/includes.chroot/etc/X11 \
  config/includes.chroot/etc/xdg/openbox \
  config/includes.chroot/usr/share/xsessions \
  config/includes.chroot/var/log/op-kiosk

cat > config/includes.chroot/etc/lightdm/lightdm.conf.d/50-op-kiosk.conf <<'EOF'
[LightDM]
run-directory=/run/lightdm

[Seat:*]
autologin-user=kiosk
autologin-user-timeout=0
autologin-session=op-kiosk
user-session=op-kiosk
greeter-session=lightdm-gtk-greeter
allow-guest=false
xserver-command=X -core -nolisten tcp -s 0 -dpms
EOF

cat > config/includes.chroot/etc/systemd/system/lightdm.service.d/10-op-kiosk.conf <<'EOF'
[Unit]
After=systemd-user-sessions.service live-config.service NetworkManager.service
Wants=NetworkManager.service

[Service]
Restart=always
RestartSec=2
EOF

cat > config/includes.chroot/etc/X11/Xwrapper.config <<'EOF'
allowed_users=anybody
needs_root_rights=auto
EOF

cat > config/includes.chroot/etc/tmpfiles.d/op-kiosk.conf <<'EOF'
d /run/op-kiosk 0755 kiosk kiosk -
d /var/log/op-kiosk 0755 kiosk kiosk -
EOF

cat > config/includes.chroot/usr/share/xsessions/op-kiosk.desktop <<'EOF'
[Desktop Entry]
Name=OP Kiosk OS
Comment=Автоматическая kiosk-сессия Chromium
Exec=/opt/op-kiosk/session.sh
TryExec=/opt/op-kiosk/session.sh
Type=Application
DesktopNames=OPKiosk
EOF

cat > config/includes.chroot/opt/op-kiosk/session.sh <<'EOF'
#!/bin/bash
set -u
exec /opt/op-kiosk/xinitrc
EOF

cat > config/includes.chroot/opt/op-kiosk/admin-terminal.sh <<'EOF'
#!/bin/bash
set -u
TITLE='OP Kiosk OS — диагностический терминал'
pass=$(zenity --password --title="$TITLE" --text='Пароль администратора:' 2>/dev/null) || exit 0
hash=$(printf '%s' "$pass" | sha256sum | awk '{print $1}')
if ! printf '%s\n' "$hash" | sudo /usr/local/sbin/op-kiosk-auth; then
    zenity --error --title="$TITLE" --text='Неверный пароль.' 2>/dev/null || true
    exit 1
fi
exec xterm -fa 'DejaVu Sans Mono' -fs 12 -title "$TITLE" -e /bin/bash -l
EOF

cat > config/includes.chroot/etc/xdg/openbox/menu.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="OP Kiosk OS"/>
</openbox_menu>
EOF''',
    "файлы LightDM",
)

# Установщик должен загрузить установленную систему тем же способом, что Live ISO.
old_installer_services = r'''chroot "$TARGET" /bin/bash -c '
  systemctl enable NetworkManager.service >/dev/null 2>&1 || true
  systemctl enable op-kiosk-network-priority.service >/dev/null 2>&1 || true
  systemctl enable getty@tty1.service >/dev/null 2>&1 || true
  systemctl set-default multi-user.target >/dev/null 2>&1 || true
' '''.rstrip()
new_installer_services = r'''chroot "$TARGET" /bin/bash -c '
  systemctl enable NetworkManager.service >/dev/null 2>&1 || true
  systemctl enable op-kiosk-network-priority.service >/dev/null 2>&1 || true
  systemctl enable lightdm.service >/dev/null 2>&1 || true
  ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service
  systemctl set-default graphical.target >/dev/null 2>&1 || true
' '''.rstrip()
replace_once(
    old_installer_services,
    new_installer_services,
    "службы установленной системы",
)

replace_heredoc(
    "config/hooks/live/0100-op-kiosk.hook.chroot",
    r'''#!/bin/bash
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
groupadd -f nopasswdlogin
usermod -aG nopasswdlogin kiosk
passwd -l kiosk >/dev/null 2>&1 || true
rm -f /home/kiosk/.bash_profile /etc/skel/.bash_profile

mkdir -p \
  /var/lib/op-kiosk/chromium \
  /var/log/op-kiosk \
  /etc/xdg/openbox
chown -R kiosk:kiosk /var/lib/op-kiosk /var/log/op-kiosk /home/kiosk
chmod 0750 /var/lib/op-kiosk
chmod 0755 /var/log/op-kiosk
chmod 0600 /var/lib/op-kiosk/kiosk.conf
chmod 0600 /etc/op-kiosk/admin.sha256
chmod 0755 /opt/op-kiosk/*.sh /opt/op-kiosk/xinitrc /usr/local/sbin/op-kiosk-* || true
chmod 0440 /etc/sudoers.d/op-kiosk

systemctl enable NetworkManager.service >/dev/null 2>&1 || true
systemctl enable op-kiosk-network-priority.service >/dev/null 2>&1 || true
systemctl enable op-kiosk-smoke.service >/dev/null 2>&1 || true
systemctl enable lightdm.service >/dev/null 2>&1 || true
ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service
systemctl set-default graphical.target >/dev/null 2>&1 || true
systemctl mask ctrl-alt-del.target >/dev/null 2>&1 || true
for n in 2 3 4 5 6; do systemctl mask "getty@tty${n}.service" >/dev/null 2>&1 || true; done

cat > /etc/xdg/openbox/menu.xml <<'EOT'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="OP Kiosk OS"/>
</openbox_menu>
EOT

# Проверяем критичные файлы прямо во время сборки chroot.
test -x /opt/op-kiosk/session.sh
test -x /opt/op-kiosk/start-browser.sh
test -f /usr/share/xsessions/op-kiosk.desktop
test -f /etc/lightdm/lightdm.conf.d/50-op-kiosk.conf
lightdm --show-config >/tmp/op-kiosk-lightdm-config.txt 2>&1 || true

apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /tmp/* /var/tmp/*''',
)

BUILD.write_text(text, encoding="utf-8")
print("build.sh подготовлен для OP Kiosk OS 1.3")
