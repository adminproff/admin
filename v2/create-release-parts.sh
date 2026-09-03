#!/usr/bin/env bash
set -Eeuo pipefail

ISO_PATH="${1:-}"
OUTPUT_DIR="${2:-}"
PART_SIZE_MIB="${OPKIOSK_PART_SIZE_MIB:-200}"
MAX_PARTS="${OPKIOSK_MAX_PARTS:-12}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

fail() {
    printf 'ОШИБКА: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

for command_name in \
    split sha256sum stat awk find sort cat basename dirname readlink cp mkdir; do
    command -v "$command_name" >/dev/null 2>&1 \
        || fail "Не найден обязательный инструмент: $command_name"
done

[[ -n "$ISO_PATH" ]] || fail "Использование: $0 /path/image.iso /path/output-dir"
[[ -f "$ISO_PATH" && -s "$ISO_PATH" ]] || fail "ISO не найден или пуст: $ISO_PATH"
[[ "$PART_SIZE_MIB" =~ ^[0-9]+$ ]] || fail "OPKIOSK_PART_SIZE_MIB должен быть целым числом"
[[ "$MAX_PARTS" =~ ^[0-9]+$ ]] || fail "OPKIOSK_MAX_PARTS должен быть целым числом"
(( PART_SIZE_MIB >= 16 )) || fail "Размер части должен быть не меньше 16 МиБ"
(( MAX_PARTS >= 1 )) || fail "Максимальное число частей должно быть не меньше 1"

ISO_PATH="$(readlink -f "$ISO_PATH")"
[[ -n "$OUTPUT_DIR" ]] || OUTPUT_DIR="$(dirname "$ISO_PATH")/release-parts"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(readlink -f "$OUTPUT_DIR")"

ISO_NAME="$(basename "$ISO_PATH")"
[[ "$ISO_NAME" == OP-Kiosk-OS-*-amd64.iso ]] \
    || fail "Неожиданное имя ISO: $ISO_NAME"

BASE_NAME="${ISO_NAME%.iso}"
PART_PREFIX="$OUTPUT_DIR/$ISO_NAME.part-"
ISO_HASH_FILE_SOURCE="$ISO_PATH.sha256"
ISO_HASH_FILE="$OUTPUT_DIR/$ISO_NAME.sha256"
PART_HASH_FILE="$OUTPUT_DIR/${BASE_NAME%-amd64}-parts.sha256"
INFO_FILE="$OUTPUT_DIR/DOWNLOAD-INFO.txt"

[[ -s "$ISO_HASH_FILE_SOURCE" ]] \
    || fail "Не найден файл итогового SHA-256: $ISO_HASH_FILE_SOURCE"

EXPECTED_ISO_HASH="$(awk 'NF {print tolower($1); exit}' "$ISO_HASH_FILE_SOURCE")"
[[ "$EXPECTED_ISO_HASH" =~ ^[0-9a-f]{64}$ ]] \
    || fail "Некорректный SHA-256 в $ISO_HASH_FILE_SOURCE"

ACTUAL_ISO_HASH="$(sha256sum "$ISO_PATH" | awk '{print tolower($1)}')"
[[ "$ACTUAL_ISO_HASH" == "$EXPECTED_ISO_HASH" ]] \
    || fail "Исходный ISO не прошёл SHA-256 перед разбиением"

log "Очистка каталога малых частей"
find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -type f -delete

log "Разбиение $ISO_NAME на части по ${PART_SIZE_MIB} МиБ"
split \
    --bytes="${PART_SIZE_MIB}M" \
    --numeric-suffixes=1 \
    --suffix-length=2 \
    --additional-suffix=.bin \
    "$ISO_PATH" \
    "$PART_PREFIX"

mapfile -t PART_FILES < <(
    find "$OUTPUT_DIR" -maxdepth 1 -type f \
        -name "$ISO_NAME.part-*.bin" -print | sort
)
PART_COUNT="${#PART_FILES[@]}"
(( PART_COUNT >= 1 )) || fail "После split не создано ни одной части"
(( PART_COUNT <= MAX_PARTS )) \
    || fail "Создано $PART_COUNT частей, но workflow поддерживает максимум $MAX_PARTS"

log "Проверка размеров частей"
PART_SIZE_BYTES=$(( PART_SIZE_MIB * 1024 * 1024 ))
for ((i = 0; i < PART_COUNT; i++)); do
    size="$(stat -c '%s' "${PART_FILES[$i]}")"
    (( size > 0 )) || fail "Нулевая часть: ${PART_FILES[$i]}"
    if (( i < PART_COUNT - 1 && size != PART_SIZE_BYTES )); then
        fail "Неверный размер части $(basename "${PART_FILES[$i]}"): $size"
    fi
done

log "Создание SHA-256 каждой части"
(
    cd "$OUTPUT_DIR"
    sha256sum "$ISO_NAME".part-*.bin >"$(basename "$PART_HASH_FILE")"
)

log "Копирование сборщика и итоговой контрольной суммы"
cp -f "$SCRIPT_DIR/download-kit/MERGE-OP-Kiosk-OS-2.0.cmd" "$OUTPUT_DIR/"
cp -f "$SCRIPT_DIR/download-kit/README-FIRST-RU.txt" "$OUTPUT_DIR/"
{
    # Windows PowerShell 5.1 корректно читает кириллицу только при наличии UTF-8 BOM.
    printf '\357\273\277'
    cat "$SCRIPT_DIR/download-kit/MERGE-OP-Kiosk-OS-2.0.ps1"
} >"$OUTPUT_DIR/MERGE-OP-Kiosk-OS-2.0.ps1"
printf '%s  %s\n' "$EXPECTED_ISO_HASH" "$ISO_NAME" >"$ISO_HASH_FILE"

log "Потоковая проверка обратной сборки"
REBUILT_HASH="$({
    for part in "${PART_FILES[@]}"; do
        cat "$part"
    done
} | sha256sum | awk '{print tolower($1)}')"
[[ "$REBUILT_HASH" == "$EXPECTED_ISO_HASH" ]] \
    || fail "Обратная сборка частей дала неверный SHA-256: $REBUILT_HASH"

SUM_PARTS=0
for part in "${PART_FILES[@]}"; do
    size="$(stat -c '%s' "$part")"
    SUM_PARTS=$(( SUM_PARTS + size ))
done
ISO_SIZE="$(stat -c '%s' "$ISO_PATH")"
(( SUM_PARTS == ISO_SIZE )) \
    || fail "Суммарный размер частей $SUM_PARTS не равен размеру ISO $ISO_SIZE"

cat >"$INFO_FILE" <<EOF
PRODUCT=OP Kiosk OS
ISO_FILE=$ISO_NAME
ISO_SIZE_BYTES=$ISO_SIZE
ISO_SHA256=$EXPECTED_ISO_HASH
PART_SIZE_MIB=$PART_SIZE_MIB
PART_COUNT=$PART_COUNT
PARTS_SHA256_FILE=$(basename "$PART_HASH_FILE")
MERGE_CMD=MERGE-OP-Kiosk-OS-2.0.cmd
MERGE_POWERSHELL=MERGE-OP-Kiosk-OS-2.0.ps1
STATUS=FULL-CYCLE-PASS-ONLY
EOF

printf '%s\n' "$PART_COUNT" >"$OUTPUT_DIR/PART-COUNT.txt"

log "Итоговая проверка комплекта"
for required in \
    "$PART_HASH_FILE" \
    "$ISO_HASH_FILE" \
    "$INFO_FILE" \
    "$OUTPUT_DIR/PART-COUNT.txt" \
    "$OUTPUT_DIR/MERGE-OP-Kiosk-OS-2.0.cmd" \
    "$OUTPUT_DIR/MERGE-OP-Kiosk-OS-2.0.ps1" \
    "$OUTPUT_DIR/README-FIRST-RU.txt"; do
    [[ -s "$required" ]] || fail "Не создан обязательный файл: $required"
done

printf '\nКомплект малых частей создан и проверен:\n'
printf '  Каталог: %s\n' "$OUTPUT_DIR"
printf '  ISO: %s\n' "$ISO_NAME"
printf '  Размер ISO: %s байт\n' "$ISO_SIZE"
printf '  SHA-256 ISO: %s\n' "$EXPECTED_ISO_HASH"
printf '  Частей: %s по %s МиБ\n' "$PART_COUNT" "$PART_SIZE_MIB"
printf '  Потоковая обратная сборка: PASS\n\n'
