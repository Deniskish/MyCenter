# Архитектурный аудит официального MeshAgent

## Паспорт аудита

| Параметр | Значение |
|---|---|
| Дата | 2026-07-30 — 2026-07-31 (Europe/Moscow) |
| Репозиторий | <https://github.com/Ylianst/MeshAgent.git> |
| Локальный checkout | `C:\projects\MeshAgent-Upstream` |
| Ветка | `master` |
| Commit | `ebff7fb7b3e0de9b13b3c7402e015f22e70fab72` |
| Последний commit | `add include for pthread_np.h for freebsd (#366)` |
| Состояние checkout | Чистое; ветки не переключались, файлы не изменялись |
| Метод | Статический анализ исходного кода и документации |
| Не выполнялось | Сборка, запуск, установка зависимостей, запуск бинарников и анализ конфигурации установленного пользовательского агента |

Все GitHub-ссылки ниже закреплены за audited commit `ebff7fb7b3e0de9b13b3c7402e015f22e70fab72`. Номера строк относятся именно к нему.

## Краткое описание архитектуры

MeshAgent — нативный кроссплатформенный host, который соединяется с MeshCentral по TLS/WebSocket, выполняет дополнительный двусторонний handshake и предоставляет серверу Node-подобную JavaScript-среду на Duktape. Сам нативный агент реализует транспорт, криптографическую идентичность, datastore, event loop, платформенные API и низкоуровневые примитивы. Высокоуровневый Mesh Core загружается с сервера и оркестрирует команды и пользовательские сессии ([docs/Architecture.md:128-152](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/docs/Architecture.md#L128-L152), [meshcore/agentcore.c:3047-3330](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3047-L3330)).

Главный Microstack event loop однопоточный и асинхронный. Некоторые платформенные компоненты создают вспомогательные потоки или процессы, но их события должны возвращаться в основной dispatch thread ([docs/Architecture.md:136-143](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/docs/Architecture.md#L136-L143)). Control channel является одним долгоживущим WebSocket. Desktop, Terminal и Files начинают отдельные relay-сессии через WebSocket; после negotiation data path может переключиться на data-only WebRTC, при этом relay WebSocket остаётся открытым для управления завершением сессии ([docs/Architecture.md:88-126](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/docs/Architecture.md#L88-L126)).

Критическая граница аудита: agent-side production-реализация высокоуровневых JSON-команд и session orchestration Terminal/Files/Desktop находится в присылаемом сервером CoreModule. Его production-исходник в этом репозитории отсутствует. Нативный код передаёт соответствующие команды событию `MeshAgent.Command`, сохраняет/запускает CoreModule и предоставляет ему API ([meshcore/agentcore.c:3047-3123](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3047-L3123), [meshcore/agentcore.c:3140-3330](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3140-L3330), [meshcore/agentcore.c:5415-5486](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L5415-L5486)). Server-side authentication, relay token issuance и permission flags также участвуют в production authorization path ([docs/Architecture.md:88-103](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/docs/Architecture.md#L88-L103)); их полный контракт нельзя вывести из MeshAgent checkout.

## Лицензия и attribution

### Что присутствует в checkout

`readme.md` называет Apache License 2.0 и ведёт на её официальный текст ([readme.md:208-209](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/readme.md#L208-L209)). Типичные исходные файлы содержат Intel copyright и Apache-2.0 boilerplate ([meshconsole/main.c:1-17](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshconsole/main.c#L1-L17), [meshservice/ServiceMain.c:1-15](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/ServiceMain.c#L1-L15)).

В audited checkout нет корневых `LICENSE`, `LICENSE.txt`, `NOTICE` или `NOTICE.txt`; README содержит только внешнюю ссылку. Это риск комплектности лицензирования: одного утверждения README недостаточно для окончательного юридического вывода о всём дереве и будущей binary distribution. Runtime-команда `-licenses` выводит Apache-2.0 boilerplate/URL, текст Duktape MIT и текст zlib, но не перечисляет все vendored-компоненты ([meshconsole/main.c:185-245](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshconsole/main.c#L185-L245), [meshservice/ServiceMain.c:476-536](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/ServiceMain.c#L476-L536)).

Обнаружены дополнительные условия:

- Duktape MIT — полный текст присутствует в исходнике и заголовке; отдельного tracked `AUTHORS.rst` нет, хотя generated single-source файл включает authors section ([microscript/duktape.c:7-50](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microscript/duktape.c#L7-L50), [microscript/duktape.h:16-42](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microscript/duktape.h#L16-L42)).
- zlib license — полный текст включён в vendored-код ([meshcore/zlib/zlib.h:1-20](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/zlib/zlib.h#L1-L20), [meshcore/zlib/README:85-103](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/zlib/README#L85-L103)).
- libjpeg-turbo содержит BSD-style условия; отдельные IJG/SIMD-файлы ссылаются на отсутствующие в checkout `README.ijg` и `jsimdext.inc` ([lib-jpeg-turbo/includes/turbojpeg.h:1-26](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/lib-jpeg-turbo/includes/turbojpeg.h#L1-L26), [lib-jpeg-turbo/includes/jpeglib.h:4-11](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/lib-jpeg-turbo/includes/jpeglib.h#L4-L11), [lib-jpeg-turbo/includes/jsimd.h:8-10](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/lib-jpeg-turbo/includes/jsimd.h#L8-L10), [lib-jpeg-turbo/includes/jsimddct.h:6-8](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/lib-jpeg-turbo/includes/jsimddct.h#L6-L8)).
- OpenSSL headers ссылаются на OpenSSL License, но её полного текста в checkout не найдено ([openssl/include/openssl/asn1.h:2-8](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/openssl/include/openssl/asn1.h#L2-L8)); SEED header содержит отдельные KISA permissive terms ([openssl/include/openssl/seed.h:10-32](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/openssl/include/openssl/seed.h#L10-L32)).
- NoTLS-код включает Yubico BSD-style SHA-2, Openwall MD5 и public-domain SHA-1 ([microstack/nossl/sha.h:3-31](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/nossl/sha.h#L3-L31), [microstack/nossl/md5.c:1-23](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/nossl/md5.c#L1-L23), [microstack/nossl/sha1.c:1-7](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/nossl/sha1.c#L1-L7)).
- Три macOS KVM-файла содержат placeholder `__MyCompanyName__` без явного license header, что требует отдельной проверки provenance до распространения ([meshcore/KVM/MacOS/mac_kvm.h:1-8](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/KVM/MacOS/mac_kvm.h#L1-L8), [meshcore/KVM/MacOS/mac_tile.c:1-8](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/KVM/MacOS/mac_tile.c#L1-L8), [meshcore/KVM/MacOS/mac_tile.h:1-8](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/KVM/MacOS/mac_tile.h#L1-L8)).

### Практические требования для будущего форка

Ниже не юридическое заключение, а технический checklist по тексту [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0) и найденным third-party notices:

1. При любом распространении Work или Derivative Work в Source или Object form, с изменениями или без, передать получателям копию Apache-2.0.
2. В Source form распространяемого Derivative Work сохранить применимые copyright, patent, trademark и attribution notices из Source form Work, исключая notices, не относящиеся к распространяемой части.
3. Помечать изменённые файлы заметным уведомлением о внесённых изменениях.
4. Если конкретный распространяемый upstream Work включает `NOTICE`, перенести применимые уведомления по правилам Apache-2.0. В текущем audited checkout upstream `NOTICE` отсутствует; нельзя представлять собственный NOTICE как исходный.
5. Apache-2.0 допускает распространение Source/Object и Derivative Works при выполнении её условий, но не предоставляет иных прав на trade names, trademarks, service marks или product names, кроме разумного описания происхождения Work и воспроизведения NOTICE. Возможность переименования здесь является технической оценкой; рекомендация не создавать ложное впечатление официального продукта — консервативная мера branding-risk, а не установленный этим checkout статус товарных знаков.
6. Отдельно включить применимые тексты/уведомления Duktape, zlib, OpenSSL, libjpeg/IJG, KISA, Yubico и Openwall.
7. До выпуска составить SBOM и сверить происхождение каждого статического архива. Текущий `-licenses` недостаточен как полный attribution bundle.

## Карта репозитория

| Путь | Назначение | Ключевые точки |
|---|---|---|
| `meshcore/` | Lifecycle агента, control channel, handshake, сертификаты, datastore, update, базовая system information | `MeshAgent_Create`, `MeshAgent_Start`, `MeshServer_Connect` ([meshcore/agentcore.c:3837-4356](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3837-L4356), [meshcore/agentcore.c:4509-4589](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4509-L4589)) |
| `microstack/` | Event loop, sockets, HTTP/WebSocket, datastore, crypto, logging и WebRTC | Компоненты перечислены в [docs/Files.md:6-37](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/docs/Files.md#L6-L37) |
| `microscript/` | Duktape и C-bindings Node-подобных модулей | Duktape 2.6.0 и native bindings ([microscript/duktape.h:173-188](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microscript/duktape.h#L173-L188), [makefile:179-187](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/makefile#L179-L187)) |
| `modules/` | JavaScript runtime modules: installer, service manager, inventory, terminal, clipboard, proxy и platform helpers | CoreModule использует эти API, но production dispatcher отсутствует |
| `meshconsole/` | Console/Unix entry point и Windows console project | [meshconsole/main.c:88-94](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshconsole/main.c#L88-L94) |
| `meshservice/` | Windows service entry point, installer UI, resources, Visual Studio project | [meshservice/ServiceMain.c:205-344](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/ServiceMain.c#L205-L344) |
| `meshcore/KVM/` | Windows, Linux и macOS remote desktop implementations | KVM source selection ([makefile:548-573](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/makefile#L548-L573)) |
| `meshcore/zlib/` | Vendored zlib 1.2.11 | [meshcore/zlib/zlib.h:35-40](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/zlib/zlib.h#L35-L40) |
| `openssl/` | Headers и prebuilt static libraries | Static/dynamic selection ([makefile:588-607](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/makefile#L588-L607)) |
| `lib-jpeg-turbo/` | Headers и static TurboJPEG libraries для KVM | [makefile:548-570](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/makefile#L548-L570) |
| `test/` | Stateful integration/self-update/leak tests | [docs/testing/UnitTests.md:23-43](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/docs/testing/UnitTests.md#L23-L43) |
| `docs/` | Архитектура, компоненты, release checklist и testing docs | [docs/Architecture.md:9-190](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/docs/Architecture.md#L9-L190) |
| `webrtc/` | Собственная data-only WebRTC implementation и старые samples | [docs/Architecture.md:105-116](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/docs/Architecture.md#L105-L116) |
| `meshreset/` | Отдельная Windows reset/remove utility | [meshreset/main.c:335-390](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshreset/main.c#L335-L390) |
| `.github/workflows/` | Linux/Windows build и CodeQL | См. раздел «Тесты и CI» |

Основные языки — C и JavaScript; Windows KVM содержит C++, а WebRTC samples — C# и HTML. Состав C/C++/JS sources задаётся root makefile ([makefile:175-192](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/makefile#L175-L192)). Подмодулей нет; third-party code и готовые библиотеки хранятся непосредственно в репозитории.

## Система сборки, toolchains и артефакты

### POSIX

Основная система сборки — GNU make. Комментарии перечисляют необходимые X11/XTest/Xext/XRandR/JPEG packages, Xcode command-line tools и особенности FreeBSD/Alpine ([makefile:1-31](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/makefile#L1-L31), [makefile:79-93](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/makefile#L79-L93)). Матрица `ARCHID` включает Linux x86/x64/ARM/ARM64/MIPS/MUSL/OpenWRT/RISC-V/Synology, macOS x64/ARM64 и BSD ([makefile:96-150](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/makefile#L96-L150)).

Компилятор по умолчанию — GCC/совместимый C compiler; используются C99, pthread, util, math и платформенные библиотеки ([makefile:198-227](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/makefile#L198-L227)). Cross-toolchain paths частично заданы локальными или относительными путями, поэтому не поставляются как самодостаточная среда. Основные targets — `linux`, `macos`, `pi`, `freebsd`, `openbsd` ([makefile:792-815](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/makefile#L792-L815)); ожидаемые артефакты называются `meshagent_<ARCHNAME>`, а release flow сохраняет unstripped debug copy и strip-ит основной файл ([makefile:609-617](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/makefile#L609-L617), [makefile:714-766](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/makefile#L714-L766)).

### Windows

Актуальная solution — `MeshAgent-2022.sln` с console и service projects ([MeshAgent-2022.sln:2-29](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/MeshAgent-2022.sln#L2-L29)). Нужен Windows SDK 10; проекты используют v142 для части обычных Win32-конфигураций и преимущественно v143 для остальных ([meshservice/MeshService-2022.vcxproj:53-125](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/MeshService-2022.vcxproj#L53-L125)).

Windows targets: x86, x64 и ARM64, с Release/Debug и OpenSSL/NoOpenSSL variants. Service outputs — `MeshService.exe`, `MeshService64.exe`, `MeshServiceARM64.exe` ([meshservice/MeshService-2022.vcxproj:246-284](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/MeshService-2022.vcxproj#L246-L284)); console outputs — `MeshConsole.exe`, `MeshConsole64.exe`, `MeshConsoleARM64.exe` ([meshconsole/MeshConsole-2022.vcxproj:371-470](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshconsole/MeshConsole-2022.vcxproj#L371-L470)). Legacy `MeshAgent.sln` рассчитан на Visual Studio 2015 и только x86/x64 ([MeshAgent.sln:2-23](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/MeshAgent.sln#L2-L23)).

Windows-проекты используют static CRT и статические OpenSSL/JPEG archives в соответствующих configurations ([meshconsole/MeshConsole-2022.vcxproj:773-806](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshconsole/MeshConsole-2022.vcxproj#L773-L806)). POSIX build также по умолчанию выбирает vendored static OpenSSL; `DYNAMICTLS=1` переключает на system OpenSSL ([makefile:594-607](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/makefile#L594-L607)).

### Важные побочные эффекты сборки

Сборка не запускалась. Статический анализ обнаружил, что даже обработка root makefile перезаписывает tracked `microscript/ILibDuktape_Commit.h` ([makefile:680-684](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/makefile#L680-L684)). Visual Studio prebuild делает то же и может перезаписать `MeshService.rc` ([meshconsole/MeshConsole-2022.vcxproj:486-494](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshconsole/MeshConsole-2022.vcxproj#L486-L494), [meshservice/MeshService-2022.vcxproj:315-322](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/MeshService-2022.vcxproj#L315-L322), [meshservice/prebuild.ps1:79-90](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/prebuild.ps1#L79-L90)). Поэтому будущую baseline-сборку следует выполнять в отдельном disposable worktree и проверять provenance generated files.

Текущие generated commit/date fields не соответствуют audited HEAD ([microscript/ILibDuktape_Commit.h:1-3](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microscript/ILibDuktape_Commit.h#L1-L3), [meshservice/MeshService.rc:87-90](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/MeshService.rc#L87-L90)). Build metadata включает `__DATE__`/`__TIME__`, поэтому по умолчанию сборка не bit-for-bit reproducible ([meshconsole/main.c:253-265](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshconsole/main.c#L253-L265)).

## Зависимости

| Компонент | Подтверждённое состояние | Риск |
|---|---|---|
| Duktape | 2.6.0 ([microscript/duktape.h:173-188](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microscript/duktape.h#L173-L188)) | Embedded runtime; обновление затрагивает весь JS API |
| zlib | 1.2.11 ([meshcore/zlib/zlib.h:35-40](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/zlib/zlib.h#L35-L40)) | Включается исходниками |
| OpenSSL | Header сообщает 1.1.1f ([openssl/include/openssl/opensslv.h:42-43](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/openssl/include/openssl/opensslv.h#L42-L43)); state file указывает другие variants ([openssl/libstatic/linux/state.txt:1-3](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/openssl/libstatic/linux/state.txt#L1-L3)) | Версия конкретного prebuilt archive неоднозначна |
| libjpeg-turbo | Header сообщает 1.5.2 ([lib-jpeg-turbo/includes/jconfig.h:5-11](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/lib-jpeg-turbo/includes/jconfig.h#L5-L11)); build notes говорят 1.4.2 ([makefile:38-46](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/makefile#L38-L46)) | Требуется provenance audit |
| Microstack/WebRTC | Собственная реализация C | Очень высокая стоимость security/support |
| OS APIs | Win32/SCM/CryptoAPI, pthread/forkpty, X11/XTest, macOS CoreGraphics/TCC | Сильные платформенные различия |

В репозитории нет package-manager manifest/lock и SBOM. Third-party source и prebuilt archives находятся в checkout, а часть системных libraries ожидается от ОС.

## Точки входа и жизненный цикл

### Точки входа

- Console/Unix target: `wmain()` или `main()` в [meshconsole/main.c:88-94](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshconsole/main.c#L88-L94). После обработки CLI создаются, запускаются и уничтожаются host objects ([meshconsole/main.c:125-430](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshconsole/main.c#L125-L430)).
- Windows service target: `wmain()` в [meshservice/ServiceMain.c:441-465](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/ServiceMain.c#L441-L465). Обычный service path идёт через `StartServiceCtrlDispatcher` в `ServiceMain` ([meshservice/ServiceMain.c:271-344](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/ServiceMain.c#L271-L344)).
- Общие lifecycle functions: `MeshAgent_Create()` ([meshcore/agentcore.c:4509-4589](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4509-L4589)), `MeshAgent_Start()` ([meshcore/agentcore.c:6073-6324](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L6073-L6324)), `MeshAgent_Destroy()` и `MeshAgent_Stop()` ([meshcore/agentcore.c:6328-6353](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L6328-L6353)).

CLI включает console/connect, service install/uninstall/start/stop/restart/state, identity information/reset и update helper modes ([meshservice/ServiceMain.c:546-673](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/ServiceMain.c#L546-L673), [meshservice/ServiceMain.c:783-849](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/ServiceMain.c#L783-L849), [meshservice/ServiceMain.c:917-937](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/ServiceMain.c#L917-L937)). UAC elevation использует штатный `ShellExecuteEx` с verb `runas` ([meshservice/ServiceMain.c:175-203](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/ServiceMain.c#L175-L203)).

### Последовательность запуска

1. Процесс входит через console `main/wmain` или Windows service `wmain`/SCM callback.
2. `MeshAgent_Create` создаёт Microstack chain, pipe manager, capability state и hostname ([meshcore/agentcore.c:4509-4589](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4509-L4589)).
3. `MeshAgent_Start` определяет executable path, вычисляет self SHA-384, настраивает рабочий каталог/logging, инициализирует OpenSSL и выбирает script либо normal agent mode ([meshcore/agentcore.c:6073-6188](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L6073-L6188)).
4. Agent mode открывает adjacent datastore, применяет CLI cached settings и импортирует `.mshx`, `.msh`, legacy либо embedded configuration ([meshcore/agentcore.c:4821-4902](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4821-L4902)).
5. Определяются service mode и платформенные параметры; загружается либо создаётся certificate identity ([meshcore/agentcore.c:5055-5192](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L5055-L5192)).
6. Создаётся HTTPS/WebSocket client, загружается сохранённый CoreModule, после чего запускается `ILibStartChain` ([meshcore/agentcore.c:5343-5350](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L5343-L5350), [meshcore/agentcore.c:5415-5486](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L5415-L5486), [meshcore/agentcore.c:6172-6185](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L6172-L6185)).
7. `MeshServer_Connect`/`MeshServer_ConnectEx` выбирают server URL, proxy, DNS address, `ServerID`/`MeshID` и открывают TLS/WebSocket ([meshcore/agentcore.c:3837-4206](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3837-L4206), [meshcore/agentcore.c:4268-4356](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4268-L4356)).
8. После HTTP 101 выполняется дополнительный challenge/signature handshake внутри WebSocket ([meshcore/agentcore.c:2863-3045](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2863-L3045), [meshcore/agentcore.c:3624-3673](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3624-L3673)).
9. Агент отправляет AuthInfo с version/platform, `MeshID`, capabilities и hostname; ранее сохранённая identity позволяет серверу сопоставить устройство ([meshcore/agentcore.c:2653-2724](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2653-L2724)).
10. Сервер при необходимости передаёт CoreModule; агент ожидает команды в event loop, обслуживает keepalive и отдельные feature sessions.
11. При разрыве выполняется backoff/reconnect; при stop/shutdown chain останавливается, ресурсы освобождаются, а pending update при необходимости применяется ([meshcore/agentcore.c:4268-4356](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4268-L4356), [meshcore/agentcore.c:6328-6353](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L6328-L6353)).

### Завершение, сигналы, потоки и дочерние процессы

Windows SCM `STOP`/`SHUTDOWN` переводит службу в pending state и вызывает `MeshAgent_Stop`; console mode обрабатывает Ctrl-C/Ctrl-Break ([meshservice/ServiceMain.c:205-216](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/ServiceMain.c#L205-L216), [meshservice/ServiceMain.c:401-414](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/ServiceMain.c#L401-L414)). POSIX ScriptContainer устанавливает SIGTERM/SIGCHLD handlers, а service host превращает SIGTERM в `serviceStop` ([microscript/ILibDuktape_ScriptContainer.c:2865-2978](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microscript/ILibDuktape_ScriptContainer.c#L2865-L2978), [modules/service-host.js:171-180](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/service-host.js#L171-L180)).

Вспомогательные процессы используются для KVM, terminal/PTY, service update и isolated ScriptContainer sessions. Windows process pipes создают reader/wait threads, POSIX использует `fork`, `vfork` и `forkpty` ([microstack/ILibProcessPipe.c:598-928](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/ILibProcessPipe.c#L598-L928), [microscript/ILibDuktape_ScriptContainer.c:4153-4200](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microscript/ILibDuktape_ScriptContainer.c#L4153-L4200)).

## Конфигурация агента

### Источники и приоритет

Публично документированный `.msh` имеет формат `key=value`, поддерживает comments и перечисляет основные поля ([readme.md:24-64](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/readme.md#L24-L64)). `importSettings()` игнорирует comment lines, удаляет пустые значения, декодирует значения с `0x` как binary и сохраняет остальные как strings в SimpleDataStore ([meshcore/agentcore.c:4433-4497](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4433-L4497)).

По умолчанию datastore лежит рядом с executable как `.db`; затем применяются CLI `--key=value`, adjacent `.mshx`, `.msh`, legacy names и embedded trailer ([meshcore/agentcore.c:4821-4902](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4821-L4902)). Embedded configuration хранится в trailer executable с GUID и length; код умеет извлечь её в adjacent `.msh` ([meshcore/agentcore.c:4375-4424](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4375-L4424)). `configUsesCWD` переключает базовый путь с executable directory на текущий каталог процесса ([meshcore/agentcore.c:6138-6150](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L6138-L6150)).

### Основные поля

| Поле/настройка | Роль и обработка |
|---|---|
| `MeshServer` | Один URL либо comma-separated URLs; стартовый index выбирается случайно, следующие attempts циклически меняют URL ([meshcore/agentcore.c:3864-3913](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3864-L3913)) |
| `MeshID` | Binary group identity длиной 32 или 48 bytes; включается в AuthInfo ([meshcore/agentcore.c:4116-4119](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4116-L4119), [meshcore/agentcore.c:2653-2671](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2653-L2671)) |
| `ServerID` | Pinned public-key hash server identity; выбирается согласованно с URL и проверяется во втором handshake ([meshcore/agentcore.c:4077-4114](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4077-L4114), [meshcore/agentcore.c:2957-3025](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2957-L3025)) |
| `agentName` | При наличии отправляется отдельным JSON message перед binary AuthInfo; hostname остаётся в AuthInfo ([meshcore/agentcore.c:2653-2712](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2653-L2712)) |
| `WebProxy` | Явный proxy; иначе Windows может получить system proxy ([meshcore/agentcore.c:3992-4015](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3992-L4015)) |
| `ignoreProxyFile` | Запрещает import adjacent `.proxy`, stored `WebProxy` и system proxy для control channel; это agent-side no-proxy switch ([meshcore/agentcore.c:3992-4015](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3992-L4015), [meshcore/agentcore.c:5204-5223](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L5204-L5223)) |
| `validateWebCert` | Включает обычную проверку outer TLS certificate chain; по умолчанию trust привязывается вторичным WebSocket handshake ([meshcore/agentcore.c:4359-4371](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4359-L4371)) |
| Update fields | `disableUpdate`, `forceUpdate`, `noUpdateCoreModule` и related options перечислены в config keys ([meshcore/agentcore.h:275-301](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.h#L275-L301)) |
| Service fields | `meshServiceName`, `displayName`, `description`, `companyName`, `target`, `installPath`; Windows default name — `Mesh Agent` ([modules/agent-installer.js:113-116](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/agent-installer.js#L113-L116), [modules/agent-installer.js:204-246](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/agent-installer.js#L204-L246), [meshcore/agentcore.c:5069-5076](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L5069-L5076)) |

`agentNoProxy` не найден как MeshAgent config key; agent-side source подтверждает только `ignoreProxyFile`, а связь с server-side option вынесена ниже как bounded inference. `agentAliasDNS` также не найден как MeshAgent field; агент получает уже сформированный hostname внутри `MeshServer` и не знает происхождение alias ([meshcore/agentcore.c:3864-4017](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3864-L4017)). Это важно для совместимости: будущий клиент должен понимать фактические поля `.msh`, а не server-side имена настроек.

Аудит не читал `.msh`, `.db`, registry values или certificate material установленного пользовательского агента.

## Сетевой стек

### Формирование адреса и TCP

`MeshServer_ConnectEx()` читает `MeshServer`, выбирает URL, применяет proxy policy, разбирает URI, валидирует `ServerID`/`MeshID`, формирует HTTP GET/Host/User-Agent и добавляет WebSocket headers ([meshcore/agentcore.c:3837-4206](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3837-L4206)). Путь `/agent.ashx` не зашит как независимая константа: он приходит как path части `MeshServer` и становится HTTP GET target ([meshcore/agentcore.c:4125-4142](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4125-L4142)).

На direct/no-proxy path URI parser получает output для одного resolved server sockaddr. При активном proxy этот output равен `NULL`: TCP endpoint выбирается для proxy, а remote hostname передаётся proxy-протоколу ([meshcore/agentcore.c:3992-4017](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3992-L4017)). Web client передаёт выбранный remote endpoint одним sockaddr в `ILibAsyncSocket_ConnectTo`; async socket создаёт AF_INET либо AF_INET6 TCP socket, включает `SO_KEEPALIVE`, переводит его в nonblocking mode и вызывает один `connect()` для этого адреса ([microstack/ILibWebClient.c:2298-2362](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/ILibWebClient.c#L2298-L2362), [microstack/ILibAsyncSocket.c:886-1019](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/ILibAsyncSocket.c#L886-L1019)).

### TLS и WebSocket

URI parser распознаёт `wss` как TLS, поддерживает bracketed IPv6 literals и hostname resolution ([microstack/ILibParsers.c:6913-7052](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/ILibParsers.c#L6913-L7052)). WebSocket v13 headers добавляются web client helper, после чего pipeline request получает TLS mode и SNI с исходным hostname ([microstack/ILibWebClient.c:3791-3810](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/ILibWebClient.c#L3791-L3810), [meshcore/agentcore.c:4152-4163](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4152-L4163)).

Outer TLS PKI validation по умолчанию не является окончательным trust decision: `ValidateMeshServer` допускает соединение, а identity проверяется дополнительным handshake внутри WebSocket; `validateWebCert` меняет это поведение на обычный `preverify_ok` ([meshcore/agentcore.c:4359-4371](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4359-L4371)). Удаление этого вторичного pinning либо подмена его обычным HTTPS login нарушит protocol compatibility и security model.

### Proxy и no-proxy

Если `ignoreProxyFile` отсутствует, агент использует stored `WebProxy` либо Windows system proxy. При proxy failure код может повторить соединение напрямую ([meshcore/agentcore.c:3992-4015](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3992-L4015), [meshcore/agentcore.c:4165-4197](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4165-L4197)). Adjacent `.proxy` импортируется только без `ignoreProxyFile` ([meshcore/agentcore.c:5204-5223](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L5204-L5223)).

`proxy-helper.js` умеет читать Windows `ProxyOverride`, но C control-channel вызывает `getProxy()` и не показывает прямого вызова per-host `ignoreProxy()` ([modules/proxy-helper.js:492-505](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/proxy-helper.js#L492-L505), [modules/proxy-helper.js:632-645](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/proxy-helper.js#L632-L645), [meshcore/agentcore.c:405-423](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L405-L423)). Поэтому применение `ProxyOverride` именно к control channel статическим анализом не подтверждено.

### Reconnect, timeout и keepalive

При первом входе в `MeshServer_Connect` retry seed устанавливается в диапазоне 500–2000 ms, но соединение вызывается сразу. При следующем scheduled retry delay выбирается между текущим seed и примерно удвоенным значением; дальнейший backoff имеет cap 4–6 minutes. Успешная отправка AgentInfo сбрасывает retry state ([meshcore/agentcore.c:4268-4356](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4268-L4356), [meshcore/agentcore.c:2711-2724](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2711-L2724)). Pending connect имеет 20-second timer, callback которого может вызвать `ConnectEx` непосредственно; network change назначает отдельный короткий reconnect ([meshcore/agentcore.c:3777-3794](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3777-L3794), [meshcore/agentcore.c:4154-4158](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4154-L4158), [meshcore/agentcore.c:4630-4667](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4630-L4667)).

Application keepalive по умолчанию использует 120-second idle timeout, отправляет WebSocket Ping и ждёт Pong 5 seconds; отсутствие Pong приводит к disconnect/reconnect ([meshcore/agentcore.c:100](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L100), [meshcore/agentcore.c:3501-3546](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3501-L3546), [meshcore/agentcore.c:3577-3601](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3577-L3601)).

## IPv6 and DNS fallback analysis

### Подтверждённый путь кода

1. На direct/no-proxy path `MeshServer_ConnectEx` передаёт `ILibParseUri` один `sockaddr_in6` output object; при `useproxy != 0` передаётся `NULL`, поэтому server hostname не резолвится этим локальным path ([meshcore/agentcore.c:3992-4017](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3992-L4017)).
2. На direct path URI parser не нормализует и не удаляет trailing dot hostname; для ненумерического IPv4 текста он вызывает resolver ([microstack/ILibParsers.c:6981-7052](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/ILibParsers.c#L6981-L7052)).
3. Макрос `ILibResolveEx` жёстко вызывает расширенный resolver с `count=1` ([microstack/ILibParsers.h:1570-1574](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/ILibParsers.h#L1570-L1574)).
4. На Windows resolver вызывает `GetAddrInfoW` с `AF_UNSPEC`, `SOCK_STREAM`, `IPPROTO_TCP`, проходит результаты в системном порядке, но при capacity 1 копирует только первый IPv4/IPv6 result ([microstack/ILibParsers.c:10861-10934](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/ILibParsers.c#L10861-L10934)).
5. На direct path web client и async socket получают один server sockaddr и выполняют один `connect()`; Happy Eyeballs и перебора второго DNS address внутри этой попытки нет. При proxy path этот вывод относится к соединению с proxy endpoint, а разрешение remote hostname может выполняться proxy ([microstack/ILibWebClient.c:2298-2362](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/ILibWebClient.c#L2298-L2362), [microstack/ILibAsyncSocket.c:886-1019](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/ILibAsyncSocket.c#L886-L1019)).
6. Числовой `127.0.0.1` успешно разбирается как AF_INET literal и не требует DNS lookup ([microstack/ILibParsers.c:7038-7051](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/ILibParsers.c#L7038-L7051)).
7. При DNS error имеется fallback только к одному ранее кэшированному sockaddr. Список альтернативных DNS addresses не сохраняется ([meshcore/agentcore.c:4035-4071](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4035-L4071)).

### Вывод по baseline-гипотезе

Для прямого соединения без proxy гипотеза «конкретная версия MeshAgent могла использовать только первый DNS-result без успешного IPv6→IPv4 fallback» **подтверждается кодом в части first-result-only и отсутствия intra-attempt fallback**. Если Windows вернул для `localhost.` сначала `::1`, а MeshCentral слушал только `127.0.0.1`, direct attempt направляется только к `::1`. При активном proxy source не подтверждает локальное разрешение server hostname этим path.

Порядок `::1` → `127.0.0.1` **не задаётся MeshAgent** и зависит от Windows resolver/runtime. Поэтому утверждение, что `localhost.` в конкретном baseline фактически разрешился именно в таком порядке, остаётся гипотезой, поддержанной наблюдением «numeric IPv4 устранил проблему», но не доказанной packet trace. На direct path повторный reconnect снова выполняет resolve, но явного обхода оставшихся результатов одной DNS-выдачи нет ([meshcore/agentcore.c:3992-4017](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3992-L4017), [meshcore/agentcore.c:4268-4356](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4268-L4356)).

Ранее установленный baseline build соответствует commit `62b206e0b485b296e8a73a6547cef02bbf5a2d62`. Он был просмотрен только через `git show`, без checkout. В нём resolver также получает capacity 1, вызывает `GetAddrInfoW(AF_UNSPEC)` и сохраняет первый result ([microstack/ILibParsers.h:1570-1574 @ 62b206e](https://github.com/Ylianst/MeshAgent/blob/62b206e0b485b296e8a73a6547cef02bbf5a2d62/microstack/ILibParsers.h#L1570-L1574), [microstack/ILibParsers.c:10854-10927 @ 62b206e](https://github.com/Ylianst/MeshAgent/blob/62b206e0b485b296e8a73a6547cef02bbf5a2d62/microstack/ILibParsers.c#L10854-L10927), [microstack/ILibAsyncSocket.c:886-1019 @ 62b206e](https://github.com/Ylianst/MeshAgent/blob/62b206e0b485b296e8a73a6547cef02bbf5a2d62/microstack/ILibAsyncSocket.c#L886-L1019)). Следовательно, анализ применим не только к текущему upstream HEAD, но и к версии baseline.

Proxy-гипотеза остаётся неподтверждённой: успешный IPv4-тест проводился при сохранённом no-proxy параметре и не был изолированным A/B тестом только proxy. System proxy при предыдущих экспериментах не менялся.

## TLS, handshake и идентичность устройства

### Identity

Агент создаёт один или два certificates в зависимости от platform/path. Windows certificate-store path может создать root identity certificate и отдельный TLS certificate, сохранив `SelfNodeTlsCert`; OpenSSL fallback сохраняет `SelfNodeCert`, а generation отдельного TLS certificate в inspected path отключён и `selftlscert` очищается ([meshcore/agentcore.c:2161-2212](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2161-L2212), [meshcore/agentcore.c:2216-2284](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2216-L2284)). `nocertstore` принудительно выбирает OpenSSL path ([meshcore/agentcore.h:294](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.h#L294), [meshcore/agentcore.c:4809-4817](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4809-L4817)).

NodeID — SHA-384 digest публичного ключа identity certificate ([microstack/ILibCrypto.c:898-911](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/ILibCrypto.c#L898-L911), [meshcore/agentcore.c:2394-2398](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2394-L2398)). Архитектурная документация прямо указывает, что сервер вычисляет этот identifier после проверки подписанного proof агента ([docs/Architecture.md:16-41](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/docs/Architecture.md#L16-L41)). Он, certificate/private-key state и datastore сохраняют identity между перезапусками. Утрата или регенерация этого материала, явный reset identity либо некоторые MAC-check reset paths могут привести к новому NodeID и новому устройству; `skipmaccheck` отключает MAC-triggered reset ([meshcore/agentcore.c:5118-5192](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L5118-L5192)).

`MeshID` выбирает device group, `ServerID` pin-ит server identity, а NodeID представляет конкретную agent identity. Эти роли нельзя смешивать.

### Handshake

После WebSocket open агент очищает auth state, отправляет configured `ServerID`, вычисляет hash outer TLS peer certificate, генерирует nonce и отправляет AuthRequest ([meshcore/agentcore.c:3624-3673](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3624-L3673)).

Далее:

1. На server AuthRequest агент сверяет заявленный TLS cert hash с реальным peer certificate.
2. Агент подписывает identity private key конструкцию из server web hash, server nonce и agent nonce и отправляет identity certificate с signature ([meshcore/agentcore.c:2863-2955](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2863-L2955)).
3. На AuthVerify агент сверяет public-key hash server identity certificate с configured `ServerID`, проверяет server signature и только затем отправляет AuthInfo ([meshcore/agentcore.c:2957-3025](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2957-L3025)).
4. AuthConfirm завершает двустороннее состояние authentication ([meshcore/agentcore.c:3027-3040](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3027-L3040)).
5. AuthInfo сообщает agent version/platform, `MeshID`, capabilities и hostname; после подписанного proof сервер вычисляет public-key-derived NodeID для распознавания identity ([meshcore/agentcore.c:2653-2724](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2653-L2724), [docs/Architecture.md:22-27](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/docs/Architecture.md#L22-L27)).

Сетевые packet structures и command identifiers заданы в native headers/structures ([meshcore/agentcore.c:152-207](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L152-L207)). Для совместимого агента недостаточно «открыть WebSocket»: нужно воспроизвести byte layout, byte order, hashes, nonce/signature sequence, auth state transitions и capability semantics.

Windows signed binary может дополнительно содержать Authenticode Opus lock: модуль извлекает hostname и server identity из signed metadata, а connection code применяет DNS/ID locks ([modules/win-authenticode-opus.js:29-153](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/win-authenticode-opus.js#L29-L153), [meshcore/agentcore.c:4022-4032](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4022-L4032), [meshcore/agentcore.c:4281-4304](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4281-L4304)). Активен ли такой lock в установленном пользовательском binary, не проверялось.

## Функциональные модули

В колонке «канал» отражён подтверждённый архитектурный уровень. Agent-side orchestration/enforcement ожидаются в отсутствующем CoreModule, server-side authentication/token/permission path — в MeshCentral; точное распределение production rights, consent и relay policy этим checkout не определяется и не приписывается native primitives.

| Функция | Основной файл и точка входа | Канал/зависимости/платформы | Оценка повторной реализации |
|---|---|---|---|
| Device Details / базовая регистрация | `MeshServer_SendAgentInfo()` ([meshcore/agentcore.c:2653-2724](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2653-L2724)); native system info ([meshcore/meshinfo.c:467-620](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/meshinfo.c#L467-L620)) | Control WebSocket/AuthInfo; cross-platform native | Базовый набор — средняя; полный parity — высокая |
| Inventory | `identifiers.js`, Windows/Linux/macOS branches ([modules/identifiers.js:66-192](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/identifiers.js#L66-L192), [modules/identifiers.js:525-871](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/identifiers.js#L525-L871)); SMBIOS ([modules/smbios.js:34-359](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/smbios.js#L34-L359)) | CoreModule orchestration; WMI, `/sys`, dmidecode, ioreg/sysctl/system_profiler | Высокая |
| Devices, sessions, monitors и volumes | Windows SetupAPI ([modules/DeviceManager.js:121-354](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/DeviceManager.js#L121-L354)); cross-platform user sessions ([modules/user-sessions.js:75-1492](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/user-sessions.js#L75-L1492)); monitor information ([modules/monitor-info.js:104-964](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/monitor-info.js#L104-L964)); Windows volumes ([modules/win-volumes.js:33-63](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/win-volumes.js#L33-L63)) | SetupAPI/WMI, X11, OS session APIs; platform coverage различается | Высокая |
| Process management | `enumerateProcesses/getProcessInfo` ([modules/process-manager.js:33-393](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/process-manager.js#L33-L393)) | CoreModule; Toolhelp/WMI, `/proc`, `ps`; privilege boundary | Высокая |
| Service management | Windows manager/control ([modules/service-manager.js:616-948](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/service-manager.js#L616-L948)); cross-platform install paths ([modules/service-manager.js:2249-2994](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/service-manager.js#L2249-L2994)) | CoreModule; SCM, systemd/init/upstart/procd, launchd | Очень высокая |
| Terminal | Windows ConPTY ([modules/win-virtual-terminal.js:23-237](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/win-virtual-terminal.js#L23-L237)); legacy console ([modules/win-terminal.js:49-721](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/win-terminal.js#L49-L721)); POSIX child process/PTTY ([microscript/ILibDuktape_ChildProcess.c:479-603](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microscript/ILibDuktape_ChildProcess.c#L479-L603), [microstack/ILibProcessPipe.c:772-889](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/ILibProcessPipe.c#L772-L889)) | Отдельный relay session, production dispatcher в CoreModule; ConPTY/Win32/forkpty | Очень высокая |
| Files | Native `fs` binding: streams, directory, metadata, rename/unlink/copy ([microscript/ILibDuktape_fs.c:1105-1504](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microscript/ILibDuktape_fs.c#L1105-L1504), [microscript/ILibDuktape_fs.c:2256-2729](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microscript/ILibDuktape_fs.c#L2256-L2729)) | Отдельный relay session; точное разделение path/ACL/symlink/race checks между server, CoreModule, native binding и ОС не подтверждено | Высокая/очень высокая |
| Desktop | Native entry `getRemoteDesktopStream` ([meshcore/agentcore.c:1223-1414](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L1223-L1414), [meshcore/agentcore.c:2012](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2012)); Windows ([meshcore/KVM/Windows/kvm.c:939-1456](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/KVM/Windows/kvm.c#L939-L1456)); Linux ([meshcore/KVM/Linux/linux_kvm.c:1548-1712](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/KVM/Linux/linux_kvm.c#L1548-L1712)); macOS ([meshcore/KVM/MacOS/mac_kvm.c:846-1082](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/KVM/MacOS/mac_kvm.c#L846-L1082)) | Отдельный relay; capture/input/compression, user-session child, X11/TCC | Критически высокая |
| Clipboard | Platform dispatch и child/session handling ([modules/clipboard.js:121-239](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/clipboard.js#L121-L239), [modules/clipboard.js:245-681](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/clipboard.js#L245-L681)) | CoreModule policy; User32, X11/xclip, macOS bridge | Высокая |
| Tunnel/relay | Control plane и отдельные relay sessions описаны в архитектуре ([docs/Architecture.md:88-126](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/docs/Architecture.md#L88-L126)); WebRTC Duktape API ([microscript/ILibDuktape_WebRTC.c:119-250](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microscript/ILibDuktape_WebRTC.c#L119-L250), [microscript/ILibDuktape_WebRTC.c:397-647](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microscript/ILibDuktape_WebRTC.c#L397-L647)) | Сессия начинается через relay WebSocket; после negotiation data path может перейти на WebRTC, relay остаётся для lifecycle; exact dispatcher отсутствует | Критически высокая |
| Logging | Agent log API/file и configurable limit ([meshcore/agentcore.c:1881-1885](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L1881-L1885), [meshcore/agentcore.c:2004-2005](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2004-L2005), [meshcore/agentcore.c:4904-4911](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4904-L4911), [meshcore/agentcore.c:6153](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L6153)); parser ([modules/util-agentlog.js:25-221](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/util-agentlog.js#L25-L221)); remote implementation ([microstack/ILibRemoteLogging.c:143-685](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/ILibRemoteLogging.c#L143-L685)) | Local file + remote logging; focused search не нашёл собственного Windows Event Log source registration | Средняя |
| Agent update | Hash response, block transfer, SHA-384 verification и apply ([meshcore/agentcore.c:3266-3498](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3266-L3498), [meshcore/agentcore.c:2727-2844](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2727-L2844)) | Authenticated control channel; privileged replace/restart | Критически высокая |

Session multiplexing реализовано не как подтверждённый единый generic multiplex protocol, а как control WebSocket плюс отдельные per-session relay WebSockets. Optional WebRTC negotiation проходит через relay; при успехе data path переключается, но relay WebSocket остаётся открытым для session lifecycle ([docs/Architecture.md:88-126](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/docs/Architecture.md#L88-L126)). Более точный protocol audit требует совместного анализа server-side CoreModule и relay code MeshCentral.

Desktop имеет существенные platform constraints: inspected Linux path отклоняет Xwayland и ожидает Xorg/Xauthority ([meshcore/agentcore.c:1373-1397](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L1373-L1397)); macOS path отдельно проверяет screen-capture permission и использует per-user helper/LaunchAgent ([meshcore/KVM/MacOS/mac_kvm.c:960-1051](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/KVM/MacOS/mac_kvm.c#L960-L1051), [meshcore/KVM/MacOS/mac_kvm.c:1153-1159](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/KVM/MacOS/mac_kvm.c#L1153-L1159)). Это не переносимые детали, которые можно заменить единым capture adapter без отдельной platform design.

## Windows service

### Установка и состояние

Installer по умолчанию задаёт service name `Mesh Agent`, target `MeshAgent`, display name равным name, description `<name> background service` и `AUTO_START` ([modules/agent-installer.js:158-303](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/agent-installer.js#L158-L303)). Имена параметризуются и потому compiled strings в `ServiceMain.c` не являются единственным источником фактического display name.

Windows install path также вызывает регистрацию службы для Safe Mode with Networking и создаёт enabled inbound UDP firewall rule для WebRTC на Public/Private/Domain profiles ([modules/agent-installer.js:292-296](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/agent-installer.js#L292-L296), [modules/agent-installer.js:356-374](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/agent-installer.js#L356-L374)). Это подтверждённые side effects штатного installer code; в ходе аудита они не выполнялись.

На Windows service manager:

- выбирает Program Files-based install folder и копирует binary ([modules/service-manager.js:2286-2321](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/service-manager.js#L2286-L2321));
- отображает `AUTO_START` как automatic и вызывает `CreateServiceW` с own-process и legacy interactive-service flags ([modules/service-manager.js:2339-2356](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/service-manager.js#L2339-L2356));
- передаёт null account/password в `CreateServiceW`; вывод о default LocalSystem следует из семантики Windows SCM и является inference, а не строковой константой агента;
- настраивает description, failure restart actions, SCM metadata и Add/Remove Programs key ([modules/service-manager.js:2360-2442](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/service-manager.js#L2360-L2442));
- предоставляет status/start/stop/restart и path/workdir accessors ([modules/service-manager.js:709-948](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/service-manager.js#L709-L948)).

Windows native startup дополнительно меняет CWD на executable directory ([meshcore/agentcore.c:6160-6167](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L6160-L6167)). Рядом с binary обычно находятся `.db`, `.msh`/embedded config, optional `.proxy`, `.log` и временный update file ([meshcore/agentcore.c:4833-4834](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4833-L4834), [meshcore/agentcore.c:4887-4899](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4887-L4899), [meshcore/agentcore.c:5197-5224](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L5197-L5224), [meshcore/agentcore.c:6153](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L6153)).

### Registry, UAC, IPC и child processes

SCM configuration находится под `HKLM\SYSTEM\CurrentControlSet\Services\<name>`, а uninstall metadata — под Windows uninstall key; эти paths используются service manager ([modules/service-manager.js:2394-2442](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/service-manager.js#L2394-L2442)). Runtime также записывает диагностическую информацию под `Software\Open Source\<service>`; service mode использует HKLM, console mode — HKCU ([meshcore/agentcore.c:5238-5337](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L5238-L5337)).

UAC выполняется штатным `runas`, без обхода ([meshservice/ServiceMain.c:175-203](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshservice/ServiceMain.c#L175-L203)). KVM запускает child copy агента и связывается pipes; terminal и isolated ScriptContainer также используют child processes и named pipes/process pipes ([meshcore/KVM/Windows/kvm.c:1346-1400](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/KVM/Windows/kvm.c#L1346-L1400), [microstack/ILibProcessPipe.c:598-717](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/microstack/ILibProcessPipe.c#L598-L717)).

Focused source search не обнаружил прямой регистрации/записи собственного Windows Event Log source через `RegisterEventSource`/`ReportEvent`. SCM может создавать собственные системные события, но это не реализация логирования агентом.

### Update, подпись и uninstall

Native update передаётся блоками через authenticated control channel, проверяется SHA-384, записывается во временный file и применяется platform helper после остановки chain ([meshcore/agentcore.c:3340-3498](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L3340-L3498), [meshcore/agentcore.c:2727-2844](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L2727-L2844)). Windows helper останавливает службу, заменяет binary и запускает службу снова ([modules/agent-installer.js:768-910](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/agent-installer.js#L768-L910)).

`signcheck_verifysign()` содержит WinVerifyTrust и version/architecture checks, но repo-wide static search не обнаружил его call site ([meshcore/signcheck.c:45-127](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/signcheck.c#L45-L127)). Нельзя на основании наличия этой функции утверждать, что каждый native update проходит Authenticode verification. Подтверждённая trust chain inspected path — authenticated channel плюс SHA-384 ожидаемого binary.

Uninstall останавливает/удаляет service, binary и associated metadata согласно options; full uninstall имеет отдельный path ([modules/agent-installer.js:398-700](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/agent-installer.js#L398-L700), [modules/service-manager.js:2996-3033](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/modules/service-manager.js#L2996-L3033)). Ни install, update, uninstall, firewall helper, Safe Mode handling, ни service management в ходе аудита не запускались.

## Тесты и CI

Встроенный self-test вызывается через `MeshServer_Agent_SelfTest()` и `modules/agent-selftest.js`; standalone/IPC modes и coverage документированы в README ([meshcore/agentcore.c:4260-4265](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/meshcore/agentcore.c#L4260-L4265), [readme.md:116-194](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/readme.md#L116-L194)).

`test/self-test.js` — не pure unit test, а stateful integration harness, который может устанавливать тестовый агент и требует agent binaries из MeshCentral ([docs/testing/UnitTests.md:23-43](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/docs/testing/UnitTests.md#L23-L43), [test/self-test.js:1967-1988](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/test/self-test.js#L1967-L1988)). Он покрывает tunnel, console, CPU/process/services, clipboard, WebRTC, Files, Terminal и KVM ([docs/testing/UnitTests.md:47-115](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/docs/testing/UnitTests.md#L47-L115)).

Другие инструменты:

- `test/update-test.js` поднимает HTTPS test server и по умолчанию устанавливает test service ([test/update-test.js:135-143](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/test/update-test.js#L135-L143), [test/update-test.js:680-701](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/test/update-test.js#L680-L701)).
- Release checklist описывает native/recovery update, manual UI/service/resource и leak/Valgrind checks ([docs/testing/ReleaseCheckList.md:35-95](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/docs/testing/ReleaseCheckList.md#L35-L95)).
- `test/leaktest.js` — интерактивный leak harness.
- `test/authtest.js` извлекает X11 auth token и не подходит для логируемой CI-среды ([test/authtest.js:1-24](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/test/authtest.js#L1-L24)).

CI:

- Linux workflow запускается на push, собирает несколько x86/ARM ARCHID и публикует `meshagent_*` ([.github/workflows/linux-build.yml:1-49](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/.github/workflows/linux-build.yml#L1-L49)).
- Windows workflow запускает MSBuild `MeshAgent-2022.sln` для Release x86/x64/ARM64 и публикует `Release/*.exe` ([.github/workflows/windows-build.yml:5-26](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/.github/workflows/windows-build.yml#L5-L26)).
- CodeQL анализирует JavaScript/C++ по push/PR/schedule и для C++ строит только Linux ARCHID 6 без KVM ([.github/workflows/codeql-analysis.yml:3-12](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/.github/workflows/codeql-analysis.yml#L3-L12), [.github/workflows/codeql-analysis.yml:27-52](https://github.com/Ylianst/MeshAgent/blob/ebff7fb7b3e0de9b13b3c7402e015f22e70fab72/.github/workflows/codeql-analysis.yml#L27-L52)).

Ни один workflow не запускает integration self-test, update test или leak test. CI подтверждает сборку и static analysis, но не end-to-end protocol compatibility.

## Confirmed findings

Ниже только выводы, непосредственно подтверждённые audited source:

- Нативный host построен вокруг C/Microstack/Duktape; production CoreModule загружается с MeshCentral и отсутствует в репозитории агента.
- Console и Windows service используют общие `MeshAgent_Create/Start/Stop/Destroy`.
- Конфигурация поступает из datastore, CLI cached settings, `.mshx`/`.msh`, legacy или embedded trailer.
- `MeshServer` определяет URL и path, включая `/agent.ashx`; `MeshID`, `ServerID` и identity-derived NodeID имеют разные роли.
- Outer TLS/WebSocket дополняется обязательным для штатной модели challenge/signature handshake.
- NodeID является SHA-384 публичного ключа identity certificate; identity material сохраняется в datastore и на Windows может использовать certificate store.
- DNS resolver запрашивает AF_UNSPEC, но вызывается с capacity 1; сохраняется только первый result.
- На direct/no-proxy path для server hostname в одну попытку передаётся один sockaddr и выполняется один `connect()`; Happy Eyeballs и same-attempt fallback к следующему server DNS result отсутствуют.
- Numeric `127.0.0.1` обходит DNS path.
- Reconnect использует randomized exponential-like backoff; control-channel keepalive использует Ping/Pong.
- `ignoreProxyFile` — agent-side no-proxy control; `agentNoProxy` и `agentAliasDNS` не являются найденными MeshAgent fields.
- Terminal, Files и Desktop используют native primitives; высокоуровневая orchestration ожидается в server-delivered CoreModule, но точное разделение authorization, consent и relay policy с MeshCentral server этим репозиторием не определяется.
- Windows installer по умолчанию создаёт auto-start service `Mesh Agent`; SCM stop штатно вызывает `MeshAgent_Stop`.
- Update path использует authenticated channel и SHA-384; отдельная `signcheck_verifysign()` присутствует, но её call site не найден.
- Build и prebuild scripts способны менять tracked provenance/resource files.
- Существующая CI не выполняет end-to-end functional tests.

## Hypotheses requiring runtime verification

- Возвращает ли конкретная Windows-конфигурация для `localhost.` сначала `::1`, а затем `127.0.0.1`. Source определяет обработку порядка, но не сам порядок ОС.
- Было ли неуспешное baseline TCP-соединение фактически направлено к `::1`. Packet/socket trace не выполнялся.
- Был ли system proxy или explicit proxy реально выбран в неуспешной baseline attempt. Proxy-гипотеза не подтверждена, системный proxy не изменялся.
- Был ли Authenticode DNS/ID lock активен в конкретном установленном binary. Binary и его embedded data не исследовались.
- Точное server-side сопоставление NodeID с существующей database record и все registration policy checks: это требует анализа MeshCentral server code и runtime trace.
- Точные JSON command schemas, access-right bits, user consent policy и per-feature relay negotiation: production CoreModule в этом репозитории отсутствует.
- Фактические версии и provenance каждого vendored OpenSSL/libjpeg static archive: метаданные внутри checkout противоречат друг другу.
- Полная Windows update signature policy: найденный WinVerifyTrust helper не имеет найденного call site в inspected tree.
- Реальное поведение Desktop на современных Wayland/TCC/multi-session systems требует platform runtime tests.

## Assumptions and bounded inferences

- Default LocalSystem account для Windows service — ограниченный вывод из null account/password в `CreateServiceW` и стандартной семантики SCM, а не hard-coded account name в MeshAgent.
- Связь server-side `agentNoProxy` с agent-side `ignoreProxyFile` основана на прежнем baseline и упаковке агента; в MeshAgent checkout найден только `ignoreProxyFile`.
- Соответствие прежнего baseline build commit `62b206e0b485b296e8a73a6547cef02bbf5a2d62` опирается на зафиксированное build metadata; DNS-path самого commit проверен отдельно через `git show`.
- Возможность минимального Online-only агента — архитектурная оценка scope, а не доказательство готовой совместимой реализации.
- Полный production-контракт не считается документированным: без server-side MeshCentral и присылаемого CoreModule нельзя окончательно зафиксировать command schemas, rights, consent и relay negotiation.

## Риски собственного C++-агента

| Категория | Компоненты | Причина |
|---|---|---|
| 1. Можно повторно реализовать относительно просто | Парсинг ограниченного `.msh`; basic OS/hostname/version info; structured local logging; retry timer после готового transport | Небольшая поверхность при строгих тестовых fixtures |
| 2. Требует значительного исследования | Proxy/PAC/no-proxy; расширенный inventory; process listing; platform packaging; capability negotiation; server CoreModule command schemas | Platform divergence и отсутствующая production orchestration |
| 3. Высокорисковая часть | Handshake/crypto; identity/key storage; privileged command execution; Windows service; update/rollback; Terminal/Files security; Desktop; relay/WebRTC | Ошибка создаёт authentication bypass, identity loss, privilege escalation или несовместимость |
| 4. Разумнее временно оставить оригинальной | Original MeshAgent для Desktop/Terminal/Files; updater; Windows installer/service integration; cross-platform inventory; WebRTC | Уже проверено upstream, очень высокая стоимость parity |
| 5. Нельзя менять без нарушения совместимости | WebSocket binary framing/command IDs/byte order; nonce/signature handshake; NodeID derivation; `MeshID`/`ServerID` semantics; AuthInfo layout; CoreModule delivery contract; `/agent.ashx` endpoint semantics | MeshCentral ожидает точный protocol contract |

Главные конкретные риски:

1. Несовместимый handshake либо неверная canonicalization/hash/signature sequence.
2. Потеря device identity из-за неправильного хранения/миграции private keys и certificates.
3. Создание duplicate devices при изменении NodeID derivation.
4. Неправильное разделение `MeshID`, `ServerID` и NodeID.
5. Небезопасный update без atomic replace, rollback, hash/signature и service recovery.
6. Terminal/Files/Desktop с правами service account и недостаточным authorization/consent.
7. Path traversal, symlink/race и ACL errors в Files.
8. Input injection, screen/session privacy и TCC/X11/Wayland ограничения Desktop.
9. ConPTY/PTY/session impersonation и child-process cleanup в Terminal.
10. Reconnect storm, stale DNS, proxy/PAC и IPv4/IPv6 corner cases.
11. LocalSystem service, IPC ACL, named-pipe spoofing и UAC/install boundary.
12. Binary signing, reputation/SmartScreen и supply-chain provenance.
13. Third-party license/notice completeness.
14. Protocol drift между будущими MeshCentral releases и forked agent.

## Minimal compatible agent scope

Ниже приведён **кандидат на минимальный Online-only scope**, а не доказанно достаточный контракт. Его достаточность должна быть подтверждена server-side аудитом MeshCentral/CoreModule и conformance tests; даже такой кандидат не является «простым WebSocket-клиентом»:

1. Безопасно прочитать ограниченный набор public configuration: `MeshServer`, `MeshID`, `ServerID`, optional agent name и explicit proxy/no-proxy.
2. Сгенерировать long-lived asymmetric identity, хранить private key с OS-appropriate protection и стабильно вычислять совместимый NodeID.
3. Разрешить hostname с корректным IPv4/IPv6 fallback или Happy Eyeballs, respecting explicit proxy policy.
4. Установить TLS connection, сформировать WebSocket v13 request к path из `MeshServer` и корректно обработать upgrade/close.
5. Реализовать точные binary packet layouts и secondary authentication: TLS certificate hash, nonces, agent signature, server certificate/public-key pinning по `ServerID`, signature verification и AuthConfirm state.
6. Отправить совместимый AuthInfo с правильным agent/platform identifier, version, `MeshID`, capabilities и hostname.
7. Поддерживать только честно заявленный минимальный capabilities set; не рекламировать Terminal/Files/Desktop до их реализации.
8. Реализовать Ping/Pong, disconnect detection, bounded randomized reconnect и network-change retry.
9. Сохранить identity и конфигурацию между перезапусками так, чтобы сервер видел то же устройство.
10. Уточнить обязательные post-auth messages и state transitions, включая accepted capability bitset, CoreModule/hash/update commands и применимость AgentCommitDate, HostInfo и AgentTag.
11. Предоставить безопасный read-only basic inventory message только после фиксации точной server-side schema.
12. Иметь protocol conformance tests против локального MeshCentral и negative tests для wrong `ServerID`, signature, malformed frames и identity persistence.

Из минимального scope сознательно исключаются: service install/update, remote shell, Files, Desktop, clipboard, process/service control, relay/WebRTC и auto-update. Их нельзя добавлять до отдельной threat model и authorization/consent design.

## Recommended implementation order

1. **Заморозить baseline.** Закрепить MeshCentral commit, MeshAgent commit, agent protocol packet captures в изолированной лаборатории и test certificates без production secrets.
2. **Составить protocol specification.** Совместно изучить MeshCentral `meshagent.js`, agent handshake structures и server-delivered CoreModule; формализовать packet layouts, endianness, state machine и error handling.
3. **Создать offline conformance fixtures.** Parser tests для `.msh`, URI, DNS result lists, WebSocket frames и binary handshake messages без сети и private production values.
4. **Identity prototype.** Реализовать generation/storage/NodeID derivation и restart-persistence tests; отдельно test migration/backup/duplicate-device scenarios.
5. **Transport-only prototype.** TLS + WebSocket + strict `ServerID` verification, но без регистрации и команд.
6. **Authentication prototype.** Реализовать secondary handshake и negative crypto tests; провести независимый security review.
7. **Online-only milestone.** AuthInfo, honest minimal capabilities, keepalive/reconnect, read-only basic inventory. Проверить появление Online на отдельной test group.
8. **Windows service packaging.** Только после стабильного console agent: least-privilege account analysis, secure IPC ACLs, clean start/stop/recovery; без updater.
9. **Read-only operations.** Расширять inventory/details маленькими platform-specific adapters.
10. **Files или Terminal — отдельными проектами.** Начать с threat model, explicit authorization/consent, sandboxing и audit log. Не реализовывать оба одновременно.
11. **Desktop последним.** Сначала Windows-only proof-of-concept в лаборатории; затем platform/session/TCC/Wayland design.
12. **Update/signing/release pipeline последним инфраструктурным этапом.** Reproducible build, SBOM, signed artifacts, atomic rollback и license bundle.
13. **Compatibility matrix.** На каждом milestone тестировать pinned и следующую MeshCentral versions; не принимать upstream updates без повторного protocol diff.

## Рекомендации

- На ближайшем этапе оставить официальный MeshAgent единственным operational agent.
- Следующий исследовательский шаг — server-side protocol audit MeshCentral и CoreModule boundary, а не написание C++ кода.
- Не копировать upstream service/update/Desktop code выборочно без license/provenance inventory и threat model.
- Для будущей сборки использовать отдельный disposable worktree: build scripts меняют tracked metadata.
- Перед любым распространением восстановить полный license/notice bundle и составить SBOM.
- Зафиксировать DNS regression test с двумя адресами, first-result failure и успешным fallback; эта проблема должна быть закрыта в собственной реализации с самого начала.
- Не извлекать production MeshID, ServerID, private keys или installed `.msh/.db` для разработки; использовать отдельные лабораторные fixtures.

## Ограничения аудита

- Выполнен только статический анализ указанного commit.
- MeshCentral и установленная служба MeshAgent не запускались.
- Бинарники не запускались, не разбирались и не проверялись на цифровую подпись.
- Build toolchains, SDK и зависимости не устанавливались; build/test commands не выполнялись.
- Конфигурация, registry data, certificates и datastore установленного агента не читались.
- Packet trace не выполнялся.
- Production CoreModule отсутствует в MeshAgent checkout, поэтому его команды и authorization policy не считаются подтверждёнными этим аудитом.
