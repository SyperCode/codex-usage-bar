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
        Group {
            if viewModel.showsCriticalWeeklyStatus,
               let primary = viewModel.snapshot?.primary,
               let secondary = viewModel.snapshot?.secondary {
                HStack(spacing: 4) {
                    limitPart(
                        label: viewModel.language.text("5h", "5ч"),
                        percentage: primary.remainingPercent
                    )
                    Text("·").foregroundStyle(.secondary)
                    limitPart(
                        label: viewModel.language.text("wk", "нед"),
                        percentage: secondary.remainingPercent
                    )
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.statusSymbol)
                        .imageScale(.medium)

                    Text(viewModel.menuBarTitle(at: viewModel.currentDate))
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, viewModel.menuBarBackgroundEnabled ? 7 : 0)
        .padding(.vertical, viewModel.menuBarBackgroundEnabled ? 2 : 0)
        .background {
            if viewModel.menuBarBackgroundEnabled {
                Capsule()
                    .fill(viewModel.accentChoice.color.opacity(0.18))
            }
        }
        .frame(maxWidth: 220, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            viewModel.language.text("Codex usage", "Лимиты Codex")
        )
        .accessibilityValue(accessibilityValue)
    }

    private func limitPart(label: String, percentage: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: viewModel.batterySymbol(for: percentage))
                .imageScale(.small)
            Text("\(label) \(percentage)%")
        }
    }

    private var accessibilityValue: String {
        guard viewModel.showsCriticalWeeklyStatus,
              let primary = viewModel.snapshot?.primary,
              let secondary = viewModel.snapshot?.secondary
        else { return viewModel.menuBarTitle(at: viewModel.currentDate) }

        return viewModel.language.text(
            "5-hour limit \(primary.remainingPercent)%, weekly limit \(secondary.remainingPercent)%",
            "5-часовой лимит \(primary.remainingPercent)%, недельный лимит \(secondary.remainingPercent)%"
        )
    }
}
