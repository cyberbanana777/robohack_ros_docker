# === 1. Базовый образ ===
# Готовый образ из jetson-containers (ветка legacy!), под L4T 32.7.1 (JetPack 4.6.x) —
# это версия L4T оригинального Jetson Nano. Внутри уже есть ROS2 Foxy. OpenCV нужной
# версии (4.1.1, под ABI UnitreeCameraSDK) собираем сами ниже — на практике оказалось,
# что готового репозитория NVIDIA с версией 4.1.1 в этом образе нет.
FROM dustynv/ros:foxy-ros-base-l4t-r32.7.1

# === 1а. Фикс просроченного GPG-ключа репозитория ROS2 (packages.ros.org) ===
# Известный, задокументированный инцидент OSRF: старый подписывающий ключ
# (EXPKEYSIG F42ED6FBAB17C654) истёк по сроку действия. Из-за этого ЛЮБОЙ
# apt-get update в базовом образе падает целиком с "repository is not signed",
# даже не добираясь до установки твоих пакетов. Это не связано с нашим
# Dockerfile — чинится один раз, здесь, до всех остальных apt-операций.
#
# Шаг 1: временно разрешаем apt пропустить проверку подписи — но только
# чтобы поставить curl/gnupg, а они идут из обычных Ubuntu-репозиториев
# (не из ROS), так что по сути ничего непроверенного не используем.
RUN apt-get update -o Acquire::AllowInsecureRepositories=true && \
    apt-get install -y --no-install-recommends curl gnupg

# Шаг 2: подтягиваем АКТУАЛЬНЫЙ ключ прямо из репозитория rosdistro на GitHub.
#
# Важно: раньше здесь был вариант через "curl | gpg | tee" — если curl внутри
# такого конвейера тихо не скачивает файл (сеть, редирект, что угодно),
# ошибка никак не всплывает в обычном /bin/sh, и получается ПУСТОЙ, но
# "успешно" созданный keyring-файл. Поэтому здесь всё через промежуточный
# файл и явные проверки: curl -f упадёт с ошибкой, если сервер вернёт что-то
# не то, а "ls -la" в конце покажет размер итогового файла в логе сборки.
#
# Куда класть: сначала проверили cat /etc/apt/sources.list.d/*.list — там
# явно прописан signed-by=/usr/share/keyrings/ros-archive-keyring.gpg.
# При явном signed-by apt смотрит ТОЛЬКО туда, /etc/apt/trusted.gpg.d
# для этой записи полностью игнорируется — поэтому кладём новый ключ
# именно по этому пути, перезатирая старый истёкший файл.
RUN curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc -o /tmp/ros.asc && \
    rm -f /usr/share/keyrings/ros-archive-keyring.gpg && \
    gpg --batch --yes --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg /tmp/ros.asc && \
    rm -f /tmp/ros.asc && \
    ls -la /usr/share/keyrings/ros-archive-keyring.gpg

# Шаг 3: теперь обычный apt-get update должен проходить чисто, без флагов
RUN apt-get update

# === 2. Системные зависимости для сборки UnitreeCameraSDK ===
# git/cmake/build-essential — собрать SDK из исходников (готовых .deb пакетов нет).
# freeglut3-dev/libglu1-mesa-dev/libgl1-mesa-dev/libx11-dev — SDK требует OpenGL/GLUT/X11
# в CMakeLists для GUI point-cloud примеров; без них cmake упадёт на этапе find_package,
# даже если вы эти примеры не запускаете.
# gstreamer* — камеры отдают MJPEG, decode идёt через GStreamer-backend OpenCV.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git cmake build-essential pkg-config \
    freeglut3-dev libglu1-mesa-dev libgl1-mesa-dev libx11-dev \
    gstreamer1.0-tools gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav \
    && rm -rf /var/lib/apt/lists/*

# === 2а. Собираем OpenCV 4.1.1 из исходников (не через apt) ===
# Статические библиотеки UnitreeCameraSDK (libunitree_camera.a и др.) собраны
# под ABI OpenCV 4.1.1 — с более новыми версиями (4.5.x и новее) меняется
# внутренняя раскладка cv::Mat, и получается не ошибка сборки, а segfault
# в рантайме при первом обращении к кадру (это мы уже видели на практике).
#
# План "поставить штатную 4.1.1 через apt из репозитория NVIDIA" не сработал:
# в этом базовом образе нет подключённого репозитория NVIDIA Jetson вообще —
# только обычный Ubuntu bionic, а там лежит OpenCV 3.2 (слишком старый, SDK
# требует >=4). Поэтому собираем 4.1.1 сами, из исходников, в отдельный
# префикс /opt/opencv-4.1.1 — дольше по времени, но не зависит от того,
# какие внешние репозитории где подключены.
#
# WITH_CUDA=OFF — сознательно: SDK не требует CUDA-ускорения в самом OpenCV,
# а сборка с CUDA на Nano — это часы, а не минуты. WITH_GSTREAMER=ON —
# обязательно, документация SDK прямо требует "OpenCV >=4, Requires GStreamer".
RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg-dev libpng-dev libtiff5-dev \
    libavcodec-dev libavformat-dev libswscale-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    python3-dev python3-numpy \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --branch 4.1.1 --depth=1 https://github.com/opencv/opencv.git opencv-4.1.1-src

WORKDIR /opt/opencv-4.1.1-src
RUN mkdir build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/opt/opencv-4.1.1 \
      -DWITH_GSTREAMER=ON \
      -DWITH_CUDA=OFF \
      -DWITH_EIGEN=OFF \
      -DBUILD_EXAMPLES=OFF \
      -DBUILD_TESTS=OFF \
      -DBUILD_PERF_TESTS=OFF \
      -DBUILD_opencv_python3=ON \
      .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig
# На реальном Nano этот шаг — самый долгий во всей сборке: рассчитывай на
# 40-90 минут в зависимости от загрузки и того, сколько ядер реально свободно.

# Проверка результата через бинарник opencv_version, который CMake сам
# собрал и установил в /opt/opencv-4.1.1/bin — специально для такой проверки.
# Раньше здесь стоял pkg-config, но у OpenCV 4.x файл opencv4.pc НЕ генерится
# по умолчанию (нужен отдельный флаг -DOPENCV_GENERATE_PKGCONFIG=YES, которого
# у нас нет) — pkg-config молча проваливался в системные пути и находил
# какой-то ЧУЖОЙ OpenCV 4.5.0, никак не связанный с нашей сборкой. Сама же
# сборка (libopencv_core.so.4.1.1 и т.д. по install-логу) прошла верно.
RUN v=$(/opt/opencv-4.1.1/bin/opencv_version) && \
    echo "OpenCV version: $v" && \
    echo "$v" | grep -q '^4\.1\.1' || (echo "ОШИБКА: ожидали 4.1.1, получили $v" && exit 1)

# Чтобы динамический линкер видел именно эту версию библиотек в рантайме
# (а не что-то ещё, если оно есть в системе):
ENV LD_LIBRARY_PATH="/opt/opencv-4.1.1/lib:${LD_LIBRARY_PATH}"

# === 3. Сборка UnitreeCameraSDK ===
# libudev-dev — отдельным шагом, а не в общем apt-блоке выше: тот блок стоит
# ДО сборки OpenCV, и правка его сейчас пересобрала бы OpenCV заново (~1 час).
# Не хватало на этапе линковки (-ludev) — судя по всему, SDK использует udev
# для определения/мониторинга USB-камер.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libudev-dev \
    && rm -rf /var/lib/apt/lists/*

# Клонируем и собираем по инструкции самого Unitree: mkdir build && cmake .. && make
WORKDIR /opt
RUN git clone --depth=1 https://github.com/unitreerobotics/UnitreecameraSDK.git
WORKDIR /opt/UnitreecameraSDK
RUN mkdir build && cd build && \
    cmake -DOpenCV_DIR=/opt/opencv-4.1.1/lib/cmake/opencv4 .. && \
    make -j$(nproc)
# Собранные бинарники лежат в /opt/UnitreecameraSDK/bin/ — можно проверить прямо
# из контейнера: ./bin/example_getRawFrame

# === 4. Рабочая директория для будущего colcon-воркспейса ===
# Кода участников здесь намеренно НЕТ — это базовый тулбокс-образ, который
# организатор кейса собирает и раздаёт командам ДО того, как появится
# какой-либо код. Участники сами примонтируют свой src/ через bind-mount
# при запуске контейнера (см. quickstart) и соберут его внутри уже своим colcon build.
RUN mkdir -p /developer_ws/src
WORKDIR /developer_ws

# Немного dev-инструментов, которые понадобятся участникам внутри контейнера:
# nano/vim/colcon — писать и собирать код; v4l-utils — команда v4l2-ctl для
# диагностики /dev/videoX (список камер, поддерживаемые форматы). Это чисто
# runtime-утилита для отладки, а не зависимость сборки SDK — поэтому она здесь,
# а не в блоке выше.
RUN apt-get update && apt-get install -y --no-install-recommends \
    nano vim v4l-utils \
    python3-colcon-common-extensions \
    neovim ranger mc \
    && rm -rf /var/lib/apt/lists/*

# === 5. Entrypoint ===
COPY ros2_custom_config_setup/ros_entrypoint.sh /ros2_custom_entrypoint.sh
RUN chmod +x /ros2_custom_entrypoint.sh && \
    echo '[ -f /ros2_custom_config_setup/setup.sh ] && source /ros2_custom_config_setup/setup.sh' >> /root/.bashrc

ENTRYPOINT ["/ros2_custom_entrypoint.sh"]
CMD ["bash"]

