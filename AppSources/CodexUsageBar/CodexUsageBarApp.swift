import AppKit
import Combine
import CodexUsageCore
import SwiftUI

@main
struct CodexUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = UsageViewModel()
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(viewModel: viewModel)
    }
}

@MainActor
private final class StatusItemController: NSObject {
    private let viewModel: UsageViewModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var stateObserver: AnyCancellable?

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        super.init()

        let hostingController = NSHostingController(rootView: UsageMenuView(viewModel: viewModel))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel(viewModel.language.text("Codex usage", "Лимиты Codex"))
        }

        stateObserver = viewModel.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }
        updateStatusItem()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        if viewModel.showsCriticalSecondaryStatus,
           let primary = viewModel.snapshot?.primary,
           let secondary = viewModel.snapshot?.secondary {
            button.image = nil
            button.attributedTitle = criticalTitle(primary: primary, secondary: secondary)
        } else {
            let image = NSImage(
                systemSymbolName: viewModel.statusSymbol,
                accessibilityDescription: nil
            )
            image?.isTemplate = true
            button.image = image
            button.attributedTitle = NSAttributedString(
                string: " \(viewModel.menuBarTitle(at: viewModel.currentDate))",
                attributes: titleAttributes
            )
        }

        button.setAccessibilityLabel(viewModel.language.text("Codex usage", "Лимиты Codex"))
        button.setAccessibilityValue(accessibilityValue)
        applyBackground(to: button)
    }

    private func criticalTitle(primary: UsageWindow, secondary: UsageWindow) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(batteryAttachment(percentage: primary.remainingPercent))
        result.append(NSAttributedString(
            string: " \(viewModel.shortLabel(for: primary)) \(primary.remainingPercent)% · ",
            attributes: titleAttributes
        ))
        result.append(batteryAttachment(percentage: secondary.remainingPercent))
        result.append(NSAttributedString(
            string: " \(viewModel.shortLabel(for: secondary)) \(secondary.remainingPercent)%",
            attributes: titleAttributes
        ))
        return result
    }

    private func batteryAttachment(percentage: Int) -> NSAttributedString {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        let image = NSImage(
            systemSymbolName: viewModel.batterySymbol(for: percentage),
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        let attachment = NSTextAttachment()
        attachment.image = image
        return NSAttributedString(attachment: attachment)
    }

    private var titleAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
    }

    private func applyBackground(to button: NSStatusBarButton) {
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = viewModel.menuBarBackgroundEnabled
            ? viewModel.accentChoice.nsColor.withAlphaComponent(0.30).cgColor
            : NSColor.clear.cgColor
    }

    private var accessibilityValue: String {
        guard viewModel.showsCriticalSecondaryStatus,
              let primary = viewModel.snapshot?.primary,
              let secondary = viewModel.snapshot?.secondary
        else { return viewModel.menuBarTitle(at: viewModel.currentDate) }

        return "\(viewModel.title(for: primary)) \(primary.remainingPercent)%, "
            + "\(viewModel.title(for: secondary)) \(secondary.remainingPercent)%"
    }
}

private extension AccentChoice {
    var nsColor: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .indigo: return .systemIndigo
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .orange: return .systemOrange
        case .green: return .systemGreen
        case .teal: return .systemTeal
        }
    }
}
