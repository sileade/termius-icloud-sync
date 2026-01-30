> ## Гайд по ручной установке Termius ↔ iCloud Sync
> 
> **Автор:** Manus AI
> **Версия:** 1.0.0
> 
> Этот гайд предназначен для опытных пользователей, которые предпочитают настраивать систему вручную, без использования интерактивного скрипта `install.sh`. Ручная установка дает полный контроль над всеми путями и параметрами.
> 
> ### Шаг 0: Подготовка
> 
> Убедитесь, что ваша система соответствует требованиям:
> 
> 1.  **macOS 12.0+** (Monterey или новее).
> 2.  **Homebrew** установлен. Если нет, выполните:
>     ```bash
>     /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
>     ```
> 3.  **Termius и Termius CLI** установлены и настроены:
>     ```bash
>     brew install termius
>     termius login
>     ```
> 4.  **iCloud Drive** включен.
> 
> ### Шаг 1: Клонирование репозитория
> 
> Сначала получите все необходимые файлы из репозитория.
> 
> ```bash
> # Клонируем репозиторий
> gh repo clone sileade/termius-icloud-sync
> 
> # Переходим в директорию
> cd termius-icloud-sync
> ```
> 
> ### Шаг 2: Создание директорий и копирование скриптов
> 
> Мы разместим исполняемые скрипты в `~/.local/bin`, а конфигурационные файлы и логи — в других директориях внутри `~/.local`.
> 
> 1.  **Создайте директории**:
>     ```bash
>     # Директория для исполняемых скриптов
>     mkdir -p ~/.local/bin
> 
>     # Директории для логов и бэкапов
>     mkdir -p ~/.local/log/termius-sync
>     mkdir -p ~/.local/backup/ssh-config
>     ```
> 
> 2.  **Скопируйте скрипты** в `~/.local/bin`:
>     ```bash
>     cp scripts/termius-import-from-icloud.sh ~/.local/bin/
>     cp scripts/termius-export-to-icloud.sh ~/.local/bin/
>     ```
> 
> 3.  **Сделайте скрипты исполняемыми**:
>     ```bash
>     chmod +x ~/.local/bin/termius-import-from-icloud.sh
>     chmod +x ~/.local/bin/termius-export-to-icloud.sh
>     ```
> 
> ### Шаг 3: Настройка PATH
> 
> Чтобы вызывать скрипты по имени из любой директории, добавьте `~/.local/bin` в переменную окружения `PATH`.
> 
> 1.  **Определите ваш shell** (скорее всего, zsh):
>     ```bash
>     echo $SHELL
>     ```
> 
> 2.  **Добавьте строку в ваш конфигурационный файл** (`.zshrc` для zsh или `.bash_profile` для bash):
> 
>     **Для zsh:**
>     ```bash
>     echo '\n# Add ~/.local/bin to PATH\nexport PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
>     ```
> 
>     **Для bash:**
>     ```bash
>     echo '\n# Add ~/.local/bin to PATH\nexport PATH="$HOME/.local/bin:$PATH"' >> ~/.bash_profile
>     ```
> 
> 3.  **Перезапустите терминал** или примените изменения командой `source ~/.zshrc` (или `source ~/.bash_profile`).
> 
> ### Шаг 4: Настройка центрального конфига в iCloud
> 
> Это самый важный шаг. Мы переместим ваш `~/.ssh/config` в iCloud и создадим на его месте символическую ссылку.
> 
> 1.  **Создайте директорию в iCloud Drive** для хранения конфига. Например, `SSH`.
>     ```bash
>     mkdir -p "$HOME/Library/Mobile Documents/com~apple~CloudDocs/SSH"
>     ```
>     *Вы можете выбрать любую другую директорию в iCloud Drive.*
> 
> 2.  **Переместите ваш текущий конфиг** в эту директорию. Если у вас нет файла `~/.ssh/config`, создайте его.
>     ```bash
>     # Если файл существует, перемещаем его
>     if [ -f ~/.ssh/config ]; then
>         mv ~/.ssh/config "$HOME/Library/Mobile Documents/com~apple~CloudDocs/SSH/config"
>     # Если файла нет, создаем пустой
>     else
>         touch "$HOME/Library/Mobile Documents/com~apple~CloudDocs/SSH/config"
>     fi
>     ```
> 
> 3.  **Создайте символическую ссылку** (симлинк):
>     ```bash
>     ln -s "$HOME/Library/Mobile Documents/com~apple~CloudDocs/SSH/config" ~/.ssh/config
>     ```
> 
> Теперь ваш `~/.ssh/config` — это просто указатель на файл в iCloud.
> 
> ### Шаг 5: Настройка автоматического импорта через `launchd`
> 
> `launchd` — это системный сервис macOS для запуска фоновых задач. Мы настроим его так, чтобы он следил за изменениями в вашем iCloud-конфиге.
> 
> 1.  **Скопируйте `.plist` файл** из репозитория в системную директорию `LaunchAgents`:
>     ```bash
>     cp launchd/com.user.termius-import.plist ~/Library/LaunchAgents/
>     ```
> 
> 2.  **Отредактируйте этот файл**, чтобы указать правильный путь к вашему конфигу в iCloud. Откройте его в текстовом редакторе:
>     ```bash
>     open ~/Library/LaunchAgents/com.user.termius-import.plist
>     ```
> 
> 3.  **Найдите** секцию `WatchPaths` и **замените путь** на тот, который вы создали в Шаге 4.
>     ```xml
>     <key>WatchPaths</key>
>     <array>
>         <!-- ЗАМЕНИТЕ ЭТОТ ПУТЬ НА ВАШ -->
>         <string>/Users/your_user/Library/Mobile Documents/com~apple~CloudDocs/SSH/config</string>
>     </array>
>     ```
>     *Не используйте `$HOME` или `~`, здесь нужен полный путь.*
> 
> 4.  **Загрузите и запустите** ваш новый `LaunchAgent`:
>     ```bash
>     launchctl load ~/Library/LaunchAgents/com.user.termius-import.plist
>     ```
> 
> Теперь `launchd` будет автоматически запускать `termius-import-from-icloud.sh` каждый раз, когда вы сохраняете изменения в файле `config`.
> 
> ### Шаг 6: Проверка
> 
> Процесс проверки идентичен тому, что описан в [гайде по автоматической установке](SETUP_GUIDE.md#шаг-3-проверка-работы).
> 
> 1.  Добавьте новый хост в `~/.ssh/config`.
> 2.  Подождите 15 секунд и проверьте, появился ли он в Termius.
> 3.  Добавьте хост с пометкой `# termius:ignore` и убедитесь, что он **не** появился.
> 4.  Добавьте хост в Termius и запустите `termius-export-to-icloud.sh`, чтобы проверить экспорт.
> 
> ### Удаление
> 
> Чтобы удалить систему, выполните обратные действия:
> 
> 1.  **Выгрузите `LaunchAgent`**:
>     ```bash
>     launchctl unload ~/Library/LaunchAgents/com.user.termius-import.plist
>     rm ~/Library/LaunchAgents/com.user.termius-import.plist
>     ```
> 2.  **Удалите симлинк** и верните конфиг на место:
>     ```bash
>     rm ~/.ssh/config
>     mv "$HOME/Library/Mobile Documents/com~apple~CloudDocs/SSH/config" ~/.ssh/config
>     ```
> 3.  **Удалите скрипты**:
>     ```bash
>     rm ~/.local/bin/termius-import-from-icloud.sh
>     rm ~/.local/bin/termius-export-to-icloud.sh
>     ```
> 4.  При желании удалите директории логов и бэкапов.
> 
> Поздравляем, вы успешно настроили систему вручную!
