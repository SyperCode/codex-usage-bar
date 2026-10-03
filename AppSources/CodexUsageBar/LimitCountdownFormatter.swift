import Foundation

enum LimitCountdownFormatter {
    static func compact(
        until resetDate: Date,
        now: Date,
        language: AppLanguage
    ) -> String {
        let remainingSeconds = resetDate.timeIntervalSince(now)
        guard remainingSeconds > 0 else {
            return language.text("restoring now", "восстанавливается")
        }

        let totalMinutes = max(1, Int(ceil(remainingSeconds / 60)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        var components: [String] = []
        if days > 0 {
            components.append(language.text("\(days)d", "\(days) д"))
        }
        if hours > 0 {
            components.append(language.text("\(hours)h", "\(hours) ч"))
        }
        if minutes > 0, days == 0 {
            components.append(language.text("\(minutes)m", "\(minutes) мин"))
        }

        let value = components.isEmpty
            ? language.text("<1m", "<1 мин")
            : components.joined(separator: " ")
        return language.text("in \(value)", "через \(value)")
    }

    static func availableMessage(
        until resetDate: Date,
        now: Date,
        language: AppLanguage
    ) -> String {
        let countdown = compact(until: resetDate, now: now, language: language)
        return language.text("Available \(countdown)", "Восстановится \(countdown)")
    }
}
