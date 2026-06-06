import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var windowController: GifWindowController?
    private var eventMonitor: Any?

    private var pendingUpdateVersion: String? = nil
    private var updateBadgeView: NSView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = menuBarIcon()
            button.image?.isTemplate = true
            button.action = #selector(toggleWindow)
            button.target = self
            button.toolTip = "Random GIF"
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Start fetching the first GIF immediately so it's ready when the user clicks
        Task { await GifPreloader.shared.kickoff() }

        // Check for updates ~5 s after launch so startup is never delayed
        UpdateChecker.shared.onUpdateAvailable = { [weak self] version in
            self?.pendingUpdateVersion = version
            self?.showUpdateBadge()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            UpdateChecker.shared.checkInBackground()
        }
    }

    private func menuBarIcon() -> NSImage? {
        let svg = AppAssets.logoSVG()
        guard let data = svg.data(using: .utf8),
              let svgImage = NSImage(data: data) else { return nil }

        let height: CGFloat = 18
        let aspect = svgImage.size.width / svgImage.size.height
        let width = height * aspect

        let img = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            svgImage.draw(in: rect)
            return true
        }
        return img
    }

    @objc private func toggleWindow() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
            return
        }

        if let controller = windowController, controller.window?.isVisible == true {
            hideWindow()
        } else {
            showWindow()
        }
    }

    private func showUpdateBadge() {
        guard let button = statusItem.button, updateBadgeView == nil else { return }

        button.toolTip = "Random GIF — right-click for update"

        let dotSize: CGFloat = 7
        let dot = NSView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        dot.layer?.cornerRadius = dotSize / 2
        // White ring so the dot pops on both light and dark menu bars
        dot.layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        dot.layer?.borderWidth = 1
        button.addSubview(dot)

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: dotSize),
            dot.heightAnchor.constraint(equalToConstant: dotSize),
            dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
            dot.topAnchor.constraint(equalTo: button.topAnchor, constant: 2),
        ])

        updateBadgeView = dot
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let titleItem = NSMenuItem(title: "RandomGif  v\(version)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let titleVersionAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let titleString = NSMutableAttributedString(string: "RandomGif", attributes: titleAttrs)
        titleString.append(NSAttributedString(string: "  v\(version)", attributes: titleVersionAttrs))
        titleItem.attributedTitle = titleString
        menu.addItem(titleItem)

        let taglines = [
            "Productivity's worst enemy, one click away.",
            "You didn't need those next five minutes anyway.",
            "Delivering chaos one GIF at a time since 2025.",
            "The menu bar distraction you didn't know you needed.",
            "Procrastination, now conveniently in your menu bar.",
            "Click. Laugh. Forget what you were doing.",
            "A random GIF a day keeps the focus away.",
            "Your meeting can wait. This GIF cannot.",
            "Turning coffee breaks into GIF marathons.",
            "Because staring at code was getting too productive.",
        ]
        let aboutItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        aboutItem.isEnabled = false
        let aboutAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        aboutItem.attributedTitle = NSAttributedString(string: taglines.randomElement()!, attributes: aboutAttrs)
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        if let newVersion = pendingUpdateVersion {
            let updateItem = NSMenuItem(
                title: "Update Available — v\(newVersion) ↗",
                action: #selector(openUpdatePage),
                keyEquivalent: ""
            )
            updateItem.target = self
            let updateAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.systemBlue
            ]
            updateItem.attributedTitle = NSAttributedString(
                string: "Update Available — v\(newVersion) ↗",
                attributes: updateAttrs
            )
            menu.addItem(updateItem)
            menu.addItem(NSMenuItem.separator())
        }

        let creditItem = NSMenuItem(title: "Made by John Kappa", action: #selector(openCreditsLink), keyEquivalent: "")
        creditItem.target = self
        menu.addItem(creditItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        if let button = statusItem.button {
            let pos = NSPoint(x: 0, y: button.bounds.height + 5)
            menu.popUp(positioning: nil, at: pos, in: button)
        }
    }

    @objc private func openCreditsLink() {
        if let url = URL(string: "https://johnkappa.com") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openUpdatePage() {
        UpdateChecker.shared.openReleasesPage()
    }

    private func showWindow() {
        let controller = GifWindowController()
        windowController = controller

        if let button = statusItem.button, let buttonWindow = button.window {
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = buttonWindow.convertToScreen(buttonRect)
            controller.showNear(rect: screenRect)
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.windowController?.window else { return }
            // Ignore clicks inside the panel — otherwise mouseUp never fires
            // and copy (which was deferred for drag support) silently fails.
            if panel.frame.contains(NSEvent.mouseLocation) { return }
            self.hideWindow()
        }
    }

    func hideWindow() {
        windowController?.close()
        windowController = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
