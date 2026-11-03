import AppKit
import SwiftUI

/// NSPopover 面板容器。
final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let statusItem: NSStatusItem

    init(model: AppModel, statusItem: NSStatusItem) {
        self.statusItem = statusItem
        super.init()
        let root = StatusPanelView(model: model)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    var isShown: Bool { popover.isShown }

    func toggle() {
        if popover.isShown { close() } else { show() }
    }

    func show() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        popover.performClose(nil)
    }
}
