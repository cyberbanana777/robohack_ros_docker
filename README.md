# Образы для хакатона: ROS2 на Jetson Nano

Базовые Docker-образы для команд хакатона с собаками Unitree Go1: на выбор ROS2 Foxy или Humble. Каждый образ содержит ROS2, CycloneDDS 0.10, OpenCV 4.1.1 и UnitreeCameraSDK. Кода участников в образах нет: свой `src/` команды монтируют сами и собирают внутри контейнера. Внутри контейнера команды работают под обычным пользователем с `sudo`, в удобном терминале: цветной prompt с меткой контейнера, баннер при входе, автодополнение `ros2` и `colcon`, цветные логи нод и подсветка синтаксиса в nano.

Целевое железо: оригинальный Jetson Nano, L4T 32.7.1 (JetPack 4.6.x, Ubuntu 18.04).

Настройка самого Jetson и ноутбука организатора (рантайм nvidia, маршрутизация, NAT) описана в [README_setup_technician.md](README_setup_technician.md).

## Два образа

| | Foxy | Humble |
|---|---|---|
| Dockerfile | `Dockerfile.foxy` | `Dockerfile.humble` |
| Образ | `unitree-hackathon:foxy` | `unitree-hackathon:humble` |
| Базовый образ | `dustynv/ros:foxy-ros-base-l4t-r32.7.1` | `dustynv/ros:humble-ros-base-l4t-r32.7.1` |
| Ubuntu в контейнере | 18.04 | 18.04 |
| Как получен ROS | Собран из исходников (jetson-containers) | Собран из исходников (jetson-containers) |
| CycloneDDS 0.10 | Собирается из исходников поверх Foxy | Штатный (собирается, только если его нет в базе) |
| Статус | Проверен на хакатонном железе | Новый, собирается по рецепту Foxy |

Оба образа построены на jetson-containers под L4T 32.7.1, запускаются с рантаймом `nvidia` (CUDA доступна) и устроены одинаково: OpenCV 4.1.1 в `/opt/opencv-4.1.1` (под ABI UnitreeCameraSDK), UnitreeCameraSDK в `/opt/UnitreecameraSDK`, рабочее пространство `/developer_ws`, инструменты (`nano`, `vim`, `neovim`, `ranger`, `mc`, `v4l-utils`, `colcon`), пользователь `ros` и общие для обоих образов настройки окружения и терминала в `ros2_custom_config_setup/`.

Отличия Humble от Foxy минимальные: другой базовый образ, отключённая Python-обёртка OpenCV (драйверу она не нужна) и шаг с CycloneDDS. В Humble CycloneDDS 0.10 штатный, поэтому отдельно он собирается, только если его не оказалось в базовом образе.

Образа с Jazzy нет: под JetPack 4 его можно запустить только на Ubuntu 24.04 без CUDA, с отдельным рецептом сборки OpenCV и требованиями к версии Docker, и для хакатона это лишний риск.

## Структура проекта

```
.
├── Dockerfile.foxy                  # образ Foxy
├── Dockerfile.humble                # образ Humble
├── docker-compose.yml               # запуск: по сервису на образ, каждый в своём профиле
├── .env                             # какой образ запускать (COMPOSE_PROFILES=foxy)
├── .dockerignore                    # что не отправлять в контекст сборки
├── build_image.sh                   # сборка образа
├── save_image.sh                    # сохранение образа в .tar
├── load_image.sh                    # загрузка образа из .tar
├── ros2_custom_config_setup/        # монтируется в контейнер, всё кроме entrypoint правится без пересборки
│   ├── setup.sh                     # окружение ROS и DDS, общий для обоих образов
│   ├── bashrc.sh                    # настройки терминала: автодополнение, метка в prompt, баннер
│   ├── banner.sh                    # баннер при входе (и сообщение от организаторов)
│   ├── cyclonedds.xml               # конфиг CycloneDDS 0.10
│   └── ros_entrypoint.sh            # вшивается в образ, не редактировать
├── src/                             # код (драйвер камеры), монтируется в /developer_ws/src
├── files_to_container/              # произвольные файлы, монтируются в /files_to_container
├── README_setup_technician.md       # настройка Jetson и ноутбука организатора
├── cyclonedds_config_host.sh        # окружение DDS на ноутбуке организатора
└── autosource_ros2_env_host.sh      # подключение этого окружения в ~/.bashrc ноутбука
```

## Подготовка Jetson

Делается один раз на каждом Jetson, на котором собираются или запускаются образы.

### Docker и nvidia-рантайм

Настройка `/etc/docker/daemon.json` с рантаймом `nvidia` описана в [README_setup_technician.md](README_setup_technician.md).

### Docker Compose

На JetPack 4 плагина Compose v2 обычно нет. Ставится одним бинарником:

```bash
mkdir -p ~/.docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-aarch64 \
  -o ~/.docker/cli-plugins/docker-compose
chmod +x ~/.docker/cli-plugins/docker-compose
docker compose version
```

Если запускаешь Docker через `sudo`, положи плагин в `/usr/local/lib/docker/cli-plugins/` вместо `~/.docker/cli-plugins/`.

Compose используется только для запуска. Собирать образы надёжнее скриптом `build_image.sh` (см. ниже): новым версиям Compose для сборки нужен свежий плагин Buildx, которого на JetPack 4 тоже нет.

### Swap

Сборка OpenCV на Nano с 4 ГБ памяти может упасть из-за нехватки памяти. Перед сборкой стоит добавить swap:

```bash
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
```

### Ядро под видео

Чтобы большие сообщения (кадры видео) не терялись, увеличь буферы сокетов и параметры сборки фрагментов. Это настраивается на хосте Jetson, а не в контейнере:

```bash
sudo tee /etc/sysctl.d/60-ros2-dds.conf > /dev/null <<'EOF'
net.core.rmem_max=2147483647
net.core.wmem_max=2147483647
net.ipv4.ipfrag_time=3
net.ipv4.ipfrag_high_thresh=134217728
EOF
sudo sysctl --system
```

После этого в `ros2_custom_config_setup/cyclonedds.xml` можно раскомментировать блок `<SocketReceiveBufferSize min="10MB"/>`. Те же настройки нужны и на ноутбуках, которые принимают видео.

## Сборка образов

```bash
./build_image.sh foxy
./build_image.sh humble
```

Скрипт собирает `Dockerfile.<distro>` в образ `unitree-hackathon:<distro>`. UID и GID пользователя в контейнере берутся от того, кто запускает скрипт (на Jetson это обычно 1000). Переопределить можно так: `USER_UID=1001 USER_GID=1001 ./build_image.sh foxy`. Для сборки нужен интернет: исходники OpenCV, UnitreeCameraSDK и CycloneDDS скачиваются с GitHub.

Самый долгий шаг — сборка OpenCV 4.1.1: на Nano это от 40 до 90 минут на каждый образ. CycloneDDS в образе Foxy добавляет ещё несколько минут. Шаги кэшируются, поэтому повторная сборка после правок в конце Dockerfile (терминал, пользователь, entrypoint) идёт быстро: OpenCV и CycloneDDS при этом не пересобираются.

## Перенос образов на другие Jetson

Собирать образ на каждом Jetson не нужно: соберите один раз и разнесите файлом.

```bash
./save_image.sh foxy     # создаёт unitree-hackathon-foxy.tar
# скопировать .tar на другой Jetson (scp, флешка), туда же положить папку проекта
./load_image.sh foxy     # загружает образ из unitree-hackathon-foxy.tar
```

Файлы `.tar` исключены из контекста сборки (`.dockerignore`), поэтому их можно хранить прямо в папке проекта.

## Запуск

### Выбор образа

Какой образ запускать, задаётся в `.env`:

```bash
COMPOSE_PROFILES=foxy      # или humble
```

Каждый сервис в `docker-compose.yml` лежит в своём профиле, поэтому без этой строки `docker compose up` не запустит ничего, а с ней запустит только выбранный образ. Это защищает Nano от случайного запуска обоих контейнеров сразу.

### Команды

Все команды выполняются из папки проекта.

| Действие | Команда |
|---|---|
| Запустить контейнер в фоне | `docker compose up -d` |
| Зайти в контейнер | `docker compose exec foxy bash` (имя сервиса = имя образа) |
| Зайти в контейнер без compose | `docker exec -it hackathon-foxy bash` |
| Зайти в контейнер под root | `docker compose exec -u root foxy bash` |
| Посмотреть, запущен ли контейнер | `docker compose ps` |
| Остановить и удалить контейнер | `docker compose down` |
| Переключиться на другой образ | `docker compose down`, поменять `COMPOSE_PROFILES` в `.env`, `docker compose up -d` |

Без `.env` профиль можно указать прямо в команде: `docker compose --profile humble up -d`. Тогда и для остановки нужен тот же профиль: `docker compose --profile humble down`.

Контейнеры запускаются с `restart: unless-stopped`: после перезагрузки Jetson контейнер поднимается сам, если перед этим его не остановили вручную через `docker compose stop` или `down`. Это закрывает пункт про автозапуск из README техника.

Команда `docker exec -it hackathon-<distro> bash` не зависит от папки проекта и профилей, её удобно использовать для автоматического входа в контейнер при подключении по SSH.

### Что монтируется

| На хосте (относительно папки проекта) | В контейнере |
|---|---|
| `src/` | `/developer_ws/src` |
| `files_to_container/` | `/files_to_container` |
| `ros2_custom_config_setup/` | `/ros2_custom_config_setup` |
| `/dev` | `/dev` (камеры и USB, вместе с `privileged`) |

Раньше `ros2_custom_config_setup` монтировался из `$HOME/ros-docker/ros2_custom_config_setup`. Теперь путь относительный: если проект лежит в `~/ros-docker`, это та же папка.

Контейнер работает с `network_mode: host`, поэтому ноды в нём видны ноутбуку и другим машинам в сети без проброса портов.

## Терминал и пользователь

### Пользователь

Внутри контейнера работает пользователь `ros` с `sudo` без пароля. Его UID и GID совпадают с пользователем Jetson, который собирал образ, поэтому файлы, созданные в примонтированном `src/`, принадлежат этому пользователю на хосте, а не root. Пользователь состоит в группах `video`, `dialout` и `plugdev`: это нужно для доступа к камерам, последовательным портам и USB-устройствам.

Если нужен root: `sudo -i` внутри контейнера или вход сразу под root через `docker compose exec -u root foxy bash`.

Учти, что контейнер запущен с `privileged` и примонтированным `/dev`, а у пользователя есть `sudo`. Это значит, что изнутри контейнера можно получить права root на самом Jetson. Отдельный профиль `student` без `sudo` на хосте от этого не защищает: изоляция на уровне контейнера здесь условная, и это нормально для учебного стенда, где Jetson не жалко перепрошить.

### Что настроено в терминале

- **Метка в prompt:** `[docker:foxy] ros@jetson:/developer_ws$`. Из-за `network_mode: host` у контейнера тот же hostname, что у Jetson, и без метки легко перепутать, где ты находишься.
- **Баннер при входе:** версия ROS, реализация DDS и версия CycloneDDS, `ROS_DOMAIN_ID`, найден ли конфиг DDS (зелёный путь или красное «файл не найден») и собрано ли рабочее пространство.
- **Сообщение от организаторов:** если заполнить переменную `MESSAGE` в начале `ros2_custom_config_setup/banner.sh`, оно будет выводиться под баннером. Удобно для пароля Wi-Fi, канала помощи или правил.
- **Автодополнение по Tab** для bash, `ros2` (команды, пакеты, топики, ноды) и `colcon`.
- **Цветные логи нод** по уровню (WARN жёлтым, ERROR красным), в том числе при `ros2 launch`: `RCUTILS_COLORIZED_OUTPUT=1` в `setup.sh`.
- **nano** с подсветкой синтаксиса и номерами строк.

Всё, кроме подсветки в nano и цветного prompt, задаётся в `bashrc.sh`, `banner.sh` и `setup.sh` на хосте. Правки применяются в новых терминалах без пересборки образа.

## Окружение и DDS

При старте контейнера (через entrypoint) и в каждом новом терминале (через `bashrc.sh`) подключается `ros2_custom_config_setup/setup.sh`. Он общий для обоих образов и сам определяет, какой ROS в контейнере:

1. Окружение ROS: `/opt/ros/<distro>/install/setup.bash`.
2. CycloneDDS 0.10 из `/opt/cyclonedds_ws`, если он собирался отдельно (всегда в Foxy, в Humble только если его не было в базовом образе).
3. `RCUTILS_COLORIZED_OUTPUT=1`, `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` и `CYCLONEDDS_URI` на `cyclonedds.xml`, если файл есть.
4. Рабочее пространство `/developer_ws/install/setup.bash`, если оно уже собрано.

`setup.sh` лежит на хосте, поэтому его можно править без пересборки образа. Изменения применяются в новых терминалах (`docker compose exec ...`), а для entrypoint — после перезапуска контейнера.

### Конфиг CycloneDDS

`ros2_custom_config_setup/cyclonedds.xml` общий для обоих образов: в обоих стоит CycloneDDS 0.10, синтаксис конфига одинаковый. По умолчанию CycloneDDS сам выбирает интерфейс. В файле есть закомментированные примеры: явный выбор интерфейсов (например, `l4tbr0` для USB-сети с ноутбуком), большой буфер приёма для видео, обнаружение по unicast и отладочный вывод. Изменения применяются при следующем запуске ноды. После правки выполни `ros2 daemon stop`, чтобы демон тоже перечитал конфиг.

Если файл удалить или переименовать, CycloneDDS будет работать с настройками по умолчанию.

### Совместимость между образами

В обоих образах одна версия CycloneDDS, поэтому на уровне DDS они совместимы. Но связь между разными дистрибутивами ROS2 (Foxy ↔ Humble) официально не поддерживается: простые топики со стандартными сообщениями обычно проходят, а сервисы, экшены и сообщения, чьё определение менялось между версиями, могут не работать. Для хакатона надёжнее, чтобы собака и ноутбук команды работали на одном дистрибутиве.

## Драйвер камеры

Драйвер `unitree_camera_driver` лежит в `src/` и собирается внутри любого из двух образов:

```bash
cd /developer_ws
colcon build --packages-select unitree_camera_driver
source install/setup.bash
ros2 launch unitree_camera_driver unitree_camera.launch.py device_node:=0
```

Драйвер проверен в образе Foxy. В Humble он собирается из тех же исходников, возможны предупреждения об устаревших функциях `image_transport`. Если что-то не соберётся, правки будут точечными.

Перед хакатоном стоит проверить камеру на каждом образе ещё до ROS: примеры SDK лежат в `/opt/UnitreecameraSDK/bin/`, например `./example_getRawFrame`.

## Частые проблемы

**Сборка OpenCV падает с `Killed` или `internal compiler error`.** Не хватило памяти. Добавь swap (см. «Подготовка Jetson»). Если не помогает, уменьши число потоков сборки: замени `make -j$(nproc)` на `make -j2` в соответствующем Dockerfile.

**Сборка зависает на «Sending build context to Docker daemon».** В папке проекта лежит что-то большое, не указанное в `.dockerignore`. Обычно это сохранённые образы с нестандартным именем: переименуй их в `*.tar` или вынеси из папки.

**`docker compose up -d` ничего не запускает.** Не задан профиль. Проверь `COMPOSE_PROFILES` в `.env` или укажи профиль явно: `docker compose --profile foxy up -d`.

**`unknown or invalid runtime name: nvidia`.** На этом Jetson не настроен nvidia-рантайм (см. README техника).

**Нода на CycloneDDS не запускается с ошибкой `failed to increase socket receive buffer size`.** В `cyclonedds.xml` включён `<SocketReceiveBufferSize>`, а ядро Jetson не настроено. Выполни настройку из раздела «Ядро под видео» или закомментируй этот блок обратно.

**Камера не открывается (`camera failed to open`) или `Permission denied` на `/dev/video*`.** Проверь, что камера видна: `v4l2-ctl --list-devices` внутри контейнера. Если устройство видно, но доступа нет, проверь группы пользователя командой `id`: в списке должна быть `video`. Если устройство не видно и на хосте, проблема в подключении камеры.

**При входе нет баннера и метки `[docker:...]`, не работает автодополнение.** Не примонтирована папка `ros2_custom_config_setup` (контейнер запущен не через compose или из другой папки) или в ней нет `bashrc.sh`. Проверь: `ls /ros2_custom_config_setup` внутри контейнера.

**Файлы в `src/` на хосте принадлежат не тому пользователю.** UID пользователя в образе не совпадает с владельцем папки на хосте. Пересобери образ от имени нужного пользователя или с явным `USER_UID`/`USER_GID` (см. «Сборка образов»). Уже созданные файлы можно вернуть себе: `sudo chown -R $USER:$USER src`.

**`ros2 topic list` зависает.** Демон `ros2` запущен со старыми настройками или завис. Выполни `ros2 daemon stop` или используй `ros2 topic list --no-daemon`.
