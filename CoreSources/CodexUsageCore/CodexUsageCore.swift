import Foundation

public enum UsageDisplayLanguage: String, CaseIterable, Sendable {
    case english
    case russian
}

public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case battery
    case compact
    case expanded

    public var id: String { rawValue }
}

public enum LimitAlertLevel: Int, Sendable {
    case none
    case warning
    case critical
}

public enum LimitAlertPolicy {
    public static let criticalThreshold = 10
    public static let defaultWarningThreshold = 20
    public static let warningThresholdRange = 10...90

    public static func level(remainingPercent: Int, warningThreshold: Int) -> LimitAlertLevel {
        if remainingPercent <= criticalThreshold { return .critical }
        let threshold = min(warningThresholdRange.upperBound, max(criticalThreshold, warningThreshold))
        return remainingPercent <= threshold ? .warning : .none
    }
}

public enum UsagePeriodKind: Equatable, Sendable {
    case fiveHour
    case hourly(Int)
    case daily
    case weekly
    case monthly
    case days(Int)
    case unknown

    public init(durationMinutes: Int?) {
        guard let minutes = durationMinutes, minutes > 0 else {
            self = .unknown
            return
        }
        switch minutes {
        case 300:
            self = .fiveHour
        case 1_440:
            self = .daily
        case 10_080:
            self = .weekly
        case 40_320...46_080:
            self = .monthly
        default:
            if minutes % 1_440 == 0 {
                self = .days(minutes / 1_440)
            } else if minutes % 60 == 0 {
                self = .hourly(minutes / 60)
            } else {
                self = .unknown
            }
        }
    }

    public func title(language: UsageDisplayLanguage) -> String {
        switch self {
        case .fiveHour:
            return language == .english ? "5-hour limit" : "5-часовой лимит"
        case .hourly(let hours):
            return language == .english ? "\(hours)-hour limit" : "Лимит на \(hours) ч"
        case .daily:
            return language == .english ? "Daily limit" : "Дневной лимит"
        case .weekly:
            return language == .english ? "Weekly limit" : "Недельный лимит"
        case .monthly:
            return language == .english ? "Monthly limit" : "Месячный лимит"
        case .days(let days):
            return language == .english ? "\(days)-day limit" : "Лимит на \(days) дн."
        case .unknown:
            return language == .english ? "Usage limit" : "Лимит использования"
        }
    }

    public func shortLabel(language: UsageDisplayLanguage) -> String {
        switch self {
        case .fiveHour:
            return language == .english ? "5h" : "5ч"
        case .hourly(let hours):
            return language == .english ? "\(hours)h" : "\(hours)ч"
        case .daily:
            return language == .english ? "day" : "день"
        case .weekly:
            return language == .english ? "wk" : "нед"
        case .monthly:
            return language == .english ? "mo" : "мес"
        case .days(let days):
            return language == .english ? "\(days)d" : "\(days)д"
        case .unknown:
            return language == .english ? "limit" : "лимит"
        }
    }
}

public struct UsageWindow: Equatable, Sendable {
    public let usedPercent: Int
    public let windowDurationMinutes: Int?
    public let resetsAt: Date?

    public init(usedPercent: Int, windowDurationMinutes: Int?, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Int { min(100, max(0, 100 - usedPercent)) }

    public var periodKind: UsagePeriodKind {
        UsagePeriodKind(durationMinutes: windowDurationMinutes)
    }

    public var compactDuration: String {
        guard let minutes = windowDurationMinutes else { return "—" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }
}

public struct CreditBalance: Equatable, Sendable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?
}

public struct UsageSnapshot: Equatable, Sendable {
    public let primary: UsageWindow?
    public let secondary: UsageWindow?
    public let credits: CreditBalance?
    public let planType: String?
    public let ordinaryUsageAllowed: Bool?
    public let availableResetCredits: Int

    public init(
        primary: UsageWindow?,
        secondary: UsageWindow?,
        credits: CreditBalance?,
        planType: String?,
        ordinaryUsageAllowed: Bool?,
        availableResetCredits: Int
    ) {
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.planType = planType
        self.ordinaryUsageAllowed = ordinaryUsageAllowed
        self.availableResetCredits = availableResetCredits
    }
}

public struct RateLimitsReadResponse: Decodable, Sendable {
    private let ordinaryUsageAllowed: Bool?
    private let rateLimits: RateLimits?
    private let rateLimitsByLimitId: [String: RateLimits]?
    private let rateLimitResetCredits: ResetCredits?

    public var usageSnapshot: UsageSnapshot {
        let limits = rateLimits ?? rateLimitsByLimitId?["codex"] ?? rateLimitsByLimitId?.values.first
        return UsageSnapshot(
            primary: limits?.primary?.usageWindow,
            secondary: limits?.secondary?.usageWindow,
            credits: limits?.credits.map {
                CreditBalance(hasCredits: $0.hasCredits, unlimited: $0.unlimited, balance: $0.balance)
            },
            planType: limits?.planType,
            ordinaryUsageAllowed: ordinaryUsageAllowed,
            availableResetCredits: rateLimitResetCredits?.availableCount ?? 0
        )
    }
}

private struct RateLimits: Decodable, Sendable {
    let primary: RateWindow?
    let secondary: RateWindow?
    let credits: Credits?
    let planType: String?
}

private struct RateWindow: Decodable, Sendable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?

    var usageWindow: UsageWindow {
        UsageWindow(
            usedPercent: Int(usedPercent.rounded()),
            windowDurationMinutes: windowDurationMins,
            resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:))
        )
    }
}

private struct Credits: Decodable, Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

private struct ResetCredits: Decodable, Sendable {
    let availableCount: Int
}

public enum CodexUsageError: LocalizedError, Sendable {
    case executableNotFound
    case launchFailed(String)
    case serverError(String)
    case invalidResponse
    case timedOut
    case processEnded(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound: return "Codex executable was not found."
        case .launchFailed(let details): return "Could not launch Codex: \(details)"
        case .serverError(let details): return "Codex returned an error: \(details)"
        case .invalidResponse: return "Codex returned an invalid response."
        case .timedOut: return "Codex did not respond in time."
        case .processEnded(let details): return "Codex stopped before returning usage data: \(details)"
        }
    }
}

public struct CodexUsageService: Sendable {
    public init() {}

    public func fetch() async throws -> UsageSnapshot {
        guard let executable = Self.findCodexExecutable() else {
            throw CodexUsageError.executableNotFound
        }
        return try await AppServerSession(executable: executable).fetch()
    }

    private static func findCodexExecutable() -> URL? {
        let fixedPaths = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        for path in fixedPaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory)).appendingPathComponent("codex").path
            if FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }
}

private final class AppServerSession: @unchecked Sendable {
    private let executable: URL
    private let lock = NSLock()
    private var finished = false
    private var buffer = Data()
    private var errorBuffer = Data()
    private var process: Process?
    private var timer: DispatchSourceTimer?
    private var continuation: CheckedContinuation<UsageSnapshot, Error>?

    init(executable: URL) { self.executable = executable }

    func fetch() async throws -> UsageSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            start()
        }
    }

    private func start() {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        self.process = process

        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.lock.withLock { self?.errorBuffer.append(handle.availableData) }
        }
        process.terminationHandler = { [weak self] _ in self?.processDidEnd() }

        do {
            try process.run()
            let messages = [
                #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-usage-bar","title":"Codex Usage Bar","version":"0.2.15"}}}"#,
                #"{"jsonrpc":"2.0","method":"initialized","params":{}}"#,
                #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}"#
            ].joined(separator: "\n") + "\n"
            try input.fileHandleForWriting.write(contentsOf: Data(messages.utf8))
        } catch {
            finish(.failure(CodexUsageError.launchFailed(error.localizedDescription)))
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + 12)
        timer.setEventHandler { [weak self] in self?.finish(.failure(CodexUsageError.timedOut)) }
        timer.resume()
        self.timer = timer
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        let lines: [Data] = lock.withLock {
            buffer.append(data)
            var found: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                found.append(buffer[..<newline])
                buffer.removeSubrange(...newline)
            }
            return found
        }
        for line in lines { parse(line) }
    }

    private func parse(_ line: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let id = object["id"] as? NSNumber,
            id.intValue == 2
        else { return }

        if let error = object["error"] as? [String: Any] {
            finish(.failure(CodexUsageError.serverError(error["message"] as? String ?? "Unknown error")))
            return
        }
        guard let result = object["result"],
              let data = try? JSONSerialization.data(withJSONObject: result),
              let response = try? JSONDecoder().decode(RateLimitsReadResponse.self, from: data)
        else {
            finish(.failure(CodexUsageError.invalidResponse))
            return
        }
        finish(.success(response.usageSnapshot))
    }

    private func processDidEnd() {
        let details = lock.withLock { String(data: errorBuffer, encoding: .utf8) ?? "" }
        finish(.failure(CodexUsageError.processEnded(details.trimmingCharacters(in: .whitespacesAndNewlines))))
    }

    private func finish(_ result: Result<UsageSnapshot, Error>) {
        let continuation: CheckedContinuation<UsageSnapshot, Error>? = lock.withLock {
            guard !finished else { return nil }
            finished = true
            let value = self.continuation
            self.continuation = nil
            return value
        }
        guard let continuation else { return }
        timer?.cancel()
        process?.standardOutput.flatMap { ($0 as? Pipe)?.fileHandleForReading }?.readabilityHandler = nil
        process?.standardError.flatMap { ($0 as? Pipe)?.fileHandleForReading }?.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
        continuation.resume(with: result)
    }
}

private extension NSLock {
    func withLock<T>(_ action: () -> T) -> T {
        lock()
        defer { unlock() }
        return action()
    }
}

public struct MenuBarTitleFormatter: Sendable {
    private let language: UsageDisplayLanguage
    private let locale: Locale
    private let timeZone: TimeZone

    public init(
        language: UsageDisplayLanguage = .english,
        locale: Locale? = nil,
        timeZone: TimeZone = .current
    ) {
        self.language = language
        self.locale = locale ?? Locale(identifier: language == .english ? "en_US" : "ru_RU")
        self.timeZone = timeZone
    }

    public func string(from snapshot: UsageSnapshot, mode: MenuBarDisplayMode) -> String {
        let leadingWindow = snapshot.primary ?? snapshot.secondary
        if mode == .battery {
            return leadingWindow.map { "\($0.remainingPercent)%" } ?? "—"
        }

        if mode == .expanded {
            let primary = snapshot.primary.map { "\($0.periodKind.shortLabel(language: language)) \($0.remainingPercent)%" }
            let secondary = snapshot.secondary.map { "\($0.periodKind.shortLabel(language: language)) \($0.remainingPercent)%" }
            let parts = [primary, secondary].compactMap { $0 }
            return parts.isEmpty ? "—" : parts.joined(separator: " · ")
        }

        var parts: [String] = []
        if let leadingWindow {
            parts.append(part(
                leadingWindow,
                shortLabel: leadingWindow.periodKind.shortLabel(language: language)
            ))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func part(_ window: UsageWindow, shortLabel: String) -> String {
        var text = "\(shortLabel) \(window.remainingPercent)%"
        guard let reset = window.resetsAt else { return text }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        text += language == .english ? " until \(formatter.string(from: reset))" : " до \(formatter.string(from: reset))"
        return text
    }
}
