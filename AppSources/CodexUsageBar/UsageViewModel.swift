import AppKit
import CodexUsageCore
import Foundation
import UserNotifications

enum NotificationAuthorizationState: Equatable {
    case unknown
    case allowed
    case denied
}

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
    @Published private(set) var primaryWarningThreshold: Int
    @Published private(set) var secondaryWarningThreshold: Int
    @Published private(set) var notificationAuthorizationState: NotificationAuthorizationState = .unknown
    @Published private(set) var menuBarBackgroundEnabled: Bool
    @Published private(set) var keepAwakeEnabled = false

    private let service = CodexUsageService()
    private let notifications = LimitNotificationService()
    private let defaults: UserDefaults
    private var refreshTimer: Timer?
    private var clockTimer: Timer?
    private var keepAwakeActivity: NSObjectProtocol?
    private var lastPrimaryAlertLevel: LimitAlertLevel = .none
    private var lastSecondaryAlertLevel: LimitAlertLevel = .none

    private enum PreferenceKey {
        static let displayMode = "menuBarDisplayMode"
        static let autoRefreshEnabled = "autoRefreshEnabled"
        static let refreshIntervalMinutes = "refreshIntervalMinutes"
        static let language = "appLanguage"
        static let theme = "appTheme"
        static let accentChoice = "accentChoice"
        static let limitAlertsEnabled = "limitAlertsEnabled"
        static let primaryWarningThreshold = "primaryWarningThreshold"
        static let secondaryWarningThreshold = "secondaryWarningThreshold"
        static let legacyWeeklyWarningThreshold = "weeklyWarningThreshold"
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
        let savedPrimaryThreshold = defaults.integer(forKey: PreferenceKey.primaryWarningThreshold)
        self.primaryWarningThreshold = LimitAlertPolicy.warningThresholdRange.contains(savedPrimaryThreshold)
            ? savedPrimaryThreshold
            : LimitAlertPolicy.defaultWarningThreshold
        let savedSecondaryThreshold = defaults.object(forKey: PreferenceKey.secondaryWarningThreshold) == nil
            ? defaults.integer(forKey: PreferenceKey.legacyWeeklyWarningThreshold)
            : defaults.integer(forKey: PreferenceKey.secondaryWarningThreshold)
        self.secondaryWarningThreshold = LimitAlertPolicy.warningThresholdRange.contains(savedSecondaryThreshold)
            ? savedSecondaryThreshold
            : LimitAlertPolicy.defaultWarningThreshold
        self.menuBarBackgroundEnabled = defaults.bool(forKey: PreferenceKey.menuBarBackgroundEnabled)

        applyAppAppearance()
        Task { await refresh() }
        configureAutoRefreshTimer()
        configureClockTimer()
    }

    deinit {
        refreshTimer?.invalidate()
        clockTimer?.invalidate()
        if let keepAwakeActivity {
            ProcessInfo.processInfo.endActivity(keepAwakeActivity)
        }
    }

    func menuBarTitle(at date: Date = Date()) -> String {
        guard let snapshot else {
            return isRefreshing ? "…" : "—"
        }
        let leadingWindow = snapshot.primary ?? snapshot.secondary

        if displayMode == .battery,
           let leadingWindow,
           leadingWindow.remainingPercent == 0,
           let resetDate = leadingWindow.resetsAt {
            return LimitCountdownFormatter.compact(
                until: resetDate,
                now: date,
                language: language
            )
        }

        if leadingWindow?.remainingPercent == 0 ||
            (displayMode == .expanded && snapshot.secondary?.remainingPercent == 0) {
            var parts: [String] = []
            if displayMode == .expanded {
                if let primary = snapshot.primary {
                    parts.append(menuBarPart(for: primary, label: shortLabel(for: primary), now: date))
                }
                if let secondary = snapshot.secondary {
                    parts.append(menuBarPart(for: secondary, label: shortLabel(for: secondary), now: date))
                }
            } else if let leadingWindow {
                parts.append(menuBarPart(
                    for: leadingWindow,
                    label: shortLabel(for: leadingWindow),
                    now: date
                ))
            }
            return parts.isEmpty ? "—" : parts.joined(separator: " · ")
        }

        return MenuBarTitleFormatter(language: language.usageDisplayLanguage)
            .string(from: snapshot, mode: displayMode)
    }

    var showsCriticalSecondaryStatus: Bool {
        guard limitAlertsEnabled,
              snapshot?.primary != nil,
              let remaining = snapshot?.secondary?.remainingPercent
        else { return false }
        return LimitAlertPolicy.level(
            remainingPercent: remaining,
            warningThreshold: secondaryWarningThreshold
        ) == .critical
    }

    func title(for window: UsageWindow) -> String {
        window.periodKind.title(language: language.usageDisplayLanguage)
    }

    func shortLabel(for window: UsageWindow) -> String {
        window.periodKind.shortLabel(language: language.usageDisplayLanguage)
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

        let leadingWindow = snapshot.primary ?? snapshot.secondary
        if leadingWindow?.remainingPercent == 0 ||
            (displayMode == .expanded && snapshot.secondary?.remainingPercent == 0) {
            return "arrow.clockwise"
        }

        if displayMode == .battery, let percentage = leadingWindow?.remainingPercent {
            return batterySymbol(for: percentage)
        }

        let visibleWindows = displayMode == .expanded
            ? [snapshot.primary, snapshot.secondary]
            : [leadingWindow]
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
            await evaluateAlerts(updatedSnapshot)
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
        resetAlertLevels()

        guard enabled else {
            notifications.clear()
            notificationAuthorizationState = .unknown
            return
        }
        Task {
            notificationAuthorizationState = await notifications.authorizationState(requestIfNeeded: true)
            if let snapshot { await evaluateAlerts(snapshot) }
        }
    }

    func setPrimaryWarningThreshold(_ threshold: Int) {
        primaryWarningThreshold = clampedThreshold(threshold)
        defaults.set(primaryWarningThreshold, forKey: PreferenceKey.primaryWarningThreshold)
        lastPrimaryAlertLevel = .none
    }

    func setSecondaryWarningThreshold(_ threshold: Int) {
        secondaryWarningThreshold = clampedThreshold(threshold)
        defaults.set(secondaryWarningThreshold, forKey: PreferenceKey.secondaryWarningThreshold)
        lastSecondaryAlertLevel = .none
    }

    func sendTestNotification() {
        Task {
            let state = await notifications.authorizationState(requestIfNeeded: true)
            notificationAuthorizationState = state
            guard state == .allowed else { return }
            await notifications.sendTest(language: language)
        }
    }

    func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func setMenuBarBackgroundEnabled(_ enabled: Bool) {
        menuBarBackgroundEnabled = enabled
        defaults.set(enabled, forKey: PreferenceKey.menuBarBackgroundEnabled)
    }

    func setKeepAwakeEnabled(_ enabled: Bool) {
        guard keepAwakeEnabled != enabled else { return }
        keepAwakeEnabled = enabled

        if let keepAwakeActivity {
            ProcessInfo.processInfo.endActivity(keepAwakeActivity)
            self.keepAwakeActivity = nil
        }

        if enabled {
            keepAwakeActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled],
                reason: "Codex Usage Bar is keeping active tasks running"
            )
        }
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

    private func evaluateAlerts(_ snapshot: UsageSnapshot) async {
        guard limitAlertsEnabled else {
            resetAlertLevels()
            return
        }

        let state = await notifications.authorizationState(requestIfNeeded: true)
        notificationAuthorizationState = state
        guard state == .allowed else { return }

        if let primary = snapshot.primary {
            let level = LimitAlertPolicy.level(
                remainingPercent: primary.remainingPercent,
                warningThreshold: primaryWarningThreshold
            )
            if level.rawValue > lastPrimaryAlertLevel.rawValue, level != .none {
                await notifications.send(
                    identifier: "primary-limit-alert",
                    level: level,
                    window: primary,
                    language: language
                )
            }
            lastPrimaryAlertLevel = level
        } else {
            lastPrimaryAlertLevel = .none
        }

        if let secondary = snapshot.secondary {
            let level = LimitAlertPolicy.level(
                remainingPercent: secondary.remainingPercent,
                warningThreshold: secondaryWarningThreshold
            )
            if level.rawValue > lastSecondaryAlertLevel.rawValue, level != .none {
                await notifications.send(
                    identifier: "secondary-limit-alert",
                    level: level,
                    window: secondary,
                    language: language
                )
            }
            lastSecondaryAlertLevel = level
        } else {
            lastSecondaryAlertLevel = .none
        }
    }

    private func resetAlertLevels() {
        lastPrimaryAlertLevel = .none
        lastSecondaryAlertLevel = .none
    }

    private func clampedThreshold(_ threshold: Int) -> Int {
        min(
            LimitAlertPolicy.warningThresholdRange.upperBound,
            max(LimitAlertPolicy.criticalThreshold, threshold)
        )
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

    func authorizationState(requestIfNeeded: Bool) async -> NotificationAuthorizationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .allowed
        case .denied:
            return .denied
        case .notDetermined:
            guard requestIfNeeded else { return .unknown }
            do {
                return try await center.requestAuthorization(options: [.alert, .sound]) ? .allowed : .denied
            } catch {
                return .denied
            }
        @unknown default:
            return .unknown
        }
    }

    func clear() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func send(
        identifier: String,
        level: LimitAlertLevel,
        window: UsageWindow,
        language: AppLanguage
    ) async {
        let content = UNMutableNotificationContent()
        let limitName = window.periodKind.title(language: language.usageDisplayLanguage)
        content.title = language.text(
            level == .critical ? "\(limitName) is critical" : "\(limitName) is running low",
            level == .critical ? "\(limitName) почти исчерпан" : "\(limitName) заканчивается"
        )
        content.body = language.text(
            "\(window.remainingPercent)% remains until reset.",
            "До сброса осталось \(window.remainingPercent)%."
        )
        content.sound = .default
        try? await center.add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        )
    }

    func sendTest(language: AppLanguage) async {
        let content = UNMutableNotificationContent()
        content.title = language.text("Codex Usage Bar notifications work", "Уведомления Codex Usage Bar работают")
        content.body = language.text(
            "You will be warned when a selected limit reaches its threshold.",
            "Предупреждение появится, когда выбранный лимит достигнет заданного порога."
        )
        content.sound = .default
        try? await center.add(
            UNNotificationRequest(identifier: "limit-alert-test", content: content, trigger: nil)
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
