#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Directory = $PSScriptRoot,

    [Parameter(Mandatory = $false)]
    [switch]$KeepBrokenIso
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
    # Старые консоли Windows могут не принять изменение кодировки.
}

function Write-Title {
    param([string]$Text)

    Write-Host ''
    Write-Host ('=' * 72)
    Write-Host ('  ' + $Text)
    Write-Host ('=' * 72)
}

function Write-Step {
    param([string]$Text)
    Write-Host ('[>] ' + $Text)
}

function Write-Ok {
    param([string]$Text)
    Write-Host ('[OK] ' + $Text)
}

function Write-WarnMessage {
    param([string]$Text)
    Write-Warning $Text
}

function Get-Sha256Record {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Line,

        [Parameter(Mandatory = $true)]
        [string]$SourceName
    )

    $trimmed = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw "Пустая строка в файле контрольных сумм: $SourceName"
    }

    if ($trimmed -notmatch '^(?<Hash>[0-9A-Fa-f]{64})\s+\*?(?<Name>.+)$') {
        throw "Некорректная строка SHA-256 в $SourceName`: $Line"
    }

    $name = $Matches.Name.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "В $SourceName не указано имя файла."
    }

    if ([System.IO.Path]::IsPathRooted($name) -or $name.Contains('..')) {
        throw "Небезопасное имя файла в $SourceName`: $name"
    }

    [pscustomobject]@{
        Hash = $Matches.Hash.ToLowerInvariant()
        Name = $name
    }
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Format-ByteSize {
    param([Parameter(Mandatory = $true)][Int64]$Bytes)

    if ($Bytes -ge 1GB) {
        return ('{0:N2} ГиБ' -f ($Bytes / 1GB))
    }
    if ($Bytes -ge 1MB) {
        return ('{0:N2} МиБ' -f ($Bytes / 1MB))
    }
    if ($Bytes -ge 1KB) {
        return ('{0:N2} КиБ' -f ($Bytes / 1KB))
    }
    return "$Bytes байт"
}

$temporaryIso = $null

try {
    Write-Title 'OP Kiosk OS 2.0 — сборка ISO из малых частей'

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        throw 'Не указан каталог с частями.'
    }

    $root = [System.IO.Path]::GetFullPath($Directory)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Каталог не найден: $root"
    }

    Set-Location -LiteralPath $root
    Write-Step "Рабочий каталог: $root"

    $partManifestFiles = @(
        Get-ChildItem -LiteralPath $root -File -Filter 'OP-Kiosk-OS-*-parts.sha256'
    )
    if ($partManifestFiles.Count -eq 0) {
        throw 'Не найден файл OP-Kiosk-OS-*-parts.sha256.'
    }
    if ($partManifestFiles.Count -gt 1) {
        throw 'Найдено несколько файлов *-parts.sha256. Оставьте в папке только один комплект одной версии.'
    }
    $partManifest = $partManifestFiles[0]

    $isoHashFiles = @(
        Get-ChildItem -LiteralPath $root -File -Filter 'OP-Kiosk-OS-*-amd64.iso.sha256'
    )
    if ($isoHashFiles.Count -eq 0) {
        throw 'Не найден файл OP-Kiosk-OS-*-amd64.iso.sha256.'
    }
    if ($isoHashFiles.Count -gt 1) {
        throw 'Найдено несколько файлов *.iso.sha256. Оставьте в папке только один комплект одной версии.'
    }
    $isoHashFile = $isoHashFiles[0]

    Write-Step "Чтение списка частей: $($partManifest.Name)"
    $manifestLines = @(
        Get-Content -LiteralPath $partManifest.FullName -Encoding UTF8 |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($manifestLines.Count -eq 0) {
        throw "Файл $($partManifest.Name) пуст."
    }

    $expectedParts = @()
    foreach ($line in $manifestLines) {
        $expectedParts += Get-Sha256Record -Line $line -SourceName $partManifest.Name
    }

    $duplicateNames = @(
        $expectedParts |
            Group-Object -Property Name |
            Where-Object Count -gt 1
    )
    if ($duplicateNames.Count -gt 0) {
        throw "В $($partManifest.Name) повторяются имена частей."
    }

    $expectedParts = @($expectedParts | Sort-Object -Property Name)

    $isoHashLines = @(
        Get-Content -LiteralPath $isoHashFile.FullName -Encoding UTF8 |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($isoHashLines.Count -ne 1) {
        throw "В $($isoHashFile.Name) должна быть ровно одна непустая строка."
    }
    $isoRecord = Get-Sha256Record -Line $isoHashLines[0] -SourceName $isoHashFile.Name

    if (-not $isoRecord.Name.EndsWith('.iso', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "В $($isoHashFile.Name) указано не ISO-имя: $($isoRecord.Name)"
    }

    $actualPartFiles = @(
        Get-ChildItem -LiteralPath $root -File -Filter 'OP-Kiosk-OS-*-amd64.iso.part-*.bin' |
            Sort-Object -Property Name
    )

    $expectedNames = @($expectedParts | ForEach-Object Name)
    $actualNames = @($actualPartFiles | ForEach-Object Name)
    $differences = @(
        Compare-Object -ReferenceObject $expectedNames -DifferenceObject $actualNames
    )
    if ($differences.Count -gt 0) {
        $details = ($differences | ForEach-Object {
            if ($_.SideIndicator -eq '<=') {
                "отсутствует: $($_.InputObject)"
            } else {
                "лишний файл: $($_.InputObject)"
            }
        }) -join '; '
        throw "Набор частей не совпадает с манифестом: $details"
    }

    if ($actualPartFiles.Count -ne $expectedParts.Count) {
        throw 'Количество найденных частей не совпадает с манифестом.'
    }

    Write-Ok "Найден полный комплект: $($expectedParts.Count) частей."

    $totalSize = [Int64]0
    for ($index = 0; $index -lt $expectedParts.Count; $index++) {
        $record = $expectedParts[$index]
        $partPath = Join-Path $root $record.Name
        $partNumber = $index + 1

        Write-Step "Проверка части $partNumber/$($expectedParts.Count): $($record.Name)"
        if (-not (Test-Path -LiteralPath $partPath -PathType Leaf)) {
            throw "Отсутствует часть: $($record.Name)"
        }

        $actualHash = Get-FileSha256 -Path $partPath
        if ($actualHash -ne $record.Hash) {
            throw "Повреждена часть $($record.Name). Ожидался SHA-256 $($record.Hash), получен $actualHash"
        }

        $partLength = (Get-Item -LiteralPath $partPath).Length
        if ($partLength -le 0) {
            throw "Часть имеет нулевой размер: $($record.Name)"
        }
        $totalSize += $partLength
        Write-Ok "Часть исправна: $(Format-ByteSize -Bytes $partLength)"
    }

    $outputIso = Join-Path $root $isoRecord.Name
    $temporaryIso = "$outputIso.assembling"

    if (Test-Path -LiteralPath $outputIso -PathType Leaf) {
        Write-Step "Проверка уже существующего ISO: $($isoRecord.Name)"
        $existingHash = Get-FileSha256 -Path $outputIso
        if ($existingHash -eq $isoRecord.Hash) {
            $existingSize = (Get-Item -LiteralPath $outputIso).Length
            if ($existingSize -eq $totalSize) {
                Write-Ok 'ISO уже собран и полностью исправен.'
                Write-Host ''
                Write-Host "Файл:   $outputIso"
                Write-Host "Размер: $(Format-ByteSize -Bytes $existingSize)"
                Write-Host "SHA-256: $existingHash"
                exit 0
            }
        }

        Write-WarnMessage 'Существующий ISO не прошёл проверку и будет пересобран.'
        Remove-Item -LiteralPath $outputIso -Force
    }

    if (Test-Path -LiteralPath $temporaryIso) {
        Remove-Item -LiteralPath $temporaryIso -Force
    }

    Write-Step "Сборка ISO: $($isoRecord.Name)"
    $outputStream = [System.IO.File]::Open(
        $temporaryIso,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
    )

    try {
        for ($index = 0; $index -lt $expectedParts.Count; $index++) {
            $record = $expectedParts[$index]
            $partPath = Join-Path $root $record.Name
            $partNumber = $index + 1

            Write-Step "Добавление части $partNumber/$($expectedParts.Count): $($record.Name)"
            $inputStream = [System.IO.File]::Open(
                $partPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::Read
            )
            try {
                $inputStream.CopyTo($outputStream, 4MB)
            } finally {
                $inputStream.Dispose()
            }
        }
        $outputStream.Flush()
    } finally {
        $outputStream.Dispose()
    }

    $assembledSize = (Get-Item -LiteralPath $temporaryIso).Length
    if ($assembledSize -ne $totalSize) {
        throw "Неверный размер собранного файла. Ожидалось $totalSize байт, получено $assembledSize байт."
    }
    Write-Ok "Размер собранного ISO совпал: $(Format-ByteSize -Bytes $assembledSize)"

    Write-Step 'Проверка итогового SHA-256. Это может занять несколько минут.'
    $assembledHash = Get-FileSha256 -Path $temporaryIso
    if ($assembledHash -ne $isoRecord.Hash) {
        throw "Итоговый SHA-256 не совпал. Ожидался $($isoRecord.Hash), получен $assembledHash"
    }
    Write-Ok 'Итоговый SHA-256 совпал.'

    Move-Item -LiteralPath $temporaryIso -Destination $outputIso -Force
    $temporaryIso = $null

    Write-Title 'ISO успешно собран и проверен'
    Write-Host "Файл:   $outputIso"
    Write-Host "Размер: $(Format-ByteSize -Bytes $assembledSize)"
    Write-Host "SHA-256: $assembledHash"
    Write-Host ''
    Write-Host 'Теперь ISO можно записывать на USB через Rufus в режиме DD.'
    exit 0
} catch {
    if ($temporaryIso -and (Test-Path -LiteralPath $temporaryIso)) {
        if ($KeepBrokenIso) {
            Write-WarnMessage "Незавершённый файл оставлен для диагностики: $temporaryIso"
        } else {
            Remove-Item -LiteralPath $temporaryIso -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host ''
    Write-Host ('ОШИБКА: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ''
    Write-Host 'Проверьте, что все части и файлы SHA-256 находятся в одной папке и относятся к одной версии.'
    exit 1
}
