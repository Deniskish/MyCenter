# MyCenter

MyCenter — инженерный fork [MeshCentral](https://github.com/Ylianst/MeshCentral)
для self-hosted удалённого управления компьютерами через браузер. Проект сохраняет
неизменным upstream protocol contract и дополняет upstream web-интерфейс собственным
branding/theme-слоем, Linux/Docker-развёртыванием и эксплуатационными инструментами.

Локальный baseline сервера и оригинального MeshAgent пройден. Production-стенд работает
по HTTPS, но несколько эксплуатационных проверок ещё не завершены.

## Что сделано мной

### Аудит и проверка совместимости

- Проведён source-level аудит запуска сервера, авторизации, agent endpoint, регистрации
  устройств, БД, relay и UI — [ARCHITECTURE_AUDIT.md](docs/ARCHITECTURE_AUDIT.md).
- Зафиксирован baseline MeshCentral 1.2.4 на Node.js 24 LTS: `npm ci`, loopback-only
  listener, TLS, persistence и корректная остановка — [BASELINE_RUN.md](docs/BASELINE_RUN.md).
- Проверены создание администратора, login/logout, отрицательная авторизация и
  основные административные разделы — [UI_SMOKE_TEST.md](docs/UI_SMOKE_TEST.md).
- Выполнен статический аудит официального MeshAgent: lifecycle, конфигурация, DNS,
  proxy, IPv4/IPv6, TLS/WebSocket, identity, reconnect и Windows service — [отчёт](docs/MESHAGENT_ARCHITECTURE_AUDIT.md).
- Проведён контролируемый A/B-тест оригинального Windows x64 MeshAgent. Подтверждены
  TCP, TLS, WebSocket upgrade `/agent.ashx`, регистрация, Online, Details, Terminal,
  Files и Desktop. Numeric IPv4 устранил лабораторную проблему подключения;
  порядок DNS-ответов не объявляется доказанным без packet trace —
  [MESHAGENT_CONNECTION.md](docs/MESHAGENT_CONNECTION.md).

### Linux, Docker и эксплуатация

- Подготовлен multi-stage Docker build на Node.js 24 LTS. Runtime работает от
  непривилегированного UID/GID 10001, с read-only root filesystem, healthcheck и
  ограниченным набором Linux capabilities.
- Настроены persistent volumes, versioned image tags и
  `restart: unless-stopped`; встроенный self-update MeshCentral отключён.
- Добавлены systemd units для boot reconciliation и планового backup.
- Реализован preflight workflow для проверки ОС, архитектуры, ресурсов, DNS, занятых
  портов, Docker-конфликтов, SSH-доступа и необходимости reboot.
- Подготовлены deployment/update/rollback scripts с health gates, maintenance
  lock, persistent fail-closed marker и recovery paths.
- Реализованы backup/restore scripts с SHA-256, retention, проверкой архива и
  restore dry-run.
- Настроен staging → production workflow вокруг встроенной Let's Encrypt
  интеграции MeshCentral без отключения TLS verification.

### Branding и web-интерфейс

- Добавлены собственные локальные SVG/PNG/ICO assets и отображаемое имя
  MyCenter без переименования протокольных сущностей.
- Реализован тёмный зелёный branding/theme-слой для навигации, карточек,
  таблиц, форм и диалогов.
- Добавлены keyboard focus, `prefers-reduced-motion` и responsive rules для 360/768/1280/1920 px.
- Branding-assets MyCenter не используют внешние fonts/CDN; сохранены Legal,
  copyright и upstream attribution.

Подробности: [MYCENTER_UI_AUDIT.md](docs/MYCENTER_UI_AUDIT.md) и
[MYCENTER_BRANDING.md](docs/MYCENTER_BRANDING.md).

## Происхождение и границы авторства

MyCenter — fork-проект, а не реализация системы удалённого управления с нуля.

- Серверное ядро, аутентификация, модель устройств, relay и базовые функции управления
  принадлежат upstream-проекту **MeshCentral**.
- Исполняемый агент и его низкоуровневый протокол принадлежат upstream-проекту
  [MeshAgent](https://github.com/Ylianst/MeshAgent).
- TLS/handshake, `agent.ashx`, `meshrelay.ashx`, `MeshID`, `ServerID`, `NodeID`
  и протоколы Terminal, Files и Desktop не написаны автором MyCenter и
  функционально не модифицировались. Изменена только визуальная web-оболочка.
- Мой вклад — аудит, настройка, проверка совместимости и диагностика связки
  server-agent, branding/theme, Linux/Docker/systemd infrastructure,
  deployment, backup/restore и update/rollback.

Исходная серверная база: upstream commit
`bd48e8a9d36d86cf860fb2a32617ac6e398274e8`.

## Архитектура

```text
[Оригинальный MeshAgent]
        |
        | TLS + WebSocket /agent.ashx (регистрация и control)
        v
[MyCenter Server / MeshCentral upstream core]
        ^
        | HTTPS + WebSocket /control.ashx (Web UI и Details)
        |
[Браузер администратора]

[MeshAgent] <--- WSS /meshrelay.ashx ---> [Server relay] <--- WSS ---> [Browser]
                                                        Terminal / Files / Desktop

Persistent state:
  meshcentral-data | meshcentral-files | meshcentral-web | backups
```

Сервер завершает TLS, отдаёт web-интерфейс и обслуживает WebSocket/relay-сессии.
MPS отключён; нужны HTTP для redirect и ACME HTTP-01, HTTPS/WSS и отдельный SSH.

## Deployment, update и восстановление

| Компонент | Назначение |
|---|---|
| [`deploy/Dockerfile`](deploy/Dockerfile), [`docker-compose.yml`](deploy/docker-compose.yml) | Non-root production image, persistent state, healthcheck и runtime hardening |
| [`deploy/deploy.sh`](deploy/deploy.sh) | Render конфигурации, build, staging ACME, production promotion и закрытие регистрации |
| [`deploy/healthcheck.sh`](deploy/healthcheck.sh) | Проверка HTTP redirect, HTTPS hostname, TLS и состояния сервиса без `-k` |
| [`deploy/update.sh`](deploy/update.sh) | Backup → versioned image → health gate → release или rollback |
| [`deploy/backup.sh`](deploy/backup.sh), [`restore.sh`](deploy/restore.sh) | Snapshot, checksum, retention, restore validation и dry-run |

Systemd units, VPS bootstrap и recovery scripts описаны в
[deploy/README.md](deploy/README.md). Runtime `.env`, `config.json`, сертификаты,
БД и backup-архивы не входят в Git.

## Текущее состояние production-стенда

Последний read-only срез выполнен 7 сентября 2026 года; публичный FQDN и IP не приводятся.

Подтверждено:

- HTTP перенаправляется на HTTPS; trusted TLS и `/health.ashx` работают;
- контейнер имеет состояние `running/healthy`;
- регистрация новых аккаунтов закрыта;
- MPS отключён;
- restart policy настроен;
- снаружи наблюдаются только предусмотренные listeners 22/80/443.

Требует завершения:

- production backup/restore drill ещё нужно подтвердить;
- automatic certificate renewal нужно проверить;
- production smoke-check оригинального MeshAgent ещё не завершён;
- deployment отстаёт от development HEAD;
- требуется контролируемый reboot с проверкой автозапуска;
- effective firewall policy требует повторной независимой проверки;
- runtime пока использует название `FronControl`, а репозиторий развивается как
  `MyCenter`.

Стенд подтверждает web/TLS/container baseline, но ещё не считается завершённым
production acceptance. Исходный checklist находится в
[MYCENTER_PRODUCTION_SMOKE_TEST.md](docs/MYCENTER_PRODUCTION_SMOKE_TEST.md); его
исторические статусы ещё не актуализированы этим срезом.

## Структура репозитория

| Путь | Происхождение и роль |
|---|---|
| [`meshcentral.js`](meshcentral.js) | Upstream entry point и lifecycle сервера |
| [`webserver.js`](webserver.js), [`meshuser.js`](meshuser.js) | Upstream web/auth/session logic; ограниченные branding/manifest/CSP changes |
| [`meshagent.js`](meshagent.js), [`meshrelay.js`](meshrelay.js) | Upstream agent handler и relay; protocol contract не менялся |
| [`views/`](views/), [`public/`](public/) | Upstream UI с branding/theme-слоем и собственными assets MyCenter |
| [`agents/`](agents/) | Оригинальные upstream agent binaries; не являются моей реализацией |
| [`deploy/`](deploy/) | Docker/systemd/deployment/backup/update infrastructure для fork |
| [`docs/`](docs/) | Аудиты, baseline, smoke-checks и эксплуатационные runbooks |

## Локальный запуск

Требуется Node.js `>=20`; baseline проверен на Node.js 24 LTS. Runtime-данные
нужно размещать вне Git. До запуска следует создать в data path `config.json` с
loopback listener, `redirPort: 0` и `mpsPort: 0`, как описано в
[BASELINE_RUN.md](docs/BASELINE_RUN.md).

```powershell
cd C:\path\to\MyCenter
npm ci
node .\meshcentral.js --datapath C:\path\outside-git\mycenter-data
```

```bash
npm ci
node ./meshcentral.js --datapath /path/outside-git/mycenter-data
```

Первый запуск создаёт БД и certificates в выбранном data path. Production data,
`.env`, `config.json`, private keys и backups нельзя использовать для локальной
разработки или добавлять в Git.

## Безопасность

- TLS verification не отключается в приложении и healthcheck.
- Agent handshake, identity и permission checks остаются upstream-compatible.
- MPS, Docker API, database ports и Node inspector не публикуются.
- Runtime secrets генерируются на VPS и не передаются через Git или CLI.
- Контейнер работает не от root, без Docker socket и с ограниченными
  capabilities.
- Update/rollback/backup/restore используют lock, health gates и fail-closed
  recovery marker.
- Dependency advisories отслеживаются отдельно; автоматические обновления
  зависимостей не применяются без проверки совместимости.

Security baseline: [MYCENTER_SECURITY.md](docs/MYCENTER_SECURITY.md).

## Планы развития

1. Завершить production smoke-check оригинального MeshAgent.
2. Подтвердить backup/restore acceptance, retention и restore dry-run.
3. Проверить automatic certificate renewal до истечения текущего сертификата.
4. Добавить CI для syntax/config/link/license checks и dependency review.
5. Продолжить изучение networking/client-agent части без изменения upstream
   protocol contract.

## Лицензия и attribution

Серверный репозиторий сохраняет [Apache License 2.0](LICENSE), copyright и
применимые bundled third-party license/credit files MeshCentral. MyCenter не
использует логотип MeshCentral как свой и не подразумевает endorsement со
стороны upstream-разработчиков.

README официального MeshAgent заявляет Apache 2.0, однако в исследованном
checkout отсутствовали корневые `LICENSE`/`NOTICE`; комплектность лицензий
конкретно распространяемого бинарника должна проверяться отдельно. Подробности:
[MYCENTER_LICENSES.md](docs/MYCENTER_LICENSES.md).

## Что демонстрирует проект

- практический опыт Linux system administration и развёртывания сетевого сервиса на VPS;
- диагностику DNS, TCP, TLS, proxy, IPv4/IPv6 и сетевых listeners;
- понимание HTTPS/WebSocket control- и relay-каналов;
- анализ и проверку client-server architecture;
- эксплуатацию Docker Compose и systemd;
- failure-safe deployment, rollback, backup и recovery workflow.
