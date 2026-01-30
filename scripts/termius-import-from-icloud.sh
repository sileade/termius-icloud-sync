#!/bin/bash
#
# termius-import-from-icloud.sh
# Скрипт импорта SSH-конфига из iCloud в Termius
#
# Функционал:
# - Читает SSH config из iCloud
# - Фильтрует хосты с комментарием # termius:ignore
# - Импортирует отфильтрованный конфиг в Termius
# - Синхронизирует с облаком Termius (push)
#
# Использование: ./termius-import-from-icloud.sh [--dry-run] [--verbose]
#

set -euo pipefail

# ============================================================================
# КОНФИГУРАЦИЯ
# ============================================================================

# Путь к SSH config в iCloud (настройте под свою структуру)
ICLOUD_SSH_CONFIG="${ICLOUD_SSH_CONFIG:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/SSH/config}"

# Альтернативный путь через симлинк
LOCAL_SSH_CONFIG="${LOCAL_SSH_CONFIG:-$HOME/.ssh/config}"

# Временная директория для обработки
TEMP_DIR="${TEMP_DIR:-/tmp/termius-sync}"

# Лог-файл
LOG_DIR="${LOG_DIR:-$HOME/.local/log/termius-sync}"
LOG_FILE="${LOG_DIR}/import-$(date +%Y%m%d).log"

# Маркер для игнорирования хостов
IGNORE_MARKER="# termius:ignore"

# Флаги
DRY_RUN=false
VERBOSE=false

# ============================================================================
# ФУНКЦИИ
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    if [[ "$VERBOSE" == "true" ]] || [[ "$level" == "ERROR" ]]; then
        echo "[$level] $message"
    fi
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        log "DEBUG" "$@"
    fi
}

die() {
    log_error "$@"
    exit 1
}

usage() {
    cat << EOF
Использование: $(basename "$0") [ОПЦИИ]

Импортирует SSH-конфиг из iCloud в Termius, исключая хосты
с комментарием '# termius:ignore'.

Опции:
    --dry-run       Показать что будет сделано, без выполнения
    --verbose, -v   Подробный вывод
    --help, -h      Показать эту справку

Переменные окружения:
    ICLOUD_SSH_CONFIG   Путь к SSH config в iCloud
                        (по умолчанию: ~/Library/Mobile Documents/com~apple~CloudDocs/SSH/config)
    LOCAL_SSH_CONFIG    Путь к локальному SSH config
                        (по умолчанию: ~/.ssh/config)
    LOG_DIR             Директория для логов
                        (по умолчанию: ~/.local/log/termius-sync)

Примеры:
    $(basename "$0")                    # Стандартный импорт
    $(basename "$0") --dry-run -v       # Тестовый запуск с подробным выводом
    ICLOUD_SSH_CONFIG=~/iCloud/ssh_config $(basename "$0")

EOF
    exit 0
}

check_dependencies() {
    log_info "Проверка зависимостей..."
    
    if ! command -v termius &> /dev/null; then
        die "Termius CLI не установлен. Установите: brew install termius"
    fi
    
    log_debug "Termius CLI найден: $(command -v termius)"
}

check_icloud_config() {
    log_info "Проверка SSH config в iCloud..."
    
    # Определяем источник конфига
    local config_source=""
    
    if [[ -f "$ICLOUD_SSH_CONFIG" ]]; then
        config_source="$ICLOUD_SSH_CONFIG"
        log_info "Используется iCloud config: $config_source"
    elif [[ -f "$LOCAL_SSH_CONFIG" ]]; then
        # Проверяем, является ли локальный конфиг симлинком на iCloud
        if [[ -L "$LOCAL_SSH_CONFIG" ]]; then
            local link_target
            link_target=$(readlink "$LOCAL_SSH_CONFIG")
            log_info "Локальный config является симлинком на: $link_target"
        fi
        config_source="$LOCAL_SSH_CONFIG"
        log_info "Используется локальный config: $config_source"
    else
        die "SSH config не найден ни в iCloud ($ICLOUD_SSH_CONFIG), ни локально ($LOCAL_SSH_CONFIG)"
    fi
    
    echo "$config_source"
}

filter_ignored_hosts() {
    local input_file="$1"
    local output_file="$2"
    
    log_info "Фильтрация хостов с маркером '$IGNORE_MARKER'..."
    
    # AWK скрипт для фильтрации хостов с # termius:ignore
    # Логика: пропускаем блоки Host, содержащие маркер игнорирования
    awk '
    BEGIN {
        in_host_block = 0
        ignore_current = 0
        buffer = ""
        ignored_count = 0
        imported_count = 0
    }
    
    # Начало нового блока Host или Match
    /^[[:space:]]*(Host|Match)[[:space:]]/ {
        # Если был предыдущий блок и он не игнорируется - выводим
        if (in_host_block && !ignore_current && buffer != "") {
            printf "%s", buffer
            imported_count++
        } else if (ignore_current) {
            ignored_count++
        }
        
        # Начинаем новый блок
        in_host_block = 1
        ignore_current = 0
        buffer = $0 "\n"
        next
    }
    
    # Проверяем маркер игнорирования
    /# termius:ignore/ {
        ignore_current = 1
        buffer = buffer $0 "\n"
        next
    }
    
    # Глобальные настройки (до первого Host) - всегда выводим
    !in_host_block {
        print
        next
    }
    
    # Добавляем строку в буфер текущего блока
    {
        buffer = buffer $0 "\n"
    }
    
    END {
        # Обрабатываем последний блок
        if (in_host_block && !ignore_current && buffer != "") {
            printf "%s", buffer
            imported_count++
        } else if (ignore_current) {
            ignored_count++
        }
        
        # Выводим статистику в stderr
        print "Импортировано хостов: " imported_count > "/dev/stderr"
        print "Пропущено хостов (termius:ignore): " ignored_count > "/dev/stderr"
    }
    ' "$input_file" > "$output_file"
    
    log_debug "Отфильтрованный конфиг сохранен в: $output_file"
}

import_to_termius() {
    local config_file="$1"
    
    log_info "Импорт конфига в Termius..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Будет выполнено: termius import-ssh-config < $config_file"
        log_info "[DRY-RUN] Содержимое для импорта:"
        if [[ "$VERBOSE" == "true" ]]; then
            cat "$config_file"
        fi
        return 0
    fi
    
    # Создаем временный симлинк для ~/.ssh/config
    local original_config="$HOME/.ssh/config"
    local backup_config=""
    
    if [[ -f "$original_config" ]] || [[ -L "$original_config" ]]; then
        backup_config="${original_config}.termius-backup.$$"
        mv "$original_config" "$backup_config"
        log_debug "Оригинальный config сохранен в: $backup_config"
    fi
    
    # Копируем отфильтрованный конфиг
    cp "$config_file" "$original_config"
    chmod 600 "$original_config"
    
    # Импортируем
    local import_result=0
    if termius import-ssh-config 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Импорт в Termius успешно завершен"
    else
        import_result=$?
        log_error "Ошибка при импорте в Termius (код: $import_result)"
    fi
    
    # Восстанавливаем оригинальный конфиг
    rm -f "$original_config"
    if [[ -n "$backup_config" ]] && [[ -f "$backup_config" ]]; then
        mv "$backup_config" "$original_config"
        log_debug "Оригинальный config восстановлен"
    fi
    
    return $import_result
}

push_to_cloud() {
    log_info "Синхронизация с облаком Termius (push)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Будет выполнено: termius push"
        return 0
    fi
    
    if termius push 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Push в облако Termius успешно завершен"
    else
        local result=$?
        log_error "Ошибка при push в облако Termius (код: $result)"
        return $result
    fi
}

cleanup() {
    log_debug "Очистка временных файлов..."
    rm -rf "${TEMP_DIR:?}/"*
}

# ============================================================================
# ОСНОВНАЯ ЛОГИКА
# ============================================================================

main() {
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                usage
                ;;
            *)
                die "Неизвестный аргумент: $1. Используйте --help для справки."
                ;;
        esac
    done
    
    # Создаем необходимые директории
    mkdir -p "$TEMP_DIR"
    mkdir -p "$LOG_DIR"
    
    # Устанавливаем обработчик очистки
    trap cleanup EXIT
    
    log_info "=========================================="
    log_info "Начало импорта iCloud → Termius"
    log_info "=========================================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Режим DRY-RUN: изменения не будут применены"
    fi
    
    # Проверяем зависимости
    check_dependencies
    
    # Находим и проверяем исходный конфиг
    local source_config
    source_config=$(check_icloud_config)
    
    # Фильтруем игнорируемые хосты
    local filtered_config="${TEMP_DIR}/filtered_ssh_config"
    filter_ignored_hosts "$source_config" "$filtered_config"
    
    # Импортируем в Termius
    import_to_termius "$filtered_config"
    
    # Синхронизируем с облаком
    push_to_cloud
    
    log_info "=========================================="
    log_info "Импорт iCloud → Termius завершен успешно"
    log_info "=========================================="
    
    echo "✓ Импорт завершен. Лог: $LOG_FILE"
}

# Запуск
main "$@"
