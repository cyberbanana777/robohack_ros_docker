#!/usr/bin/env bash
# Сохранение образа в файл для переноса на другие Jetson: ./save_image.sh foxy|humble
set -euo pipefail
cd "$(dirname "$0")"
DISTRO="${1:-}"
case "${DISTRO}" in
  foxy|humble) ;;
  *) echo "Использование: $0 foxy|humble" >&2; exit 1 ;;
esac
sudo docker save "unitree-hackathon:${DISTRO}" -o "unitree-hackathon-${DISTRO}.tar"
sudo chown "$(id -u):$(id -g)" "unitree-hackathon-${DISTRO}.tar"
echo "Сохранено: unitree-hackathon-${DISTRO}.tar"
