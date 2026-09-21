import Cocoa
import WebKit
import Darwin

private enum LauncherError: Error {
    case couldNotReservePort
    case missingServer
}

private func reserveLocalPort() throws -> UInt16 {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw LauncherError.couldNotReservePort }
    defer { close(descriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            Darwin.bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else { throw LauncherError.couldNotReservePort }

    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            getsockname(descriptor, socketAddress, &length)
        }
    }
    guard nameResult == 0 else { throw LauncherError.couldNotReservePort }
    return UInt16(bigEndian: address.sin_port)
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var server: Process?
    private var gameURL: URL!
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installMenus()
        createWindow()

        do {
            try startServer()
            waitForServer()
        } catch {
            showFatalError("Micro Space Empire could not start its game server.")
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        terminating = true
        guard let server, server.isRunning else { return }
        server.terminate()
        server.waitUntilExit()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let destination = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if destination.host == gameURL.host && destination.port == gameURL.port {
            decisionHandler(.allow)
        } else if navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(destination)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.cancel)
        }
    }

    private func createWindow() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Micro Space Empire"
        window.minSize = NSSize(width: 1000, height: 700)
        window.center()
        window.contentView = webView
        window.delegate = self
    }

    private func startServer() throws {
        guard let serverURL = Bundle.main.resourceURL?.appendingPathComponent("micro-space-empire-server"),
              FileManager.default.isExecutableFile(atPath: serverURL.path) else {
            throw LauncherError.missingServer
        }

        let supportRoot = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Micro Space Empire", isDirectory: true)
        try FileManager.default.createDirectory(at: supportRoot, withIntermediateDirectories: true)

        let port = try reserveLocalPort()
        gameURL = URL(string: "http://127.0.0.1:\(port)/")!

        var environment = ProcessInfo.processInfo.environment
        environment["KEMAL_ENV"] = "production"
        environment["MSE_HOST"] = "127.0.0.1"
        environment["MSE_PORT"] = String(port)
        environment["MSE_DATABASE_PATH"] = supportRoot.appendingPathComponent("micro_space_empire.db").path
        environment["MSE_OPEN_BROWSER"] = "false"

        let process = Process()
        process.executableURL = serverURL
        process.currentDirectoryURL = supportRoot
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self, !self.terminating else { return }
                self.showFatalError("The local game server stopped unexpectedly.")
            }
        }
        try process.run()
        server = process
    }

    private func waitForServer(attempt: Int = 0) {
        guard attempt < 100 else {
            showFatalError("The local game server did not respond.")
            return
        }

        var request = URLRequest(url: gameURL)
        request.timeoutInterval = 0.25
        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            guard let self else { return }
            if let response = response as? HTTPURLResponse, response.statusCode == 200 {
                DispatchQueue.main.async {
                    self.webView.load(URLRequest(url: self.gameURL))
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.waitForServer(attempt: attempt + 1)
                }
            }
        }.resume()
    }

    private func showFatalError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Unable to Start"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func installMenus() {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "About Micro Space Empire", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit Micro Space Empire", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }
}

let application = NSApplication.shared
private let delegate = AppDelegate()
application.delegate = delegate
application.run()
