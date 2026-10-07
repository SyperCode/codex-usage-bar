import AppKit
import CodexUsageCore
import SwiftUI

struct UsageMenuView: View {
    @ObservedObject var viewModel: UsageViewModel
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @Environment(\.colorScheme) private var effectiveColorScheme
    @State private var selectedTab: PopoverTab = .overview

    var body: some View {
        ZStack {
            background

            VStack(alignment: .leading, spacing: 14) {
                header
                tabSwitcher

                Group {
                    switch selectedTab {
                    case .overview:
                        overview
                    case .settings:
                        settings
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))

                footer
            }
            .padding(16)
        }
        .frame(width: 392)
        .tint(viewModel.accentChoice.color)
        .preferredColorScheme(viewModel.theme.colorScheme)
        .animation(.snappy(duration: 0.24), value: selectedTab)
    }

    private var background: some View {
        ZStack {
            Rectangle()
                .fill(
                    isDarkAppearance
                        ? Color(red: 0.045, green: 0.052, blue: 0.072)
                        : Color(red: 0.955, green: 0.965, blue: 0.982)
                )

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isDarkAppearance ? 0.48 : 0.72)

            LinearGradient(
                colors: [
                    viewModel.accentChoice.color.opacity(isDarkAppearance ? 0.24 : 0.15),
                    viewModel.accentChoice.color.opacity(isDarkAppearance ? 0.07 : 0.035),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var isDarkAppearance: Bool {
        switch viewModel.theme {
        case .dark: return true
        case .light: return false
        case .system: return effectiveColorScheme == .dark
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Usage")
                    .font(.headline)

                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            RefreshActionButton(viewModel: viewModel)
        }
    }

    private var tabSwitcher: some View {
        Picker(t("Section", "Раздел"), selection: $selectedTab) {
            Label(t("Overview", "Обзор"), systemImage: "chart.bar.fill")
                .tag(PopoverTab.overview)
            Label(t("Settings", "Настройки"), systemImage: "slider.horizontal.3")
                .tag(PopoverTab.settings)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot = viewModel.snapshot {
                usageContent(snapshot)
            } else if viewModel.isRefreshing {
                loadingState
            } else {
                emptyState
            }

            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            keepAwakeControl
        }
    }

    private var keepAwakeControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                t("Keep Mac awake", "Не давать Mac уснуть"),
                isOn: Binding(
                    get: { viewModel.keepAwakeEnabled },
                    set: { viewModel.setKeepAwakeEnabled($0) }
                )
            )
            .toggleStyle(.checkbox)
            .font(.callout.weight(.medium))

            Text(keepAwakeDescription)
            .font(.caption2)
            .foregroundStyle(viewModel.keepAwakeIssue == nil ? Color.secondary : Color.orange)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 12)
    }

    private var keepAwakeDescription: String {
        if let issue = viewModel.keepAwakeIssue { return issue }
        if viewModel.keepAwakeEnabled {
            return t(
                "Active: automatic system sleep is blocked until you turn this off or quit the app.",
                "Активно: автоматический сон заблокирован до выключения функции или выхода из приложения."
            )
        }
        return t(
            "Keeps tasks running while the lid is open. Closing the lid can still put a MacBook to sleep.",
            "Сохраняет работу задач при открытой крышке. Закрытие крышки всё равно может усыпить MacBook."
        )
    }

    @ViewBuilder
    private func usageContent(_ snapshot: UsageSnapshot) -> some View {
        if let primary = snapshot.primary {
            UsageCard(
                title: viewModel.title(for: primary),
                window: primary,
                symbol: "clock",
                language: viewModel.language,
                accent: viewModel.accentChoice.color
            )
        }

        if let secondary = snapshot.secondary {
            UsageCard(
                title: viewModel.title(for: secondary),
                window: secondary,
                symbol: "calendar",
                language: viewModel.language,
                accent: viewModel.accentChoice.color
            )
        }

        if shouldShowCredits(snapshot) {
            creditsRow(snapshot)
                .padding(11)
                .glassPanel(cornerRadius: 12)
        }

        if snapshot.ordinaryUsageAllowed == false {
            Label(
                t("Included usage is exhausted", "Включённый лимит исчерпан"),
                systemImage: "exclamationmark.octagon.fill"
            )
            .font(.caption)
            .foregroundStyle(.red)
        }
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(viewModel.accentChoice.color)
            Text(t("Loading current limits…", "Загружаем текущие лимиты…"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
        .glassPanel(cornerRadius: 14)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(t("Usage data is unavailable", "Данные о лимитах недоступны"))
                .font(.callout.weight(.medium))
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
        .glassPanel(cornerRadius: 14)
    }

    private func errorBanner(_ message: String) -> some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            appearanceSettings
            behaviorSettings
        }
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(t("APPEARANCE", "ОФОРМЛЕНИЕ"))

            settingsRow(t("Language", "Язык"), symbol: "globe") {
                Picker(
                    t("Language", "Язык"),
                    selection: Binding(
                        get: { viewModel.language },
                        set: { viewModel.setLanguage($0) }
                    )
                ) {
                    Text("English").tag(AppLanguage.english)
                    Text("Русский").tag(AppLanguage.russian)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            Divider().opacity(0.42)

            VStack(alignment: .leading, spacing: 8) {
                Label(t("Theme", "Тема"), systemImage: "circle.lefthalf.filled")
                    .font(.callout)

                Picker(
                    t("Theme", "Тема"),
                    selection: Binding(
                        get: { viewModel.theme },
                        set: { viewModel.setTheme($0) }
                    )
                ) {
                    Text(t("System", "Системная")).tag(AppTheme.system)
                    Text(t("Light", "Светлая")).tag(AppTheme.light)
                    Text(t("Dark", "Тёмная")).tag(AppTheme.dark)
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                if viewModel.theme == .system {
                    Text(
                        t(
                            "Following macOS · \(effectiveColorScheme == .dark ? "Dark" : "Light")",
                            "Как в macOS · \(effectiveColorScheme == .dark ? "Тёмная" : "Светлая")"
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            Divider().opacity(0.42)

            VStack(alignment: .leading, spacing: 9) {
                Label(t("Accent color", "Акцентный цвет"), systemImage: "paintpalette.fill")
                    .font(.callout)

                HStack(spacing: 10) {
                    ForEach(AccentChoice.allCases) { choice in
                        Button {
                            withAnimation(.snappy(duration: 0.22)) {
                                viewModel.setAccentChoice(choice)
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(choice.color)
                                    .frame(width: 28, height: 28)

                                if viewModel.accentChoice == choice {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(accentName(choice))
                        .accessibilityLabel(accentName(choice))
                        .accessibilityValue(
                            viewModel.accentChoice == choice
                                ? t("Selected", "Выбран")
                                : t("Not selected", "Не выбран")
                        )
                    }
                }
            }

            Divider().opacity(0.42)

            Toggle(
                t("Menu bar background", "Подложка в строке меню"),
                isOn: Binding(
                    get: { viewModel.menuBarBackgroundEnabled },
                    set: { viewModel.setMenuBarBackgroundEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(13)
        .glassPanel(cornerRadius: 14)
    }

    private var behaviorSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(t("BEHAVIOR", "ПОВЕДЕНИЕ"))

            VStack(alignment: .leading, spacing: 8) {
                Label(t("Menu bar content", "Данные в строке меню"), systemImage: "menubar.rectangle")
                    .font(.callout)

                Picker(
                    t("Menu bar content", "Данные в строке меню"),
                    selection: Binding(
                        get: { viewModel.displayMode },
                        set: { viewModel.setDisplayMode($0) }
                    )
                ) {
                    Text(t("Percent", "Процент")).tag(MenuBarDisplayMode.battery)
                    Text(
                        (viewModel.snapshot?.primary ?? viewModel.snapshot?.secondary)
                            .map { viewModel.title(for: $0) }
                            ?? t("Primary limit", "Основной лимит")
                    )
                    .tag(MenuBarDisplayMode.compact)
                    Text(t("All limits", "Все лимиты")).tag(MenuBarDisplayMode.expanded)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Divider().opacity(0.42)

            Toggle(
                t("Auto refresh", "Автообновление"),
                isOn: Binding(
                    get: { viewModel.autoRefreshEnabled },
                    set: { viewModel.setAutoRefreshEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)

            if viewModel.autoRefreshEnabled {
                settingsRow(t("Refresh interval", "Интервал обновления"), symbol: "timer") {
                    Picker(
                        t("Refresh interval", "Интервал обновления"),
                        selection: Binding(
                            get: { viewModel.refreshIntervalMinutes },
                            set: { viewModel.setRefreshIntervalMinutes($0) }
                        )
                    ) {
                        Text(t("1 minute", "1 минута")).tag(1)
                        Text(t("5 minutes", "5 минут")).tag(5)
                        Text(t("15 minutes", "15 минут")).tag(15)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .font(.caption)
            }

            Divider().opacity(0.42)

            Toggle(
                t("Limit alerts", "Предупреждения о лимитах"),
                isOn: Binding(
                    get: { viewModel.limitAlertsEnabled },
                    set: { viewModel.setLimitAlertsEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)

            if viewModel.limitAlertsEnabled {
                VStack(alignment: .leading, spacing: 7) {
                    if let primary = viewModel.snapshot?.primary {
                        warningThresholdControl(
                            window: primary,
                            threshold: viewModel.primaryWarningThreshold,
                            setThreshold: viewModel.setPrimaryWarningThreshold
                        )
                    }

                    if let secondary = viewModel.snapshot?.secondary {
                        warningThresholdControl(
                            window: secondary,
                            threshold: viewModel.secondaryWarningThreshold,
                            setThreshold: viewModel.setSecondaryWarningThreshold
                        )
                    }

                    notificationControls
                }
            }

            Divider().opacity(0.42)

            Toggle(
                t("Launch after macOS login", "Запускать после входа в macOS"),
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)

            if let issue = launchAtLogin.issue {
                Text(launchAtLoginMessage(for: issue))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().opacity(0.42)

            settingsRow(t("Version", "Версия"), symbol: "info.circle") {
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(13)
        .glassPanel(cornerRadius: 14)
    }

    private func launchAtLoginMessage(for issue: LaunchAtLoginController.Issue) -> String {
        switch issue {
        case .requiresApproval:
            return t(
                "Allow Codex Usage Bar in System Settings → General → Login Items.",
                "Разрешите Codex Usage Bar в «Системные настройки → Основные → Объекты входа»."
            )
        case .registrationFailed:
            return t(
                "Move the app to Applications and try again.",
                "Переместите приложение в папку «Программы» и попробуйте снова."
            )
        }
    }

    private var footer: some View {
        HStack {
            Button(t("Open Usage", "Открыть лимиты")) {
                guard let url = URL(string: "https://chatgpt.com/settings/usage") else { return }
                NSWorkspace.shared.open(url)
            }

            Spacer()

            Button(t("Quit", "Выйти")) {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.link)
        .font(.caption)
        .padding(.horizontal, 2)
    }

    private var headerSubtitle: String {
        if let plan = viewModel.snapshot?.planType {
            return t(
                "\(planDisplayName(plan)) plan · \(updatedText)",
                "Тариф \(planDisplayName(plan)) · \(updatedText)"
            )
        }
        return updatedText
    }

    private var updatedText: String {
        guard let date = viewModel.lastUpdated else {
            return t("updating…", "обновляем…")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: viewModel.language == .english ? "en_US" : "ru_RU")
        formatter.dateFormat = "HH:mm"
        return t(
            "updated at \(formatter.string(from: date))",
            "обновлено в \(formatter.string(from: date))"
        )
    }

    private func warningThresholdControl(
        window: UsageWindow,
        threshold: Int,
        setThreshold: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(viewModel.title(for: window), systemImage: "bell.badge")
                Spacer()
                Text("\(threshold)%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Slider(
                value: Binding(
                    get: { Double(threshold) },
                    set: { setThreshold(Int($0)) }
                ),
                in: Double(LimitAlertPolicy.warningThresholdRange.lowerBound)...Double(LimitAlertPolicy.warningThresholdRange.upperBound),
                step: 5
            )
            .accessibilityLabel(
                t(
                    "Warning threshold for \(viewModel.title(for: window))",
                    "Порог предупреждения: \(viewModel.title(for: window))"
                )
            )
            .accessibilityValue("\(threshold)%")
        }
    }

    @ViewBuilder
    private var notificationControls: some View {
        HStack(spacing: 10) {
            Button(t("Test notification", "Проверить уведомление")) {
                viewModel.sendTestNotification()
            }
            .buttonStyle(.link)

            if viewModel.notificationAuthorizationState == .denied {
                Button(t("Open Settings", "Открыть настройки")) {
                    viewModel.openNotificationSettings()
                }
                .buttonStyle(.link)
            }
        }
        .font(.caption)

        if viewModel.notificationAuthorizationState == .denied {
            Text(
                t(
                    "Notifications are disabled for Codex Usage Bar in macOS.",
                    "Уведомления Codex Usage Bar отключены в macOS."
                )
            )
            .font(.caption2)
            .foregroundStyle(.orange)
        }
    }

    private func planDisplayName(_ plan: String) -> String {
        switch plan.lowercased() {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "promax": return "Pro 500"
        case "prolite": return "Pro 100"
        case "team", "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu": return "Edu"
        default: return plan.capitalized
        }
    }

    private func shouldShowCredits(_ snapshot: UsageSnapshot) -> Bool {
        snapshot.credits?.hasCredits == true ||
            snapshot.credits?.unlimited == true ||
            snapshot.availableResetCredits > 0
    }

    private func creditsRow(_ snapshot: UsageSnapshot) -> some View {
        HStack {
            Label(t("Extra credits", "Дополнительные кредиты"), systemImage: "sparkles")
                .foregroundStyle(.secondary)
            Spacer()
            Text(creditText(snapshot))
                .fontWeight(.semibold)
        }
        .font(.caption)
    }

    private func creditText(_ snapshot: UsageSnapshot) -> String {
        if snapshot.credits?.unlimited == true { return t("Unlimited", "Без ограничений") }
        if let balance = snapshot.credits?.balance, snapshot.credits?.hasCredits == true {
            return balance
        }
        if snapshot.availableResetCredits > 0 {
            return t(
                "Resets: \(snapshot.availableResetCredits)",
                "Сбросы: \(snapshot.availableResetCredits)"
            )
        }
        return "—"
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .tracking(0.7)
            .foregroundStyle(.secondary)
    }

    private func settingsRow<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: symbol)
            Spacer()
            content()
        }
    }

    private func accentName(_ choice: AccentChoice) -> String {
        switch choice {
        case .blue: return t("Blue", "Синий")
        case .indigo: return t("Indigo", "Индиго")
        case .purple: return t("Purple", "Фиолетовый")
        case .pink: return t("Pink", "Розовый")
        case .orange: return t("Orange", "Оранжевый")
        case .green: return t("Green", "Зелёный")
        case .teal: return t("Teal", "Бирюзовый")
        }
    }

    private func t(_ english: String, _ russian: String) -> String {
        viewModel.language.text(english, russian)
    }
}

private enum PopoverTab: Hashable {
    case overview
    case settings
}

private struct RefreshActionButton: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var phase: RefreshPhase = .idle

    var body: some View {
        Button(action: runRefresh) {
            Group {
                if phase == .loading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: symbol)
                        .foregroundStyle(foregroundColor)
                        .scaleEffect(phase == .success ? 1.08 : 1)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 14, height: 14)
        }
        .buttonStyle(
            GlassIconButtonStyle(
                isActive: phase != .idle,
                accent: phase == .failure ? .orange : viewModel.accentChoice.color
            )
        )
        .disabled(viewModel.isRefreshing && phase == .idle)
        .help(viewModel.language.text("Refresh now", "Обновить сейчас"))
        .accessibilityLabel(viewModel.language.text("Refresh usage", "Обновить лимиты"))
    }

    private var symbol: String {
        switch phase {
        case .idle, .loading: return "arrow.clockwise"
        case .success: return "checkmark"
        case .failure: return "exclamationmark"
        }
    }

    private var foregroundColor: Color {
        switch phase {
        case .success: return viewModel.accentChoice.color
        case .failure: return .orange
        default: return .primary
        }
    }

    private func runRefresh() {
        guard phase == .idle, !viewModel.isRefreshing else { return }

        phase = .loading

        Task { @MainActor in
            await viewModel.refresh()

            withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                phase = viewModel.errorMessage == nil ? .success : .failure
            }

            try? await Task.sleep(nanoseconds: 850_000_000)
            withAnimation(.easeOut(duration: 0.18)) {
                phase = .idle
            }
        }
    }
}

private enum RefreshPhase {
    case idle
    case loading
    case success
    case failure
}

private struct UsageCard: View {
    let title: String
    let window: UsageWindow
    let symbol: String
    let language: AppLanguage
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text("\(window.remainingPercent)%")
                    .font(.title3.monospacedDigit().weight(.semibold))
            }

            UsageProgressBar(
                value: window.remainingPercent,
                color: progressColor,
                language: language
            )

            HStack {
                Text(language.text("Remaining", "Осталось"))
                Spacer()
                Text(resetText(now: Date()))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(13)
        .glassPanel(cornerRadius: 14)
    }

    private var progressColor: Color {
        switch window.remainingPercent {
        case 0...10: return .red
        case 11...30: return .orange
        default: return accent
        }
    }

    private func resetText(now: Date) -> String {
        guard let date = window.resetsAt else {
            return language.text("Reset time unknown", "Время сброса неизвестно")
        }

        if window.remainingPercent == 0 {
            return LimitCountdownFormatter.availableMessage(
                until: date,
                now: now,
                language: language
            )
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .english ? "en_US" : "ru_RU")
        formatter.dateFormat = language == .english ? "MMM d, HH:mm" : "d MMM, HH:mm"
        return language.text(
            "Resets \(formatter.string(from: date))",
            "Сброс \(formatter.string(from: date))"
        )
    }
}

private struct UsageProgressBar: View {
    let value: Int
    let color: Color
    let language: AppLanguage

    private var fraction: CGFloat {
        CGFloat(min(100, max(0, value))) / 100
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.09))

                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 7)
        .accessibilityElement()
        .accessibilityLabel(language.text("Remaining usage", "Оставшийся лимит"))
        .accessibilityValue(language.text("\(value) percent", "\(value) процентов"))
    }
}

private struct GlassIconButtonStyle: ButtonStyle {
    var isActive = false
    var accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 28, height: 28)
            .background(
                isActive
                    ? accent.opacity(configuration.isPressed ? 0.28 : 0.17)
                    : Color.primary.opacity(configuration.isPressed ? 0.1 : 0.045),
                in: Circle()
            )
            .contentShape(Circle())
    }
}

private extension View {
    func glassPanel(cornerRadius: CGFloat) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius))
    }
}

private struct GlassPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        shape.fill(
                            colorScheme == .dark
                                ? Color.white.opacity(0.035)
                                : Color.white.opacity(0.38)
                        )
                    }
            }
    }
}
