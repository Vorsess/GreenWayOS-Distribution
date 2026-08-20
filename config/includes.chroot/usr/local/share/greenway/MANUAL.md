# 🛡️ GreenWayOS Security Module

Модуль безопасности для управления защитой системы, режимом паники и анонимным режимом.

## Команды

### Установка уровня безопасности
```bash
greenway-security level <normal|elevated|high|critical|panic>
```

### Режим паники (экстренная защита)
```bash
greenway-security panic              # Активировать
greenway-security deactivate-panic   # Деактивировать
```

**Что делает режим паники:**
- Немедленно закрывает все приложения
- Отключает сеть
- Блокирует USB-порты (кроме клавиатуры/мыши)
- Очищает буфер обмена
- Удаляет временные файлы

### Анонимный режим
```bash
greenway-security anonymous
```

**Что делает анонимный режим:**
- Очищает историю команд
- Отключает системное логирование
- Рандомизирует MAC-адрес
- Отключает телеметрию
- Использует приватные DNS (Cloudflare, Quad9)

### Просмотр статуса
```bash
greenway-security status
```

### Просмотр лога безопасности
```bash
greenway-security log [--lines 50]
```

---

# 🔄 GreenWayOS Recovery Manager

Система восстановления, создания снимков системы и аварийного сброса.

## Команды

### Создание снимка системы
```bash
greenway-recovery snapshot [--name имя] [--desc "описание"] [--type full|system|home|config]
```

**Типы снимков:**
- `full` - полная резервная копия
- `system` - только системные файлы
- `home` - только домашняя директория
- `config` - только конфигурации

### Список снимков
```bash
greenway-recovery list
```

### Восстановление из снимка
```bash
greenway-recovery restore <имя_снимка> [--force]
```

### Проверка целостности снимка
```bash
greenway-recovery verify <имя_снимка>
```

### Удаление снимка
```bash
greenway-recovery delete <имя_снимка>
```

### Сброс к заводским настройкам
```bash
greenway-recovery factory-reset [--confirm]
```

⚠️ **ВНИМАНИЕ:** Это действие удалит все пользовательские данные!

### Аварийный режим
```bash
greenway-recovery emergency
```

### Просмотр лога восстановления
```bash
greenway-recovery log [--lines 50]
```

---

# 🎨 GreenWayOS Theme Engine

Динамическое управление темами в стиле Watch Dogs ctOS HUD.

## Команды

### Список доступных тем
```bash
greenway-theme list
```

### Применение темы
```bash
greenway-theme apply <theme_id>
```

### Создание пользовательской темы
```bash
greenway-theme create "Название темы" [--base ctos-hud-default]
```

### Экспорт темы
```bash
greenway-theme export <theme_id> /path/to/output.tar.gz
```

### Импорт темы
```bash
greenway-theme import /path/to/theme.tar.gz
```

### Авто-переключение по времени
```bash
greenway-theme auto
```

---

# ⚡ GreenWayOS Performance Manager

Управление производительностью, драйверами и мониторинг в стиле HUD.

## Команды

### Установка профиля производительности
```bash
greenway-performance profile <power_save|balanced|performance|gaming|low_latency>
```

**Профили:**
- `power_save` - энергосбережение
- `balanced` - сбалансированный (по умолчанию)
- `performance` - максимальная производительность
- `gaming` - игровой режим с оптимизациями
- `low_latency` - режим низкой задержки

### Определение оборудования
```bash
greenway-performance detect
```

### Установка драйверов
```bash
greenway-performance install-driver <nvidia|amd|intel|wifi>
```

### Системный мониторинг
```bash
greenway-performance monitor [--hud]
```

**HUD режим** показывает мониторинг в стиле Watch Dogs ctOS.

---

# 📦 GreenWayOS Package Manager

Умный менеджер пакетов с магазином приложений.

## Команды

### Обновление кэша пакетов
```bash
greenway-pkg update
```

### Обновление системы
```bash
greenway-pkg upgrade [--full]
```

### Установка пакета
```bash
greenway-pkg install <package_name> [--simulate]
```

### Удаление пакета
```bash
greenway-pkg remove <package_name> [--purge]
```

### Поиск пакетов
```bash
greenway-pkg search <query>
```

### Информация о пакете
```bash
greenway-pkg info <package_name>
```

### Список пакетов
```bash
greenway-pkg list [--installed] [--upgradable] [--filter query]
```

### Очистка кэша
```bash
greenway-pkg clean
```

### Магазин приложений
```bash
greenway-pkg store [--gui]
```

---

## 🔧 Все утилиты доступны через:

```bash
greenway-security    # Безопасность
greenway-recovery    # Восстановление
greenway-theme       # Темы
greenway-performance # Производительность
greenway-pkg         # Менеджер пакетов
```

Для получения помощи по каждой утилите используйте флаг `--help`:
```bash
greenway-security --help
```
