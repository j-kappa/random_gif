import AppKit
import WebKit

private extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int(c.redComponent * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent * 255)
        let a = c.alphaComponent
        if a < 1 {
            return "rgba(\(r),\(g),\(b),\(String(format: "%.2f", a)))"
        }
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

// MARK: - In-memory GIF scheme handler

/// Serves preloaded GIF bytes to WKWebView via giflocal:// so the
/// web view never makes a second network request.
private class GifSchemeHandler: NSObject, WKURLSchemeHandler {
    var gifData: Data?

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let data = gifData else {
            task.didFailWithError(URLError(.resourceUnavailable))
            return
        }
        let url = task.request.url ?? URL(string: "giflocal://gif")!
        let response = URLResponse(
            url: url,
            mimeType: "image/gif",
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// MARK: - Click-only overlay (status label)

private class ClickCaptureView: NSView {
    var onClicked: (() -> Void)?
    var isEnabled = true

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onClicked?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}


// MARK: - Branding button with hover shimmer

private class BrandingButton: NSView {
    var onClicked: (() -> Void)?
    private var contentLayer: CALayer!

    private let leftPad: CGFloat = 14

    init(frame: NSRect, icon: NSImage, iconSize: NSSize) {
        super.init(frame: frame)
        wantsLayer = true

        let snapshot = renderBranding(frame: frame, icon: icon, iconSize: iconSize)
        contentLayer = CALayer()
        contentLayer.frame = bounds
        contentLayer.contents = snapshot
        contentLayer.opacity = 0.35
        layer?.addSublayer(contentLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func renderBranding(frame: NSRect, icon: NSImage, iconSize: NSSize) -> NSImage {
        let pad = leftPad
        let img = NSImage(size: frame.size, flipped: false) { rect in
            let iconRect = NSRect(x: pad, y: (rect.height - iconSize.height) / 2, width: iconSize.width, height: iconSize.height)
            icon.draw(in: iconRect)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let str = NSAttributedString(string: "RandomGif", attributes: attrs)
            let strSize = str.size()
            let strOrigin = NSPoint(x: iconRect.maxX + 5, y: (rect.height - strSize.height) / 2)
            str.draw(at: strOrigin)
            return true
        }
        return img
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        onClicked?()
    }

    override func mouseEntered(with event: NSEvent) {
        contentLayer.removeAnimation(forKey: "pulse")

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        contentLayer.opacity = 1.0
        CATransaction.commit()

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.6
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.beginTime = CACurrentMediaTime() + 0.15
        contentLayer.add(pulse, forKey: "pulse")
    }

    override func mouseExited(with event: NSEvent) {
        contentLayer.removeAnimation(forKey: "pulse")
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        contentLayer.opacity = 0.35
        CATransaction.commit()
    }
}

// MARK: - Window Controller

class GifWindowController: NSWindowController, WKNavigationDelegate {

    private static let windowSize = CGSize(width: 400, height: 370)
    private static let gifMargin: CGFloat = 12
    private static let bottomBarH: CGFloat = 52

    private var webView: WKWebView!
    private var schemeHandler: GifSchemeHandler!
    private var spinner: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var clickCapture: ClickCaptureView!
    // Static so the copied file survives this panel closing — the clipboard URL
    // must stay valid after dismiss. Cleaned up only when the next copy happens.
    private static var lastClipboardDir: URL?
    private var labelClickArea: ClickCaptureView!
    private var currentData: Data?

    private enum LoadState { case loading, ready, error }
    private var loadState: LoadState = .loading
    private var isFetching = false

    // MARK: - Init

    convenience init() {
        let size = GifWindowController.windowSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.init(window: panel)
        buildUI()
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let bounds = content.bounds
        let margin = GifWindowController.gifMargin
        let bottomH = GifWindowController.bottomBarH

        // Root container — rounded + clipped
        let container = NSView(frame: bounds)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.cornerRadius = 18
        container.layer?.masksToBounds = true
        content.addSubview(container)

        let fx = NSVisualEffectView(frame: bounds)
        fx.autoresizingMask = [.width, .height]
        fx.material = .hudWindow
        fx.state = .active
        fx.blendingMode = .behindWindow
        container.addSubview(fx)

        let tint = NSView(frame: bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(white: 0.04, alpha: 0.55).cgColor
        container.addSubview(tint)

        let gifW = bounds.width - margin * 2
        let gifH = bounds.height - bottomH - margin
        let gifFrame = NSRect(x: margin, y: bottomH - 1, width: gifW, height: gifH + 1)

        let gifCard = NSView(frame: gifFrame)
        gifCard.wantsLayer = true
        gifCard.layer?.cornerRadius = 13
        gifCard.layer?.masksToBounds = true
        gifCard.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        gifCard.layer?.borderWidth = 0.5
        container.addSubview(gifCard)

        let backdrop = NSView(frame: gifCard.bounds)
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor.black.cgColor
        gifCard.addSubview(backdrop)

        // WebView with custom giflocal:// scheme — no second network fetch
        let webConfig = WKWebViewConfiguration()
        schemeHandler = GifSchemeHandler()
        webConfig.setURLSchemeHandler(schemeHandler, forURLScheme: "giflocal")

        webView = WKWebView(frame: gifCard.bounds, configuration: webConfig)
        webView.autoresizingMask = [.width, .height]
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")
        webView.alphaValue = 0
        webView.navigationDelegate = self
        gifCard.addSubview(webView)

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isIndeterminate = true
        let sSize: CGFloat = 32
        spinner.frame = NSRect(
            x: (gifCard.bounds.width - sSize) / 2,
            y: (gifCard.bounds.height - sSize) / 2,
            width: sSize, height: sSize
        )
        spinner.appearance = NSAppearance(named: .vibrantDark)
        gifCard.addSubview(spinner)

        clickCapture = ClickCaptureView(frame: gifCard.bounds)
        clickCapture.autoresizingMask = [.width, .height]
        clickCapture.isEnabled = false
        clickCapture.onClicked = { [weak self] in self?.handleGifClick() }
        gifCard.addSubview(clickCapture)

        // Bottom bar — branding left, status right
        let separator = NSView(frame: NSRect(x: margin, y: bottomH - 0.5, width: bounds.width - margin * 2, height: 0.5))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        container.addSubview(separator)

        let brandingSvg = gifSvgString(fill: "white")
        let iconH: CGFloat = 13
        if let svgData = brandingSvg.data(using: .utf8),
           let svgImg = NSImage(data: svgData) {
            let aspect = svgImg.size.width / svgImg.size.height
            let iconW = iconH * aspect
            let brandingW = 10 + iconW + 5 + 75 + 10
            let brandingBtn = BrandingButton(
                frame: NSRect(x: 0, y: 0, width: brandingW, height: bottomH),
                icon: svgImg,
                iconSize: NSSize(width: iconW, height: iconH)
            )
            brandingBtn.onClicked = { [weak self] in self?.startLoad(skipCache: true) }
            container.addSubview(brandingBtn)
        }

        statusLabel = NSTextField(labelWithString: "")
        let labelFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let labelH = labelFont.ascender - labelFont.descender + labelFont.leading
        let statusX = bounds.width / 2
        statusLabel.frame = NSRect(x: statusX, y: (bottomH - labelH) / 2, width: bounds.width - statusX - margin - 2, height: labelH)
        statusLabel.alignment = .right
        statusLabel.font = labelFont
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        statusLabel.isSelectable = false
        container.addSubview(statusLabel)

        // Transparent overlay so clicks on the status label copy the GIF
        labelClickArea = ClickCaptureView(frame: NSRect(
            x: statusX, y: 0, width: bounds.width - statusX - margin - 2, height: bottomH
        ))
        labelClickArea.isEnabled = false
        labelClickArea.onClicked = { [weak self] in
            guard let self else { return }
            switch self.loadState {
            case .ready:   self.handleGifClick()
            case .error:   self.startLoad(skipCache: true)
            case .loading: break
            }
        }
        container.addSubview(labelClickArea)

        statusLabel.stringValue = "Loading…"
    }

    // MARK: - Show

    func showNear(rect buttonRect: NSRect) {
        guard let window = window else { return }
        let size = GifWindowController.windowSize

        var x = buttonRect.midX - size.width / 2
        var y = buttonRect.minY - size.height - 10

        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            x = max(sf.minX + 8, min(x, sf.maxX - size.width - 8))
            y = max(sf.minY + 8, y)
        }

        window.setFrameOrigin(NSPoint(x: x, y: y))
        showWindow(nil)
        startLoad()
    }

    // MARK: - Loading

    private static let staticGifNames = [
        "tv_static_01", "tv_static_02", "tv_static_03", "tv_static_04"
    ]

    private func showStatic() {
        let name = Self.staticGifNames.randomElement() ?? "tv_static_04"
        if let path = Bundle.main.path(forResource: name, ofType: "gif"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            schemeHandler.gifData = data
            let html = """
            <!DOCTYPE html><html><head>
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <style>*{margin:0;padding:0}html,body{width:100%;height:100%;overflow:hidden;background:#000}
            img{width:100%;height:100%;object-fit:cover;display:block;opacity:0.6}</style>
            </head><body><img src="giflocal://static-\(UUID().uuidString).gif"></body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        } else {
            webView.loadHTMLString("<html><body style='background:#000'></body></html>", baseURL: nil)
        }
        webView.alphaValue = 1
        spinner.isHidden = true
    }

    /// Single entry point for all loads. `skipCache` bypasses the preloader
    /// (used when the user explicitly requests a new GIF). Guards against
    /// concurrent fetches so rapid taps on the reload button are no-ops.
    private func startLoad(skipCache: Bool = false) {
        guard !isFetching else { return }
        isFetching = true

        loadState = .loading
        currentData = nil
        clickCapture.isEnabled = false
        labelClickArea.isEnabled = false
        statusLabel.stringValue = "Loading…"
        showStatic()

        Task {
            defer { isFetching = false }

            if skipCache {
                // Drain any preloaded GIF so it doesn't surface stale content,
                // then kick off a fresh background fetch for next time.
                _ = await GifPreloader.shared.consume()
            } else if let cached = await GifPreloader.shared.consume() {
                displayGif(data: cached.data)
                return
            }

            do {
                let url  = try await GifFetcher.fetchRandomGifURL()
                let data = try await GifFetcher.fetchGifData(from: url)
                displayGif(data: data)
                if skipCache { Task { await GifPreloader.shared.kickoff() } }
            } catch {
                setErrorState()
            }
        }
    }

    private func setErrorState() {
        loadState = .error
        let retryAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
        ]
        statusLabel.attributedStringValue = NSAttributedString(
            string: "Couldn't load — tap to retry",
            attributes: retryAttrs
        )
        labelClickArea.isEnabled = true
    }

    /// Hands data to the scheme handler and loads the single-image HTML page.
    private func displayGif(data: Data) {
        loadState = .ready
        currentData = data
        schemeHandler.gifData = data
        clickCapture.isEnabled = true
        labelClickArea.isEnabled = true

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        html, body { width:100%; height:100%; overflow:hidden; background:#000; }
        img { position:absolute; top:-1px; left:-1px; width:calc(100% + 2px); height:calc(100% + 2px); object-fit:cover; display:block; }
        </style>
        </head>
        <body><img src="giflocal://gif-\(UUID().uuidString).gif"></body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        statusLabel.attributedStringValue = copyStatusString()
    }

    override func close() {
        super.close()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            webView.animator().alphaValue = 1
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        setErrorState()
    }

    // MARK: - Clipboard

    private func handleGifClick() {
        guard let data = currentData else {
            flash("Still loading…")
            return
        }

        if let old = Self.lastClipboardDir {
            try? FileManager.default.removeItem(at: old)
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        Self.lastClipboardDir = tempDir
        let tempURL = tempDir.appendingPathComponent("RandomGif.gif")

        guard (try? data.write(to: tempURL)) != nil else {
            flash("Copy failed")
            return
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([tempURL as NSURL])
        pb.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))

        flash("✓  Copied!")

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            webView.animator().alphaValue = 0.5
        } completionHandler: {
            DispatchQueue.main.async {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    self.webView.animator().alphaValue = 1
                }
            }
        }
    }

    private func flash(_ message: String) {
        statusLabel.stringValue = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, self.currentData != nil else { return }
            self.statusLabel.attributedStringValue = self.copyStatusString()
        }
    }

    // MARK: - SVG helpers

    private func gifSvgString(fill: String) -> String {
        AppAssets.logoSVG(fill: fill)
    }

    // MARK: - Lucide copy icon

    private func lucideCopyIcon(size: CGFloat, color: NSColor) -> NSImage {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(size))" height="\(Int(size))" \
        viewBox="0 0 24 24" fill="none" stroke="\(color.hexString)" \
        stroke-width="2" stroke-linecap="round" stroke-linejoin="round">\
        <rect width="14" height="14" x="8" y="8" rx="2" ry="2"/>\
        <path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>\
        </svg>
        """
        guard let data = svg.data(using: .utf8), let img = NSImage(data: data) else {
            return NSImage()
        }
        img.size = NSSize(width: size, height: size)
        return img
    }

    private func copyStatusString() -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let color = NSColor.white.withAlphaComponent(0.5)
        let para = NSMutableParagraphStyle()
        para.alignment = .right
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]

        let result = NSMutableAttributedString(string: "Click to copy  ", attributes: attrs)

        let iconSize: CGFloat = 13
        let attachment = NSTextAttachment()
        attachment.image = lucideCopyIcon(size: iconSize, color: color)
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - iconSize) / 2, width: iconSize, height: iconSize)
        result.append(NSAttributedString(attachment: attachment))

        return result
    }
}
