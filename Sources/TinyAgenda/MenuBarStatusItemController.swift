import AppKit
import Combine
import SwiftUI

/// AppKit status item + popover. SwiftUI `MenuBarExtra` can fail to appear for some LSUIElement / accessory setups; `NSStatusItem` is reliable.
@MainActor
final class MenuBarStatusItemController: NSObject {
    private let viewModel: CalendarViewModel
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    /// True if `NSStatusBar` gave us a button (rare failure should be logged by the app delegate).
    var hasVisibleButton: Bool {
        guard let b = statusItem?.button else { return false }
        return !b.isHidden && b.alphaValue > 0.01
    }

    init(viewModel: CalendarViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if #available(macOS 11.0, *) {
            item.isVisible = true
        }
        guard let button = item.button else { return }

        if let img = NSImage(systemSymbolName: "calendar", accessibilityDescription: "TinyAgenda") {
            img.isTemplate = true
            button.image = img
        } else {
            button.title = "Cal"
        }
        button.imagePosition = .imageLeading
        button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        button.toolTip = "TinyAgenda"
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.contentSize = NSSize(width: 320, height: 520)
        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: MenuBarContentView(viewModel: viewModel))
        popover.contentViewController = host

        viewModel.$menuBarTitle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncButtonTitle()
            }
            .store(in: &cancellables)

        viewModel.$menuBarIdleShowsText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncButtonTitle()
            }
            .store(in: &cancellables)

        syncButtonTitle()

        // Nudge AppKit to lay out the item (helps some multi-display / Stage Manager setups).
        button.needsDisplay = true
    }

    private func syncButtonTitle() {
        statusItem?.button?.title = viewModel.menuBarStatusItemTitle
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
