# OP Kiosk OS 2.0

Чистая переработка kiosk-системы для HP t530 после отзыва линейки 1.3.x.

## Статус

`2.0.0-alpha1` — экспериментальная сборка. Она не публикуется как готовый образ, пока GitHub Actions не пройдёт полный цикл установки и последующей загрузки с внутреннего диска в BIOS и UEFI.

## Архитектура

```text
Live ISO
  ├─ Live mode
  │    └─ systemd -> LightDM -> Openbox -> Chromium
  └─ Debian Installer live-installer
       └─ штатная разметка, копирование SquashFS, fstab, initramfs и GRUB

Installed system
  └─ systemd graphical.target
       └─ LightDM autologin: kiosk
            └─ Openbox
                 └─ Chromium --kiosk
```

Собственный установщик из версии 1.3 удалён полностью. В сервисном меню нет команды установки.

## Управление

```text
Ctrl+Alt+M      сервисное меню
Ctrl+Alt+T      диагностический xterm
Ctrl+Shift+F12  запасное сочетание для меню
Ctrl+Shift+F11  запасное сочетание для терминала
```

Пароль сервисного меню по умолчанию:

```text
opkiosk
```

## Сеть

Поддерживаются:

- Ethernet и Wi-Fi;
- WPA2/WPA3;
- DHCP и статический IPv4;
- пользовательские DNS и шлюз;
- приоритет Ethernet над Wi-Fi;
- proxy;
- внутренний HTTPS-сертификат по отдельной настройке.

## Сборка

На Debian 13 или в GitHub Actions:

```bash
sudo chmod +x v2/build.sh v2/prepare-config.sh
sudo OPKIOSK_VERSION=2.0.0-alpha1 \
     OPKIOSK_URL=http://op-arkhbum.local:3080 \
     v2/build.sh
```

Результат:

```text
v2/output/OP-Kiosk-OS-2.0.0-alpha1-amd64.iso
```

## Полный автоматический тест

```bash
chmod +x v2/ci/test-full-cycle.sh
v2/ci/test-full-cycle.sh \
  v2/output/OP-Kiosk-OS-2.0.0-alpha1-amd64.iso \
  v2/test-results
```

Тест выполняет:

1. структурную проверку ISO и SquashFS;
2. live-загрузку точного ISO в BIOS;
3. live-загрузку точного ISO в UEFI;
4. установку штатным Debian Installer на пустой диск в BIOS;
5. отключение ISO и три холодные загрузки установленного диска;
6. проверку LightDM, Openbox, Chromium и фактической CI-страницы;
7. проверку `Ctrl+Alt+M`;
8. тот же полный цикл в UEFI.

## Правило публикации

Образ можно назвать готовым только при наличии строки:

```text
OP Kiosk OS full-cycle CI: PASS
```

в `full-cycle-report.txt` для того же SHA-256 ISO, который публикуется пользователю.
