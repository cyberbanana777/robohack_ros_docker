#!/usr/bin/env bash
# Сборка образа: ./build_image.sh foxy|humble
set -euo pipefail
cd "$(dirname "$0")"
DISTRO="${1:-}"
case "${DISTRO}" in
  foxy|humble) ;;
  *) echo "Использование: $0 foxy|humble" >&2; exit 1 ;;
esac
sudo docker build -f "Dockerfile.${DISTRO}" -t "unitree-hackathon:${DISTRO}" .
