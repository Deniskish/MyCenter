# MyCenter branding

Дата фиксации: 2026-08-03

Ветка: `feature/mycenter-production`

Проверенная UI-ревизия: `abda27698449a1273961114ab1a4e95fccd1ebf1` (`style: add green pixel interface`)

## Статус документа

Документ описывает branding, реализованный в исходном коде MyCenter на указанной UI-ревизии. Он не подтверждает production-развёртывание, публичный домен, выпуск TLS-сертификата или завершённый production browser smoke-check.

## Идентичность продукта

- Название: **MyCenter**.
- Подзаголовок: **Remote Systems Console**.
- Назначение: self-hosted web-консоль удалённого управления компьютерами на базе MeshCentral и совместимого оригинального MeshAgent.
- Визуальный характер: тёмная пиксельная оболочка, зелёный основной акцент, прямые углы, двухпиксельные границы, жёсткие тени и системный моноширинный шрифт.

Основная палитра определена централизованно в [`public/styles/custom.css`](../public/styles/custom.css#L1):

| Token | Значение | Назначение |
|---|---:|---|
| `--mc-bg` | `#07110A` | Основной фон. |
| `--mc-surface` | `#0D1F12` | Панели и навигация. |
| `--mc-surface-raised` | `#132A19` | Поднятые панели и диалоги. |
| `--mc-primary` | `#39FF6A` | Основной акцент и Online state. |
| `--mc-primary-hover` | `#24D957` | Hover/active state. |
| `--mc-primary-muted` | `#176C32` | Приглушённый зелёный. |
| `--mc-text` | `#E4FFE9` | Основной текст. |
| `--mc-text-muted` | `#91B99A` | Вторичный текст и Offline state. |
| `--mc-border` | `#2A6B3A` | Границы. |
| `--mc-warning` | `#FFCF4A` | Предупреждения. |
| `--mc-danger` | `#FF5C5C` | Ошибки и опасные действия. |
| `--mc-info` | `#61C7FF` | Информационные состояния и keyboard focus. |

Шрифт не загружается из сети. Используется локальный системный стек: `"Lucida Console", "Cascadia Mono", "Courier New", monospace` ([`custom.css`](../public/styles/custom.css#L18)).

## Brand assets

Все MyCenter assets оригинальны для этого форка, находятся локально и имеют уникальный префикс `mycenter-`:

| Файл | Использование |
|---|---|
| [`mycenter-logo.svg`](../public/images/mycenter-logo.svg) | Редактируемый горизонтальный логотип с MC и подзаголовком. |
| [`mycenter-favicon.svg`](../public/images/mycenter-favicon.svg) | Основной векторный favicon и знак в интерфейсе. |
| [`mycenter-favicon.ico`](../public/images/mycenter-favicon.ico) | Fallback для браузеров с ICO support. |
| [`mycenter-favicon-16.png`](../public/images/mycenter-favicon-16.png), [`mycenter-favicon-32.png`](../public/images/mycenter-favicon-32.png) | Малые растровые варианты. |
| [`mycenter-pwa.svg`](../public/images/mycenter-pwa.svg) | Редактируемый исходник PWA icon. |
| [`mycenter-pwa-192.png`](../public/images/mycenter-pwa-192.png) | Apple touch icon и совместимый mobile asset. |
| [`mycenter-pwa-512.png`](../public/images/mycenter-pwa-512.png) | Default PWA icon. |

Основные шаблоны подключают SVG favicon вместе с ICO fallback и PNG Apple icon, например [`views/default3.handlebars`](../views/default3.handlebars#L21) и [`views/login2.handlebars`](../views/login2.handlebars#L13).

## Где применяется branding

- Default title и masthead name формируются как `MyCenter`, если domain `title` не задан; существующий domain override сохранён ([`webserver.js`](../webserver.js#L10142)).
- Modern, legacy, login, download, invitation, sharing, terminal и error templates используют локальные favicon assets.
- Видимые подписи версии, server errors, уведомлений, session player и вариантов агента отображаются как MyCenter/MyCenter Agent.
- PWA manifest содержит имя MyCenter, тёмные цвета и штатную ссылку `pwalogo.png` ([`webserver.js`](../webserver.js#L3990)).
- `pwalogo.png` по-прежнему обслуживается `handlePWALogoRequest()`: domain `pwaLogo` и web-public overrides имеют приоритет над MyCenter fallback ([`webserver.js`](../webserver.js#L4139)).
- Login card, навигация, карточки устройств, таблицы, формы, модальные окна, уведомления, progress bars и remote-session wrappers стилизуются общим [`custom.css`](../public/styles/custom.css).

## Единая локальная тема

MyCenter сознательно предоставляет одну локальную тему. [`theme-switcher.js`](../public/scripts/themes/theme-switcher.js#L1) нормализует выбор к локальному Bootstrap stylesheet, а My Account показывает `Theme: MyCenter` ([`views/default3.handlebars`](../views/default3.handlebars#L750)). Это product policy: внешний вид должен быть детерминированным и не зависеть от Bootswatch font imports или внешних сервисов.

Основной CSP не разрешает Google Fonts: `font-src` ограничен `'self'` и `data:`, `style-src` — `'self'` и необходимыми inline styles ([`webserver.js`](../webserver.js#L7221)). MyCenter не добавляет CDN, remote JavaScript, remote fonts или remote images.

Внутреннее имя JavaScript-объекта `MeshCentralTheme` сохранено намеренно. Это технический upstream identifier, а не пользовательское название продукта.

## Accessibility и responsive rules

Тема возвращает видимый `:focus-visible`, не определяет критические состояния только цветом, снимает минимальную ширину основной страницы на малых экранах и отключает анимации при `prefers-reduced-motion` ([`custom.css`](../public/styles/custom.css#L110), [`custom.css`](../public/styles/custom.css#L687), [`custom.css`](../public/styles/custom.css#L797)).

Pixel styling применяется только к оболочке. Remote Desktop canvas/video, terminal buffer и пользовательское содержимое не получают pixelation, фильтры или текстовые тени ([`custom.css`](../public/styles/custom.css#L622)).

Требуется отдельная browser-проверка на 360, 768, 1280 и 1920 px; наличие CSS rules само по себе не считается подтверждением результата во всех браузерах.

## Compatibility boundaries

Branding не должен менять:

- оригинальный MeshAgent и его бинарники;
- `agent.ashx`, `meshrelay.ashx` и WebSocket routes;
- handshake и бинарный протокол;
- `MeshID`, `ServerID`, `NodeID` и форматы `.msh`;
- protocol actions, database record types и внутренние identifiers;
- authentication, permission checks и consent policy;
- форматы session recordings.

Пользовательская подпись **MyCenter Agent** допустима только как UI label. Фактический совместимый компонент остаётся оригинальным MeshAgent; его технические имена и протокол не переименовываются.

## Attribution и лицензии

Legal page явно сообщает:

> MyCenter is based on the MeshCentral and MeshAgent open-source projects.

Она также содержит ссылки на официальные upstream-репозитории MeshCentral и MeshAgent и поясняет происхождение совместимого агента ([`views/terms.handlebars`](../views/terms.handlebars#L48)). При наличии пользовательского `terms.txt` legal notice добавляется повторно после подстановки его содержимого, поэтому attribution сохраняется ([`views/terms.handlebars`](../views/terms.handlebars#L181)).

Корневой [`LICENSE`](../LICENSE), copyright notices и существующие third-party disclosures не удаляются и не заменяются. MyCenter logo не использует товарные знаки или графику MeshCentral.

## Правила дальнейших изменений

1. Новые assets хранить локально и называть с префиксом `mycenter-`.
2. Визуальные изменения держать преимущественно в `public/styles/custom.css`.
3. Не выполнять массовую замену строки `MeshCentral`: часть вхождений является именем компонента или protocol identifier.
4. Сохранять domain overrides `title`, `title2`, `titlePicture`, `loginPicture` и `pwaLogo`.
5. После обновления upstream повторно проверять title, favicon, manifest, Legal, login, My Devices, Terminal, Files и Desktop.
6. Не заявлять production readiness до отдельного deployment и smoke-check отчёта.
