import AppKit
import CodexUsageCore
import Foundation

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

    private let service = CodexUsageService()
    private let defaults: UserDefaults
    private var refreshTimer: Timer?
    private var clockTimer: Timer?

    private enum PreferenceKey {
        static let displayMode = "menuBarDisplayMode"
        static let autoRefreshEnabled = "autoRefreshEnabled"
        static let refreshIntervalMinutes = "refreshIntervalMinutes"
        static let language = "appLanguage"
        static let theme = "appTheme"
        static let accentChoice = "accentChoice"
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

        applyAppAppearance()
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

    var statusSymbol: String {
        guard let snapshot else {
            return lastError == nil ? "gauge.with.dots.needle.50percent" : "exclamationmark.triangle"
        }

        if snapshot.primary?.remainingPercent == 0 ||
            (displayMode == .expanded && snapshot.secondary?.remainingPercent == 0) {
            return "arrow.clockwise"
        }

        let minimum = [snapshot.primary, snapshot.secondary]
            .compactMap { $0?.remainingPercent }
            .min() ?? 100

        if minimum <= 10 { return "gauge.with.dots.needle.100percent" }
        if minimum <= 30 { return "gauge.with.dots.needle.67percent" }
        return "gauge.with.dots.needle.33percent"
    }

    var primaryRemainingPercent: Int? {
        snapshot?.primary?.remainingPercent
    }

    var primaryResetDate: Date? {
        snapshot?.primary?.resetsAt
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
            snapshot = try await service.fetch()
            lastUpdated = Date()
            lastError = nil
        } catch {
            lastError = error
        }

        isRefreshing = false
    }

    func toggleDisplayMode() {
        setDisplayMode(displayMode == .expanded ? .compact : .expanded)
    }

    func toggleBatteryMode() {
        setDisplayMode(displayMode == .battery ? .compact : .battery)
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

    private func menuBarPart(
        for window: UsageWindow,
        label: String,
        now: Date
    ) -> String {
        if window.remainingPercent == 0, let resetDate = window.resetsAt {
            return "\(label) \(LimitCountdownFormatter.compact(until: resetDate, now: now, language: language))"
        }

        guard let resetDate = window.resetsAt else {
            return "\(label) \(window.remainingPercent)%"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .english ? "en_US" : "ru_RU")
        formatter.timeZone = .current
        formatter.dateFormat = label == language.text("wk", "нед")
            ? (language == .english ? "MMM d, HH:mm" : "d MMM, HH:mm")
            : "HH:mm"
        return language.text(
            "\(label) \(window.remainingPercent)% until \(formatter.string(from: resetDate))",
            "\(label) \(window.remainingPercent)% до \(formatter.string(from: resetDate))"
        )
    }

}
