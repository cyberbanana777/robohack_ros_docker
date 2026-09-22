#!/usr/bin/env bash
# setup_cyclonedds_env.sh
# Добавляет строку source <папка_скрипта>/cyclonedds_config_host.sh в ~/.bashrc
# (если её там ещё нет) и применяет изменения.
#
# Использование (рекомендуется, чтобы переменные попали в текущий терминал):
#   source ./setup_cyclonedds_env.sh
# или просто:
#   ./setup_cyclonedds_env.sh   (тогда после него выполните: source ~/.bashrc)

# Запущен ли скрипт через source/. (а не как отдельный процесс)
(return 0 2>/dev/null) && _SOURCED=1 || _SOURCED=0

_finish() {
    local code="$1"
    unset SCRIPT_DIR CONFIG_FILE BASHRC SOURCE_LINE
    if [[ $_SOURCED -eq 1 ]]; then
        unset _SOURCED
        unset -f _finish
        return "$code"
    else
        exit "$code"
    fi
}

# Абсолютный путь к папке, где лежит этот скрипт (работает и при source, и при запуске)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/cyclonedds_config_host.sh"
BASHRC="${HOME}/.bashrc"
SOURCE_LINE="source \"${CONFIG_FILE}\""

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Ошибка: не найден файл $CONFIG_FILE" >&2
    _finish 1; return 1 2>/dev/null
fi

touch "$BASHRC"

# Ищем незакомментированную строку, которая уже подключает именно этот файл
if grep -vE '^[[:space:]]*#' "$BASHRC" | grep -qF "$CONFIG_FILE"; then
    echo "В $BASHRC уже есть подключение $CONFIG_FILE — ничего не добавляю."
else
    # Если .bashrc не заканчивается переводом строки — добавим его
    if [[ -s "$BASHRC" && -n "$(tail -c1 "$BASHRC")" ]]; then
        echo >> "$BASHRC"
    fi
    {
        echo "# CycloneDDS host config"
        echo "$SOURCE_LINE"
    } >> "$BASHRC"
    echo "Добавлено в $BASHRC: $SOURCE_LINE"
fi

if [[ $_SOURCED -eq 1 ]]; then
    # shellcheck disable=SC1090
    source "$BASHRC"
    echo "~/.bashrc перечитан в текущем терминале."
else
    echo "Скрипт запущен как отдельный процесс, поэтому текущий терминал не обновится."
    echo "Выполните:  source ~/.bashrc   (или откройте новый терминал)"
fi

_finish 0
