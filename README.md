# Удалённая отладка Go через VSCode

Содержимое данный репозитория предназначено для обеспечения по возможности прозрачной удалённой отладки Go приложений.

Удалённая отладка включает в себя:

- сборку приложения кросскомпилятором Go;
- загрузку приложения на целевую систему;
- запуск удалённой отладочной сессии при помощи отладчика Delve.

Все эти функции реализуются скриптами, написанными на простом `bash`. Кроме самой удалённой отладки скрипты позволяют автоматизировать некоторые второстепенные, но необходимые задачи, как то:

- загрузка вспомогательных файлов на целевую платформу (конфигурации, скриптов, программ и тд.);
- запуск и останов сервисов `systemd`, произвольных процессов;
- выполнение любых вспомогательных команд (например `wget` для включения специальных функций через HTTP);
- кеширование, сжатие, таким образом ускорение процесса загрузки данных по `ssh`.

Все скрипты и конфигурации находятся в стадии разработки (доработки) и могут быть кастомизированы/доработаны под конкретные условия и задачи.

---
## Установка VSCode

Существуют 2 варианта установки VSCode под RHEL, Fedora и CentOS. Первый - это установка соответствующего `snap` пакета. Второй - добавление `rpm` репозитория и установка из него. Предполагается, что VSCode должен обновляться и если в вашу систему не интегрированы инструменты для автоматического обновления snap, например, Discover, то в этом случае будет целесообразно устанавливать VSCode из `rpm`.

Итак, для установки VSCode из Snap Store достаточно выполнить:

```bash
sudo snap install code —classic
```

Установка VSCode из `rpm` пакета описана на странице [Установка VSCode](https://code.visualstudio.com/docs/setup/linux#_rhel-fedora-and-centos-based-distributions).

Добавление ключа и регистрация репозитория VSCode:


```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
```

Обновление списка пакетов и установка VSCode через `dnf`:

```bash
dnf check-update
sudo dnf install code
```

Так же можно использовать `yum`:

```bash
yum check-update
sudo yum install code
```

После установки в меню `Пуск` должен появиться пункт `Visual Studio Code`. Так же VSCode можно запустить из командной строки:

```bash
$ code --version
1.78.2
b3e4e68a0bc097f0ae7907b217c1119af9e03435
x64
```

---
## Установка расширений VSCode

Для корректной работы VSCode с Go, а так же, чтобы упростить себе жизнь, необходимо установить несколько расширений.

Процесс установки расширений единообразен. Для установки необходимо запустить VS Code Quick Open (Ctrl+P), вставить определённую команду `ext install` и нажать Enter.

#### Расширение Go Nightly [Link](https://marketplace.visualstudio.com/items?itemName=golang.go-nightly)

Расширение поддержи языка Go для VSCode. Целесообразно устанавливать именно основанной на `master` ночную сборку, т. к. в ней раньше всего появляются новые фичи.

```bash
ext install golang.go-nightly
```

После установки расширение предложит доустановить некоторый инструментарий Go. Со всеми его просьбами желательно согласиться.

#### Расширение Go Critic (customizable) [Link](https://marketplace.visualstudio.com/items?itemName=imgg.go-critic-imgg)

Еще один, пожалуй, *наиболее авторитетный* линтер для Go.

```bash
ext install imgg.go-critic-imgg
```

#### Расширение Tab-Indent Space-Align [Link](https://marketplace.visualstudio.com/items?itemName=j-zeppenfeld.tab-indent-space-align)

VSCode из коробки *не умеет* автоматическую идентацию текста (путает пробелы с табуляцией, неверно заполняет идентацию). Это расширение исправляет данное недоразумение.

```bash
ext install j-zeppenfeld.tab-indent-space-align
```

#### Расширение Command Variable [Link](https://marketplace.visualstudio.com/items?itemName=rioj7.command-variable)

Расширение, которое позволяет получать параметры конфигурации VSCode из внешних файлов. Расширение необходимо для автоматизации некоторых связанных с удалённой отладкой моментов.

```bash
ext install rioj7.command-variable
```

Можно сказать, что это минимально базовый набор расширений, который позволяет разрабатывать приложения на Go. Многие другие полезные расширения можно найти на [Visual Studio Marketplace](https://marketplace.visualstudio.com/).

---
## Предварительные требования

Удалённая отладка активно использует SSH соединение. Для того чтобы запускать SSH в неинтерактином режиме, используется утилита `sshpass`. Если не установлена в системе, следует установить:

```bash
sudo dnf install sshpass
```

Удалённая отладка предполагает кроссплатформенную сборку приложения Go и запуск полученного исполняемого файла на целевой платформе с архитектурой, как правило, отличной от архитектуры хоста (x86_64).

Итак, для сборки и отладки Go приложения понадобятся:

* кросскомпилятор `go`;
* отладчик `devle`.

Все эти инструменты будут получены из `buildroot’. Если компилятор `go` включен в процесс сборки безусловно, то для сборки дополнительного пакета с отладчиком `delve` необходимо внести изменения в конфигурацию пакетов `buildroot’.

Для этого в каталоге `"$BUILDROOT/external-ipcam/fragments"` необходимо создать файл с именем `"dbg.fragment"` и следующим содержимым:

```bash
BR2_PACKAGE_DELVE=y
BR2_PACKAGE_PPROF=y
```

В этот файл можно добавить любые необходимые настройки `buildroot`.

Необходимо включить новый фрагмент в конфигурацию `buildroot` и, если не собран, собрать buildroot полностью, либо дособрать пакет `delve`:

```bash
make ecam03_defconfig FRAGMENTS=dev:dm:dbg
# пересборка delve
make delve-rebuild
# полная сборка buildroot
make all
```

В результате сборки должны быть созданы исполняемые файлы:

```bash
GO="$BUILDROOT/buildroot/output/host/bin/go"
DLV="$BUILDROOT/buildroot/output/target/usr/bin/dlv"
```

Следует заметить, что компилятор `go` собирается под архитектуру хоста (x86_64), а отладчик `dlv` (delve) - под архитектуру целевой платформы.

Для сборки приложения кросс компилятор задействует менеджер пакетов Go. Менеджер пакетов автоматически скачивает все необходимые зависимости и устанавливает их, распределяя компоненты по каталогам. Менеджер пакетов Go ограничен границами `buildroot` (фактически, Go живет внутри buildroot). С этой точки зрения нам могут быть следующие переменные окружения Go:

```bash
BUILDROOT_HOSTDIR="$BUILDROOT/buildroot/output/host"
GOROOT="$BUILDROOT_HOSTDIR/lib/go"
GOPATH="$BUILDROOT_HOSTDIR/usr/share/go-path"
GOMODCACHE="$BUILDROOT_HOSTDIR/usr/share/go-path/pkg/mod"
GOTOOLDIR="$BUILDROOT_HOSTDIR/lib/go/pkg/tool/linux_arm64"
GOCACHE="$BUILDROOT_HOSTDIR/usr/share/go-cache"
```

Из-за того, что Go использует каталоги `buildroot` для хранения зависимостей, пакетов и кеша сборки, в процессе сборки в `buildroot` будет появляться некоторое количество неизвестных для `buildroot` файлов (например, имеющих неправильного с точки зрения `buildroot` владельца). Это не сломает сборку `buildroot`, но может привести к непредвиденным результатам. Поэтому: 

> **Настоятельно не рекомендуется использовать один и тот же buildroot для удалённой отладки и сборки образа либо обновлений для последующей загрузки на устройство.** 

Для удалённой отладки желательно использовать отдельно стоящий `buildroot`, который никак не участвует в процессе разработки.

---
## Подготовка проекта

Конфигурация проекта для среды VSCode находится в корне проекта, в каталоге с именем `".vscode"`. Конфигурация проекта сводится к замене либо созданию данного каталога.

Итак, прежде всего необходимо распаковать приложенный к данному документу архив либо склонировать [репозиторий проекта](https://bitbucket.org/proton-workspace/vscode-go-utils/):

```bash
git clone git@bitbucket.org:proton-workspace/vscode-go-utils.git
```

В итоге в `"vscode-go-utils"` получаем копию проекта со всеми необходимыми для удалённой отладки настройками VSCode и скриптами. Один и тот-же экземпляр `"vscode-go-utils"` может быть использован в нескольких проектах одновременно. Для этого в каждом из проектов нужно создать символьную ссылку с именем `".vscode"`:

```bash
ln -s "$PWD/vscode-go-utils/vscode" "$PROJECT_DIR/.vscode"
```

Далее, в файле `"vscode-go-utils/vscode/config.ini"` в переменную `TARGET_IPADDR` необходимо записать IP адрес целевого устройства, а также установить переменную `BUILDROOT_DIR` таким образом, чтобы она указывала на `buildroot` (а не на суперпроект) с собранными ранее инструментами Go (`go`, `dlv`).

```bash
TARGET_IPADDR=10.113.11.65
BUILDROOT_DIR="$BUILDROOT_SUPER/buildroot"
```

Где `$BUILDROOT_SUPER` - путь к суперпроекту. Переменная `BUILDROOT_DIR` необходима для получения путей к инструментам Go.

Назначение некоторых параметров в `"vscode-go-utils/vscode/config.ini"`:
`BUILDROOT_DIR` - переменная необходима для получения путей к инструментам Go.
`TARGET_USER` - имя пользователя SSH.
`TARGET_PASS` - пароль доступа по SSH.
`TARGET_IPPORT` - порт Delve, на котором запускается отладка.
`RUN_GO_VET` - запуск линтера `go vet` перед сборкой проекта.
`RUN_STATICCHECK` - запуск линтера `statickcheck` перед сборкой проекта.
`RUN_STATICCHECK_ALL` - включение pedantic mode в `statickcheck`.

На этом конфигурирование проекта можно считать завершённым. Все необходимые файлы конфигурации и скрипты находятся в каталоге проекта, в подкаталоге `".vscode"`.

---
## Удалённая отладка

В VSCode через меню «File/Open Folder» (Ctrl+K Ctrl+O) открываем проект (который содержит `".vscode"`). Если все установлено правильно, VSCode подхватит настройки проекта и попытается запустить инструменты Go из окружения `buildroot`. Т.к. в ранее собранном `buildroot` отсутствуют такие инструменты как линтеры, приложение автоматического форматирования кода и некоторые другие, VSCode (уже второй раз) предложит их загрузить и установить. Все загруженное будет установлено в `buildroot`. После установки можно приступать к, собственно, сборке проекта и его отладке.

Переходим к вкладке «Run and Debug» (Ctrl+Shift+D) и в выпадающем списке «RUN AND DEBUG» выбираем «Remote Deploy and Attach». Это одна из пользовательских конфигураций запуска, обявленная в файле `".vscode/launch.json"`.

Перед первым запуском необходимо выполнить полную сборку проекта. Открываем «VS Code Quick Run» (Ctrl+Shit+P) и выполняем команду `Go: Build Workspace` (Ctrl+B). Этот шаг необходимо выполнять каждый раз, когда начинаем работу с новым устройством и кроме самой сборки команда `Go: Build Workspace` выполняет:

* загрузку вспомогательных скриптов и отладчика delve;
* загрузку собранного исполняемого файла;
* загрузку/обновление файлов конфигурации (если нужно);
* включение features на отлаживаемом устройстве;
* принудительная остановка некоторых служб (onvifd).

> Для отладки не обязательно, чтобы на целевое устройство была установлена прошивка содержащая Delve - отладчик будет загружен на устройство автоматически.

Т.е. таким образом полная пересборка проекта так-же настраивает целевое устройство. Теоретически, все эти шаги можно выполнять непосредственно перед запуском отлаживаемого файла, но это несколько увеличивает и без того немалое время запуска. 

В панели OUTPUT VSCode появится текст с ходом выполнения сборки:

```
Starting building the current workspace at $PROJECTDIR
$PROJECTDIR>Finished running tool: $PROJECTDIR/.vscode/scripts/go.sh build
17/05/2023 20:01:28 [go] Building `cmd/onvifd/onvifd.go'
17/05/2023 20:01:28 [go] Installing to remote host `root@10.113.11.65'
17/05/2023 20:01:29 [go] Camera feature "videoanalytics" is set to "true".
17/05/2023 20:01:29 [go] Stopping 2 services: onvifd, onvifd-debug
17/05/2023 20:01:29 [go] Terminating 3 processes: dlv, onvifd, onvifd_debug
17/05/2023 20:01:29 [go] Removing 3 files: onvifd_debug, onvifd_debug.log, dlv.log
17/05/2023 20:01:29 [go] Uploading 7 files: dl, ds, onvifd-debug.service, onvifd_debug, dlv, onvifd.conf, users.toml
17/05/2023 20:01:33 [go] Total runtime: 4.9802s
```

Теперь необходимо открыть любой терминал (GNOME Terminal, Konsole). Так же можно воспользоваться терминалом встроенным в VSCode (но, как показала практика, это менее удобно). В терминале необходимо войти на устройство по SSH и запустить загруженный ранее скрипт отладки `dl` (Delve Loop):

```bash
$ ssh root@IP_ADDRESS
# dl
Starting Delve headless server loop in DAP mode. To stop use: $ ds
DAP server listening at: [::]:2345
```

В этот момент Delve ожидает входящего соединения на порту `2345`. Запускаем отладку в VSCode через «Run/Start Debugging» (F5). VSCode попробует собрать проект и одновременно загрузит собранный файл на целевое устройство. На вкладке «TERMINAL» появятся следующие сообщения:

```
17/05/2023 20:04:43 [launch-deploy-attach] Building & deploying `onvifd_debug' to remote host http://10.113.11.65
17/05/2023 20:04:43 [launch-deploy-attach] Total runtime: 0.4136s
 *  Terminal will be reused by tasks, press any key to close it. 
```

> Текст `http://10.113.11.65` распознается VSCode как гиперссылка и при его помощи можно быстро открыть браузер по IP адресу устройства.

После этого VSCode запустит удалённую отладку и переключится на вкладку «DEBUG CONSOLE». Но эта консоль останется пустой - Delve не умеет пробрасывать STDOUT/STDERR отлаживаемой программы на хостовую систему. Таким образом в открытом терминале (GNOME Terminal, Konsole) можно наблюдать, что приложение запустилось и даже что-то пишет в консоль:

```
Starting Delve headless server loop in DAP mode. To stop use: $ ds
DAP server listening at: [::]:2345
2023-05-18T08:09:39Z info layer=debugger launching process with args: [/usr/bin/onvifd_debug -settings /root/onvifd.settings]
2023/05/18 08:09:43 server.go:376: Starting server at 127.0.0.1:8899 ...
2023/05/18 08:09:43 operations.go:126: Starting discovery service
2023/05/18 08:09:44 server.go:779: Operation: Device.GetSystemDateAndTime
2023/05/18 08:09:44 server.go:779: Operation: Device.GetServiceCapabilities
2023/05/18 08:09:44 server.go:779: Operation: Device.GetSystemDateAndTime
2023/05/18 08:09:44 server.go:779: Operation: Device.GetServiceCapabilities
2023/05/18 08:09:44 server.go:779: Operation: Device.GetSystemDateAndTime
2023/05/18 08:09:44 server.go:775: Operation: Device.GetDeviceInformation: Unauthorized
```

На данном этапе с отладчиком можно работать так же, как будто приложение отлаживается локально: ставить точки останова, останавливать, выполнять пошагово, перезапускать, просматривать содержимое переменных.

---
## Известные проблемы

Не всегда все работает как задумано, а изредка даже так, как не задумано.

1. Иногда, после обновления исходного кода внешней программой, например, через `git fetch` в VSCode перестают работать точки останова. Пересборка/перезапуск приложения проблему не решает. В таких случаях помогает исключительно перезапуск VSCode.
2. В отладчике не всегда видно содержимое локальных переменных. Проблема связана с оптипизацие приложений Go и на данный момент не имеет решения. Проект собирается с флагами, которые запрещают оптимизацию и добавляют отладочную информацию — все в соответствии с рекомендациями документации Go. Единственный вариант посмотреть состояние таких переменных: выводить их значение через `log.Println`. Как правило, в этом случае Go перестаёт оптимизировать такую переменную и она становится видна и в отладчике.
3. В некоторых случаях после обновления прошивки отладка становится невозможна из за устаревания отпечатка в `$HOME/.ssh/known_hosts`. Лечится удалением соответствующей строки и повторным входом на устройство по SSH. Хоть скрипты отладки работают таким образом, что не добавляют отпечатки в `known_hosts`, но, как показала практика, уже добавленные в других SSH сессиях неправильные отпечатки могут приводить к невозможности установки соединения и запуска отладки.
4. Разночтения в `config.ini`. Хоть файл `config.ini` по сути является bash скриптом, этот же файл используется VSCode расширением Command Variable для получения IP адреса и номера порта. Проблема разночтения происходит если в `config.ini` несколько раз переопределяется `TARGET_IPADDR` либо `TARGET_IPPORT`. Bash использует последнее присвоенное значение, в то время как Command Variable - первое найденное.

---
## TODO

Для поддержки разных проектов Go необходимо вынести некоторые переменные в `config.ini`, а сам файл `config.ini` перенести из `.vscode` в корень проекта, назвав его, например, `vcsode_config.ini` (этот файл можно сделать опциональным).

Список внутренних переменных, которые хотелось бы видеть в составе `config.ini`: `TARGET_BUILD_LAUNCHER`, `TARGET_BUILD_GOFLAGS`, `TARGET_BUILD_LDFLAGS`, `TARGET_BIN_SOURCE`, `TARGET_BIN_DESTIN`, `TARGET_EXEC_ARGS`.

Так как для разработки на Go в основном используется VSCode, было бы неплохо внесение каталога `.vscode` и сопутствующих/промежуточных файлов в `.gitignore`.

Для упрощения разработки где-то в отдельном `.ini` файле можно вести список ASSET-ов и соответствующих им IP адресов, что должно упростить переключение между несколькими устройствами.
