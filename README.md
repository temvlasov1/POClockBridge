# PO Clock Bridge 0.2

PO Clock Bridge — iOS 16+ приложение-контейнер и AUv3 Music Effect (`aumf`).
Плагин пропускает стерео без изменений, обнаруживает аналоговые sync-импульсы
Pocket Operator в выбранном аудиоканале и выдаёт sample-timestamped MIDI:

- MIDI Clock 24 PPQN (`F8`);
- MIDI Start (`FA`) и один MIDI Stop (`FC`) при dropout;
- MIDI note 60 (C3) раз в четверть для MIDI Learn → Tap Tempo в AUM.

Сигнальный тракт:

`Pocket Operator (2 PPQN) → RØDE AI-Micro → PO Clock Bridge AUv3 → MIDI / AUM Tap Tempo`

## Что проверено

| Уровень | Статус |
|---|---|
| C++17 detector / PLL / scheduler | Проверено локально: 13 групп тестов |
| 60, 90, 120, 123, 180 BPM | Проверено |
| ±0,5 / ±2 мс jitter, пропуск, ложный фронт | Проверено |
| 100 → 128 BPM, dropout/restart, обе полярности | Проверено |
| 44,1 / 48 / 96 кГц, 10 минут без накопления drift | Проверено |
| Device Release build + embedded `.appex` | Выполняет GitHub Actions на macOS |
| Реальный iPhone + AUM + AI-Micro + PO | Требуется device test по чек-листу |

## Получение unsigned IPA без Mac

1. Создайте пустой GitHub-репозиторий и загрузите в него содержимое этой папки.
2. Откройте вкладку **Actions** → **Build unsigned iOS IPA** → **Run workflow**.
3. Дождитесь зелёного результата. Workflow запускает C++-тесты, собирает arm64
   app и AUv3 на `macos-26`, проверяет вложенный
   `POClockBridgeAU.appex` и создаёт IPA.
4. Внизу страницы выполненного run скачайте artifact
   **POClockBridge-unsigned** и распакуйте ZIP artifact.
5. Внутри будут `POClockBridge-unsigned.ipa`, SHA-256 и полный build log.

Unsigned IPA нельзя установить напрямую на обычный iPhone. AltStore Classic или
Sideloadly легально переподписывают **и приложение, и вложенное AUv3** вашим
Apple ID. Проект не обходит Apple code signing.

## Путь A — Windows + бесплатный Apple ID

### Вариант A1: AltStore Classic

1. Установите актуальные web-версии iTunes и iCloud с сайта Apple, а не версии
   Microsoft Store. Затем установите AltServer for Windows с
   [официального сайта AltStore](https://altstore.io/).
2. Подключите iPhone по USB, разблокируйте его, нажмите **Trust / Доверять** и
   оставьте iTunes/iCloud и AltServer доступными.
3. В меню AltServer выберите **Install AltStore** → ваш iPhone и войдите в Apple ID.
4. На iPhone включите **Settings → Privacy & Security → Developer Mode**;
   подтвердите перезагрузку и повторное включение.
5. Передайте `POClockBridge-unsigned.ipa` в Files/iCloud Drive. В AltStore
   Classic откройте **My Apps**, нажмите `+` и выберите IPA.
6. PO Clock Bridge использует два App ID: один для containing app и ещё один для
   AUv3 extension. У бесплатного аккаунта лимит — 10 активных App ID за 7 дней.
7. После установки один раз откройте **PO Clock Bridge**, затем полностью
   перезапустите AUM, если AUv3 ещё не появился.

Бесплатная подпись действует 7 дней. AltStore пытается обновлять её, когда iPhone
видит AltServer; можно вручную нажать **Refresh All**. Это ограничение Apple,
легального постоянного unsigned-варианта для stock iOS нет.

### Вариант A2: Sideloadly

1. Установите web-версии iTunes/iCloud и Sideloadly только с
   [официального сайта](https://sideloadly.io/).
2. Подключите и разблокируйте iPhone, подтвердите **Trust**, перетащите IPA в
   Sideloadly, выберите устройство и нажмите **Start**.
3. После установки включите Developer Mode. Если iOS показывает
   **Untrusted Developer**, откройте **Settings → General → VPN & Device
   Management**, выберите ваш Apple ID и нажмите **Trust**.
4. У бесплатного Apple ID приложение также истекает через 7 дней. Включите
   automatic refresh или переподписывайте тем же Apple ID и bundle ID.

## Путь B — Apple Developer Program / TestFlight

1. Зарегистрируйте App ID `com.poclockbridge.app` и extension App ID
   `com.poclockbridge.app.au` в вашей developer team.
2. Настройте App Store Connect app, distribution certificate и API key.
3. Переименуйте
   `.github/workflows/testflight-template.yml.disabled` в `testflight.yml`.
4. Добавьте GitHub Environment `app-store` и Secrets:
   `APPLE_TEAM_ID`, `DISTRIBUTION_P12_BASE64`,
   `DISTRIBUTION_P12_PASSWORD`, `TEMP_KEYCHAIN_PASSWORD`, `ASC_KEY_ID`,
   `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_BASE64`.
5. Запустите workflow вручную. Не коммитьте сертификаты, `.p8`, пароли или
   provisioning profiles.

Сборка TestFlight доступна тестерам до 90 дней; затем нужно загрузить новую.

## Настройка Pocket Operator и AI-Micro

1. Включите PO sync mode, где sync и audio разделены по L/R. Для PO-33 обычно
   используется режим, соответствующий вашей цепочке устройств; проверьте схему
   sync mode в руководстве конкретного Pocket Operator.
2. Используйте корректный stereo breakout: оба канала TRS выхода PO должны
   попасть на два входных канала AI-Micro. Обычный моно-кабель потеряет канал.
3. В AUM создайте stereo hardware input для AI-Micro. Если AUM видит два mono
   input, объедините/маршрутизируйте их в стереоканал перед плагином.

## Настройка внутри AUM

1. На stereo input channel нажмите `+` в effect slot и выберите
   **Audio Unit Extension → POCB: PO Clock Bridge**.
2. Откройте UI плагина. По умолчанию: `Clock channel L`, `Input PPQN 2`,
   `Auto threshold On`, `Output Both`.
3. Запустите Pocket Operator. После **двух** валидных импульсов появятся
   `LOCKED` и BPM. Это исключает неверный стартовый burst.
4. Откройте MIDI routing matrix AUM. Источником выберите MIDI output экземпляра
   PO Clock Bridge.
5. Для AUM направьте его в **MIDI Control**, включите MIDI Learn для Tap Tempo и
   дайте пройти note 60/C3. Для другого clock-capable приложения направьте туда
   `F8/FA/FC` напрямую.
6. При остановке PO через три ожидаемых input-интервала плагин выдаст ровно один
   `FC`, снимет LOCK и будет ждать новую пару импульсов.

Важно: host обязан поддерживать MIDI output от AUv3 effect. Если конкретный host
не показывает MIDI source плагина, используйте AUM/Loopy Pro с соответствующей
поддержкой или standalone MIDI bridge в будущей версии.

## Параметры

- **Clock channel** — L/R; аудио обоих каналов остаётся неизменным.
- **Input PPQN** — Auto/1/2/4/12/24/48. Для Pocket Operator оставьте 2.
- **Auto threshold** — адаптивный порог над измеренным noise floor.
- **Threshold** — ручной Schmitt threshold, когда Auto выключен.
- **Smoothing** — компромисс между стабильностью и скоростью реакции на tempo.
- **Phase correction** — сила подтягивания MIDI grid к аналоговым фронтам.
- **Output** — Tap, Clock или Both.
- **Start / Stop** — включает transport bytes `FA/FC`.
- **Phase Reset** — сбрасывает lock и требует два новых импульса.

Параметры находятся в `AUParameterTree` и включены в `fullState`, поэтому host
может сохранить их вместе с AUM session/preset.

## Локальная сборка на Mac

Нужны Xcode, CMake и XcodeGen:

```bash
brew install cmake xcodegen
chmod +x build.sh
./build.sh
```

Результаты находятся в `.build/artifacts/`. Скрипт выполняет тот же test/build/
inspect/package pipeline, что и GitHub Actions.

Core-only тесты работают на macOS, Linux и Windows:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
```

## Ableton Link

Link не заявлен как работающая функция в 0.2. AUv3 живёт в процессе host (AUM),
а containing app обычно не запущено; Apple не предоставляет прямой realtime
канал между ними. App Group даёт shared data/IPC, но не гарантирует, что
containing app останется активным и будет непрерывно обслуживать Link timeline.
Кроме того, LinkKit требует Local Network consent и одобренный multicast
entitlement. Поэтому приложение не имитирует Link и не пытается менять tempo
host. Рабочие выходы версии 0.2 — MIDI Clock и Tap Tempo.

Подробнее: [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md),
[ARCHITECTURE.md](ARCHITECTURE.md) и
[DEVICE_TEST_CHECKLIST_RU.md](DEVICE_TEST_CHECKLIST_RU.md).
