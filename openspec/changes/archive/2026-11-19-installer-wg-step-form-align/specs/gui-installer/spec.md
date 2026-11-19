## Purpose

Мастер установки VLANit PBX OS (HTML GUI primary, Cursive/dialog fallback):
поток экранов настройки, отдельный шаг WireGuard и выравнивание полей
форм без JavaScript.

## ADDED Requirements

### Requirement: Master screen sequence

Мастер MUST вести пользователя по экранам в порядке: оборудование →
диск → сеть → система → WireGuard → подтверждение → прогресс → завершение.
Шаги progress/finish не собирают новые поля конфигурации.

#### Scenario: Forward navigation reaches WireGuard after system

- **WHEN** пользователь успешно завершает экран «Система» и нажимает «Далее»
- **THEN** следующий экран MUST быть «WireGuard»

#### Scenario: Confirm follows WireGuard

- **WHEN** пользователь завершает экран WireGuard
- **THEN** следующий экран MUST быть «Подтверждение» со сводкой, включающей
  состояние WireGuard (вкл/выкл)

### Requirement: WireGuard setup step

На экране WireGuard пользователь MUST явно выбрать, включать ли WireGuard
после установки. При включении MUST задаваться адрес интерфейса wg0 (CIDR)
и listen port; дефолты `10.66.66.1/24` и `51820`. При «не включать»
значения адреса/порта MAY игнорироваться установщиком. Контракт
autoinstall YAML / install-config.json (`wireguard.enabled|address|listen_port`)
MUST остаться совместимым.

#### Scenario: User disables WireGuard

- **WHEN** пользователь выбирает «Не включать» и продолжает
- **THEN** в конфиг пишется `wireguard.enabled` = no (или эквивалент) и
  этап настройки WireGuard на целевой системе не выполняется

#### Scenario: User enables WireGuard with defaults

- **WHEN** пользователь выбирает «Включить после установки», оставляет
  дефолтные адрес/порт и подтверждает установку
- **THEN** после установки WireGuard настроен с этими параметрами и
  автозапуском wg-quick

#### Scenario: Autoinstall unchanged

- **WHEN** установка идёт через `/autoinstall.yaml` с секцией `wireguard`
- **THEN** поведение MUST совпадать с прежним контрактом YAML без новых
  обязательных ключей

### Requirement: System screen without WireGuard

Экран «Система» MUST содержать hostname, локального администратора,
пароль, SSH, часовой пояс и поля MikoPBX. Поля WireGuard MUST NOT
присутствовать на этом экране.

#### Scenario: System form fields

- **WHEN** открыт экран «Система»
- **THEN** форма содержит системные и MikoPBX-поля и не содержит
  управления WireGuard

### Requirement: Form field alignment

HTML-формы мастера MUST выравнивать контролы по одной вертикали слева
от меток: колонка меток фиксированной ширины, поля ввода/select с
ограниченной шириной (не на всю карточку). Выравнивание MUST работать
без JavaScript и без единственной опоры на CSS `table-layout: fixed` /
элемент `<col>` (NetSurf-fb).

#### Scenario: Inputs share left edge

- **WHEN** на экране формы несколько строк метка+контрол
- **THEN** левые края контролов визуально совпадают, а ширина контрола
  не растягивается на всю ширину контейнера мастера

### Requirement: Screen registry

Порядок и состав экранов collect-фазы MUST задаваться декларативным
реестром (`screens.yaml` или эквивалент). Каждый экран имеет id,
заголовок и флаг enabled. Выключенный экран MUST быть пропущен при
навигации «Далее»/«Назад». Добавление нового collect-экрана MUST
сводиться к записи в реестре + обработчику/шаблону без правки
жёсткой нумерации step==N по всему коду.

#### Scenario: Disabled screen skipped

- **WHEN** в реестре экран `wireguard` имеет `enabled: false`
- **THEN** переход с «Система» ведёт на следующий включённый экран
  (обычно подтверждение), минуя WireGuard

#### Scenario: Enabled order preserved

- **WHEN** все стандартные экраны включены
- **THEN** порядок навигации совпадает с порядком записей в реестре

### Requirement: Branding profiles

Визуальный бренд GUI (имя продукта, акцентный цвет, фон, логотип)
MUST загружаться из профиля брендинга. Активный профиль MUST
переключаться переменной окружения или одноимённым ключом без
пересборки логики экранов. Смена профиля MUST менять логотип и
цвета на всех экранах мастера.

#### Scenario: Default branding applied

- **WHEN** GUI стартует с профилем по умолчанию
- **THEN** страница содержит логотип и акцентный цвет профиля

#### Scenario: Alternate branding via env

- **WHEN** задан `VLANIT_BRANDING=<name>` и каталог профиля существует
- **THEN** GUI использует логотип и цвета этого профиля
