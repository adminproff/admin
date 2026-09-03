#!/usr/bin/env bash
set -Eeuo pipefail

PRODUCT="OP-Kiosk-OS"
VERSION="${OPKIOSK_VERSION:-2.0.0-alpha1}"
ARCH="amd64"
DIST="${OPKIOSK_DIST:-trixie}"
DEFAULT_URL="${OPKIOSK_URL:-http://op-arkhbum.local:3080}"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="${OPKIOSK_WORK_DIR:-$ROOT_DIR/.work}"
OUT_DIR="${OPKIOSK_OUT_DIR:-$ROOT_DIR/output}"
LOG_DIR="$OUT_DIR/logs"

log() {
    printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
    printf '\nОШИБКА: %s\n' "$*" >&2
    exit 1
}

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    fail "Запустите сборку от root: sudo $0"
fi

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8

if [[ "${OPKIOSK_SKIP_APT:-0}" != 1 ]]; then
    log "Установка инструментов сборки"
    apt-get update
    apt-get install -y --no-install-recommends \
        live-build debootstrap xorriso squashfs-tools dosfstools rsync \
        ca-certificates curl gnupg file isolinux syslinux-common \
        grub-pc-bin grub-efi-amd64-bin grub-efi-amd64-signed shim-signed \
        mtools fdisk parted jq python3-minimal
fi

for command_name in lb xorriso sha256sum rsync file python3; do
    command -v "$command_name" >/dev/null 2>&1 \
        || fail "Не найден обязательный инструмент: $command_name"
done

log "Очистка предыдущей сборки"
rm -rf "$WORK_DIR" "$OUT_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR" "$LOG_DIR"
cd "$WORK_DIR"

lb clean --purge >/dev/null 2>&1 || true

log "Формирование конфигурации live-build"
lb config noauto \
    --mode debian \
    --distribution "$DIST" \
    --distribution-binary "$DIST" \
    --distribution-chroot "$DIST" \
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
    --debian-installer live \
    --debian-installer-distribution "$DIST" \
    --debian-installer-gui true \
    --debian-installer-preseedfile preseed.cfg \
    --uefi-secure-boot auto \
    --memtest none \
    --checksums sha256 \
    --iso-application "OP Kiosk OS $VERSION" \
    --iso-publisher "OP Kiosk OS Project" \
    --iso-preparer "OP Kiosk OS automated build" \
    --iso-volume "OPKIOSK_2_0" \
    --bootappend-live "boot=live components username=kiosk user-fullname=OP_Kiosk hostname=op-kiosk locales=ru_RU.UTF-8 keyboard-layouts=us quiet loglevel=3 systemd.show_status=false vt.global_cursor_default=0"

"$ROOT_DIR/prepare-config.sh" \
    --work-dir "$WORK_DIR" \
    --version "$VERSION" \
    --default-url "$DEFAULT_URL"

bash "$ROOT_DIR/fix-generated-config.sh" --work-dir "$WORK_DIR"

log "Проверка созданной конфигурации"
while IFS= read -r -d '' script; do
    bash -n "$script"
done < <(
    find config -type f \
        \( -name '*.sh' -o -name '*.hook.chroot' -o -name '*.hook.binary' \) \
        -print0
)

for required in \
    config/package-lists/op-kiosk.list.chroot \
    config/includes.chroot/etc/lightdm/lightdm.conf.d/50-op-kiosk.conf \
    config/includes.chroot/usr/share/xsessions/op-kiosk.desktop \
    config/includes.chroot/opt/op-kiosk/session.sh \
    config/includes.chroot/opt/op-kiosk/browser-supervisor.sh \
    config/includes.chroot/opt/op-kiosk/admin-menu.sh \
    config/includes.chroot/usr/local/sbin/op-kiosk-finalize \
    config/includes.installer/usr/lib/finish-install.d/90op-kiosk \
    config/binary_debian-installer/preseed.cfg; do
    [[ -s "$required" ]] || fail "Отсутствует обязательный файл: $required"
done

log "Сборка ISO с Debian Live Installer"
set +e
lb build 2>&1 | tee "$LOG_DIR/build.log"
BUILD_RC=${PIPESTATUS[0]}
set -e
(( BUILD_RC == 0 )) || fail "live-build завершился с кодом $BUILD_RC"

ISO_SOURCE="$(
    find . -maxdepth 1 -type f \
        \( -name 'live-image-amd64.hybrid.iso' -o -name '*.iso' \) \
        -print -quit
)"
[[ -n "$ISO_SOURCE" && -s "$ISO_SOURCE" ]] || fail "Готовый ISO не найден"

ISO_NAME="${PRODUCT}-${VERSION}-${ARCH}.iso"
ISO_PATH="$OUT_DIR/$ISO_NAME"
cp -f "$ISO_SOURCE" "$ISO_PATH"
(
    cd "$OUT_DIR"
    sha256sum "$ISO_NAME" >"$ISO_NAME.sha256"
    sha256sum -c "$ISO_NAME.sha256"
)

log "Структурная проверка ISO"
xorriso -indev "$ISO_PATH" -report_el_torito plain \
    >"$LOG_DIR/iso-el-torito.txt" 2>&1
xorriso -indev "$ISO_PATH" -find / -maxdepth 3 -type f -print \
    >"$LOG_DIR/iso-files.txt" 2>&1
file "$ISO_PATH" >"$LOG_DIR/iso-file-info.txt"

if ! grep -Eiq '/install(\.amd)?/(vmlinuz|linux)' "$LOG_DIR/iso-files.txt"; then
    fail "В ISO не найдено ядро Debian Installer"
fi
if ! grep -Eiq '/install(\.amd)?/initrd' "$LOG_DIR/iso-files.txt"; then
    fail "В ISO не найден initrd Debian Installer"
fi
if ! grep -Fqi '/live/filesystem.squashfs' "$LOG_DIR/iso-files.txt"; then
    fail "В ISO не найден filesystem.squashfs"
fi

cat >"$OUT_DIR/BUILD-INFO.txt" <<EOF
PRODUCT=OP Kiosk OS
VERSION=$VERSION
ARCH=$ARCH
DISTRIBUTION=$DIST
DEFAULT_URL=$DEFAULT_URL
ISO_FILE=$ISO_NAME
ISO_SIZE=$(stat -c '%s' "$ISO_PATH")
ISO_SHA256=$(sha256sum "$ISO_PATH" | awk '{print $1}')
INSTALLER=Debian Installer live-installer
SESSION=systemd -> LightDM -> Openbox -> Chromium
STATUS=EXPERIMENTAL; release is forbidden until full install-and-cold-boot CI passes
EOF

printf '\nСборка создана:\n  %s\n  %s\n\n' \
    "$ISO_PATH" "$ISO_PATH.sha256"
