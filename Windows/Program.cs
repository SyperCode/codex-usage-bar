using System.Diagnostics;
using System.Globalization;
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
    private readonly bool russian = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ru";
    private readonly NotifyIcon tray;
    private readonly ToolStripMenuItem fiveHour;
    private readonly ToolStripMenuItem weekly;
    private readonly ToolStripMenuItem updated;
    private readonly ToolStripMenuItem launchAtLogin;
    private readonly System.Windows.Forms.Timer timer;

    public TrayApplication()
    {
        fiveHour = new ToolStripMenuItem(T("5-hour limit: loading…", "5-часовой лимит: загрузка…")) { Enabled = false };
        weekly = new ToolStripMenuItem(T("Weekly limit: loading…", "Недельный лимит: загрузка…")) { Enabled = false };
        updated = new ToolStripMenuItem(T("Not updated yet", "Ещё не обновлено")) { Enabled = false };
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
        menu.Items.AddRange([fiveHour, weekly, updated, new ToolStripSeparator(), refresh, openUsage, launchAtLogin, new ToolStripSeparator(), quit]);
        tray = new NotifyIcon {
            Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? SystemIcons.Application,
            Text = "Codex Usage Bar",
            ContextMenuStrip = menu,
            Visible = true
        };

        timer = new System.Windows.Forms.Timer { Interval = 5 * 60 * 1000, Enabled = true };
        timer.Tick += async (_, _) => await RefreshAsync();
        _ = RefreshAsync();
    }

    protected override void ExitThreadCore()
    {
        timer.Dispose();
        tray.Visible = false;
        tray.Dispose();
        base.ExitThreadCore();
    }

    private async Task RefreshAsync()
    {
        fiveHour.Text = T("5-hour limit: updating…", "5-часовой лимит: обновление…");
        try
        {
            var usage = await CodexClient.ReadUsageAsync();
            fiveHour.Text = FormatWindow(T("5-hour limit", "5-часовой лимит"), usage.Primary);
            weekly.Text = FormatWindow(T("Weekly limit", "Недельный лимит"), usage.Secondary);
            updated.Text = T("Updated", "Обновлено") + $": {DateTime.Now:HH:mm}";
            tray.Text = Tooltip(usage.Primary);
        }
        catch (Exception error)
        {
            fiveHour.Text = T("Usage unavailable", "Лимиты недоступны");
            weekly.Text = error.Message.Length > 70 ? error.Message[..70] + "…" : error.Message;
            updated.Text = T("Open Codex or ChatGPT and sign in", "Откройте Codex или ChatGPT и войдите в аккаунт");
            tray.Text = "Codex Usage Bar — " + T("error", "ошибка");
        }
    }

    private string FormatWindow(string title, UsageWindow? window)
    {
        if (window is null) return title + ": —";
        if (window.Remaining == 0 && window.ResetAt is { } resetAt)
            return $"{title}: ↻ {Countdown(resetAt)}";
        var reset = window.ResetAt is null ? "" : T(" · reset ", " · сброс ") + window.ResetAt.Value.ToLocalTime().ToString("dd.MM HH:mm");
        return $"{title}: {window.Remaining}%{reset}";
    }

    private string Tooltip(UsageWindow? window)
    {
        var value = window switch {
            { Remaining: 0, ResetAt: { } resetAt } => "↻ " + Countdown(resetAt),
            not null => $"{window.Remaining}%",
            _ => "—"
        };
        var text = $"Codex Usage Bar · 5h {value}";
        return text.Length <= 63 ? text : text[..63];
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

        await process.StandardInput.WriteLineAsync("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"codex-usage-bar\",\"title\":\"Codex Usage Bar\",\"version\":\"0.2.3\"}}}");
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
        if (value.TryGetProperty("resetsAt", out var timestamp) && timestamp.ValueKind == JsonValueKind.Number)
            reset = DateTimeOffset.FromUnixTimeSeconds((long)timestamp.GetDouble());
        return new UsageWindow(Math.Clamp((int)Math.Round(100 - used), 0, 100), reset);
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

internal sealed record UsageWindow(int Remaining, DateTimeOffset? ResetAt);
internal sealed record UsageSnapshot(UsageWindow? Primary, UsageWindow? Secondary);
