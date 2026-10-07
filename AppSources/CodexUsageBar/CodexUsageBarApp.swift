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
    private static let panelSize = NSSize(width: 392, height: 618)

    private let viewModel: UsageViewModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: StatusPanel
    private var stateObserver: AnyCancellable?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        self.panel = StatusPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize))
        super.init()

        let hostingController = NSHostingController(rootView: UsageMenuView(viewModel: viewModel))
        hostingController.view.frame = NSRect(origin: .zero, size: Self.panelSize)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 18
        hostingController.view.layer?.cornerCurve = .continuous
        hostingController.view.layer?.masksToBounds = true

        panel.contentViewController = hostingController
        panel.setContentSize(Self.panelSize)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

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
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover() {
        if panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button else { return }
        positionPanel(below: button)
        panel.makeKeyAndOrderFront(nil)
        startOutsideClickMonitors()
        updateStatusItem()
    }

    private func closePanel() {
        panel.orderOut(nil)
        stopOutsideClickMonitors()
        updateStatusItem()
    }

    private func positionPanel(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let windowRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(windowRect)
        let availableFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let preferredX = screenRect.minX
        let x = min(
            max(preferredX, availableFrame.minX + 8),
            availableFrame.maxX - Self.panelSize.width - 8
        )
        let preferredTopY = min(screenRect.minY - 2, availableFrame.maxY - 2)
        let topY = max(
            preferredTopY,
            availableFrame.minY + Self.panelSize.height + 8
        )
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: topY))
    }

    private func startOutsideClickMonitors() {
        stopOutsideClickMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePanel()
            }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.window !== self.panel, event.window !== self.statusItem.button?.window {
                self.closePanel()
            }
            return event
        }
    }

    private func stopOutsideClickMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
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
            .foregroundColor: showsNativeHighlight
                ? NSColor.selectedMenuItemTextColor
                : NSColor.labelColor
        ]
    }

    private func applyBackground(to button: NSStatusBarButton) {
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.cornerRadius = 0
        button.wantsLayer = false
        button.contentTintColor = showsNativeHighlight ? .selectedMenuItemTextColor : nil
        button.highlight(showsNativeHighlight)
    }

    private var showsNativeHighlight: Bool {
        viewModel.menuBarBackgroundEnabled || panel.isVisible
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

private final class StatusPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
