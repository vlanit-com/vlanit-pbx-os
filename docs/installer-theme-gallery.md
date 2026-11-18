# Галерея: тема установщика VLANit PBX OS 1.3.3

Пошаговые скрины TUI-мастера после фикса `dialogrc` (полный набор
ключей темы, без defaults Debian). Спека:
[`docs/specs/1.3.3-installer-theme.md`](specs/1.3.3-installer-theme.md).

**Артефакты:** `build/release-shots/1.3.3/` (не в git — бинарники).
Пересъём: `ISO=… bash scripts/shot-installer-walk.sh`.

Палитра (16-цветная VGA): фон чёрный · текст белый · рамки/заголовки/
теги золото (YELLOW) · выделение чёрный на белом.

---

## 01. Меню GRUB

![GRUB](../build/release-shots/1.3.3/01-grub-menu.png)

## 02. Проверка оборудования (msgbox)

![Экран 1](../build/release-shots/1.3.3/02-hardware.png)

Золотая рамка и заголовок; OK — светлая плашка (не коричневая).

## 03. Выбор диска (menu)

![Выбор диска](../build/release-shots/1.3.3/03-disk-select.png)

Menubox на чёрном (в 1.3.2 был серый внутренний список). Теги «1»/«2» — золото.

## 03b. Подтверждение диска (yesno)

![Подтверждение диска](../build/release-shots/1.3.3/03b-disk-confirm.png)

## 04. Режим дисков (menu)

![Режим дисков](../build/release-shots/1.3.3/04-disk-mode.png)

## 04b. Второй диск зеркала

![Второй диск](../build/release-shots/1.3.3/04b-mirror-disk2.png)

## 05. Подтверждение зеркала (yesno)

![Зеркало](../build/release-shots/1.3.3/05-mirror-confirm.png)

## 06. Сеть (menu)

![Сеть](../build/release-shots/1.3.3/06-network.png)

## 07. Параметры системы (inputbox)

![Hostname / админ](../build/release-shots/1.3.3/07-system-params.png)

## 08. Сводка (yesno)

![Сводка](../build/release-shots/1.3.3/08-summary.png)

## 09–10. Gauge установки

![Gauge early](../build/release-shots/1.3.3/09-gauge-early.png)

![Gauge mid](../build/release-shots/1.3.3/10-gauge-mid.png)

Fill полосы — YELLOW как фон VGA → визуально «коричневый»; рамка/title
золотые. Ограничение палитры, не утечка Debian.

## 12. Поздний gauge (кадр walk; финальный msgbox в этом прогоне не пойман)

![Поздний прогресс](../build/release-shots/1.3.3/12-finish.png)

На кадре — импорт MikoPBX ~85 %. Для кадра «Экран 7. Установка
завершена» нужен дольше walk (зеркало).

---

## Сравнение с 1.3.2 (пиксели, disk-select)

| версия | серый menubox | BROWN (жёлтый фон) |
|---|---|---|
| 1.3.2 | 744 | 31 |
| 1.3.3 | 61 | 0 |
