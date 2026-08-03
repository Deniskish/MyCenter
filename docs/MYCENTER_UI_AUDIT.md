# MyCenter UI audit

Дата аудита: 2026-08-03

Ветка: `feature/mycenter-production`

Исходный commit до UI-изменений: `a7d4c2ade15c5d028eaf41b1c225c496fd8282e9`

Проверенная UI-ревизия: `abda27698449a1273961114ab1a4e95fccd1ebf1` (`style: add green pixel interface`)

## Цель и границы

Этот аудит фиксирует реальные точки UI MeshCentral и фактическую реализацию ребрендинга MyCenter на указанной UI-ревизии. Изменения остаются в web-слое: MeshAgent, `agent.ashx`, `meshrelay.ashx`, handshake, идентификаторы `MeshID`/`ServerID`/`NodeID`, форматы сообщений, проверки прав и database record types не переименовывались.

Целевая production-конфигурация должна фиксировать modern UI через `siteStyle: 3`. Это требование конфигурации, а не утверждение о уже выполненном production-развёртывании. Legacy UI остаётся совместимым и получает общую тему через штатный custom CSS, но крупные монолитные шаблоны не дублируются и не переписываются без необходимости.

## Формирование страниц

`webserver.js` выбирает modern/legacy шаблоны и формирует render arguments, включая `title`, `title2`, `titlehtml`, custom CSS и custom JavaScript ([`webserver.js`](../webserver.js#L3302), [`webserver.js`](../webserver.js#L9970), [`webserver.js`](../webserver.js#L10137)). Настройки `siteStyle`, `title`, `title2`, `titlePicture`, `loginPicture` и `pwaLogo` описаны в схеме конфигурации ([`meshcentral-config-schema.json`](../meshcentral-config-schema.json#L1223)).

Logout не имеет отдельного шаблона: обработчик завершает сессию и возвращает пользователя на login page ([`webserver.js`](../webserver.js#L926)). Поэтому login branding одновременно покрывает экран после logout.

## Карта UI-файлов

| Область | Основные файлы и точки | План изменения |
|---|---|---|
| Modern shell | [`views/default3.handlebars`](../views/default3.handlebars#L243) | Сохранить DOM ID, handlers и permission checks; использовать конфигурацию и custom CSS. |
| Modern login | [`views/login2.handlebars`](../views/login2.handlebars#L19) | Название через `title`/`title2`; локальный favicon и тема. |
| Legacy shell | [`views/default.handlebars`](../views/default.handlebars#L56) | Только общий CSS, favicon и точечные product strings. |
| Mobile legacy | [`views/default-mobile.handlebars`](../views/default-mobile.handlebars#L11), [`views/login-mobile.handlebars`](../views/login-mobile.handlebars#L11) | Общий CSS, локальный favicon, responsive smoke-check. |
| Browser title | [`views/default3.handlebars`](../views/default3.handlebars#L66), [`views/login2.handlebars`](../views/login2.handlebars#L19) | Значение `MyCenter` приходит из domain configuration. |
| Header and primary navigation | [`views/default3.handlebars`](../views/default3.handlebars#L243) | CSS-only styling; не менять `go(...)` и menu handlers. |
| My Devices | [`views/default3.handlebars`](../views/default3.handlebars#L496), `updateDeviceViewHtml()` ([`views/default3.handlebars`](../views/default3.handlebars#L5907)) | Стилизовать существующую карточку и статусы без изменения генератора данных. |
| My Account | [`views/default3.handlebars`](../views/default3.handlebars#L678) | CSS-only. |
| My Events | [`views/default3.handlebars`](../views/default3.handlebars#L764) | CSS-only, сохранить таблицы и фильтры. |
| My Users | [`views/default3.handlebars`](../views/default3.handlebars#L799) | CSS-only, сохранить admin checks. |
| My Server | [`views/default3.handlebars`](../views/default3.handlebars#L905) | CSS-only; self-update отключается конфигурацией, а не скрытием предупреждений. |
| Device page | [`views/default3.handlebars`](../views/default3.handlebars#L968) | Стилизовать tabs/toolbars, не менять routing и rights. |
| Desktop | Разметка [`views/default3.handlebars`](../views/default3.handlebars#L1076), `setupDesktop()` ([`views/default3.handlebars`](../views/default3.handlebars#L10757)) | Стилизовать toolbar/wrapper; не применять фильтры к canvas/video. |
| Terminal | Разметка [`views/default3.handlebars`](../views/default3.handlebars#L1315), `setupTerminal()` ([`views/default3.handlebars`](../views/default3.handlebars#L12904)) | Стилизовать wrapper/toolbar; не переопределять rendering `.xterm`. |
| Files | Разметка [`views/default3.handlebars`](../views/default3.handlebars#L1456), `setupFiles()` ([`views/default3.handlebars`](../views/default3.handlebars#L13376)) | Стилизовать toolbar/table; не менять file commands или permissions. |
| Dialogs and forms | [`views/default3.handlebars`](../views/default3.handlebars#L2078) | CSS для modal/card/input/button; сохранить callbacks и validation. |
| Footer | Modern [`views/default3.handlebars`](../views/default3.handlebars#L2065), legacy [`views/default.handlebars`](../views/default.handlebars#L1431), login [`views/login2.handlebars`](../views/login2.handlebars#L354) | Attribution задаётся `footer`/`loginfooter`; Legal остаётся доступен. |
| Terms/Legal | [`views/terms.handlebars`](../views/terms.handlebars#L48), [`views/terms-mobile.handlebars`](../views/terms-mobile.handlebars#L51) | MyCenter attribution и upstream links добавлены без удаления существующих disclosures; desktop-шаблон повторно вставляет notice после загрузки пользовательского `terms.txt` ([`views/terms.handlebars`](../views/terms.handlebars#L181)). |
| PWA manifest | `handleManifestRequest()` ([`webserver.js`](../webserver.js#L3990)) | MyCenter metadata и цвета используют штатный URL `pwalogo.png`, поэтому domain override `pwaLogo` сохраняется. |
| Logo/PWA handlers | [`webserver.js`](../webserver.js#L4089) | Пользовательские PNG/JPEG overrides сохранены; локальный fallback PWA указывает на `public/images/mycenter-pwa-512.png` ([`webserver.js`](../webserver.js#L4139)). |
| Favicon | Links в modern/legacy/login templates, например [`views/default3.handlebars`](../views/default3.handlebars#L21) | Используются локальные MyCenter SVG и совместимые ICO/PNG fallbacks; MeshCentral logo не переиспользуется. |
| Theme policy | [`public/scripts/themes/theme-switcher.js`](../public/scripts/themes/theme-switcher.js#L1), [`views/default3.handlebars`](../views/default3.handlebars#L750) | Осознанно поддерживается одна локальная MyCenter theme; удалённые theme/font dependencies не загружаются. |
| Session player | [`views/player.handlebars`](../views/player.handlebars#L680) | Менять только отображаемый product label; не менять magic strings и recording format. |

## Стили и расширения

Базовые стили modern UI находятся в [`public/styles/style-bootstrap.css`](../public/styles/style-bootstrap.css), legacy/login — в [`public/styles/style.css`](../public/styles/style.css). MyCenter theme реализована в [`public/styles/custom.css`](../public/styles/custom.css#L1), который подключается после базовых styles через `generateCustomCSSTags()` ([`webserver.js`](../webserver.js#L10024)). Аналогичная точка для необязательного JavaScript — [`public/scripts/custom.js`](../public/scripts/custom.js) и `generateCustomJSTags()` ([`webserver.js`](../webserver.js#L10068)); для текущего визуального слоя дополнительный JavaScript не требуется.

MyCenter сознательно использует один source-controlled `custom.css` и локальный Bootstrap stylesheet. `theme-switcher.js` нормализует любой выбор к `default`, а UI показывает `Theme: MyCenter`; это зафиксированная product policy для детерминированного вида без внешних font imports, а не случайная потеря настройки. Production config не должен загружать theme packs, CDN или удалённые ресурсы. Scoped custom files доступны в schema ([`meshcentral-config-schema.json`](../meshcentral-config-schema.json#L2045)), но отдельный pack сейчас увеличит deployment complexity без выигрыша.

## Фактические brand assets

Все ресурсы созданы для MyCenter, хранятся локально в `public/images/` и не используют внешние изображения или товарные знаки MeshCentral:

| Файл | Назначение |
|---|---|
| [`mycenter-logo.svg`](../public/images/mycenter-logo.svg) | Редактируемый горизонтальный логотип и подпись `Remote Systems Console`. |
| [`mycenter-favicon.svg`](../public/images/mycenter-favicon.svg) | Основной векторный favicon и пиксельный знак MC. |
| [`mycenter-favicon.ico`](../public/images/mycenter-favicon.ico) | Совместимый favicon fallback. |
| [`mycenter-favicon-16.png`](../public/images/mycenter-favicon-16.png), [`mycenter-favicon-32.png`](../public/images/mycenter-favicon-32.png) | Растровые варианты малых размеров. |
| [`mycenter-pwa.svg`](../public/images/mycenter-pwa.svg) | Редактируемый исходник PWA-иконки. |
| [`mycenter-pwa-192.png`](../public/images/mycenter-pwa-192.png), [`mycenter-pwa-512.png`](../public/images/mycenter-pwa-512.png) | Совместимые raster icons для Apple/PWA и fallback handler. |

Manifest продолжает ссылаться на `pwalogo.png` ([`webserver.js`](../webserver.js#L4005)). Этот URL обслуживает штатный `handlePWALogoRequest()`: сначала учитывается domain `pwaLogo`, затем web-public overrides, и только после этого возвращается MyCenter PNG fallback ([`webserver.js`](../webserver.js#L4139)). Так ребрендинг не ломает существующую конфигурационную точку расширения.

## Локальные ресурсы и CSP

Основной CSP разрешает шрифты только с `'self'` и `data:`, а стили — с `'self'` и необходимые inline styles; `fonts.googleapis.com` и `fonts.gstatic.com` удалены из allowlist ([`webserver.js`](../webserver.js#L7221)). MyCenter использует системный моноширинный стек из [`custom.css`](../public/styles/custom.css#L18), поэтому внешний font download не требуется. Разрешения `extraScriptSrc` и `extraImgSrc` остаются штатными конфигурационными механизмами MeshCentral; MyCenter сам их не заполняет внешними ресурсами.

## Устойчивое Legal/attribution

Default Terms содержит явное указание на MeshCentral и MeshAgent, ссылки на официальные upstream-репозитории и пояснение о совместимом оригинальном MeshAgent ([`views/terms.handlebars`](../views/terms.handlebars#L48)). Если администратор задаёт собственный `terms.txt`, исходный `#column_l` заменяется его содержимым, после чего MyCenter legal notice добавляется снова ([`views/terms.handlebars`](../views/terms.handlebars#L181)). Поэтому attribution не зависит от наличия пользовательских Terms. Существующие third-party disclosures и корневой [`LICENSE`](../LICENSE) не удалены.

## Реализованные изолированные изменения

На текущем HEAD изменения изолированы следующим образом:

- `title`, `title2`, `footer`, `loginfooter`, `welcomeText` и `siteStyle` остаются конфигурационными точками; default product name изменён на MyCenter;
- палитра, focus, controls, cards, tabs, tables, dialogs и responsive overrides сосредоточены в `public/styles/custom.css`;
- SVG, PNG и ICO имеют уникальные имена `mycenter-*` в `public/images/` и подключены точечно;
- PWA metadata изменена в одном небольшом handler, а штатный `pwaLogo` override сохранён;
- заменены только видимые product strings; Router/Assistant, protocol magic и внутренние tags не переименованы;
- attribution добавлен в Terms/Legal с сохранением существующих notices и пользовательского `terms.txt`.

## Монолитные файлы и конфликтность

`views/default3.handlebars` и `views/default.handlebars` содержат одновременно HTML и большую часть client-side logic. Любая правка этих файлов повышает риск конфликтов при merge upstream. Поэтому план ограничивает изменения в них favicon-ссылками и несколькими пользовательскими строками; styling остаётся в отдельном CSS.

`webserver.js` также монолитен. Локальные правки ограничены manifest metadata, MyCenter default title, CSP для локальных ресурсов и fallback PWA asset; они не пересекаются с Agent WebSocket, relay или authentication routes. Protocol handlers и protocol identifiers не переименованы.

## Accessibility и responsive риски

Modern template задаёт inline `min-width:495px` на body ([`views/default3.handlebars`](../views/default3.handlebars#L69)), а base CSS местами убирает outline. MyCenter CSS компенсирует это и должен сохранять следующие свойства при дальнейших изменениях:

- принудительно снять минимальную ширину на 360 px;
- вернуть заметный `:focus-visible`;
- не полагаться только на цвет статуса;
- разрешить wrapping toolbars/tables без горизонтальной прокрутки основной страницы;
- не изменять размеры/фильтрацию remote desktop canvas;
- не менять шрифт и rendering terminal buffer;
- отключать анимации при `prefers-reduced-motion: reduce`.

Правила реализованы в [`public/styles/custom.css`](../public/styles/custom.css#L1), включая `:focus-visible`, мобильные media queries, исключения для Desktop/Terminal content и `prefers-reduced-motion`. Ручной responsive smoke-check на 360, 768, 1280 и 1920 px зафиксирован как PASS в [`MYCENTER_PRODUCTION_SMOKE_TEST.md`](MYCENTER_PRODUCTION_SMOKE_TEST.md); независимая browser automation оставлена как NOT TESTED, и этот статический аудит её не подменяет.

## Upstream strategy

1. Держать brand assets в уникальных `mycenter-*` файлах.
2. Держать всю визуальную тему в одном `custom.css` commit.
3. Отделить branding strings/assets от styling и deployment commits.
4. При обновлении upstream сначала переносить server changes, затем запускать визуальный smoke-check на неизменённом MyCenter CSS.
5. Никогда не решать конфликт массовой заменой строки `MeshCentral`: часть таких строк является именем upstream-компонента, форматом записи или protocol identifier.
