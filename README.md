# Codex Usage Bar

Нативное приложение для macOS и Windows, которое показывает оставшиеся лимиты Codex прямо в строке меню или системном трее.

![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows)

## Что показывает приложение

- оставшийся 5-часовой лимит;
- оставшийся недельный лимит;
- точное время следующего сброса;
- состояние подключения и время последнего обновления;
- автоматическое обновление каждые 5 минут;
- быстрый переход на официальную страницу Usage.

Приложение использует уже выполненный вход в ChatGPT/Codex на компьютере. Оно не просит и не хранит API-ключ, пароль или токен аккаунта.

## Скачать

<p>
  <a href="https://github.com/SyperCode/codex-usage-bar/releases/latest/download/Codex-Usage-Bar-macOS.zip">
    <img alt="Скачать для macOS" src="https://img.shields.io/badge/Download_for-macOS-111111?style=for-the-badge&logo=apple&logoColor=white">
  </a>
  <a href="https://github.com/SyperCode/codex-usage-bar/releases/latest/download/Codex-Usage-Bar-Windows-x64.zip">
    <img alt="Скачать для Windows" src="https://img.shields.io/badge/Download_for-Windows-0078D4?style=for-the-badge&logo=windows&logoColor=white">
  </a>
</p>

Кнопки скачивают готовое приложение из [последнего релиза](../../releases/latest).

Выберите файл для своей системы:

| Устройство | Файл |
|---|---|
| Mac с Apple Silicon или Intel | `Codex-Usage-Bar-macOS.zip` |
| Windows 10/11, x64 | `Codex-Usage-Bar-Windows-x64.zip` |

Исходный код скачивать не нужно. Архивы `Source code` на странице релиза предназначены для разработчиков.

## Установка на macOS

1. Установите приложение ChatGPT или Codex и войдите в аккаунт.
2. Скачайте `Codex-Usage-Bar-macOS.zip` из последнего релиза.
3. Распакуйте архив двойным кликом.
4. Переместите `Codex Usage Bar.app` в папку **Программы** (`Applications`).
5. При первом запуске нажмите по приложению правой кнопкой мыши, выберите **Открыть**, затем подтвердите запуск.
6. Иконка и текущий 5-часовой лимит появятся в верхней строке меню macOS.

Приложение пока подписано локальной подписью, а не сертификатом Apple Developer. Поэтому macOS может показать стандартное предупреждение для приложений, загруженных не из App Store. Если система продолжает блокировать запуск, откройте **Системные настройки → Конфиденциальность и безопасность** и нажмите **Всё равно открыть**.

Чтобы приложение запускалось автоматически, откройте его меню → **Settings / Настройки** → включите **Launch at login / Запускать при входе**.

## Установка на Windows

1. Установите Codex и войдите в аккаунт. Команда `codex` должна запускаться в PowerShell.
2. Скачайте `Codex-Usage-Bar-Windows-x64.zip` из последнего релиза.
3. Распакуйте архив в постоянную папку, например `C:\Program Files\Codex Usage Bar` или папку пользователя.
4. Запустите `CodexUsageBar.exe`.
5. Иконка появится в системном трее рядом с часами. Если её не видно, откройте список скрытых значков через стрелку `˄`.

Windows SmartScreen может предупредить о новом неподписанном приложении. Проверьте, что файл скачан из Releases этого репозитория, затем выберите **Подробнее → Выполнить в любом случае**.

В меню значка можно обновить данные, открыть страницу Usage, включить запуск вместе с Windows или закрыть приложение.

## Первый запуск и возможные ошибки

Если вместо процентов показана ошибка:

1. откройте ChatGPT или Codex и убедитесь, что вход выполнен;
2. запустите `codex` в Terminal на macOS или PowerShell на Windows;
3. перезапустите Codex Usage Bar;
4. нажмите **Refresh / Обновить**.

Если команда `codex` не найдена в Windows, установите Codex CLI и заново откройте PowerShell, чтобы обновился `PATH`.

## Конфиденциальность

Codex Usage Bar запускает локальный `codex app-server`, выполняет `account/rateLimits/read` и показывает ответ в интерфейсе. Приложение не отправляет данные на собственный сервер и не содержит аналитики.

## Сборка из исходного кода

### macOS

Требуются macOS 14+, Xcode и Swift 5.10+.

```bash
./scripts/build-app.sh
```

Готовое универсальное приложение для Apple Silicon и Intel появится в `dist/Codex Usage Bar.app`.

### Windows

Требуется .NET 8 SDK.

```powershell
dotnet publish Windows/CodexUsageBar.Windows.csproj -c Release -r win-x64 -o publish
```

Готовый файл появится в `publish/CodexUsageBar.exe`.

## Как выпускаются обновления

GitHub Actions автоматически собирает обе платформы при публикации тега вида `v1.0.0` и прикладывает готовые ZIP-архивы к GitHub Release.

## Ограничения

- macOS: версия 14 или новее;
- Windows: Windows 10/11 x64;
- интерфейс `codex app-server` экспериментальный и может измениться после обновления Codex;
- установщики и автоматическое обновление не добавлены: для небольшого приложения надёжнее скачать новый архив из Releases.
