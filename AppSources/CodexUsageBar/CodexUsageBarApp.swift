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
        HStack(spacing: 5) {
            Image(systemName: viewModel.statusSymbol)
                .imageScale(.medium)

            Text(viewModel.menuBarTitle(at: viewModel.currentDate))
        }
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: 160, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            viewModel.language.text("Codex usage", "Лимиты Codex")
        )
        .accessibilityValue(viewModel.menuBarTitle(at: viewModel.currentDate))
    }
}
