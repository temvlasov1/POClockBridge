# Device test: iPhone + AUM + RØDE AI-Micro + Pocket Operator

Заполняйте версию iOS/AUM и результат каждого пункта. При сбое приложите видео,
скрин routing matrix и `xcodebuild.log` из artifact.

## Окружение

- iPhone / iPad:
- iOS / iPadOS:
- AUM:
- Pocket Operator и sync mode:
- RØDE AI-Micro firmware:
- Кабель / breakout:
- Метод подписи: AltStore / Sideloadly / TestFlight:

## 1. Установка и обнаружение

- [ ] IPA переподписан без удаления вложенного extension.
- [ ] Developer Mode включён, containing app запускается.
- [ ] После запуска app и перезапуска AUM виден
      `Audio Unit Extension → POCB: PO Clock Bridge`.
- [ ] Плагин открывается, UI не зависает, показывает SEARCHING.

## 2. Аудио и каналы

- [ ] AI-Micro выбран как audio input/output route.
- [ ] В AUM доступны оба входных канала.
- [ ] Без bypass PO audio проходит без изменения уровня/панорамы.
- [ ] При Clock L плагин видит sync слева; при Clock R — справа.
- [ ] Mono channel не вызывает crash; R безопасно сводится к доступному mono.

## 3. Detector / PLL

- [ ] Default 2 PPQN: SEARCHING → LOCKED ровно после двух импульсов.
- [ ] BPM совпадает с PO при 60/90/120/123/180 BPM в пределах 0,1 BPM после lock.
- [ ] Meter реагирует, Auto threshold ниже пиков и выше noise floor.
- [ ] Ручной threshold может восстановить lock при проблемном уровне.
- [ ] Переключение полярности/фазы кабеля не мешает обнаружению.
- [ ] Резкая смена 100 → 128 стабилизируется без clock burst.

## 4. MIDI

Подключите MIDI monitor к AUv3 output.

- [ ] На lock приходит один `FA` и `F8`.
- [ ] Между четвертями приходит 24 `F8`; нет UI/main-thread timer jitter.
- [ ] Note 60 velocity 100/0 приходит раз в четверть.
- [ ] Остановка PO даёт один `FC`, затем тишина без повторных Stop.
- [ ] Restart даёт новую пару импульсов, один новый `FA`, стабильный Clock.
- [ ] Output Tap/Clock/Both включает только выбранные сообщения.
- [ ] Start/Stop Off оставляет F8/Tap, но убирает FA/FC.

## 5. AUM Tap Tempo

- [ ] AUv3 source направлен в AUM MIDI Control.
- [ ] Note 60 выучен контролом Tap Tempo.
- [ ] AUM tempo следует PO на 60/90/120/123/180 BPM.
- [ ] В течение 10 минут нет слышимого/измеримого накопления phase drift.

## 6. Форматы и lifecycle

- [ ] 44,1 кГц работает.
- [ ] 48 кГц работает.
- [ ] 96 кГц работает, если route/host разрешает.
- [ ] Смена buffer size не вызывает crash или MIDI burst.
- [ ] Disconnect/reconnect AI-Micro безопасно сбрасывает lock.
- [ ] Смена sample rate/route безопасно требует нового lock.
- [ ] AUM project сохраняет Clock Channel, PPQN, Threshold, Smoothing,
      Phase Correction и Output mode.
- [ ] Закрытие/повторное открытие UI не меняет MIDI timing.

## 7. Итог

- [ ] DEVICE TEST PASSED
- [ ] DEVICE TEST FAILED — номер пункта и описание:
