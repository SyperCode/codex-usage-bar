import AppKit
import CodexUsageCore
import Foundation
import UserNotifications

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var currentDate = Date()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: Error?
    @Published private(set) var displayMode: MenuBarDisplayMode
    @Published private(set) var autoRefreshEnabled: Bool
    @Published private(set) var refreshIntervalMinutes: Int
    @Published private(set) var language: AppLanguage
    @Published private(set) var theme: AppTheme
    @Published private(set) var accentChoice: AccentChoice
    @Published private(set) var limitAlertsEnabled: Bool
    @Published private(set) var weeklyWarningThreshold: Int
    @Published private(set) var menuBarBackgroundEnabled: Bool

    private let service = CodexUsageService()
    private let notifications = LimitNotificationService()
    private let defaults: UserDefaults
    private var refreshTimer: Timer?
    private var clockTimer: Timer?
    private var lastAlertLevel: WeeklyAlertLevel = .none

    private enum PreferenceKey {
        static let displayMode = "menuBarDisplayMode"
        static let autoRefreshEnabled = "autoRefreshEnabled"
        static let refreshIntervalMinutes = "refreshIntervalMinutes"
        static let language = "appLanguage"
        static let theme = "appTheme"
        static let accentChoice = "accentChoice"
        static let limitAlertsEnabled = "limitAlertsEnabled"
        static let weeklyWarningThreshold = "weeklyWarningThreshold"
        static let menuBarBackgroundEnabled = "menuBarBackgroundEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.displayMode = MenuBarDisplayMode(
            rawValue: defaults.string(forKey: PreferenceKey.displayMode) ?? ""
        ) ?? .compact

        if defaults.object(forKey: PreferenceKey.autoRefreshEnabled) == nil {
            self.autoRefreshEnabled = true
        } else {
            self.autoRefreshEnabled = defaults.bool(forKey: PreferenceKey.autoRefreshEnabled)
        }

        let savedInterval = defaults.integer(forKey: PreferenceKey.refreshIntervalMinutes)
        self.refreshIntervalMinutes = [1, 5, 15].contains(savedInterval) ? savedInterval : 5
        self.language = AppLanguage(
            rawValue: defaults.string(forKey: PreferenceKey.language) ?? ""
        ) ?? .english
        self.theme = AppTheme(
            rawValue: defaults.string(forKey: PreferenceKey.theme) ?? ""
        ) ?? .system
        self.accentChoice = AccentChoice(
            rawValue: defaults.string(forKey: PreferenceKey.accentChoice) ?? ""
        ) ?? .indigo
        self.limitAlertsEnabled = defaults.object(forKey: PreferenceKey.limitAlertsEnabled) == nil
            ? true
            : defaults.bool(forKey: PreferenceKey.limitAlertsEnabled)
        let savedWarningThreshold = defaults.integer(forKey: PreferenceKey.weeklyWarningThreshold)
        self.weeklyWarningThreshold = WeeklyAlertPolicy.warningThresholdRange.contains(savedWarningThreshold)
            ? savedWarningThreshold
            : WeeklyAlertPolicy.defaultWarningThreshold
        self.menuBarBackgroundEnabled = defaults.bool(forKey: PreferenceKey.menuBarBackgroundEnabled)

        applyAppAppearance()
        if limitAlertsEnabled { notifications.requestAuthorization() }
        Task { await refresh() }
        configureAutoRefreshTimer()
        configureClockTimer()
    }

    deinit {
        refreshTimer?.invalidate()
        clockTimer?.invalidate()
    }

    func menuBarTitle(at date: Date = Date()) -> String {
        guard let snapshot else {
            return isRefreshing ? "…" : "—"
        }

        if displayMode == .battery,
           let primary = snapshot.primary,
           primary.remainingPercent == 0,
           let resetDate = primary.resetsAt {
            return LimitCountdownFormatter.compact(
                until: resetDate,
                now: date,
                language: language
            )
        }

        if snapshot.primary?.remainingPercent == 0 ||
            (displayMode == .expanded && snapshot.secondary?.remainingPercent == 0) {
            var parts: [String] = []
            if let primary = snapshot.primary {
                parts.append(menuBarPart(for: primary, label: language.text("5h", "5ч"), now: date))
            }
            if displayMode == .expanded, let secondary = snapshot.secondary {
                parts.append(menuBarPart(for: secondary, label: language.text("wk", "нед"), now: date))
            }
            return parts.isEmpty ? "—" : parts.joined(separator: " · ")
        }

        return MenuBarTitleFormatter(language: language.usageDisplayLanguage)
            .string(from: snapshot, mode: displayMode)
    }

    var showsCriticalWeeklyStatus: Bool {
        guard limitAlertsEnabled, let remaining = snapshot?.secondary?.remainingPercent else { return false }
        return WeeklyAlertPolicy.level(
            remainingPercent: remaining,
            warningThreshold: weeklyWarningThreshold
        ) == .critical
    }

    func batterySymbol(for percentage: Int) -> String {
        switch percentage {
        case 76...: return "battery.100percent"
        case 51...: return "battery.75percent"
        case 26...: return "battery.50percent"
        case 11...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    var statusSymbol: String {
        guard let snapshot else {
            return lastError == nil ? "gauge.with.dots.needle.50percent" : "exclamationmark.triangle"
        }

        if snapshot.primary?.remainingPercent == 0 ||
            (displayMode == .expanded && snapshot.secondary?.remainingPercent == 0) {
            return "arrow.clockwise"
        }

        if displayMode == .battery, let percentage = snapshot.primary?.remainingPercent {
            return batterySymbol(for: percentage)
        }

        let visibleWindows = displayMode == .expanded
            ? [snapshot.primary, snapshot.secondary]
            : [snapshot.primary]
        let minimum = visibleWindows
            .compactMap { $0?.remainingPercent }
            .min() ?? 100

        if minimum <= 10 { return "gauge.with.dots.needle.100percent" }
        if minimum <= 30 { return "gauge.with.dots.needle.67percent" }
        return "gauge.with.dots.needle.33percent"
    }

    var errorMessage: String? {
        guard let lastError else { return nil }

        guard let error = lastError as? CodexUsageError else {
            return lastError.localizedDescription
        }

        switch error {
        case .executableNotFound:
            return language.text(
                "Codex was not found. Install or open the ChatGPT app.",
                "Codex не найден. Установите или откройте приложение ChatGPT."
            )
        case .launchFailed(let details):
            return language.text(
                "Could not start Codex: \(details)",
                "Не удалось запустить Codex: \(details)"
            )
        case .serverError(let details):
            return language.text(
                "Codex returned an error: \(details)",
                "Codex вернул ошибку: \(details)"
            )
        case .invalidResponse:
            return language.text(
                "Codex returned data in an unknown format.",
                "Codex вернул данные в неизвестном формате."
            )
        case .timedOut:
            return language.text(
                "Codex did not respond in time.",
                "Codex не ответил вовремя."
            )
        case .processEnded(let details):
            if details.isEmpty {
                return language.text(
                    "The Codex connection ended unexpectedly.",
                    "Соединение с Codex неожиданно завершилось."
                )
            }
            return language.text(
                "The Codex connection ended: \(details)",
                "Соединение с Codex завершилось: \(details)"
            )
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        do {
            let updatedSnapshot = try await service.fetch()
            snapshot = updatedSnapshot
            lastUpdated = Date()
            lastError = nil
            evaluateWeeklyAlert(updatedSnapshot)
        } catch {
            lastError = error
        }

        isRefreshing = false
    }

    func setDisplayMode(_ mode: MenuBarDisplayMode) {
        displayMode = mode
        defaults.set(mode.rawValue, forKey: PreferenceKey.displayMode)
    }

    func setAutoRefreshEnabled(_ enabled: Bool) {
        autoRefreshEnabled = enabled
        defaults.set(enabled, forKey: PreferenceKey.autoRefreshEnabled)
        configureAutoRefreshTimer()

        if enabled {
            Task { await refresh() }
        }
    }

    func setRefreshIntervalMinutes(_ minutes: Int) {
        guard [1, 5, 15].contains(minutes) else { return }
        refreshIntervalMinutes = minutes
        defaults.set(minutes, forKey: PreferenceKey.refreshIntervalMinutes)
        configureAutoRefreshTimer()
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        defaults.set(language.rawValue, forKey: PreferenceKey.language)
    }

    func setTheme(_ theme: AppTheme) {
        self.theme = theme
        defaults.set(theme.rawValue, forKey: PreferenceKey.theme)
        applyAppAppearance()
    }

    func setAccentChoice(_ accentChoice: AccentChoice) {
        self.accentChoice = accentChoice
        defaults.set(accentChoice.rawValue, forKey: PreferenceKey.accentChoice)
    }

    func setLimitAlertsEnabled(_ enabled: Bool) {
        limitAlertsEnabled = enabled
        defaults.set(enabled, forKey: PreferenceKey.limitAlertsEnabled)
        lastAlertLevel = .none

        guard enabled else {
            notifications.clear()
            return
        }
        notifications.requestAuthorization()
        if let snapshot { evaluateWeeklyAlert(snapshot) }
    }

    func setWeeklyWarningThreshold(_ threshold: Int) {
        let value = min(
            WeeklyAlertPolicy.warningThresholdRange.upperBound,
            max(WeeklyAlertPolicy.criticalThreshold, threshold)
        )
        weeklyWarningThreshold = value
        defaults.set(value, forKey: PreferenceKey.weeklyWarningThreshold)
        lastAlertLevel = .none
        if let snapshot { evaluateWeeklyAlert(snapshot) }
    }

    func setMenuBarBackgroundEnabled(_ enabled: Bool) {
        menuBarBackgroundEnabled = enabled
        defaults.set(enabled, forKey: PreferenceKey.menuBarBackgroundEnabled)
    }

    private func applyAppAppearance() {
        switch theme {
        case .system:
            NSApplication.shared.appearance = nil
        case .light:
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func configureAutoRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        guard autoRefreshEnabled else { return }

        let timer = Timer(timeInterval: TimeInterval(refreshIntervalMinutes * 60), repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func configureClockTimer() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentDate = Date()
            }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func evaluateWeeklyAlert(_ snapshot: UsageSnapshot) {
        guard limitAlertsEnabled, let remaining = snapshot.secondary?.remainingPercent else {
            lastAlertLevel = .none
            return
        }

        let level = WeeklyAlertPolicy.level(
            remainingPercent: remaining,
            warningThreshold: weeklyWarningThreshold
        )
        if level.rawValue > lastAlertLevel.rawValue, level != .none {
            notifications.send(level: level, remainingPercent: remaining, language: language)
        }
        lastAlertLevel = level
    }

    private func menuBarPart(
        for window: UsageWindow,
        label: String,
        now: Date
    ) -> String {
        if window.remainingPercent == 0, let resetDate = window.resetsAt {
            return "\(label) \(LimitCountdownFormatter.compact(until: resetDate, now: now, language: language))"
        }

        return "\(label) \(window.remainingPercent)%"
    }

}

private final class LimitNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func clear() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func send(level: WeeklyAlertLevel, remainingPercent: Int, language: AppLanguage) {
        let content = UNMutableNotificationContent()
        content.title = language.text(
            level == .critical ? "Weekly limit is critical" : "Weekly limit is running low",
            level == .critical ? "Недельный лимит почти исчерпан" : "Недельный лимит заканчивается"
        )
        content.body = language.text(
            "\(remainingPercent)% remains until the weekly reset.",
            "До недельного сброса осталось \(remainingPercent)%."
        )
        content.sound = .default
        center.add(
            UNNotificationRequest(identifier: "weekly-limit-alert", content: content, trigger: nil),
            withCompletionHandler: nil
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
