# Первичный технический аудит архитектуры MeshCentral

## Область и фиксация аудита

Этот отчёт фиксирует первый, репозиторный этап аудита, выполненный до последующих baseline- и UI-проверок: на данном этапе сервер не запускался, конфигурация и существующий код не изменялись. Анализ относится к ветке `master`, commit `bd48e8a9d36d86cf860fb2a32617ac6e398274e8`, версия пакета `1.2.4` ([`package.json`](../package.json#L3)). В репозитории присутствуют `.git`, `README.md`, `package.json`, `meshcentral.js` и исходные файлы проекта.

MeshCentral — монолитное Node.js-приложение с событийной архитектурой. Главный модуль загружает конфигурацию и зависимости, открывает БД, создаёт сертификаты и подсистемы, после чего запускает Express/HTTPS/WebSocket-сервер. Браузерная сессия общается с сервером через `control.ashx`, MeshAgent — через `agent.ashx`, а интерактивные потоки desktop/terminal/files соединяются через relay WebSocket. Это подтверждается фабриками [`CreateMeshCentralServer`](../meshcentral.js#L23), [`CreateWebServer`](../webserver.js#L34), [`CreateMeshUser`](../meshuser.js#L23), [`CreateMeshAgent`](../meshagent.js#L18) и [`CreateMeshRelay`](../meshrelay.js#L82).

## Установка и локальный запуск

Требование пакета — Node.js `>=20.0.0` ([`package.json`, `engines`](../package.json#L60)). Для воспроизводимой установки из текущего checkout следует использовать lock-файл:

```powershell
cd C:\projects\MyCenter
node --version
npm ci
node .\meshcentral.js
```

Эквивалентный запуск через объявленный CLI:

```powershell
cd C:\projects\MyCenter
npm ci
node .\bin\meshcentral
```

`bin/meshcentral` только загружает `meshcentral.js` ([`bin/meshcentral`](../bin/meshcentral#L2)), а поле `main` также указывает на него ([`package.json`](../package.json#L19)). В `package.json` нет секции `scripts`, поэтому `npm start` и `npm test` как контракт проекта не определены. `npm install` допустим для обычной разработки, но `npm ci` точнее воспроизводит `package-lock.json`.

При запуске из checkout каталог данных по умолчанию находится рядом с репозиторием: `C:\projects\meshcentral-data`; рядом создаются `meshcentral-files`, `meshcentral-backups` и `meshcentral-recordings` ([`meshcentral.js`](../meshcentral.js#L98-L109)). Настройки `settings.datapath` и `settings.filespath` могут переопределить первые два пути ([`meshcentral.js`](../meshcentral.js#L119-L125)).

Основная конфигурация — `<datapath>\config.json`. Путь выбирается в `mainStart`, а `--configfile` позволяет задать другое имя внутри data path ([`meshcentral.js`](../meshcentral.js#L4149-L4159)). При первом старте код копирует `sample-config.json` как отправную точку ([`meshcentral.js`](../meshcentral.js#L4158-L4168)); полная схема находится в [`meshcentral-config-schema.json`](../meshcentral-config-schema.json), расширенный пример — в [`sample-config-advanced.json`](../sample-config-advanced.json). Функция `getConfigFilePath` также допускает адресные переопределения через `config.configfiles` ([`meshcentral.js`](../meshcentral.js#L4091-L4099)). Существуют специальные режимы загрузки конфигурационных файлов из БД или Vault, но это не базовый локальный путь ([`meshcentral.js`](../meshcentral.js#L813-L900), [`meshcentral.js`](../meshcentral.js#L1415-L1450)).

Первый запуск создаёт самоподписанные сертификаты и обычно слушает HTTPS; фактический адрес/порт следует брать из строки `MeshCentral HTTPS server running...`, которую выводит обработчик запуска HTTPS ([`webserver.js`](../webserver.js#L9302-L9308)). Для разработки без привилегированного порта безопасно заранее создать `C:\projects\meshcentral-data\config.json` на основе sample и установить, например, `"Port": 8443` в `settings`; сам аудит файл конфигурации не создаёт.

## Последовательность запуска

1. Node загружает `meshcentral.js`; `mainStart` разбирает аргументы, вычисляет data path и читает `config.json` ([`meshcentral.js`](../meshcentral.js#L4137-L4168)).
2. Проверяется версия Node и рассчитывается перечень базовых и условных модулей БД/интеграций ([`meshcentral.js`](../meshcentral.js#L4377-L4411)).
3. После наличия модулей создаётся `CreateMeshCentralServer(config, args)` и вызывается `Start()` ([`meshcentral.js`](../meshcentral.js#L4476-L4477)).
4. `Start()` обрабатывает служебные команды и передаёт обычный запуск в `StartEx()` ([`meshcentral.js`](../meshcentral.js#L137-L170), [`meshcentral.js`](../meshcentral.js#L599-L600)).
5. `StartEx()` нормализует настройки и вызывает `CreateDB`; затем `SetupDatabase` подготавливает хранилище ([`meshcentral.js`](../meshcentral.js#L951-L1005)).
6. После загрузки состояния создаются серверные подсистемы, включая web server через `CreateWebServer` ([`meshcentral.js`](../meshcentral.js#L1964)).
7. `CreateWebServer` регистрирует HTTP/WS endpoints. Браузер подключается к `control.ashx`, relay — к `meshrelay.ashx`, агент — к `agent.ashx` ([`webserver.js`](../webserver.js#L7398-L7450), [`webserver.js`](../webserver.js#L7861-L7866)).
8. HTTPS listener сообщает итоговый адрес и порт в консоль ([`webserver.js`](../webserver.js#L9302-L9308)).

## Основные каталоги и файлы

| Путь | Назначение и опорные точки |
|---|---|
| [`meshcentral.js`](../meshcentral.js) | Точка входа, пути данных, конфигурация, зависимости, жизненный цикл и сборка подсистем: `CreateMeshCentralServer`, `Start`, `StartEx`, `mainStart`. |
| [`webserver.js`](../webserver.js) | Express/HTTPS/WS, login/session/SSO, HTML routes, выдача агента и `.msh`, endpoints `control.ashx`, `meshrelay.ashx`, `agent.ashx`; фабрика `CreateWebServer`. |
| [`meshuser.js`](../meshuser.js) | Серверная логика авторизованной браузерной WebSocket-сессии и команды UI; `CreateMeshUser`. |
| [`meshagent.js`](../meshagent.js) | Аутентификация, регистрация, состояние и сообщения MeshAgent; `CreateMeshAgent`, `completeAgentConnection*`, `processAgentData`. |
| [`meshrelay.js`](../meshrelay.js) | Парное соединение browser↔agent и транспорт интерактивных протоколов; `CreateMeshRelay`, `CreateMeshRelayEx`. |
| [`meshdesktopmultiplex.js`](../meshdesktopmultiplex.js) | Опциональный desktop multiplexor 1→N, подключаемый для desktop relay ([`webserver.js`](../webserver.js#L7440-L7446)). |
| [`db.js`](../db.js) | Единый адаптер данных, события, power/statistics и реализации поддерживаемых БД; `CreateDB`, `SetupDatabase`. |
| [`pass.js`](../pass.js) | Хеширование и проверка локальных паролей; используется обычной аутентификацией ([`webserver.js`](../webserver.js#L798-L817)). |
| [`certoperations.js`](../certoperations.js) | Сертификаты, подписи и криптографическая идентичность сервера/агента; используется handshake в `meshagent.js`. |
| [`views/`](../views/) | Handlebars-страницы: `login*.handlebars`, `default*.handlebars`, `xterm.handlebars`, sharing/download/messenger и мобильные варианты. |
| [`public/`](../public/) | Статические browser assets: scripts, styles, themes, images/icons и отдельные HTML-инструменты. |
| [`emails/`](../emails/) | HTML/text шаблоны email и SMS. |
| [`translate/`](../translate/) | Исходная локализация `translate.json` и генератор `translate.js`; локализованные UI-файлы также лежат в `public`. |
| [`agents/`](../agents/) | Поставляемые бинарники MeshAgent, meshcore-модули, installer scripts, recovery/diagnostic core и `testsuite.js`. Это не исходный C++ MeshAgent. |
| [`amt/`](../amt/) | Intel AMT/WS-Man/redirect реализация. |
| [`rdp/`](../rdp/) | Встроенная JS-реализация RDP для соответствующих relay-сценариев. |
| [`docker/`](../docker/) | Dockerfiles, compose, entrypoint и документация вариантов образа/БД. |
| [`sample-config.json`](../sample-config.json), [`sample-config-advanced.json`](../sample-config-advanced.json), [`meshcentral-config-schema.json`](../meshcentral-config-schema.json) | Минимальный пример, расширенный справочник и JSON Schema конфигурации. |

Пути `views`, `public`, `emails` задаются централизованно; без изменения core можно использовать sibling-каталог `meshcentral-web/{views,public,emails}` как override ([`meshcentral.js`](../meshcentral.js#L92-L109)). Это предпочтительная точка минимального визуального ребрендинга.

## Реализация пользовательских функций

### Авторизация

Локальная аутентификация и выбор LDAP/других стратегий находятся в `webserver.js`: обычная ветка начинается в блоке `Regular login` ([`webserver.js`](../webserver.js#L798-L817)), HTTP login orchestration — `handleLoginRequest` ([`webserver.js`](../webserver.js#L1228-L1449)), завершение и создание сессии/события — `completeLoginRequest` ([`webserver.js`](../webserver.js#L1494-L1556)). Проверка пароля делегируется [`pass.js`](../pass.js). Браузерная авторизованная WS-сессия создаётся на `control.ashx` через `CreateMeshUser` ([`webserver.js`](../webserver.js#L7398-L7421)).

### Список компьютеров и регистрация устройств

UI отправляет команду `nodes`; обработчик `CreateMeshUser` запрашивает доступные узлы, фильтрует их по правам и возвращает `action: "nodes"` ([`meshuser.js`](../meshuser.js#L719-L867)). При первом валидном подключении агента `completeAgentConnection` ищет node по криптографическому node id ([`meshagent.js`](../meshagent.js#L743-L766)); `completeAgentConnection2` создаёт запись `type: "node"` и событие `addnode` ([`meshagent.js`](../meshagent.js#L843-L883)).

### Удалённый рабочий стол, терминал и файлы

Эти функции не являются отдельными REST endpoints. Browser control-channel проверяет права и направляет tunnel-команду агенту; подготовка relay-команды, view-only и consent/notification options находится в `meshuser.js` ([`meshuser.js`](../meshuser.js#L276-L363), [`meshuser.js`](../meshuser.js#L1031-L1076)). Реальный двунаправленный поток соединяет стороны в `CreateMeshRelayEx` ([`meshrelay.js`](../meshrelay.js#L161)); WebSocket endpoint регистрируется как `meshrelay.ashx` ([`webserver.js`](../webserver.js#L7440-L7446)). Номера MeshCentral relay-протоколов: `1` terminal, `2` desktop, `4` files, что явно зафиксировано в проверке guest sharing ([`meshuser.js`](../meshuser.js#L4482-L4482)). Для SSH/RDP/VNC есть отдельные relay endpoints и протокольные адаптеры ([`webserver.js`](../webserver.js#L7497-L7522), [`meshrelay.js`](../meshrelay.js#L1292-L1298)).

Клиентская реализация собрана преимущественно в крупных Handlebars-шаблонах [`views/default.handlebars`](../views/default.handlebars) и [`views/default-mobile.handlebars`](../views/default-mobile.handlebars), с terminal-страницей [`views/xterm.handlebars`](../views/xterm.handlebars) и библиотеками в [`public/scripts/`](../public/scripts/). Поэтому изменение DOM/id/JS-контрактов в этих шаблонах существенно рискованнее замены CSS и изображений.

### Журнал событий

События создаются централизованными вызовами `DispatchEvent` (например, login в [`webserver.js`](../webserver.js#L1513-L1527), addnode в [`meshagent.js`](../meshagent.js#L870-L880), relay start/end в [`meshrelay.js`](../meshrelay.js#L1292-L1300)). Команда браузера `events` выполняет проверку прав и выбирает пользовательские, device или общие события ([`meshuser.js`](../meshuser.js#L1092-L1181)). Адаптеры хранения событий и операции выборки/удаления реализованы в [`db.js`](../db.js#L3033-L3164); для NeDB используется отдельный `meshcentral-events.db` ([`db.js`](../db.js#L4120-L4123)).

## Путь регистрации и подключения MeshAgent

```text
Пользователь создаёт device group
  → сервер формирует .msh/встраивает policy
  → MeshServer=wss://host[:port]/[domain/]agent.ashx
  → HTTPS upgrade / agent.ashx
  → CreateMeshAgent
  → взаимная проверка TLS hash, nonce, сертификатов и RSA-SHA384 подписей
  → agent сообщает MeshID, platform, version, capabilities, computerName
  → node id выводится из SHA-384 fingerprint публичного ключа сертификата агента
  → completeAgentConnection
  → существующий node обновляется либо создаётся type:"node"
  → authenticated=2; агент помещается в wsagents
  → control.ashx сообщает UI состояние/событие устройства
```

При выдаче агента сервер формирует policy с `MeshID`, `ServerID` и `MeshServer=wss://.../agent.ashx` ([`webserver.js`](../webserver.js#L6230-L6232), [`webserver.js`](../webserver.js#L6670-L6675)); отдельный `.msh` строится аналогично ([`webserver.js`](../webserver.js#L6757-L6825)). Endpoint вызывает `CreateMeshAgent` ([`webserver.js`](../webserver.js#L7861-L7866)).

Handshake разбирает бинарные команды до аутентификации: проверяет SHA-384 hash web-сертификата, отвечает сертификатом и подписью server agent certificate, проверяет сертификат/подпись агента и принимает agent info/MeshID ([`meshagent.js`](../meshagent.js#L433-L560)). Node id вычисляется как SHA-384 fingerprint публичного ключа сертификата агента ([`meshagent.js`](../meshagent.js#L510-L529)); подпись проверяется `RSA-SHA384`/`SHA384` в `processAgentSignature` ([`meshagent.js`](../meshagent.js#L1135-L1177)). Только после выполнения этих условий `completeAgentConnection` регистрирует или обновляет устройство ([`meshagent.js`](../meshagent.js#L670-L883)).

Следовательно, совместимость MeshAgent зависит не от отображаемого бренда, а от неизменности endpoint/path semantics, `.msh` keys/encoding, бинарных command IDs/layout, MeshID/ServerID/node-id derivation, сертификатов, подписей, relay protocol IDs и agent update metadata.

## Поддерживаемые базы данных

Канонический список адаптера: NeDB, MongoJS, MongoDB, MariaDB, MySQL, PostgreSQL, AceBase и SQLite ([`db.js`](../db.js#L38)). Выбор реализаций находится в `CreateDB`: SQLite ([`db.js`](../db.js#L783-L851)), AceBase ([`db.js`](../db.js#L852-L875)), MariaDB/MySQL ([`db.js`](../db.js#L876-L935)), PostgreSQL ([`db.js`](../db.js#L936-L998)), MongoDB ([`db.js`](../db.js#L999-L1181)), legacy MongoJS ([`db.js`](../db.js#L1182-L1286)) и default NeDB ([`db.js`](../db.js#L1287-L1359)).

NeDB — база по умолчанию и единственный её модуль входит в обязательные зависимости. Драйверы остальных БД условно добавляются согласно конфигурации (`mysql2`, `mongodb`, `pg`, `mariadb`, `acebase`, `sqlite3`, legacy `mongojs`) ([`meshcentral.js`](../meshcentral.js#L4390-L4411)). Docker-проект публикует варианты для local-only, MongoDB, PostgreSQL и MySQL/MariaDB ([`docker/README.md`](../docker/README.md#L18-L28)). MongoJS следует считать legacy: настройка называется `xmongodb`, а код прямо помечает драйвер как old ([`meshcentral.js`](../meshcentral.js#L4410-L4411)).

## UI, стили, изображения и локализация

- Handlebars-шаблоны: [`views/`](../views/), включая login/default/mobile/sharing/download/terminal.
- CSS и темы: [`public/styles/`](../public/styles/), включая xterm и Bootstrap themes.
- Browser JavaScript: [`public/scripts/`](../public/scripts/).
- Изображения, favicon/PWA assets и статические HTML: [`public/`](../public/).
- Переводы: [`translate/translate.json`](../translate/translate.json), генератор [`translate/translate.js`](../translate/translate.js), а также сгенерированные локализованные страницы в `public`.
- Email/SMS: [`emails/`](../emails/).
- Поддерживаемые override-каталоги: `meshcentral-web/views`, `meshcentral-web/public`, `meshcentral-web/emails` рядом с data path ([`meshcentral.js`](../meshcentral.js#L95-L109)).

## Тесты и инструменты проверки

Полноценного npm test pipeline в текущем `package.json` нет: секция `scripts` отсутствует ([`package.json`](../package.json)). Найден агентский сценарий [`agents/testsuite.js`](../agents/testsuite.js), но он предназначен для среды MeshAgent, а не является unit/integration suite Node-сервера. Имеются:

- JSON Schema конфигурации [`meshcentral-config-schema.json`](../meshcentral-config-schema.json);
- CI CodeQL workflow [`.github/workflows/codeql-analysis.yml`](../.github/workflows/codeql-analysis.yml);
- workflows сборки Docker [`.github/workflows/docker-alpine.yml`](../.github/workflows/docker-alpine.yml) и [`.github/workflows/docker-debian.yml`](../.github/workflows/docker-debian.yml);
- release automation [`.github/workflows/release.yml`](../.github/workflows/release.yml);
- переводчик/проверка локализуемых ресурсов [`translate/translate.js`](../translate/translate.js);
- runtime CLI-диагностика и DB inspection (`--showusers`, `--shownodes`, `--showevents`, `--dbstats`) в [`meshcentral.js`](../meshcentral.js#L1008-L1024).

Вывод: перед развитием собственного API нужна отдельная regression/smoke matrix, но добавлять её в рамках этого этапа запрещено и не выполнялось.

## Безопасный минимальный ребрендинг

Первый ребрендинг следует делать конфигурационно и через поддержанные web override paths:

1. Зафиксировать smoke-сценарии login → devices → desktop → terminal → files → events и подключение неизменённого MeshAgent.
2. Использовать поддержанные domain branding/`agentcustomization` параметры из [`meshcentral-config-schema.json`](../meshcentral-config-schema.json), не переименовывая protocol fields. Код уже применяет `agentcustomization.filename`, `servicename` и `companyname` при выдаче артефактов ([`webserver.js`](../webserver.js#L6144-L6147), [`webserver.js`](../webserver.js#L6701-L6724)).
3. Размещать заменяемые CSS, изображения и при необходимости копии templates в sibling `meshcentral-web`, поскольку этот override предусмотрен startup-кодом ([`meshcentral.js`](../meshcentral.js#L95-L109)).
4. Сначала менять только текст, цвета, логотипы/favicon и email templates. Сохранять DOM IDs, имена JS-функций, action names и структуру форм.
5. Не заменять существующие сертификаты на работающей инсталляции без отдельного плана миграции: `ServerID`, web certificate hashes и agent certificate участвуют в доверии агента.

Необходимо сохранить Apache-2.0 [`LICENSE`](../LICENSE), сведения об авторе в [`package.json`](../package.json#L17-L25), attribution и сторонние лицензии (например [`rdp/LICENSE`](../rdp/LICENSE)).

## Что нельзя менять на первом этапе

- `agent.ashx`, `meshrelay.ashx`, `control.ashx` и правила domain URL: они являются сетевым контрактом ([`webserver.js`](../webserver.js#L7398-L7450), [`webserver.js`](../webserver.js#L7861-L7905)).
- Бинарный handshake, command IDs и layouts в `meshagent.js`, включая команды 1–5 ([`meshagent.js`](../meshagent.js#L433-L568)).
- Формирование/парсинг `.msh`: ключи `MeshID`, `ServerID`, `MeshServer`, их кодировка и path ([`webserver.js`](../webserver.js#L6230-L6232), [`webserver.js`](../webserver.js#L6785-L6825)).
- Вывод node id, SHA-384/RSA подписи, agent/server certificates и сохранённые production keys ([`meshagent.js`](../meshagent.js#L510-L529), [`meshagent.js`](../meshagent.js#L1135-L1177)).
- Идентификаторы БД (`user/<domain>/<id>`, `mesh/<domain>/<id>`, `node/<domain>/<id>`), типы документов и event/action names, используемые UI и dispatch.
- Relay protocol IDs и tunnel semantics (`1` terminal, `2` desktop, `4` files).
- Agent update binaries/hashes, содержимое `agents/` и core update flow до появления отдельной стратегии агента.
- Права/bit masks, session cookies, CSRF/origin/IP checks и login/2FA/SSO flow.
- Имена DOM элементов и тесно связанный inline JavaScript больших `default*.handlebars`.
- LICENSE, attribution, copyright notices и лицензии третьих сторон.

## Точки расширения для REST API и SwiftUI

Существующий `control.ashx` — не REST API, а stateful WebSocket command bus. Наиболее безопасная стратегия — добавить отдельный, версионированный слой `/api/v1`, который вызывает существующие сервисные функции и DB abstraction, но не меняет команды `CreateMeshUser`.

Подходящие seams:

- аутентификация: повторно использовать установленную session/login policy и password/2FA/SSO правила из `webserver.js`, не создавать параллельную проверку пароля;
- авторизация объектов: вынести/переиспользовать `GetNodeWithRights`, `GetNodesWithRights`, `GetMeshRights` из [`webserver.js`](../webserver.js), поскольку `meshuser.js` уже основывает выдачу nodes и tunnels на них;
- read models: строить devices/events через API адаптера [`db.js`](../db.js), а не обращаться к конкретной БД;
- realtime: оставить отдельный versioned WebSocket/SSE stream поверх `DispatchEvent`/subscription-механизма; SwiftUI сможет получать snapshot REST и incremental events;
- remote sessions: API должен только выдавать короткоживущий авторизованный relay descriptor/cookie, после чего SwiftUI подключается к совместимому relay. Не проксировать desktop frames через обычный JSON REST;
- DTO: не отдавать внутренние DB documents напрямую; стабилизировать отдельные versioned DTO для device, group, event, session и capabilities.

Для SwiftUI минимальный вертикальный срез: login/token lifecycle → список groups/devices → device details/events → terminal → files → desktop. Desktop потребует отдельной реализации бинарного relay/desktop protocol либо промежуточного gateway; сам текущий web UI нельзя считать документированным мобильным API.

## Технические риски форка

| Риск | Почему существенен | Снижение риска |
|---|---|---|
| Расхождение с upstream | Монолитные крупные файлы и inline UI дают тяжёлые merge conflicts. | Минимальные патчи, overrides, регулярный upstream merge, журнал отклонений. |
| Поломка MeshAgent trust | Сертификаты, ServerID, SHA-384 и бинарный handshake связаны. | Заморозить protocol code; проверять released agents разных ОС на каждом релизе. |
| Нестабильный внутренний API | `control.ashx` — command bus, а DB docs не являются публичными DTO. | Версионированный facade и contract tests. |
| Ошибки прав доступа | Права проверяются во многих ветках user/relay logic. | Переиспользовать `Get*Rights`; negative authorization tests для каждого endpoint. |
| Потеря realtime-семантики | UI зависит от snapshot `nodes` плюс `DispatchEvent`. | API проектировать как snapshot + ordered incremental stream. |
| Различия БД | Один abstraction содержит различные транзакционные/индексные реализации. | CI matrix минимум NeDB + выбранная production БД; миграции отдельно. |
| Недостаток тестов | Нет npm unit/integration test contract. | До функций продукта создать smoke/contract harness без переписывания core. |
| UI fork cost | Handlebars содержит тесно связанный DOM и JavaScript. | На первом этапе CSS/assets/config overrides; не менять DOM contract. |
| Лицензии и attribution | Форк обязан сохранять Apache-2.0 и сторонние лицензии. | Автоматическая проверка LICENSE/NOTICE/third-party attribution в release process. |
| Собственный C++ агент | Это отдельный protocol/security/update проект, не обычный ребрендинг. | Отложить до стабилизации API; специфицировать handshake/relay и conformance tests. |

## Рекомендуемый порядок разработки

1. Зафиксировать upstream remote/tag, release policy и процесс регулярной синхронизации форка.
2. Создать воспроизводимое dev/staging окружение на Node.js 20+ с отдельным data path и выбранной production БД.
3. Снять black-box baseline: login, 2FA, создание group, подключение released MeshAgent, nodes/events, desktop/terminal/files, reconnect/update.
4. Описать protocol/API boundaries и добавить contract/smoke tests, не меняя реализацию.
5. Выполнить минимальный config/override-based ребрендинг с неизменным агентом и повторить baseline.
6. Спроектировать `/api/v1`: auth model, DTO, errors, pagination, rights и realtime stream.
7. Реализовать read-only вертикальный срез для SwiftUI: login → devices → device/events.
8. Добавлять mutation endpoints и relay session issuance по одному сценарию с negative authorization tests.
9. Создать SwiftUI-клиент: сначала inventory/events, затем terminal/files, последним desktop.
10. Только после стабилизации серверного API и protocol conformance оценивать собственный C++ агент.

Следующий этап не должен начинаться автоматически: рекомендуемое отдельное решение — утвердить baseline test matrix и границы `/api/v1`, прежде чем выполнять ребрендинг или менять серверный код.
