# MyCenter production smoke test

- Дата последнего обновления: 2026-08-06
- Ветка: `feature/mycenter-production`
- Проверенная локальная ревизия: `abda27698449a1273961114ab1a4e95fccd1ebf1` (`style: add green pixel interface`)
- Версия MeshCentral: `1.2.4`

## Назначение и правила статусов

Это живой checklist локальной и будущей production-проверки MyCenter. Документ отделяет непосредственно наблюдавшиеся результаты от ручных подтверждений пользователя и от действий, которые ещё не выполнялись.

| Статус | Значение |
|---|---|
| PASS | Проверка выполнена, фактический результат соответствует ожидаемому. |
| WARNING | Проверка выполнена и выявила риск, не созданный текущим UI-изменением. |
| PENDING | Для завершения уже начатой проверки требуется подтверждение пользователя. |
| NOT TESTED | Проверка не выполнялась; успешный результат не подразумевается. |

Пароли, cookies, session tokens, ключи, содержимое сертификатов, runtime-БД и другие секреты в этот документ не записываются.

## Локальное тестовое окружение

| Параметр | Фактическое значение |
|---|---|
| ОС | Windows, локальная рабочая станция; точная редакция в этом прогоне не фиксировалась |
| Node.js | `v24.18.0` |
| npm | `11.16.0` |
| Установка зависимостей | `npm.cmd ci` |
| URL | `https://localhost:8443/` |
| Listener | `127.0.0.1:8443` |
| TLS-проверка | Выполнена с явно указанным локальным публичным CA-файлом; отключение проверки сертификата не использовалось |
| Browser automation | Недоступна в этом прогоне |
| MeshAgent | Новый локальный агент не устанавливался и functional Agent smoke в этом прогоне не выполнялся |

Локальная проверка использовала отдельные тестовые runtime-данные, а не ранее существовавший каталог production/runtime. Приватные ключи и содержимое runtime-состояния не исследовались и не включались в Git.

## Локальный pre-auth smoke-check

| Проверка | Ожидаемый результат | Фактический результат | Статус |
|---|---|---|---|
| Версия Node.js | Node.js 24 LTS и не ниже требуемой проектом версии 20 | `v24.18.0` | PASS |
| Версия npm | npm доступен из текущей консоли | `11.16.0`; в Windows PowerShell использовался `npm.cmd` | PASS |
| `npm ci` | Установка из lock-файла завершается без обновления версий | Команда завершилась успешно | PASS |
| Запуск сервера | Сервер стартует из проверяемого checkout | Сервер запустился | PASS |
| HTTPS listener | Доступен только loopback listener | Наблюдался `127.0.0.1:8443` | PASS |
| Проверка TLS | Клиент доверяет явно переданному тестовому CA; hostname проверяется | HTTPS-запрос прошёл с явным CA, без `-k`, `--insecure` или изменения TLS-кода | PASS |
| Login page | Корневая страница возвращает страницу входа | Страница входа получена по HTTPS | PASS |
| Product title | Пользовательское название — MyCenter | В title и видимом branding отображается MyCenter | PASS |
| Subtitle | Отображается `Remote Systems Console` | Подзаголовок присутствует | PASS |
| Favicon и logo assets | Используются локальные MyCenter assets | Локальные favicon/logo/PWA assets доступны; ссылки на них сформированы корректно | PASS |
| Pixel CSS | Загружается зелёная тёмная MyCenter-тема | Основные CSS-переменные и pixel-theme присутствуют в загруженной странице | PASS |
| Pre-auth external assets | Login не требует CDN, удалённых изображений или remote fonts | Статическая проверка HTML/CSS и pre-auth ресурсов не выявила внешней загрузки UI-assets | PASS |
| CSP | Политика не требует внешних UI-assets и не нарушает загрузку локального login UI | Pre-auth CSP и локальные assets прошли проверку | PASS |
| JavaScript console | Нет runtime-ошибок браузера | Browser automation и независимый сбор console events были недоступны | NOT TESTED |
| Responsive 360/768/1280/1920 | Нет горизонтального overflow и элементы доступны | Пользователь вручную подтвердил корректную адаптивность на всех четырёх запрошенных ширинах; автоматизированная viewport-проверка не выполнялась | PASS |

PASS для external assets и CSP основан на HTTP/static inspection текущей pre-auth страницы. Это не заменяет production browser network trace для аутентифицированных страниц, сохранённой пользовательской темы и всех responsive viewport.

## Ручной post-auth smoke-check

Ручной вход выполнил пользователь без передачи логина или пароля. Секреты не запрашивались и не сохранялись.

| Проверка | Ожидаемый результат | Фактический результат | Статус |
|---|---|---|---|
| Первичный вход | Существующий тестовый пользователь успешно входит | Вход подтверждён вручную | PASS |
| Главная страница | После входа загружается оболочка MyCenter | Главная страница открылась | PASS |
| My Devices | Раздел открывается без изменения permission checks | Раздел открыт вручную; отображён пустой список устройств | PASS |
| My Account | Раздел открывается | Раздел открыт вручную | PASS |
| My Server | Административный раздел открывается для администратора | Раздел открыт вручную | PASS |
| My Events | Журнал событий открывается | Раздел открыт вручную | PASS |
| My Users | Управление пользователями открывается для администратора | Раздел открыт вручную | PASS |
| Logout | Сессия завершается и возвращает пользователя на login page | Logout и возврат к странице входа подтверждены пользователем в составе ручного UI-checklist | PASS |
| Повторный вход до рестарта | Пользователь повторно входит | Повторный вход подтверждён пользователем без передачи учётных данных | PASS |
| Вход после рестарта | Тот же пользователь входит после перезапуска сервера, данные не пересозданы | Пользователь подтвердил успешный вход после перезапуска без передачи учётных данных | PASS |
| Сохранность пользователя после рестарта | Существующая учётная запись доступна без повторной регистрации | Успешный вход подтвердил логическую сохранность учётной записи; физические NeDB-файлы могли быть атомарно перезаписаны или скомпактированы при штатной работе | PASS |
| Финальная остановка локального сервера | После завершения ручной проверки сервер остановлен и listener закрыт | Остановлены только два Node-процесса изолированного smoke-runtime; процессов и listener `127.0.0.1:8443` не осталось, оба временных каталога удалены | PASS |
| Post-auth console errors | При навигации нет JavaScript errors | Независимый сбор browser console был недоступен | NOT TESTED |
| Keyboard-only navigation | Focus видим, основные действия доступны с клавиатуры | Полная проверка не выполнялась | NOT TESTED |
| Responsive authenticated UI | Основные разделы пригодны при 360/768/1280/1920 px | Пользователь вручную подтвердил отсутствие горизонтальной прокрутки основной страницы и доступность навигации, текста и кнопок на всех четырёх ширинах | PASS |

Успешный вход после перезапуска подтверждён пользователем. Логин, пароль и данные сессии не запрашивались и не сохранялись.

## Dependency audit

`npm audit fix` и обновление зависимостей не выполнялись.

| Проверка | Фактический результат | Статус |
|---|---|---|
| Audit сразу после воспроизводимого `npm ci` | `npm audit --omit=dev` обнаружил один high-severity package finding: locked `brace-expansion@2.1.2` по цепочкам `archiver`/`readdir-glob`/`minimatch` и `express-handlebars`/`glob`/`minimatch`; автоматическое исправление не выполнялось | WARNING |
| Audit с Windows runtime-модулями | После добавления требуемых самим MeshCentral Windows runtime-зависимостей audit surface содержит четыре finding; среди добавленных модулей присутствует `node-windows@0.1.14` | WARNING |
| Происхождение findings | Findings относятся к upstream dependency/runtime baseline, а не к добавленным SVG, CSS или шаблонным строкам MyCenter | WARNING |
| Автоматическое исправление | `npm audit fix` и `npm audit fix --force` не запускались | PASS |

Windows-особенность важна для воспроизводимости: `npm ci` удаляет extraneous runtime-модули, после чего MeshCentral может штатно установить `node-windows` и `loadavg-windows` при первом запуске. Перед commit необходимо отдельно убедиться, что вызванная runtime-установкой мутация `package.json` или `package-lock.json` не попала в staged changes.

## Проверки совместимости, не завершённые локально

| Проверка | Статус | Причина |
|---|---|---|
| WebSocket `control.ashx` под нагрузкой | NOT TESTED | Выполнялся только базовый UI smoke, без отдельного traffic trace |
| `agent.ashx` с оригинальным MeshAgent | NOT TESTED | Новый локальный агент устанавливать запрещено |
| Relay end-to-end | NOT TESTED | Нет подключённого к этому тестовому runtime устройства |
| Device Details | NOT TESTED | Нет Online-устройства в изолированном runtime |
| Terminal | NOT TESTED | Нет Online-устройства; команды не выполнялись |
| Files | NOT TESTED | Нет Online-устройства; файлы пользователя не изменялись |
| Desktop | NOT TESTED | Нет Online-устройства |
| Reconnect агента после server restart | NOT TESTED | Перенесено в production Agent smoke |

UI-изменения не должны считаться доказательством совместимости агентского протокола. Такая совместимость подтверждается отсутствием изменений handshake/protocol identifiers и отдельным production smoke с оригинальным MeshAgent.

## Production/VPS checklist

Production deployment на момент создания документа не начинался. Все пункты ниже имеют статус NOT TESTED независимо от локального результата.

| Область | Проверка | Статус |
|---|---|---|
| Inputs | Получены VPS IP, SSH user, локальный путь к ключу, FQDN и ACME email | NOT TESTED |
| SSH | Key-based вход проверен без изменения SSH policy | NOT TESTED |
| VPS baseline | Ubuntu 24.04 LTS x86_64, CPU, RAM, disk, swap и hostname проверены | NOT TESTED |
| Conflicts | Порты 80/443 свободны, конфликтующие сервисы не удалялись автоматически | NOT TESTED |
| DNS | A-record разрешается ровно в публичный IPv4 VPS | NOT TESTED |
| DNS | Ошибочный AAAA отсутствует либо IPv6 полностью настроен | NOT TESTED |
| Transfer | Git bundle создан, проверен и передан без GitHub push | NOT TESTED |
| Source | Bundle клонирован в `/opt/mycenter/src`, commit history проверена | NOT TESTED |
| Docker | Docker Engine установлен из официального репозитория | NOT TESTED |
| Compose | Docker Compose plugin доступен | NOT TESTED |
| Image | Versioned image `mycenter:<SHORT_COMMIT>` успешно собран | NOT TESTED |
| Container user | Процесс работает не от root, если это совместимо с MeshCentral | NOT TESTED |
| Compose config | Итоговая конфигурация проходит `docker compose config --quiet` | NOT TESTED |
| Secrets | Реальный `.env` существует только на VPS, mode 600, не tracked | NOT TESTED |
| Persistence | Data, files, backups и web размещены в persistent volumes | NOT TESTED |
| Ports | Публично открыты только SSH, 80/tcp и 443/tcp | NOT TESTED |
| MPS | Порт 4433 не опубликован, `mpsPort` отключён | NOT TESTED |
| Firewall | UFW включён только после проверки второй SSH-сессии | NOT TESTED |
| HTTP | `http://<domain>/` перенаправляется на HTTPS | NOT TESTED |
| ACME staging | Let’s Encrypt staging challenge и сертификат успешны | NOT TESTED |
| ACME production | Выпущен доверенный production-сертификат для точного FQDN | NOT TESTED |
| TLS | Hostname, chain и срок действия сертификата корректны | NOT TESTED |
| Health | Container healthcheck имеет статус healthy | NOT TESTED |
| Restart policy | `restart: unless-stopped` и автозапуск после reboot проверены | NOT TESTED |
| Branding | Public login title, logo, favicon и pixel theme — MyCenter | NOT TESTED |
| Browser resources | На public pre-auth и post-auth страницах нет внешних UI-assets | NOT TESTED |
| Responsive | 360/768/1280/1920 px проверены на public URL | NOT TESTED |
| First administrator | Администратор создан пользователем через HTTPS UI | NOT TESTED |
| Registration | `newAccounts` остаётся выключен; известный bootstrap token после создания администратора заменён непоказываемым постоянным guard | NOT TESTED |
| 2FA | Пользователю предложено включить 2FA без раскрытия secret/recovery codes | NOT TESTED |
| Auth | Logout, повторный вход и запрет новой регистрации проверены | NOT TESTED |
| Agent download | Агент скачан только из production UI | NOT TESTED |
| Agent TLS/WSS | Оригинальный MeshAgent подключается к ожидаемому домену по HTTPS/WSS | NOT TESTED |
| Agent identity | После reconnect нет дубликата устройства | NOT TESTED |
| Device functions | Details, Terminal, Files и Desktop открываются | NOT TESTED |
| Safe Agent smoke | Команды и изменения файлов во время первого smoke не выполнялись | NOT TESTED |
| Backup | Ежедневный backup создан с ограниченными правами | NOT TESTED |
| Retention | Настроено 7 daily и 4 weekly backups | NOT TESTED |
| Restore dry-run | Архив, checksum и распаковка во временный каталог проверены | NOT TESTED |
| Update | Backup → versioned image → healthcheck процедура проверена | NOT TESTED |
| Rollback | Возврат к предыдущему working image проверен | NOT TESTED |

## Read-only финальная проверка deployment-файлов

Эти команды предназначены для проверки уже созданных файлов и запущенного deployment. Они не создают ресурсы, не меняют firewall и не выводят значения `.env`.

Локально перед commit:

```powershell
git status --short
git diff --stat
git diff --check
git diff --cached --name-only
git diff --cached --name-only | Select-String -Pattern '^agents/(MeshCmd|MeshService)(64)?\.exe$'
git ls-files deploy/.env
```

Последние две команды должны вернуть пустой результат. Добавлять файлы следует явным списком.

На VPS до запуска:

```bash
bash -n /opt/mycenter/src/deploy/*.sh
docker compose \
  --env-file /opt/mycenter/deploy/.env \
  -f /opt/mycenter/src/deploy/docker-compose.yml \
  config --quiet
systemd-analyze verify \
  /opt/mycenter/src/deploy/mycenter.service \
  /opt/mycenter/src/deploy/mycenter-backup.service \
  /opt/mycenter/src/deploy/mycenter-backup.timer
stat -c '%a %U:%G %n' /opt/mycenter/deploy/.env
test -L /opt/mycenter/deploy/current-tools
test ! -e /opt/mycenter/state/maintenance-incomplete
```

После запуска, не раскрывая environment контейнера:

```bash
docker compose \
  --env-file /opt/mycenter/deploy/.env \
  -f /opt/mycenter/deploy/docker-compose.yml \
  ps
docker inspect --format '{{.Config.User}} {{.HostConfig.RestartPolicy.Name}} {{.State.Health.Status}}' mycenter
readlink -f /opt/mycenter/deploy/current-tools
cat /opt/mycenter/state/current-image-tag
test ! -e /opt/mycenter/state/maintenance-incomplete
sudo ss -lntp
sudo ufw status verbose
systemctl list-timers --all | grep mycenter-backup
```

Проверка public HTTP/TLS:

```bash
curl --fail --silent --show-error --head "http://${MYCENTER_DOMAIN}/"
curl --fail --silent --show-error --head "https://${MYCENTER_DOMAIN}/"
openssl s_client \
  -connect "${MYCENTER_DOMAIN}:443" \
  -servername "${MYCENTER_DOMAIN}" \
  </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

`MYCENTER_DOMAIN` должен задаваться в текущей shell-сессии без вывода других значений `.env`. Нельзя использовать `curl -k` или `--insecure`.

Для проверки отсутствия секретов в Git выводятся только имена подозрительных файлов, а не совпавшие строки:

```bash
cd /opt/mycenter/src
git grep -Il -E 'BEGIN ([A-Z0-9 ]+)?PRIVATE KEY|github_pat_|gh[pousr]_|npm_[A-Za-z0-9]{20,}|_authToken' \
  -- . ':(exclude)docs/MYCENTER_PRODUCTION_SMOKE_TEST.md'
git status --short
```

Любой результат secret scan требует ручного разбора до дальнейшего deployment; найденные значения нельзя копировать в логи или отчёт.

## Открытые ограничения

- Вход после локального рестарта подтверждён вручную; логическая сохранность пользователя проверена без фиксации учётных данных.
- Browser automation была недоступна, поэтому console и network waterfall не подтверждены автоматически; четыре viewport проверены пользователем вручную.
- Post-auth результат основан на ручной навигации пользователя.
- Локальный сертификат является тестовым; он не доказывает готовность Let’s Encrypt и public TLS.
- Dependency audit содержит upstream baseline findings; автоматическое исправление намеренно не выполнялось.
- Agent, relay, Terminal, Files и Desktop не проверялись в изолированном локальном runtime.
- Ни один production/VPS пункт ещё не проверен.
- Этот документ не является production acceptance до замены всех обязательных NOT TESTED и PENDING на фактические результаты.
