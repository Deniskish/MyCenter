# MyCenter product

Дата фиксации: 2026-08-03

Ветка: `feature/mycenter-production`

Проверенная UI-ревизия: `abda27698449a1273961114ab1a4e95fccd1ebf1` (`style: add green pixel interface`)

## Краткое описание

MyCenter — self-hosted web-система удалённого управления компьютерами. Сервер основан на текущем форке MeshCentral, а конечные устройства используют оригинальный совместимый MeshAgent без функциональных изменений. Отдельное мобильное или desktop-приложение и собственный протокол не входят в scope продукта.

Основной пользовательский интерфейс — браузерная консоль **MyCenter / Remote Systems Console** с тёмной зелёной pixel-style оболочкой. Архитектура, permissions и удалённые каналы остаются MeshCentral-compatible.

## Product scope

MyCenter предназначен для администраторов, которым требуется собственная web-консоль для:

- группировки и просмотра управляемых компьютеров;
- контроля Online/Offline state и сведений об устройстве;
- открытия Device Details;
- штатного удалённого Terminal;
- штатной передачи файлов;
- штатного Remote Desktop;
- просмотра событий и журналов;
- управления пользователями, правами и настройками сервера через web UI.

Доступность конкретной функции всегда определяется существующими permission checks, состоянием агента, платформой устройства и настройками consent. Ребрендинг не расширяет права пользователя и не добавляет скрытые функции.

## Архитектурная граница

Логическая цепочка продукта:

```text
Web browser
    -> MyCenter web UI / MeshCentral server
        -> штатные HTTPS, WebSocket и relay endpoints
            -> оригинальный MeshAgent
                -> управляемая ОС
```

MyCenter меняет отображаемое название, локальные assets, manifest metadata и CSS theme. Он не меняет agent handshake, device identity или remote-control protocol. Подробная карта серверной архитектуры приведена в [`ARCHITECTURE_AUDIT.md`](ARCHITECTURE_AUDIT.md), а границы MeshAgent — в [`MESHAGENT_ARCHITECTURE_AUDIT.md`](MESHAGENT_ARCHITECTURE_AUDIT.md).

## Основные web-разделы

| Раздел | Назначение | Реализация UI |
|---|---|---|
| My Devices | Список и группы устройств, Online/Offline state, основные действия. | [`views/default3.handlebars`](../views/default3.handlebars#L496) |
| My Account | Профиль, безопасность и пользовательские настройки. | [`views/default3.handlebars`](../views/default3.handlebars#L678) |
| My Events | Журнал доступных пользователю событий. | [`views/default3.handlebars`](../views/default3.handlebars#L764) |
| My Users | Управление пользователями при наличии административных прав. | [`views/default3.handlebars`](../views/default3.handlebars#L799) |
| My Server | Настройки и состояние сервера при наличии прав. | [`views/default3.handlebars`](../views/default3.handlebars#L905) |
| Device Details | Информация о выбранном устройстве. | [`views/default3.handlebars`](../views/default3.handlebars#L1682) |
| Desktop | Оболочка удалённого рабочего стола. | [`views/default3.handlebars`](../views/default3.handlebars#L1076) |
| Terminal | Оболочка удалённого терминала. | [`views/default3.handlebars`](../views/default3.handlebars#L1315) |
| Files | Оболочка файлового менеджера. | [`views/default3.handlebars`](../views/default3.handlebars#L1456) |

Pixel-style применяется к navigation, cards, forms, tables, dialogs и toolbars. Он намеренно не меняет rendering удалённого экрана, terminal buffer или пользовательских файлов ([`public/styles/custom.css`](../public/styles/custom.css#L622)).

## Product identity и UI

- Default product title: `MyCenter` ([`webserver.js`](../webserver.js#L10142)).
- Subtitle для целевой конфигурации: `Remote Systems Console`.
- Modern UI выбирается целевой конфигурацией через `siteStyle: 3`; legacy templates остаются в репозитории.
- Палитра, системный моноширинный font stack, focus states и responsive overrides находятся в [`public/styles/custom.css`](../public/styles/custom.css#L1).
- Brand assets поставляются локально в `public/images/mycenter-*`; список и правила описаны в [`MYCENTER_BRANDING.md`](MYCENTER_BRANDING.md).
- PWA manifest использует штатный `pwalogo.png`, сохраняя domain `pwaLogo` override ([`webserver.js`](../webserver.js#L3990), [`webserver.js`](../webserver.js#L4139)).
- MyCenter использует одну локальную theme как осознанную product policy; внешние fonts/CDN не требуются.

## MeshAgent compatibility

В UI агент может отображаться как **MyCenter Agent**, но исполняемый компонент остаётся оригинальным MeshAgent. Не изменяются:

- адрес и semantics `agent.ashx`;
- MeshAgent handshake и WebSocket flow;
- `MeshID`, `ServerID`, `NodeID`;
- встроенная или `.msh` configuration;
- device identity и key material;
- protocol messages и relay behavior;
- механизм штатной установки и обновления агента.

Исходный baseline соединения с оригинальным MeshAgent зафиксирован в [`MESHAGENT_CONNECTION.md`](MESHAGENT_CONNECTION.md). Этот baseline был выполнен до текущего UI-ребрендинга; после подготовки production-конфигурации требуется отдельный end-to-end smoke-check текущего HEAD.

## Security principles

- HTTPS/TLS verification не отключается.
- Authentication, permissions и consent checks не заменяются CSS или branding logic.
- Пароли, cookies, session tokens, private keys, certificate contents, MeshID и ServerID не должны попадать в Git или документацию.
- Внешние CDN, Google Fonts, remote JavaScript и remote images не используются MyCenter theme.
- Security warnings не скрываются визуальным слоем.
- Оригинальный MeshAgent не получает stealth-функций или скрытого управления.
- Self-hosted deployment должен хранить данные, certificates, files и backups в persistent storage; конкретная production-реализация документируется отдельно после её создания и проверки.

Основной CSP для web UI исключает Google font origins и разрешает локальные fonts/styles ([`webserver.js`](../webserver.js#L7221)). Это не отменяет необходимости отдельного security review production-конфигурации.

## Accessibility и mobile web

MyCenter остаётся web-продуктом и должен быть usable в браузере телефона без отдельного приложения. Тема содержит:

- заметный keyboard `:focus-visible`;
- текстовые Online/Offline state в дополнение к цвету;
- responsive wrapping для основных toolbars;
- ограничения ширины login cards и dialogs;
- touch-friendly минимальную высоту кнопок на узких экранах;
- отключение animations при `prefers-reduced-motion`.

Реализация находится в [`custom.css`](../public/styles/custom.css#L110) и responsive блоках ближе к [`custom.css`](../public/styles/custom.css#L687). Ручная проверка на 360, 768, 1280 и 1920 px зафиксирована как PASS в [`MYCENTER_PRODUCTION_SMOKE_TEST.md`](MYCENTER_PRODUCTION_SMOKE_TEST.md); независимая browser automation оставлена как NOT TESTED.

## Attribution и происхождение

MyCenter основан на open-source проектах MeshCentral и MeshAgent. Legal page содержит это указание, ссылки на официальные upstream repositories и пояснение, что совместимый агент является оригинальным MeshAgent ([`views/terms.handlebars`](../views/terms.handlebars#L48)). Notice сохраняется и при использовании собственного `terms.txt` ([`views/terms.handlebars`](../views/terms.handlebars#L181)).

Корневой [`LICENSE`](../LICENSE), copyright и third-party notices должны сопровождать исходный код и применимые дистрибутивы. Branding не предоставляет прав на чужие товарные знаки; MyCenter использует собственный логотип.

## Подтверждённое состояние и ограничения

Подтверждено исходным кодом на указанном HEAD:

- MyCenter default title и пользовательские product labels;
- локальные SVG, PNG и ICO assets;
- тёмная зелёная pixel-style theme;
- CSP без Google Fonts;
- сохранение `pwaLogo` override;
- сохранение Legal attribution при пользовательском `terms.txt`;
- отсутствие изменений оригинального MeshAgent в рамках UI commits.

Не подтверждено этим документом:

- production VPS и его hardening;
- публичный DNS и доверенный TLS certificate;
- Docker image, volumes, автозапуск и firewall;
- production administrator и закрытие регистрации;
- backup/restore и rollback procedures;
- post-branding browser console без ошибок;
- post-branding end-to-end Agent connectivity.

Эти пункты нельзя считать выполненными до отдельных deployment и smoke-test результатов.

## Рекомендуемая следующая проверка

1. Запустить текущий HEAD с отдельным временным data directory на loopback.
2. Проверить login, title, favicon, manifest и Legal с default Terms и тестовым `terms.txt`.
3. Выполнить authenticated UI smoke-check разделов My Devices, My Account, My Server, My Events и My Users.
4. Проверить responsive UI и browser console на целевых ширинах.
5. Убедиться, что Desktop, Terminal и Files открываются без изменения их rendering/permission behavior.
6. Только после локального PASS переходить к документированию production deployment.
