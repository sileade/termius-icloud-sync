#!/bin/bash
#
# test_filter.sh
# Тесты для функции фильтрации хостов
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DATA_DIR="${SCRIPT_DIR}/test_data"
TEMP_DIR="/tmp/termius-sync-tests"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Счетчики
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================================
# УТИЛИТЫ
# ============================================================================

setup() {
    mkdir -p "$TEMP_DIR"
    echo "Тестовая директория: $TEMP_DIR"
}

teardown() {
    rm -rf "$TEMP_DIR"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        echo "  Expected to contain: $needle"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        echo "  Expected NOT to contain: $needle"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist: $file}"
    
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        ((TESTS_FAILED++))
        return 1
    fi
}

count_hosts() {
    local file="$1"
    local count
    count=$(grep -c "^Host " "$file" 2>/dev/null || true)
    echo "${count:-0}"
}

# ============================================================================
# ФУНКЦИЯ ФИЛЬТРАЦИИ (копия из основного скрипта для тестирования)
# ============================================================================

filter_ignored_hosts() {
    local input_file="$1"
    local output_file="$2"
    
    awk '
    BEGIN {
        in_host_block = 0
        ignore_current = 0
        buffer = ""
        ignored_count = 0
        imported_count = 0
    }
    
    /^[[:space:]]*(Host|Match)[[:space:]]/ {
        if (in_host_block && !ignore_current && buffer != "") {
            printf "%s", buffer
            imported_count++
        } else if (ignore_current) {
            ignored_count++
        }
        
        in_host_block = 1
        ignore_current = 0
        buffer = $0 "\n"
        next
    }
    
    /# termius:ignore/ {
        ignore_current = 1
        buffer = buffer $0 "\n"
        next
    }
    
    !in_host_block {
        print
        next
    }
    
    {
        buffer = buffer $0 "\n"
    }
    
    END {
        if (in_host_block && !ignore_current && buffer != "") {
            printf "%s", buffer
            imported_count++
        } else if (ignore_current) {
            ignored_count++
        }
        
        print "Импортировано хостов: " imported_count > "/dev/stderr"
        print "Пропущено хостов (termius:ignore): " ignored_count > "/dev/stderr"
    }
    ' "$input_file" > "$output_file"
}

extract_ignored_hosts() {
    local input_file="$1"
    local output_file="$2"
    
    awk '
    BEGIN {
        in_host_block = 0
        is_ignored = 0
        buffer = ""
        ignored_count = 0
    }
    
    /^[[:space:]]*(Host|Match)[[:space:]]/ {
        if (in_host_block && is_ignored && buffer != "") {
            printf "%s", buffer
            ignored_count++
        }
        
        in_host_block = 1
        is_ignored = 0
        buffer = $0 "\n"
        next
    }
    
    /# termius:ignore/ {
        is_ignored = 1
        buffer = buffer $0 "\n"
        next
    }
    
    !in_host_block {
        next
    }
    
    {
        buffer = buffer $0 "\n"
    }
    
    END {
        if (in_host_block && is_ignored && buffer != "") {
            printf "%s", buffer
            ignored_count++
        }
        
        print "Найдено игнорируемых хостов: " ignored_count > "/dev/stderr"
    }
    ' "$input_file" > "$output_file"
}

# ============================================================================
# ТЕСТЫ
# ============================================================================

test_filter_basic() {
    echo ""
    echo "=== Тест 1: Базовая фильтрация ==="
    
    local input="${TEST_DATA_DIR}/sample_ssh_config"
    local output="${TEMP_DIR}/filtered_config"
    
    filter_ignored_hosts "$input" "$output" 2>/dev/null
    
    local content
    content=$(cat "$output")
    
    # Проверяем, что импортируемые хосты присутствуют
    assert_contains "$content" "Host prod-web-01" "prod-web-01 должен быть в выводе"
    assert_contains "$content" "Host dev-api" "dev-api должен быть в выводе"
    assert_contains "$content" "Host k8s-master" "k8s-master должен быть в выводе"
    assert_contains "$content" "Host staging-app" "staging-app должен быть в выводе"
    assert_contains "$content" "Host *.example.com" "Wildcard хост должен быть в выводе"
    
    # Проверяем, что игнорируемые хосты отсутствуют
    assert_not_contains "$content" "Host local-docker" "local-docker НЕ должен быть в выводе"
    assert_not_contains "$content" "Host secret-bastion" "secret-bastion НЕ должен быть в выводе"
    assert_not_contains "$content" "Host temp-test-machine" "temp-test-machine НЕ должен быть в выводе"
}

test_filter_preserves_global_settings() {
    echo ""
    echo "=== Тест 2: Сохранение глобальных настроек ==="
    
    local input="${TEST_DATA_DIR}/sample_ssh_config"
    local output="${TEMP_DIR}/filtered_config"
    
    filter_ignored_hosts "$input" "$output" 2>/dev/null
    
    local content
    content=$(cat "$output")
    
    assert_contains "$content" "AddKeysToAgent yes" "Глобальная настройка AddKeysToAgent должна сохраниться"
    assert_contains "$content" "IdentityFile ~/.ssh/id_ed25519" "Глобальная настройка IdentityFile должна сохраниться"
}

test_filter_host_count() {
    echo ""
    echo "=== Тест 3: Подсчет хостов ==="
    
    local input="${TEST_DATA_DIR}/sample_ssh_config"
    local output="${TEMP_DIR}/filtered_config"
    
    filter_ignored_hosts "$input" "$output" 2>/dev/null
    
    local original_count
    original_count=$(count_hosts "$input")
    
    local filtered_count
    filtered_count=$(count_hosts "$output")
    
    # В sample_ssh_config: 8 хостов, 3 игнорируемых = 5 должно остаться
    assert_equals "8" "$original_count" "Оригинальный файл должен содержать 8 хостов"
    assert_equals "5" "$filtered_count" "Отфильтрованный файл должен содержать 5 хостов"
}

test_extract_ignored_hosts() {
    echo ""
    echo "=== Тест 4: Извлечение игнорируемых хостов ==="
    
    local input="${TEST_DATA_DIR}/sample_ssh_config"
    local output="${TEMP_DIR}/ignored_hosts"
    
    extract_ignored_hosts "$input" "$output" 2>/dev/null
    
    local content
    content=$(cat "$output")
    
    # Проверяем, что игнорируемые хосты присутствуют
    assert_contains "$content" "Host local-docker" "local-docker должен быть в выводе"
    assert_contains "$content" "Host secret-bastion" "secret-bastion должен быть в выводе"
    assert_contains "$content" "Host temp-test-machine" "temp-test-machine должен быть в выводе"
    
    # Проверяем, что обычные хосты отсутствуют
    assert_not_contains "$content" "Host prod-web-01" "prod-web-01 НЕ должен быть в выводе"
    assert_not_contains "$content" "Host dev-api" "dev-api НЕ должен быть в выводе"
    
    local ignored_count
    ignored_count=$(count_hosts "$output")
    assert_equals "3" "$ignored_count" "Должно быть извлечено 3 игнорируемых хоста"
}

test_empty_config() {
    echo ""
    echo "=== Тест 5: Пустой конфиг ==="
    
    local input="${TEMP_DIR}/empty_config"
    local output="${TEMP_DIR}/filtered_empty"
    
    touch "$input"
    
    filter_ignored_hosts "$input" "$output" 2>/dev/null
    
    assert_file_exists "$output" "Выходной файл должен быть создан"
    
    local size
    size=$(wc -c < "$output" | tr -d ' ')
    assert_equals "0" "$size" "Выходной файл должен быть пустым"
}

test_config_only_ignored() {
    echo ""
    echo "=== Тест 6: Конфиг только с игнорируемыми хостами ==="
    
    local input="${TEMP_DIR}/only_ignored_config"
    local output="${TEMP_DIR}/filtered_only_ignored"
    
    cat > "$input" << 'EOF'
Host ignored-1
    # termius:ignore
    HostName 1.1.1.1

Host ignored-2
    # termius:ignore
    HostName 2.2.2.2
EOF
    
    filter_ignored_hosts "$input" "$output" 2>/dev/null
    
    local host_count
    host_count=$(count_hosts "$output")
    assert_equals "0" "$host_count" "Не должно быть хостов в выводе"
}

test_config_no_ignored() {
    echo ""
    echo "=== Тест 7: Конфиг без игнорируемых хостов ==="
    
    local input="${TEMP_DIR}/no_ignored_config"
    local output="${TEMP_DIR}/filtered_no_ignored"
    
    cat > "$input" << 'EOF'
Host server-1
    HostName 1.1.1.1

Host server-2
    HostName 2.2.2.2

Host server-3
    HostName 3.3.3.3
EOF
    
    filter_ignored_hosts "$input" "$output" 2>/dev/null
    
    local host_count
    host_count=$(count_hosts "$output")
    assert_equals "3" "$host_count" "Все 3 хоста должны быть в выводе"
}

test_marker_variations() {
    echo ""
    echo "=== Тест 8: Вариации маркера игнорирования ==="
    
    local input="${TEMP_DIR}/marker_variations"
    local output="${TEMP_DIR}/filtered_variations"
    
    cat > "$input" << 'EOF'
Host host-with-spaces
    # termius:ignore
    HostName 1.1.1.1

Host host-with-text-before
    # some comment # termius:ignore
    HostName 2.2.2.2

Host host-marker-in-middle
    HostName 3.3.3.3
    # termius:ignore
    User admin

Host normal-host
    HostName 4.4.4.4
EOF
    
    filter_ignored_hosts "$input" "$output" 2>/dev/null
    
    local content
    content=$(cat "$output")
    
    # Все хосты с маркером должны быть отфильтрованы
    assert_not_contains "$content" "Host host-with-spaces" "host-with-spaces должен быть отфильтрован"
    assert_not_contains "$content" "Host host-with-text-before" "host-with-text-before должен быть отфильтрован"
    assert_not_contains "$content" "Host host-marker-in-middle" "host-marker-in-middle должен быть отфильтрован"
    
    # Обычный хост должен остаться
    assert_contains "$content" "Host normal-host" "normal-host должен остаться"
}

test_multiline_host_block() {
    echo ""
    echo "=== Тест 9: Многострочные блоки хостов ==="
    
    local input="${TEMP_DIR}/multiline_config"
    local output="${TEMP_DIR}/filtered_multiline"
    
    cat > "$input" << 'EOF'
Host complex-host
    HostName example.com
    User admin
    Port 2222
    IdentityFile ~/.ssh/key
    ForwardAgent yes
    ProxyJump bastion
    LocalForward 8080 localhost:80
    RemoteForward 9090 localhost:90
    ServerAliveInterval 60
    ServerAliveCountMax 3

Host simple-host
    HostName simple.com
EOF
    
    filter_ignored_hosts "$input" "$output" 2>/dev/null
    
    local content
    content=$(cat "$output")
    
    # Проверяем, что все параметры complex-host сохранились
    assert_contains "$content" "HostName example.com" "HostName должен сохраниться"
    assert_contains "$content" "ForwardAgent yes" "ForwardAgent должен сохраниться"
    assert_contains "$content" "ProxyJump bastion" "ProxyJump должен сохраниться"
    assert_contains "$content" "LocalForward 8080 localhost:80" "LocalForward должен сохраниться"
}

test_special_characters_in_hostname() {
    echo ""
    echo "=== Тест 10: Специальные символы в именах хостов ==="
    
    local input="${TEMP_DIR}/special_chars_config"
    local output="${TEMP_DIR}/filtered_special"
    
    cat > "$input" << 'EOF'
Host host-with-dash
    HostName dash.example.com

Host host_with_underscore
    HostName underscore.example.com

Host host.with.dots
    HostName dots.example.com

Host 192.168.1.1
    HostName 192.168.1.1

Host *.wildcard.com
    HostName wildcard.example.com

Host host?pattern
    HostName pattern.example.com
EOF
    
    filter_ignored_hosts "$input" "$output" 2>/dev/null
    
    local host_count
    host_count=$(count_hosts "$output")
    assert_equals "6" "$host_count" "Все 6 хостов со специальными символами должны сохраниться"
}

# ============================================================================
# ЗАПУСК ТЕСТОВ
# ============================================================================

main() {
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Тестирование системы фильтрации SSH-конфига               ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    
    setup
    
    test_filter_basic
    test_filter_preserves_global_settings
    test_filter_host_count
    test_extract_ignored_hosts
    test_empty_config
    test_config_only_ignored
    test_config_no_ignored
    test_marker_variations
    test_multiline_host_block
    test_special_characters_in_hostname
    
    teardown
    
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo -e "Результаты: ${GREEN}$TESTS_PASSED пройдено${NC}, ${RED}$TESTS_FAILED провалено${NC}"
    echo "════════════════════════════════════════════════════════════"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
