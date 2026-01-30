#!/bin/bash
#
# install.sh
# Скрипт установки системы синхронизации SSH-конфига между iCloud и Termius
#
# Использование: ./install.sh [--uninstall]
#

set -euo pipefail

# ============================================================================
# КОНФИГУРАЦИЯ
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Директории установки
BIN_DIR="${HOME}/.local/bin"
LOG_DIR="${HOME}/.local/log/termius-sync"
BACKUP_DIR="${HOME}/.local/backup/ssh-config"
LAUNCHD_DIR="${HOME}/Library/LaunchAgents"

# Файлы для установки
IMPORT_SCRIPT="termius-import-from-icloud.sh"
EXPORT_SCRIPT="termius-export-to-icloud.sh"
LAUNCHD_PLIST="com.user.termius-import.plist"

# Путь к SSH config в iCloud (по умолчанию)
DEFAULT_ICLOUD_SSH_DIR="${HOME}/Library/Mobile Documents/com~apple~CloudDocs/SSH"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# ФУНКЦИИ
# ============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${GREEN}Termius ↔ iCloud SSH Config Sync${NC}                          ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  Система синхронизации SSH-конфига                         ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

die() {
    log_error "$@"
    exit 1
}

check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        die "Этот скрипт предназначен только для macOS"
    fi
    log_info "Операционная система: macOS $(sw_vers -productVersion)"
}

check_termius() {
    if command -v termius &> /dev/null; then
        log_info "Termius CLI найден: $(command -v termius)"
        return 0
    fi
    
    log_warn "Termius CLI не установлен"
    echo ""
    echo "Для установки Termius CLI выполните:"
    echo "  brew install termius"
    echo ""
    read -p "Продолжить установку без Termius CLI? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        die "Установка отменена. Установите Termius CLI и повторите."
    fi
}

check_icloud() {
    local icloud_root="${HOME}/Library/Mobile Documents/com~apple~CloudDocs"
    
    if [[ -d "$icloud_root" ]]; then
        log_info "iCloud Drive доступен: $icloud_root"
        return 0
    fi
    
    log_warn "iCloud Drive не найден или не настроен"
    echo ""
    echo "Убедитесь, что:"
    echo "  1. Вы вошли в iCloud в Системных настройках"
    echo "  2. iCloud Drive включен"
    echo ""
    read -p "Продолжить установку? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        die "Установка отменена"
    fi
}

setup_icloud_ssh_dir() {
    echo ""
    log_info "Настройка директории SSH в iCloud..."
    
    if [[ -d "$DEFAULT_ICLOUD_SSH_DIR" ]]; then
        log_info "Директория SSH в iCloud уже существует: $DEFAULT_ICLOUD_SSH_DIR"
    else
        echo ""
        echo "Директория SSH в iCloud не найдена."
        echo "Рекомендуемый путь: $DEFAULT_ICLOUD_SSH_DIR"
        echo ""
        read -p "Создать директорию? (Y/n): " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            mkdir -p "$DEFAULT_ICLOUD_SSH_DIR"
            log_info "Директория создана: $DEFAULT_ICLOUD_SSH_DIR"
        fi
    fi
    
    # Проверяем наличие config файла
    local icloud_config="${DEFAULT_ICLOUD_SSH_DIR}/config"
    local local_config="${HOME}/.ssh/config"
    
    if [[ ! -f "$icloud_config" ]]; then
        echo ""
        echo "SSH config в iCloud не найден."
        
        if [[ -f "$local_config" ]]; then
            echo "Найден локальный SSH config: $local_config"
            read -p "Скопировать локальный config в iCloud? (Y/n): " -n 1 -r
            echo ""
            
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                cp "$local_config" "$icloud_config"
                chmod 600 "$icloud_config"
                log_info "Config скопирован в iCloud: $icloud_config"
            fi
        else
            echo "Создаю пустой config в iCloud..."
            touch "$icloud_config"
            chmod 600 "$icloud_config"
            log_info "Создан пустой config: $icloud_config"
        fi
    fi
    
    # Предлагаем создать симлинк
    echo ""
    echo "Рекомендуется создать симлинк ~/.ssh/config → iCloud config"
    echo "Это позволит всем терминалам использовать единый конфиг из iCloud."
    echo ""
    
    if [[ -L "$local_config" ]]; then
        local current_link
        current_link=$(readlink "$local_config")
        log_info "Симлинк уже существует: $local_config → $current_link"
    elif [[ -f "$local_config" ]]; then
        read -p "Заменить локальный config симлинком на iCloud? (y/N): " -n 1 -r
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Бэкап локального конфига
            local backup
            backup="${local_config}.backup.$(date +%Y%m%d_%H%M%S)"
            mv "$local_config" "$backup"
            log_info "Бэкап локального config: $backup"
            
            # Создаем симлинк
            ln -s "$icloud_config" "$local_config"
            log_info "Симлинк создан: $local_config → $icloud_config"
        fi
    else
        read -p "Создать симлинк ~/.ssh/config → iCloud? (Y/n): " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            mkdir -p "${HOME}/.ssh"
            ln -s "$icloud_config" "$local_config"
            log_info "Симлинк создан: $local_config → $icloud_config"
        fi
    fi
}

create_directories() {
    log_info "Создание директорий..."
    
    mkdir -p "$BIN_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$LAUNCHD_DIR"
    
    log_info "  $BIN_DIR"
    log_info "  $LOG_DIR"
    log_info "  $BACKUP_DIR"
    log_info "  $LAUNCHD_DIR"
}

install_scripts() {
    log_info "Установка скриптов..."
    
    # Копируем скрипты
    cp "${SCRIPT_DIR}/scripts/${IMPORT_SCRIPT}" "${BIN_DIR}/"
    cp "${SCRIPT_DIR}/scripts/${EXPORT_SCRIPT}" "${BIN_DIR}/"
    
    # Устанавливаем права на выполнение
    chmod +x "${BIN_DIR}/${IMPORT_SCRIPT}"
    chmod +x "${BIN_DIR}/${EXPORT_SCRIPT}"
    
    log_info "  ${BIN_DIR}/${IMPORT_SCRIPT}"
    log_info "  ${BIN_DIR}/${EXPORT_SCRIPT}"
}

configure_launchd_plist() {
    local plist_source="${SCRIPT_DIR}/launchd/${LAUNCHD_PLIST}"
    local plist_dest="${LAUNCHD_DIR}/${LAUNCHD_PLIST}"
    
    log_info "Настройка LaunchAgent..."
    
    # Создаем временный файл с заменой путей
    local temp_plist
    temp_plist=$(mktemp)
    
    # Заменяем пути в plist на актуальные
    sed -e "s|\$HOME|${HOME}|g" \
        -e "s|~/|${HOME}/|g" \
        "$plist_source" > "$temp_plist"
    
    # Копируем настроенный plist
    cp "$temp_plist" "$plist_dest"
    rm -f "$temp_plist"
    
    log_info "  ${plist_dest}"
}

load_launchd() {
    local plist_path="${LAUNCHD_DIR}/${LAUNCHD_PLIST}"
    
    log_info "Загрузка LaunchAgent..."
    
    # Выгружаем если уже загружен
    if launchctl list | grep -q "com.user.termius-import"; then
        launchctl unload "$plist_path" 2>/dev/null || true
    fi
    
    # Загружаем
    if launchctl load "$plist_path"; then
        log_info "LaunchAgent загружен успешно"
    else
        log_warn "Не удалось загрузить LaunchAgent"
        echo "Попробуйте вручную: launchctl load $plist_path"
    fi
}

add_to_path() {
    log_info "Проверка PATH..."
    
    if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
        echo ""
        log_warn "${BIN_DIR} не в PATH"
        echo ""
        echo "Добавьте в ваш ~/.zshrc или ~/.bashrc:"
        echo ""
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
    else
        log_info "${BIN_DIR} уже в PATH"
    fi
}

print_usage_instructions() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  Установка завершена успешно!                              ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Использование:"
    echo ""
    echo -e "  ${BLUE}Автоматическая синхронизация iCloud → Termius:${NC}"
    echo "    Запускается автоматически через LaunchAgent:"
    echo "    - При изменении SSH config в iCloud"
    echo "    - Каждые 30 минут"
    echo "    - При входе в систему"
    echo ""
    echo -e "  ${BLUE}Ручной импорт iCloud → Termius:${NC}"
    echo "    termius-import-from-icloud.sh"
    echo "    termius-import-from-icloud.sh --dry-run -v"
    echo ""
    echo -e "  ${BLUE}Экспорт Termius → iCloud (по запросу):${NC}"
    echo "    termius-export-to-icloud.sh"
    echo "    termius-export-to-icloud.sh --dry-run -v"
    echo ""
    echo -e "  ${BLUE}Управление LaunchAgent:${NC}"
    echo "    launchctl list | grep termius     # Статус"
    echo "    launchctl start com.user.termius-import  # Запустить вручную"
    echo "    launchctl stop com.user.termius-import   # Остановить"
    echo ""
    echo "Логи: ${LOG_DIR}/"
    echo "Бэкапы: ${BACKUP_DIR}/"
    echo ""
    echo -e "${YELLOW}Совет:${NC} Добавьте '# termius:ignore' после Host для хостов,"
    echo "       которые не нужно синхронизировать с Termius."
    echo ""
}

uninstall() {
    print_header
    log_info "Удаление системы синхронизации..."
    
    # Выгружаем LaunchAgent
    local plist_path="${LAUNCHD_DIR}/${LAUNCHD_PLIST}"
    if [[ -f "$plist_path" ]]; then
        launchctl unload "$plist_path" 2>/dev/null || true
        rm -f "$plist_path"
        log_info "LaunchAgent удален"
    fi
    
    # Удаляем скрипты
    rm -f "${BIN_DIR}/${IMPORT_SCRIPT}"
    rm -f "${BIN_DIR}/${EXPORT_SCRIPT}"
    log_info "Скрипты удалены"
    
    echo ""
    log_info "Удаление завершено"
    echo ""
    echo "Следующие директории сохранены (удалите вручную при необходимости):"
    echo "  Логи: ${LOG_DIR}/"
    echo "  Бэкапы: ${BACKUP_DIR}/"
    echo ""
}

# ============================================================================
# ОСНОВНАЯ ЛОГИКА
# ============================================================================

main() {
    # Проверяем аргументы
    if [[ "${1:-}" == "--uninstall" ]]; then
        uninstall
        exit 0
    fi
    
    print_header
    
    # Проверки
    check_macos
    check_termius
    check_icloud
    
    # Настройка iCloud
    setup_icloud_ssh_dir
    
    # Установка
    create_directories
    install_scripts
    configure_launchd_plist
    load_launchd
    add_to_path
    
    # Инструкции
    print_usage_instructions
}

main "$@"
