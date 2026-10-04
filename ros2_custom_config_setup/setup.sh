
# --- This file can be edited. ---
# Общий для обоих образов (foxy, humble): лежит на хосте и монтируется
# в контейнер в /ros2_custom_config_setup. Подключается entrypoint-ом и в каждом bash.
# Важно: файл подключается из entrypoint с `set -e`, поэтому все проверки здесь
# через if/fi, а не через `[ ... ] && ...` (иначе контейнер может не стартовать).

# base environment
# Путь к окружению ROS зависит от образа:
#   foxy, humble (jetson-containers, ROS собран из исходников): /opt/ros/<distro>/install/setup.bash
#   официальные образы ROS (на будущее):                        /opt/ros/<distro>/setup.bash
if [ -z "${ROS_DISTRO}" ]; then
    ROS_DISTRO=$(ls /opt/ros | head -n1)
fi
if [ -f "/opt/ros/${ROS_DISTRO}/install/setup.bash" ]; then
    source "/opt/ros/${ROS_DISTRO}/install/setup.bash"
else
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
fi

# CycloneDDS 0.10, собранный из исходников поверх ROS
# (всегда в образе foxy, в образе humble — только если его не было в базовом образе)
if [ -f /opt/cyclonedds_ws/install/setup.bash ]; then
    source /opt/cyclonedds_ws/install/setup.bash
fi

# dds setup
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
# Конфиг CycloneDDS лежит рядом с этим файлом. Если его убрать, CycloneDDS
# работает с настройками по умолчанию.
if [ -f /ros2_custom_config_setup/cyclonedds.xml ]; then
    export CYCLONEDDS_URI=file:///ros2_custom_config_setup/cyclonedds.xml
fi

# workspace участников
if [ -f /developer_ws/install/setup.bash ]; then
    source /developer_ws/install/setup.bash
fi
