#!/bin/bash
#
# termius-export-to-icloud.sh
# Скрипт экспорта хостов из Termius в SSH-конфиг iCloud
#
# Функционал:
# - Выполняет termius pull для получения актуальных данных
# - Экспортирует хосты через termius export-ssh-config
# - Создает бэкап текущего iCloud конфига
# - Мержит экспорт с игнорируемыми хостами из оригинала
# - Перезаписывает iCloud конфиг с правильными правами
#
# Использование: ./termius-export-to-icloud.sh [--dry-run] [--verbose] [--no-backup]
#

set -euo pipefail

# ============================================================================
# КОНФИГУРАЦИЯ
# ============================================================================

# Путь к SSH config в iCloud (настройте под свою структуру)
ICLOUD_SSH_CONFIG="${ICLOUD_SSH_CONFIG:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/SSH/config}"

# Альтернативный путь через симлинк
LOCAL_SSH_CONFIG="${LOCAL_SSH_CONFIG:-$HOME/.ssh/config}"

# Директория для бэкапов
BACKUP_DIR="${BACKUP_DIR:-$HOME/.local/backup/ssh-config}"

# Максимальное количество хранимых бэкапов
MAX_BACKUPS="${MAX_BACKUPS:-30}"

# Временная директория для обработки
TEMP_DIR="${TEMP_DIR:-/tmp/termius-sync}"

# Лог-файл
LOG_DIR="${LOG_DIR:-$HOME/.local/log/termius-sync}"
LOG_FILE="${LOG_DIR}/export-$(date +%Y%m%d).log"

# Маркер для игнорирования хостов
IGNORE_MARKER="# termius:ignore"

# Флаги
DRY_RUN=false
VERBOSE=false
NO_BACKUP=false

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

Экспортирует хосты из Termius в SSH-конфиг iCloud, сохраняя
хосты с комментарием '# termius:ignore' из оригинального файла.

Опции:
    --dry-run       Показать что будет сделано, без выполнения
    --verbose, -v   Подробный вывод
    --no-backup     Не создавать бэкап перед перезаписью
    --help, -h      Показать эту справку

Переменные окружения:
    ICLOUD_SSH_CONFIG   Путь к SSH config в iCloud
                        (по умолчанию: ~/Library/Mobile Documents/com~apple~CloudDocs/SSH/config)
    LOCAL_SSH_CONFIG    Путь к локальному SSH config
                        (по умолчанию: ~/.ssh/config)
    BACKUP_DIR          Директория для бэкапов
                        (по умолчанию: ~/.local/backup/ssh-config)
    MAX_BACKUPS         Максимальное количество бэкапов
                        (по умолчанию: 30)
    LOG_DIR             Директория для логов
                        (по умолчанию: ~/.local/log/termius-sync)

Примеры:
    $(basename "$0")                    # Стандартный экспорт
    $(basename "$0") --dry-run -v       # Тестовый запуск с подробным выводом
    $(basename "$0") --no-backup        # Экспорт без создания бэкапа

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

get_target_config_path() {
    # Определяем целевой путь для записи конфига
    local target_path=""
    
    # Приоритет: iCloud путь, затем локальный
    if [[ -d "$(dirname "$ICLOUD_SSH_CONFIG")" ]]; then
        target_path="$ICLOUD_SSH_CONFIG"
        log_info "Целевой путь (iCloud): $target_path"
    elif [[ -L "$LOCAL_SSH_CONFIG" ]]; then
        # Если локальный - симлинк, пишем в него (он указывает на iCloud)
        target_path="$LOCAL_SSH_CONFIG"
        log_info "Целевой путь (симлинк): $target_path -> $(readlink "$LOCAL_SSH_CONFIG")"
    else
        target_path="$LOCAL_SSH_CONFIG"
        log_info "Целевой путь (локальный): $target_path"
    fi
    
    echo "$target_path"
}

pull_from_cloud() {
    log_info "Получение актуальных данных из облака Termius (pull)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Будет выполнено: termius pull"
        return 0
    fi
    
    if termius pull 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Pull из облака Termius успешно завершен"
    else
        local result=$?
        log_warn "Предупреждение при pull из облака Termius (код: $result)"
        # Не прерываем выполнение, возможно данные уже актуальны
    fi
}

export_from_termius() {
    local output_dir="$1"
    
    log_info "Экспорт хостов из Termius..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Будет выполнено: termius export-ssh-config"
        # Создаем пустой файл для dry-run
        mkdir -p "${output_dir}/termius"
        touch "${output_dir}/termius/sshconfig"
        echo "${output_dir}/termius/sshconfig"
        return 0
    fi
    
    # Переходим в директорию для экспорта
    local original_dir
    original_dir=$(pwd)
    cd "$output_dir"
    
    # Создаем директорию termius, куда экспортируется конфиг
    mkdir -p termius
    
    if termius export-ssh-config 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Экспорт из Termius успешно завершен"
    else
        local result=$?
        cd "$original_dir"
        die "Ошибка при экспорте из Termius (код: $result)"
    fi
    
    cd "$original_dir"
    
    # Проверяем наличие экспортированного файла
    local exported_file="${output_dir}/termius/sshconfig"
    if [[ ! -f "$exported_file" ]]; then
        die "Экспортированный файл не найден: $exported_file"
    fi
    
    log_debug "Экспортированный файл: $exported_file"
    echo "$exported_file"
}

extract_ignored_hosts() {
    local input_file="$1"
    local output_file="$2"
    
    log_info "Извлечение хостов с маркером '$IGNORE_MARKER'..."
    
    if [[ ! -f "$input_file" ]]; then
        log_warn "Исходный файл не найден: $input_file"
        touch "$output_file"
        return 0
    fi
    
    # AWK скрипт для извлечения ТОЛЬКО игнорируемых хостов
    awk '
    BEGIN {
        in_host_block = 0
        is_ignored = 0
        buffer = ""
        ignored_count = 0
    }
    
    # Начало нового блока Host или Match
    /^[[:space:]]*(Host|Match)[[:space:]]/ {
        # Если предыдущий блок был игнорируемым - выводим его
        if (in_host_block && is_ignored && buffer != "") {
            printf "%s", buffer
            ignored_count++
        }
        
        # Начинаем новый блок
        in_host_block = 1
        is_ignored = 0
        buffer = $0 "\n"
        next
    }
    
    # Проверяем маркер игнорирования
    /# termius:ignore/ {
        is_ignored = 1
        buffer = buffer $0 "\n"
        next
    }
    
    # Глобальные настройки (до первого Host) - пропускаем
    !in_host_block {
        next
    }
    
    # Добавляем строку в буфер текущего блока
    {
        buffer = buffer $0 "\n"
    }
    
    END {
        # Обрабатываем последний блок
        if (in_host_block && is_ignored && buffer != "") {
            printf "%s", buffer
            ignored_count++
        }
        
        print "Найдено игнорируемых хостов: " ignored_count > "/dev/stderr"
    }
    ' "$input_file" > "$output_file"
    
    log_debug "Игнорируемые хосты сохранены в: $output_file"
}

extract_global_settings() {
    local input_file="$1"
    local output_file="$2"
    
    log_info "Извлечение глобальных настроек..."
    
    if [[ ! -f "$input_file" ]]; then
        touch "$output_file"
        return 0
    fi
    
    # Извлекаем все строки до первого Host/Match блока
    awk '
    /^[[:space:]]*(Host|Match)[[:space:]]/ { exit }
    { print }
    ' "$input_file" > "$output_file"
    
    log_debug "Глобальные настройки сохранены в: $output_file"
}

create_backup() {
    local source_file="$1"
    
    if [[ "$NO_BACKUP" == "true" ]]; then
        log_info "Создание бэкапа пропущено (--no-backup)"
        return 0
    fi
    
    if [[ ! -f "$source_file" ]]; then
        log_warn "Файл для бэкапа не существует: $source_file"
        return 0
    fi
    
    log_info "Создание бэкапа..."
    
    mkdir -p "$BACKUP_DIR"
    
    local backup_name
    backup_name="ssh_config_$(date +%Y%m%d_%H%M%S).bak"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Будет создан бэкап: $backup_path"
        return 0
    fi
    
    cp "$source_file" "$backup_path"
    log_info "Бэкап создан: $backup_path"
    
    # Ротация старых бэкапов
    rotate_backups
    
    echo "$backup_path"
}

rotate_backups() {
    log_debug "Ротация бэкапов (максимум: $MAX_BACKUPS)..."
    
    local backup_count
    backup_count=$(find "$BACKUP_DIR" -maxdepth 1 -name "*.bak" -type f 2>/dev/null | wc -l)
    
    if [[ $backup_count -gt $MAX_BACKUPS ]]; then
        local to_delete=$((backup_count - MAX_BACKUPS))
        log_info "Удаление $to_delete старых бэкапов..."
        
        # Используем find вместо ls для корректной обработки имен файлов
        find "$BACKUP_DIR" -maxdepth 1 -name "*.bak" -type f -printf '%T@ %p\n' | \
            sort -n | head -n "$to_delete" | cut -d' ' -f2- | \
            while IFS= read -r old_backup; do
                rm -f "$old_backup"
                log_debug "Удален старый бэкап: $old_backup"
            done
    fi
}

merge_configs() {
    local exported_file="$1"
    local ignored_hosts_file="$2"
    local global_settings_file="$3"
    local output_file="$4"
    
    log_info "Объединение конфигов..."
    
    {
        # 1. Сначала глобальные настройки из оригинала
        if [[ -s "$global_settings_file" ]]; then
            echo "# ============================================"
            echo "# Global Settings"
            echo "# ============================================"
            cat "$global_settings_file"
            echo ""
        fi
        
        # 2. Затем хосты из Termius
        if [[ -s "$exported_file" ]]; then
            echo "# ============================================"
            echo "# Hosts from Termius (auto-synced)"
            echo "# Last sync: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "# ============================================"
            echo ""
            # Пропускаем глобальные настройки из экспорта Termius
            awk '
            BEGIN { in_host = 0 }
            /^[[:space:]]*(Host|Match)[[:space:]]/ { in_host = 1 }
            in_host { print }
            ' "$exported_file"
            echo ""
        fi
        
        # 3. В конце игнорируемые хосты из оригинала
        if [[ -s "$ignored_hosts_file" ]]; then
            echo "# ============================================"
            echo "# Local-only hosts (termius:ignore)"
            echo "# These hosts are NOT synced with Termius"
            echo "# ============================================"
            echo ""
            cat "$ignored_hosts_file"
        fi
        
    } > "$output_file"
    
    log_debug "Объединенный конфиг сохранен в: $output_file"
}

write_final_config() {
    local source_file="$1"
    local target_file="$2"
    
    log_info "Запись финального конфига..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Будет записан файл: $target_file"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "=== Содержимое финального конфига ==="
            cat "$source_file"
            echo "=== Конец содержимого ==="
        fi
        return 0
    fi
    
    # Создаем директорию если не существует
    mkdir -p "$(dirname "$target_file")"
    
    # Копируем с правильными правами
    cp "$source_file" "$target_file"
    chmod 600 "$target_file"
    
    log_info "Конфиг записан: $target_file"
    log_info "Права доступа: 600"
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
            --no-backup)
                NO_BACKUP=true
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
    mkdir -p "$BACKUP_DIR"
    
    # Устанавливаем обработчик очистки
    trap cleanup EXIT
    
    log_info "=========================================="
    log_info "Начало экспорта Termius → iCloud"
    log_info "=========================================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Режим DRY-RUN: изменения не будут применены"
    fi
    
    # Проверяем зависимости
    check_dependencies
    
    # Определяем целевой путь
    local target_config
    target_config=$(get_target_config_path)
    
    # Получаем актуальные данные из облака
    pull_from_cloud
    
    # Экспортируем из Termius
    local export_dir="${TEMP_DIR}/export"
    mkdir -p "$export_dir"
    local exported_file
    exported_file=$(export_from_termius "$export_dir")
    
    # Извлекаем игнорируемые хосты из текущего конфига
    local ignored_hosts_file="${TEMP_DIR}/ignored_hosts"
    extract_ignored_hosts "$target_config" "$ignored_hosts_file"
    
    # Извлекаем глобальные настройки из текущего конфига
    local global_settings_file="${TEMP_DIR}/global_settings"
    extract_global_settings "$target_config" "$global_settings_file"
    
    # Создаем бэкап текущего конфига
    create_backup "$target_config"
    
    # Объединяем конфиги
    local merged_config="${TEMP_DIR}/merged_config"
    merge_configs "$exported_file" "$ignored_hosts_file" "$global_settings_file" "$merged_config"
    
    # Записываем финальный конфиг
    write_final_config "$merged_config" "$target_config"
    
    log_info "=========================================="
    log_info "Экспорт Termius → iCloud завершен успешно"
    log_info "=========================================="
    
    echo "✓ Экспорт завершен. Лог: $LOG_FILE"
    
    if [[ "$NO_BACKUP" != "true" ]] && [[ -d "$BACKUP_DIR" ]]; then
        echo "✓ Бэкапы хранятся в: $BACKUP_DIR"
    fi
}

# Запуск
main "$@"
