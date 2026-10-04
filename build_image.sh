#!/usr/bin/env bash
# Сборка образа: ./build_image.sh foxy|humble
set -euo pipefail
cd "$(dirname "$0")"
DISTRO="${1:-}"
case "${DISTRO}" in
  foxy|humble) ;;
  *) echo "Использование: $0 foxy|humble" >&2; exit 1 ;;
esac
# UID/GID пользователя в контейнере = текущий пользователь Jetson (обычно 1000),
# чтобы файлы в примонтированном src/ принадлежали ему, а не root.
# Переопределить: USER_UID=1001 USER_GID=1001 ./build_image.sh foxy
USER_UID="${USER_UID:-$(id -u)}"
USER_GID="${USER_GID:-$(id -g)}"
sudo docker build -f "Dockerfile.${DISTRO}" -t "unitree-hackathon:${DISTRO}" \
    --build-arg USER_UID="${USER_UID}" --build-arg USER_GID="${USER_GID}" .
