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
    private static let panelWidth: CGFloat = 392
    private static let initialPanelHeight: CGFloat = 618

    private let viewModel: UsageViewModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: StatusPanel
    private let panelSizeRelay = PanelSizeRelay()
    private var stateObserver: AnyCancellable?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        let initialPanelSize = NSSize(
            width: Self.panelWidth,
            height: Self.initialPanelHeight
        )
        self.panel = StatusPanel(contentRect: NSRect(origin: .zero, size: initialPanelSize))
        super.init()

        let hostingController = NSHostingController(
            rootView: UsageMenuView(viewModel: viewModel) { [weak panelSizeRelay] height in
                panelSizeRelay?.report(height)
            }
        )
        hostingController.view.frame = NSRect(origin: .zero, size: initialPanelSize)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 18
        hostingController.view.layer?.cornerCurve = .continuous
        hostingController.view.layer?.masksToBounds = true

        panel.contentViewController = hostingController
        panel.setContentSize(initialPanelSize)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        panelSizeRelay.onHeightChange = { [weak self] height in
            self?.resizePanel(toContentHeight: height)
        }

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
            availableFrame.maxX - panel.frame.width - 8
        )
        let preferredTopY = min(screenRect.minY - 2, availableFrame.maxY - 2)
        let topY = max(
            preferredTopY,
            availableFrame.minY + panel.frame.height + 8
        )
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: topY))
    }

    private func resizePanel(toContentHeight contentHeight: CGFloat) {
        guard contentHeight.isFinite, contentHeight > 0 else { return }

        let screen = statusItem.button?.window?.screen ?? panel.screen ?? NSScreen.main
        let maximumHeight = max(
            1,
            (screen?.visibleFrame.height ?? contentHeight) - 16
        )
        let targetHeight = min(ceil(contentHeight), maximumHeight)
        guard abs(panel.frame.height - targetHeight) > 0.5 else { return }

        let previousTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        panel.setContentSize(NSSize(width: Self.panelWidth, height: targetHeight))

        if panel.isVisible, let button = statusItem.button {
            positionPanel(below: button)
        } else {
            panel.setFrameTopLeftPoint(previousTopLeft)
        }
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

        let renderedImage: NSImage?
        let renderedTitle: NSAttributedString
        if viewModel.showsCriticalSecondaryStatus,
           let primary = viewModel.snapshot?.primary,
           let secondary = viewModel.snapshot?.secondary {
            renderedImage = nil
            renderedTitle = criticalTitle(primary: primary, secondary: secondary)
        } else {
            renderedImage = whiteSymbol(named: viewModel.statusSymbol, pointSize: 12)
            renderedTitle = NSAttributedString(
                string: " \(viewModel.menuBarTitle(at: viewModel.currentDate))",
                attributes: titleAttributes
            )
        }

        applyBackground(to: button)
        button.image = renderedImage
        button.alternateImage = renderedImage
        button.attributedTitle = renderedTitle
        button.attributedAlternateTitle = renderedTitle
        button.setAccessibilityLabel(viewModel.language.text("Codex usage", "Лимиты Codex"))
        button.setAccessibilityValue(accessibilityValue)
    }

    private func criticalTitle(primary: UsageWindow, secondary: UsageWindow) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(statusAttachment(for: primary))
        result.append(NSAttributedString(
            string: " \(statusText(for: primary)) · ",
            attributes: titleAttributes
        ))
        result.append(statusAttachment(for: secondary))
        result.append(NSAttributedString(
            string: " \(statusText(for: secondary))",
            attributes: titleAttributes
        ))
        return result
    }

    private func statusAttachment(for window: UsageWindow) -> NSAttributedString {
        if window.remainingPercent == 0 {
            return symbolAttachment(named: "arrow.clockwise")
        }
        return batteryAttachment(percentage: window.remainingPercent)
    }

    private func statusText(for window: UsageWindow) -> String {
        let label = viewModel.shortLabel(for: window)
        guard window.remainingPercent == 0, let resetDate = window.resetsAt else {
            return "\(label) \(window.remainingPercent)%"
        }

        let countdown = LimitCountdownFormatter.compact(
            until: resetDate,
            now: viewModel.currentDate,
            language: viewModel.language
        )
        return "\(label) \(countdown)"
    }

    private func batteryAttachment(percentage: Int) -> NSAttributedString {
        symbolAttachment(named: viewModel.batterySymbol(for: percentage))
    }

    private func symbolAttachment(named symbolName: String) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = whiteSymbol(named: symbolName, pointSize: 11)
        return NSAttributedString(attachment: attachment)
    }

    private func whiteSymbol(named symbolName: String, pointSize: CGFloat) -> NSImage? {
        let sizeConfiguration = NSImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .medium
        )
        let whiteConfiguration = NSImage.SymbolConfiguration(paletteColors: [.white])
        let configuration = sizeConfiguration.applying(whiteConfiguration)
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image
    }

    private var titleAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
    }

    private func applyBackground(to button: NSStatusBarButton) {
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.cornerRadius = 0
        button.wantsLayer = false
        button.contentTintColor = .white
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

@MainActor
private final class PanelSizeRelay {
    var onHeightChange: ((CGFloat) -> Void)? {
        didSet {
            if let latestHeight {
                onHeightChange?(latestHeight)
            }
        }
    }

    private var latestHeight: CGFloat?

    func report(_ height: CGFloat) {
        latestHeight = height
        onHeightChange?(height)
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
