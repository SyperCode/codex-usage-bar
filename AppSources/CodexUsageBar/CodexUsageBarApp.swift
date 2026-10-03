import SwiftUI

@main
struct CodexUsageBarApp: App {
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView(viewModel: viewModel)
        } label: {
            MenuBarStatusLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        if viewModel.displayMode == .battery {
            BatteryMenuBarLabel(
                percentage: viewModel.primaryRemainingPercent,
                resetDate: viewModel.primaryResetDate,
                now: viewModel.currentDate,
                language: viewModel.language
            )
        } else {
            HStack(spacing: 5) {
                Image(systemName: viewModel.statusSymbol)
                    .imageScale(.medium)

                Text(viewModel.menuBarTitle(at: viewModel.currentDate))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

private struct BatteryMenuBarLabel: View {
    let percentage: Int?
    let resetDate: Date?
    let now: Date
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 5) {
            if percentage == 0, let resetLabel {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.medium)
                Text(resetLabel)
            } else {
                BatteryGlyph(percentage: percentage ?? 0)

                if let percentage {
                Text("\(percentage)%")
                    .fontWeight(.semibold)

                    if let resetLabel {
                        Text(resetLabel)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("…")
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            language.text("Codex five-hour limit", "Пятичасовой лимит Codex")
        )
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let percentage else { return language.text("Updating", "Обновление") }
        if let resetLabel {
            return language.text(
                "\(percentage) percent remaining, \(resetLabel)",
                "Осталось \(percentage) процентов, \(resetLabel)"
            )
        }
        return language.text(
            "\(percentage) percent remaining",
            "Осталось \(percentage) процентов"
        )
    }

    private var resetLabel: String? {
        guard let resetDate else { return nil }
        if percentage == 0 {
            return LimitCountdownFormatter.compact(
                until: resetDate,
                now: now,
                language: language
            )
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .english ? "en_US" : "ru_RU")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return language.text(
            "until \(formatter.string(from: resetDate))",
            "до \(formatter.string(from: resetDate))"
        )
    }
}

private struct BatteryGlyph: View {
    let percentage: Int

    private var level: CGFloat {
        CGFloat(min(100, max(0, percentage))) / 100
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(lineWidth: 1.2)

                if level > 0 {
                    RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                        .fill(.primary)
                        .frame(width: 17 * level, height: 6)
                        .padding(.leading, 2)
                }
            }
            .frame(width: 21, height: 10)

            Capsule()
                .fill(.primary)
                .frame(width: 2, height: 5)
        }
        .frame(width: 25, height: 12)
    }
}
