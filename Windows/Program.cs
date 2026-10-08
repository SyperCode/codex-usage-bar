using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Win32;

namespace CodexUsageBar;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApplication());
    }
}

internal sealed class TrayApplication : ApplicationContext
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValue = "Codex Usage Bar";
    private const string SettingsKey = @"Software\Migalev\CodexUsageBar";
    private const string AutoRefreshValue = "AutoRefreshEnabled";
    private const string RefreshIntervalValue = "RefreshIntervalMinutes";
    private const string LimitAlertsValue = "LimitAlertsEnabled";
    private const string PrimaryWarningThresholdValue = "PrimaryWarningThreshold";
    private const string SecondaryWarningThresholdValue = "SecondaryWarningThreshold";
    private const string LegacyWarningThresholdValue = "WeeklyWarningThreshold";
    private const int CriticalThreshold = 10;
    private readonly bool russian = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ru";
    private readonly NotifyIcon tray;
    private readonly ToolStripMenuItem fiveHour;
    private readonly ToolStripMenuItem weekly;
    private readonly ToolStripMenuItem updated;
    private readonly ToolStripMenuItem autoRefresh;
    private readonly ToolStripMenuItem refreshInterval;
    private readonly ToolStripMenuItem limitAlerts;
    private readonly ToolStripMenuItem warningThresholds;
    private readonly ToolStripMenuItem primaryWarningThreshold;
    private readonly ToolStripMenuItem secondaryWarningThreshold;
    private readonly ToolStripMenuItem keepAwake;
    private readonly ToolStripMenuItem launchAtLogin;
    private readonly System.Windows.Forms.Timer timer;
    private bool refreshInProgress;
    private int lastPrimaryAlertLevel;
    private int lastSecondaryAlertLevel;
    private UsageSnapshot? latestUsage;

    public TrayApplication()
    {
        var savedRefreshInterval = ReadRefreshInterval();
        timer = new System.Windows.Forms.Timer {
            Interval = savedRefreshInterval * 60 * 1000,
            Enabled = false
        };
        timer.Tick += async (_, _) => await RefreshAsync();

        fiveHour = new ToolStripMenuItem(T("5-hour limit: loading…", "5-часовой лимит: загрузка…")) { Enabled = false };
        weekly = new ToolStripMenuItem(T("Weekly limit: loading…", "Недельный лимит: загрузка…")) { Enabled = false };
        updated = new ToolStripMenuItem(T("Not updated yet", "Ещё не обновлено")) { Enabled = false };
        autoRefresh = new ToolStripMenuItem(T("Auto refresh", "Автообновление")) {
            CheckOnClick = true,
            Checked = ReadAutoRefreshEnabled()
        };
        autoRefresh.CheckedChanged += (_, _) => SetAutoRefresh(autoRefresh.Checked);

        refreshInterval = new ToolStripMenuItem(T("Refresh interval", "Интервал обновления"));
        foreach (var minutes in new[] { 1, 5, 15 })
        {
            var intervalItem = new ToolStripMenuItem(IntervalTitle(minutes)) {
                Checked = minutes == savedRefreshInterval,
                Tag = minutes
            };
            intervalItem.Click += (_, _) => SetRefreshInterval(minutes);
            refreshInterval.DropDownItems.Add(intervalItem);
        }
        refreshInterval.Enabled = autoRefresh.Checked;

        limitAlerts = new ToolStripMenuItem(T("Limit alerts", "Предупреждения о лимитах")) {
            CheckOnClick = true,
            Checked = ReadLimitAlertsEnabled()
        };
        limitAlerts.CheckedChanged += (_, _) => SetLimitAlerts(limitAlerts.Checked);

        warningThresholds = new ToolStripMenuItem(T("Warning thresholds", "Пороги предупреждений"));
        primaryWarningThreshold = CreateThresholdMenu(
            T("Primary limit", "Основной лимит"),
            ReadWarningThreshold(PrimaryWarningThresholdValue),
            SetPrimaryWarningThreshold
        );
        secondaryWarningThreshold = CreateThresholdMenu(
            T("Secondary limit", "Дополнительный лимит"),
            ReadWarningThreshold(SecondaryWarningThresholdValue, LegacyWarningThresholdValue),
            SetSecondaryWarningThreshold
        );
        warningThresholds.DropDownItems.AddRange([primaryWarningThreshold, secondaryWarningThreshold]);
        warningThresholds.Enabled = limitAlerts.Checked;

        keepAwake = new ToolStripMenuItem(T("Keep computer awake", "Не давать компьютеру уснуть")) {
            CheckOnClick = true,
            Checked = false
        };
        keepAwake.CheckedChanged += (_, _) => SetKeepAwake(keepAwake.Checked);

        launchAtLogin = new ToolStripMenuItem(T("Launch with Windows", "Запускать вместе с Windows")) {
            CheckOnClick = true,
            Checked = IsLaunchAtLoginEnabled()
        };
        launchAtLogin.CheckedChanged += (_, _) => SetLaunchAtLogin(launchAtLogin.Checked);

        var refresh = new ToolStripMenuItem(T("Refresh", "Обновить"));
        refresh.Click += async (_, _) => await RefreshAsync();
        var openUsage = new ToolStripMenuItem(T("Open usage page", "Открыть страницу лимитов"));
        openUsage.Click += (_, _) => Process.Start(new ProcessStartInfo("https://chatgpt.com/settings/usage") { UseShellExecute = true });
        var quit = new ToolStripMenuItem(T("Quit", "Выйти"));
        quit.Click += (_, _) => ExitThread();

        var menu = new ContextMenuStrip();
        menu.Items.AddRange([
            fiveHour,
            weekly,
            updated,
            new ToolStripSeparator(),
            refresh,
            autoRefresh,
            refreshInterval,
            new ToolStripSeparator(),
            limitAlerts,
            warningThresholds,
            keepAwake,
            openUsage,
            launchAtLogin,
            new ToolStripSeparator(),
            quit
        ]);
        tray = new NotifyIcon {
            Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? SystemIcons.Application,
            Text = "Codex Usage Bar",
            ContextMenuStrip = menu,
            Visible = true
        };

        timer.Enabled = autoRefresh.Checked;
        _ = RefreshAsync();
    }

    protected override void ExitThreadCore()
    {
        SetKeepAwake(false);
        timer.Dispose();
        tray.Visible = false;
        tray.Dispose();
        base.ExitThreadCore();
    }

    private async Task RefreshAsync()
    {
        if (refreshInProgress) return;
        refreshInProgress = true;
        fiveHour.Text = T("Usage limit: updating…", "Лимит: обновление…");
        try
        {
            var usage = await CodexClient.ReadUsageAsync();
            fiveHour.Visible = usage.Primary is not null;
            weekly.Visible = usage.Secondary is not null;
            primaryWarningThreshold.Visible = usage.Primary is not null;
            secondaryWarningThreshold.Visible = usage.Secondary is not null;
            fiveHour.Text = FormatWindow(WindowTitle(usage.Primary), usage.Primary);
            weekly.Text = FormatWindow(WindowTitle(usage.Secondary), usage.Secondary);
            primaryWarningThreshold.Text = WindowTitle(usage.Primary);
            secondaryWarningThreshold.Text = WindowTitle(usage.Secondary);
            updated.Text = T("Updated", "Обновлено") + $": {DateTime.Now:HH:mm}";
            latestUsage = usage;
            tray.Text = Tooltip(usage);
            EvaluateAlerts(usage);
        }
        catch (Exception error)
        {
            fiveHour.Text = T("Usage unavailable", "Лимиты недоступны");
            weekly.Visible = true;
            weekly.Text = error.Message.Length > 70 ? error.Message[..70] + "…" : error.Message;
            updated.Text = T("Open Codex or ChatGPT and sign in", "Откройте Codex или ChatGPT и войдите в аккаунт");
            tray.Text = "Codex Usage Bar — " + T("error", "ошибка");
        }
        finally
        {
            refreshInProgress = false;
        }
    }

    private void SetAutoRefresh(bool enabled)
    {
        timer.Enabled = enabled;
        refreshInterval.Enabled = enabled;

        using var key = Registry.CurrentUser.CreateSubKey(SettingsKey);
        key.SetValue(AutoRefreshValue, enabled ? 1 : 0, RegistryValueKind.DWord);

        if (enabled) _ = RefreshAsync();
    }

    private void SetRefreshInterval(int minutes)
    {
        if (minutes is not (1 or 5 or 15)) return;

        timer.Interval = minutes * 60 * 1000;
        foreach (var item in refreshInterval.DropDownItems.OfType<ToolStripMenuItem>())
            item.Checked = item.Tag is int value && value == minutes;

        using var key = Registry.CurrentUser.CreateSubKey(SettingsKey);
        key.SetValue(RefreshIntervalValue, minutes, RegistryValueKind.DWord);
    }

    private void SetLimitAlerts(bool enabled)
    {
        warningThresholds.Enabled = enabled;
        lastPrimaryAlertLevel = 0;
        lastSecondaryAlertLevel = 0;

        using var key = Registry.CurrentUser.CreateSubKey(SettingsKey);
        key.SetValue(LimitAlertsValue, enabled ? 1 : 0, RegistryValueKind.DWord);

        if (latestUsage is { } usage)
        {
            tray.Text = Tooltip(usage);
            if (enabled) EvaluateAlerts(usage);
        }
    }

    private ToolStripMenuItem CreateThresholdMenu(string title, int selected, Action<int> setter)
    {
        var menu = new ToolStripMenuItem(title);
        for (var percentage = 10; percentage <= 90; percentage += 5)
        {
            var thresholdItem = new ToolStripMenuItem($"{percentage}%") {
                Checked = percentage == selected,
                Tag = percentage
            };
            thresholdItem.Click += (sender, _) => setter((int)((ToolStripMenuItem)sender!).Tag!);
            menu.DropDownItems.Add(thresholdItem);
        }
        return menu;
    }

    private void SetPrimaryWarningThreshold(int percentage)
    {
        SetWarningThreshold(primaryWarningThreshold, PrimaryWarningThresholdValue, percentage);
        lastPrimaryAlertLevel = 0;
        if (latestUsage is { } usage) EvaluateAlerts(usage);
    }

    private void SetSecondaryWarningThreshold(int percentage)
    {
        SetWarningThreshold(secondaryWarningThreshold, SecondaryWarningThresholdValue, percentage);
        lastSecondaryAlertLevel = 0;
        if (latestUsage is { } usage) EvaluateAlerts(usage);
    }

    private static void SetWarningThreshold(ToolStripMenuItem menu, string registryName, int percentage)
    {
        var value = Math.Clamp(percentage, CriticalThreshold, 90);
        foreach (var item in menu.DropDownItems.OfType<ToolStripMenuItem>())
            item.Checked = item.Tag is int threshold && threshold == value;

        using var key = Registry.CurrentUser.CreateSubKey(SettingsKey);
        key.SetValue(registryName, value, RegistryValueKind.DWord);
    }

    private void EvaluateAlerts(UsageSnapshot usage)
    {
        if (!limitAlerts.Checked)
        {
            lastPrimaryAlertLevel = 0;
            lastSecondaryAlertLevel = 0;
            return;
        }

        EvaluateAlert(
            usage.Primary,
            ReadWarningThreshold(PrimaryWarningThresholdValue),
            ref lastPrimaryAlertLevel
        );
        EvaluateAlert(
            usage.Secondary,
            ReadWarningThreshold(SecondaryWarningThresholdValue, LegacyWarningThresholdValue),
            ref lastSecondaryAlertLevel
        );
    }

    private void EvaluateAlert(UsageWindow? window, int threshold, ref int lastLevel)
    {
        if (window is null)
        {
            lastLevel = 0;
            return;
        }

        var level = window.Remaining <= CriticalThreshold
            ? 2
            : window.Remaining <= threshold ? 1 : 0;
        if (level > lastLevel)
        {
            var limitName = WindowTitle(window);
            var title = level == 2
                ? T($"{limitName} is critical", $"{limitName} почти исчерпан")
                : T($"{limitName} is running low", $"{limitName} заканчивается");
            var resetText = window.ResetAt is { } resetAt
                ? resetAt.ToLocalTime().ToString("dd.MM HH:mm")
                : T("unknown", "неизвестно");
            var message = T(
                $"Remaining: {window.Remaining}%. Reset: {resetText}.",
                $"Осталось {window.Remaining}%. Сброс: {resetText}."
            );
            tray.ShowBalloonTip(5_000, title, message, level == 2 ? ToolTipIcon.Warning : ToolTipIcon.Info);
        }
        lastLevel = level;
    }

    private string IntervalTitle(int minutes) => minutes switch {
        1 => T("1 minute", "1 минута"),
        5 => T("5 minutes", "5 минут"),
        15 => T("15 minutes", "15 минут"),
        _ => minutes.ToString(CultureInfo.InvariantCulture)
    };

    private string FormatWindow(string title, UsageWindow? window)
    {
        if (window is null) return title + ": —";
        if (window.Remaining == 0 && window.ResetAt is { } resetAt)
            return $"{title}: ↻ {Countdown(resetAt)}";
        var reset = window.ResetAt is null ? "" : T(" · reset ", " · сброс ") + window.ResetAt.Value.ToLocalTime().ToString("dd.MM HH:mm");
        return $"{title}: {window.Remaining}%{reset}";
    }

    private string WindowTitle(UsageWindow? window)
    {
        if (window is null) return T("Usage limit", "Лимит использования");
        return window.DurationMinutes switch {
            300 => T("5-hour limit", "5-часовой лимит"),
            1440 => T("Daily limit", "Дневной лимит"),
            10080 => T("Weekly limit", "Недельный лимит"),
            >= 40320 and <= 46080 => T("Monthly limit", "Месячный лимит"),
            int minutes when minutes % 1440 == 0 => T($"{minutes / 1440}-day limit", $"Лимит на {minutes / 1440} дн."),
            int minutes when minutes % 60 == 0 => T($"{minutes / 60}-hour limit", $"Лимит на {minutes / 60} ч"),
            _ => T("Usage limit", "Лимит использования")
        };
    }

    private string ShortLabel(UsageWindow window)
    {
        return window.DurationMinutes switch {
            300 => T("5h", "5ч"),
            1440 => T("day", "день"),
            10080 => T("wk", "нед"),
            >= 40320 and <= 46080 => T("mo", "мес"),
            int minutes when minutes % 1440 == 0 => T($"{minutes / 1440}d", $"{minutes / 1440}д"),
            int minutes when minutes % 60 == 0 => T($"{minutes / 60}h", $"{minutes / 60}ч"),
            _ => T("limit", "лимит")
        };
    }

    private string Tooltip(UsageSnapshot usage)
    {
        if (limitAlerts.Checked &&
            usage.Primary is { } primaryLimit &&
            usage.Secondary is { Remaining: <= CriticalThreshold } secondaryLimit)
        {
            var criticalText = $"{ShortLabel(primaryLimit)} {primaryLimit.Remaining}% · "
                + $"{ShortLabel(secondaryLimit)} {secondaryLimit.Remaining}%";
            return TruncateTooltip("Codex Usage Bar · " + criticalText);
        }

        var leadingWindow = usage.Primary ?? usage.Secondary;
        var value = leadingWindow switch {
            { Remaining: 0, ResetAt: { } resetAt } => "↻ " + Countdown(resetAt),
            { } leadingLimit => $"{leadingLimit.Remaining}%",
            _ => "—"
        };
        var label = leadingWindow is { } primary ? ShortLabel(primary) : T("limit", "лимит");
        return TruncateTooltip($"Codex Usage Bar · {label} {value}");
    }

    private static string TruncateTooltip(string text) => text.Length <= 63 ? text : text[..63];

    private static void SetKeepAwake(bool enabled)
    {
        SetThreadExecutionState(enabled
            ? ExecutionState.Continuous | ExecutionState.SystemRequired
            : ExecutionState.Continuous);
    }

    private string Countdown(DateTimeOffset resetAt)
    {
        var remaining = resetAt - DateTimeOffset.Now;
        if (remaining <= TimeSpan.Zero) return T("restoring now", "обновляется");
        var minutes = Math.Max(1, (int)Math.Ceiling(remaining.TotalMinutes));
        var days = minutes / 1440;
        var hours = minutes % 1440 / 60;
        var mins = minutes % 60;
        var parts = new List<string>();
        if (days > 0) parts.Add(T($"{days}d", $"{days} д"));
        if (hours > 0) parts.Add(T($"{hours}h", $"{hours} ч"));
        if (mins > 0 && days == 0) parts.Add(T($"{mins}m", $"{mins} мин"));
        return T("in ", "через ") + string.Join(" ", parts);
    }

    private string T(string english, string russianText) => russian ? russianText : english;

    private static bool ReadAutoRefreshEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(SettingsKey);
        return key?.GetValue(AutoRefreshValue) is int enabled ? enabled != 0 : true;
    }

    private static int ReadRefreshInterval()
    {
        using var key = Registry.CurrentUser.OpenSubKey(SettingsKey);
        var minutes = key?.GetValue(RefreshIntervalValue) is int savedMinutes ? savedMinutes : 5;
        return minutes is 1 or 5 or 15 ? minutes : 5;
    }

    private static bool ReadLimitAlertsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(SettingsKey);
        return key?.GetValue(LimitAlertsValue) is int enabled ? enabled != 0 : true;
    }

    private static int ReadWarningThreshold(string valueName, string? fallbackValueName = null)
    {
        using var key = Registry.CurrentUser.OpenSubKey(SettingsKey);
        var stored = key?.GetValue(valueName);
        if (stored is not int && fallbackValueName is not null)
            stored = key?.GetValue(fallbackValueName);
        var threshold = stored is int savedThreshold ? savedThreshold : 20;
        return Math.Clamp(threshold, CriticalThreshold, 90);
    }

    private static bool IsLaunchAtLoginEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey);
        return key?.GetValue(RunValue) is string;
    }

    private static void SetLaunchAtLogin(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (enabled) key.SetValue(RunValue, $"\"{Environment.ProcessPath}\"");
        else key.DeleteValue(RunValue, false);
    }

    [Flags]
    private enum ExecutionState : uint
    {
        SystemRequired = 0x00000001,
        Continuous = 0x80000000
    }

    [DllImport("kernel32.dll")]
    private static extern ExecutionState SetThreadExecutionState(ExecutionState executionState);
}

internal static class CodexClient
{
    public static async Task<UsageSnapshot> ReadUsageAsync()
    {
        using var process = new Process {
            StartInfo = new ProcessStartInfo {
                FileName = FindCodex(),
                Arguments = "app-server --stdio",
                UseShellExecute = false,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            }
        };
        try { process.Start(); }
        catch (Exception error) { throw new InvalidOperationException("Codex: " + error.Message); }

        await process.StandardInput.WriteLineAsync("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"codex-usage-bar\",\"title\":\"Codex Usage Bar\",\"version\":\"0.2.16\"}}}");
        await process.StandardInput.WriteLineAsync("{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}");
        await process.StandardInput.WriteLineAsync("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"account/rateLimits/read\",\"params\":{}}");

        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(12));
        try
        {
            while (await process.StandardOutput.ReadLineAsync(timeout.Token) is { } line)
            {
                using var json = JsonDocument.Parse(line);
                var root = json.RootElement;
                if (!root.TryGetProperty("id", out var id) || id.GetInt32() != 2) continue;
                if (root.TryGetProperty("error", out var serverError))
                    throw new InvalidOperationException(serverError.GetProperty("message").GetString());
                return Parse(root.GetProperty("result"));
            }
            throw new InvalidOperationException("Codex stopped before returning usage data.");
        }
        catch (OperationCanceledException)
        {
            throw new TimeoutException("Codex did not respond in time.");
        }
        finally
        {
            if (!process.HasExited) process.Kill(true);
        }
    }

    private static UsageSnapshot Parse(JsonElement result)
    {
        JsonElement limits;
        if (result.TryGetProperty("rateLimits", out var direct) && direct.ValueKind == JsonValueKind.Object) limits = direct;
        else if (result.TryGetProperty("rateLimitsByLimitId", out var collection) && collection.ValueKind == JsonValueKind.Object)
            limits = collection.EnumerateObject().First().Value;
        else throw new InvalidOperationException("Unknown usage response.");
        return new UsageSnapshot(ReadWindow(limits, "primary"), ReadWindow(limits, "secondary"));
    }

    private static UsageWindow? ReadWindow(JsonElement limits, string name)
    {
        if (!limits.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.Object) return null;
        var used = value.GetProperty("usedPercent").GetDouble();
        DateTimeOffset? reset = null;
        int? durationMinutes = null;
        if (value.TryGetProperty("windowDurationMins", out var duration) && duration.ValueKind == JsonValueKind.Number)
            durationMinutes = duration.GetInt32();
        if (value.TryGetProperty("resetsAt", out var timestamp) && timestamp.ValueKind == JsonValueKind.Number)
            reset = DateTimeOffset.FromUnixTimeSeconds((long)timestamp.GetDouble());
        return new UsageWindow(Math.Clamp((int)Math.Round(100 - used), 0, 100), durationMinutes, reset);
    }

    private static string FindCodex()
    {
        var candidates = new[] {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Codex", "resources", "codex.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "ChatGPT", "resources", "codex.exe")
        };
        return candidates.FirstOrDefault(File.Exists) ?? "codex";
    }
}

internal sealed record UsageWindow(int Remaining, int? DurationMinutes, DateTimeOffset? ResetAt);
internal sealed record UsageSnapshot(UsageWindow? Primary, UsageWindow? Secondary);
