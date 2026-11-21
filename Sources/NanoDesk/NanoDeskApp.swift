import AppKit

@main
@MainActor
enum NanoDeskApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = NanoDeskDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class NanoDeskDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var desktop: DesktopWindowController?
    private var statusItem: NSStatusItem?
    private var deviceActions: [NSMenuItem] = []
    private var visibilityItem: NSMenuItem?
    private var topItem: NSMenuItem?
    private var clickThroughItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        Task { await loadDesktop() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        desktop?.show()
        return true
    }

    private func loadDesktop() async {
        do {
            let scene = try await DeviceScene.load()
            let controller = try DesktopWindowController(scene: scene) { [weak self] error in
                self?.showFailure(error)
            }
            desktop = controller
            controller.show()
        } catch {
            showFailure(error)
        }
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "NanoDesk"
        statusItem = item

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        visibilityItem = add("Show Device", #selector(toggleVisibility), to: menu)
        add("Reset Orientation", #selector(resetOrientation), to: menu)
        add("Reset Position", #selector(resetPosition), to: menu)
        menu.addItem(.separator())
        add("Increase Size", #selector(increaseSize), to: menu)
        add("Decrease Size", #selector(decreaseSize), to: menu)
        add("Reset Size", #selector(resetSize), to: menu)
        menu.addItem(.separator())
        topItem = add("Always on Top", #selector(toggleTop), to: menu)
        clickThroughItem = add("Click Through", #selector(toggleClickThrough), to: menu)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit NanoDesk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        deviceActions.append(item)
        menu.addItem(item)
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in deviceActions { item.isEnabled = desktop != nil }
        visibilityItem?.title = desktop?.visible == true ? "Hide Device" : "Show Device"
        topItem?.state = desktop?.alwaysOnTop == true ? .on : .off
        clickThroughItem?.state = desktop?.clickThrough == true ? .on : .off
    }

    @objc private func toggleVisibility() {
        guard let desktop else { return }
        if desktop.visible { desktop.hide() } else { desktop.show() }
    }
    @objc private func resetOrientation() { desktop?.resetOrientation() }
    @objc private func resetPosition() { desktop?.resetPosition() }
    @objc private func resetSize() { desktop?.resetSize() }
    @objc private func increaseSize() { desktop?.zoom(by: 1.12) }
    @objc private func decreaseSize() { desktop?.zoom(by: 1 / 1.12) }
    @objc private func toggleTop() { desktop?.toggleAlwaysOnTop() }
    @objc private func toggleClickThrough() { desktop?.toggleClickThrough() }

    private func showFailure(_ error: any Error) {
        desktop?.hide()
        desktop = nil
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "NanoDesk could not display the device."
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}
