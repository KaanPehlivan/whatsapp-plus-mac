// WhatsApp+: WhatsApp Web in a native Mac window, themed with navy.css, with macOS notifications and a Dock badge.
// Build and install: ./build.sh
import AppKit
import WebKit
import UserNotifications

let home = URL(string: "https://web.whatsapp.com/")!
let navy = NSColor(red: 10 / 255, green: 19 / 255, blue: 37 / 255, alpha: 1)
// WhatsApp Web rejects browsers it doesn't know, so identify as the system Safari (same WebKit as this web view).
let safari = Bundle(path: "/Applications/Safari.app")?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "27.0"
let css = try! String(contentsOf: Bundle.main.url(forResource: "navy", withExtension: "css")!, encoding: .utf8)
// Demo mode, for README screenshots: WAPLUS_DEMO=<folder with index.html> shows made-up chats instead of WhatsApp in three
// throwaway numbers. Real logins, the saved number list and the window position aren't touched; the demo posts one
// sample notification, which stays in Notification Center.
let demo = ProcessInfo.processInfo.environment["WAPLUS_DEMO"].map { URL(fileURLWithPath: $0, isDirectory: true) }
let firstName = demo != nil ? "Alex" : NSFullUserName().components(separatedBy: " ").first ?? "" // for the greeting
func jsString(_ s: String) -> String { String(decoding: try! JSONEncoder().encode(s), as: UTF8.self) }

// Runs before WhatsApp's own scripts: adds the theme, and replaces Notification (WKWebView can't grant web
// notifications) with a shim that hands each one to Swift. WhatsApp's own JavaScript is never touched.
let injected = """
(() => {
  const style = document.createElement('style');
  style.textContent = \(jsString(css));
  document.documentElement.appendChild(style);
  const live = window.__navyNotifs = new Map();
  class NavyNotification extends EventTarget {
    static permission = 'granted';
    static requestPermission(cb) { cb?.('granted'); return Promise.resolve('granted'); }
    constructor(title, options = {}) {
      super();
      Object.assign(this, { title, body: options.body || '', tag: options.tag || '', id: crypto.randomUUID() }); // unique across reloads, so old banners never collide
      live.set(this.id, this);
      webkit.messageHandlers.notify.postMessage({ id: this.id, title: String(title), body: String(this.body), tag: String(this.tag) });
    }
    close() { live.delete(this.id); webkit.messageHandlers.notify.postMessage({ close: this.id }); }
  }
  window.Notification = NavyNotification;
  // Chat-list header: a greeting instead of the WhatsApp wordmark; navy.css shows this variable there.
  const name = \(jsString(firstName));
  const greet = () => {
    const h = new Date().getHours();
    const part = h < 5 ? 'Good night' : h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : h < 22 ? 'Good evening' : 'Good night';
    document.documentElement.style.setProperty('--navy-greeting', JSON.stringify(name ? `${part}, ${name}` : part));
  };
  greet();
  setInterval(greet, 60000);
  // Clicking the chat that's already open closes it, the same as pressing Esc in WhatsApp.
  // "Already open" is judged at pointer-down, so the click that opens a chat never closes it again.
  const chatRow = e => e.target.closest?.('[data-testid="chat-list"] [role="row"]');
  let openRow = null;
  addEventListener('pointerdown', e => { const row = chatRow(e); openRow = row?.querySelector('[aria-selected="true"]') ? row : null; }, true);
  addEventListener('click', e => {
    const row = openRow;
    openRow = null;
    // Not on a double-click (its first click just opened the chat), and not on buttons inside the row (its menu chevron).
    if (!row || chatRow(e) !== row || e.detail > 1 || row.contains(e.target.closest('button'))) return;
    e.preventDefault();
    e.stopPropagation();
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
  }, true);
})();
"""

// A WhatsApp number in the app: its name in the switcher and its WebKit data store ("default" holds the first login,
// the others a UUID). Saved in UserDefaults. Never change or reuse a store id: the login lives in it.
struct Account: Codable { var name: String; let store: String }
let maxAccounts = 3

@MainActor
final class App: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate,
                 UNUserNotificationCenterDelegate, NSToolbarDelegate, NSMenuDelegate, NSMenuItemValidation {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    var accounts = demo != nil ? ["Personal", "Work", "Studio"].map { Account(name: $0, store: "demo-\($0)") } : UserDefaults.standard.data(forKey: "accounts").flatMap { try? JSONDecoder().decode([Account].self, from: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        ?? [Account(name: "Personal", store: "default")] // first launch: one number; add more with "+"
    var webs: [WKWebView] = [] // these three arrays follow the order of accounts
    var unread: [Int] = []
    var titleWatches: [NSKeyValueObservation] = []
    let switcher = NSSegmentedControl()
    let accountMenu = NSMenu(title: "Account")
    var addItem: NSToolbarItem?
    var selfTested = false
    var current: Int { switcher.selectedSegment }

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua) // tokens navy.css doesn't override stay dark, even in light mode
        accounts.forEach(addWebView)

        // The switcher and "+" are native toolbar items, so macOS gives them Liquid Glass and lines them up with the window buttons.
        switcher.trackingMode = .selectOne
        switcher.target = self
        switcher.action = #selector(switchFromBar)
        switcher.menu = NSMenu() // right-click a number: rename or remove it
        switcher.menu?.delegate = self
        refresh() // segments first, so the toolbar can measure the switcher
        let toolbar = NSToolbar(identifier: "main")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
        let menuItem = NSMenuItem()
        menuItem.submenu = accountMenu
        NSApp.mainMenu?.insertItem(menuItem, at: 3) // before Window

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = navy
        window.isReleasedWhenClosed = false // closing hides it; WhatsApp keeps running for notifications
        if demo != nil { window.setContentSize(NSSize(width: 1240, height: 760)) } else { window.setFrameAutosaveName("main") }
        window.center()
        show(demo != nil ? min(Int(ProcessInfo.processInfo.environment["WAPLUS_DEMO_SHOW"] ?? "") ?? 0, accounts.count - 1) : 0)
        window.makeKeyAndOrderFront(nil)

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func addWebView(_ account: Account) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = demo != nil ? .nonPersistent() : account.store == "default" ? .default()
            : UUID(uuidString: account.store).map { WKWebsiteDataStore(forIdentifier: $0) } ?? .nonPersistent()
        config.preferences.inactiveSchedulingPolicy = .none // numbers you're not looking at keep running, so their notifications arrive
        config.applicationNameForUserAgent = "Version/\(safari) Safari/605.1.15"
        config.userContentController.addUserScript(WKUserScript(source: injected, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.add(self, name: "notify")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.underPageBackgroundColor = navy
        web.isInspectable = true // Safari → Develop menu, to find renamed tokens after a WhatsApp update
        webs.append(web)
        unread.append(0)
        // WhatsApp Web puts the unread chat count in the title: "(3) WhatsApp".
        titleWatches.append(web.observe(\.title) { [unowned self] web, _ in
            MainActor.assumeIsolated {
                guard let i = self.webs.firstIndex(of: web) else { return }
                self.unread[i] = web.title?.firstMatch(of: #/^\((\d+)\)/#).flatMap { Int($0.1) } ?? 0
                self.refresh()
            }
        })
        if let demo { web.loadFileURL(URL(string: "index.html?a=\(webs.count - 1)", relativeTo: demo)!, allowingReadAccessTo: demo) }
        else { web.load(URLRequest(url: home)) }
    }

    func show(_ i: Int) {
        switcher.selectedSegment = i
        window.contentView = webs[i]
        window.makeFirstResponder(webs[i]) // ⌘C/⌘V/⌘R go to the visible number
    }

    @objc func switchFromBar() { show(switcher.selectedSegment) }
    @objc func showAccount(_ sender: NSMenuItem) {
        show(sender.tag)
        window.makeKeyAndOrderFront(nil) // also when the window was closed
    }

    // Redraws everything that shows the numbers: switcher segments with unread badges, Dock badge (total), "+", Account menu.
    func refresh() {
        let selected = max(switcher.selectedSegment, 0)
        switcher.segmentCount = accounts.count
        for (i, account) in accounts.enumerated() {
            let image = segmentImage(account.name, unread[i])
            switcher.setImage(image, forSegment: i)
            switcher.setWidth(image.size.width + 24, forSegment: i)
            switcher.setToolTip(image.accessibilityDescription, forSegment: i)
        }
        switcher.selectedSegment = min(selected, accounts.count - 1)
        switcher.sizeToFit()
        let total = unread.reduce(0, +)
        NSApp.dockTile.badgeLabel = total > 0 ? String(total) : nil
        addItem?.isHidden = accounts.count >= maxAccounts

        accountMenu.removeAllItems()
        for (i, account) in accounts.enumerated() {
            accountMenu.addItem(withTitle: account.name, action: #selector(showAccount), keyEquivalent: "\(i + 1)").tag = i // ⌘1…⌘3
        }
        accountMenu.addItem(.separator())
        accountMenu.addItem(withTitle: "Add Account…", action: #selector(addAccount), keyEquivalent: "N") // ⇧⌘N
        accountMenu.addItem(withTitle: "Rename Account…", action: #selector(renameAccount), keyEquivalent: "")
        accountMenu.addItem(withTitle: "Remove Account…", action: #selector(removeAccount), keyEquivalent: "")
        if demo == nil { UserDefaults.standard.set(try? JSONEncoder().encode(accounts), forKey: "accounts") }
    }

    // A segment's content: the name, then a blue pill with the unread count. Drawn as one image, because a segmented
    // control can't place a badge after its label.
    func segmentImage(_ name: String, _ count: Int) -> NSImage {
        let text = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize), .foregroundColor: NSColor.labelColor])
        let badge = NSAttributedString(string: count > 99 ? "99+" : "\(count)",
                                       attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.white])
        let pill = NSSize(width: count > 0 ? max(ceil(badge.size().width) + 10, 18) : 0, height: 16)
        let size = NSSize(width: ceil(text.size().width) + (count > 0 ? pill.width + 6 : 0), height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            text.draw(at: NSPoint(x: 0, y: (size.height - text.size().height) / 2))
            if count > 0 {
                let rect = NSRect(x: size.width - pill.width, y: (size.height - pill.height) / 2, width: pill.width, height: pill.height)
                NSColor(red: 79 / 255, green: 131 / 255, blue: 1, alpha: 1).setFill()
                NSBezierPath(roundedRect: rect, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
                badge.draw(at: NSPoint(x: rect.midX - badge.size().width / 2, y: rect.midY - badge.size().height / 2))
            }
            return true
        }
        image.accessibilityDescription = count > 0 ? "\(name), \(count) unread" : name
        return image
    }

    // MARK: adding, renaming, removing numbers

    // Context-menu items carry the right-clicked index; menu-bar items act on the visible number.
    func index(_ sender: Any?) -> Int { (sender as? NSMenuItem)?.representedObject as? Int ?? current }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // The segment under the pointer; a menu opened from the keyboard (no mouse event) acts on the visible number.
        var i = current
        if let event = NSApp.currentEvent, [.rightMouseDown, .leftMouseDown].contains(event.type) {
            let x = switcher.convert(event.locationInWindow, from: nil).x
            var edge: CGFloat = 0
            i = accounts.indices.first { edge += switcher.width(forSegment: $0); return x < edge } ?? accounts.count - 1
        }
        for (title, action) in [("Rename “\(accounts[i].name)”…", #selector(renameAccount)), ("Remove “\(accounts[i].name)”…", #selector(removeAccount))] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = i
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let editing = [#selector(addAccount), #selector(renameAccount), #selector(removeAccount)].contains(item.action)
        if editing && window.attachedSheet != nil { return false } // one account sheet at a time
        return switch item.action {
        case #selector(addAccount): accounts.count < maxAccounts
        case #selector(removeAccount): accounts.count > 1
        default: true
        }
    }

    @objc func addAccount() {
        guard accounts.count < maxAccounts, window.attachedSheet == nil else { return }
        askName("Add Account", button: "Add", initial: "Account \(accounts.count + 1)") { name in
            self.accounts.append(Account(name: name, store: UUID().uuidString))
            self.addWebView(self.accounts[self.accounts.count - 1])
            self.refresh()
            self.show(self.accounts.count - 1)
        }
    }

    @objc func renameAccount(_ sender: Any?) {
        guard window.attachedSheet == nil else { return }
        let i = index(sender)
        askName("Rename Account", button: "Rename", initial: accounts[i].name) { name in
            self.accounts[i].name = name
            self.refresh()
        }
    }

    @objc func removeAccount(_ sender: Any?) {
        let i = index(sender)
        guard accounts.count > 1, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Remove “\(accounts[i].name)”?"
        alert.informativeText = "This logs the number out of this app and deletes its data here. Its chats stay on your phone; also remove it under Linked Devices there."
        alert.addButton(withTitle: "Remove").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let visible = self.webs[self.current]
            let web = self.webs.remove(at: i)
            web.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
            web.configuration.userContentController.removeAllScriptMessageHandlers()
            self.titleWatches.remove(at: i).invalidate()
            self.unread.remove(at: i)
            let store = self.accounts.remove(at: i).store
            self.refresh()
            self.show(self.webs.firstIndex(of: visible) ?? min(i, self.accounts.count - 1)) // stay on the number you were looking at
            // A UUID store can only be deleted once no web view uses it; "default" just stays emptied.
            if let id = UUID(uuidString: store) { Task { try? await WKWebsiteDataStore.remove(forIdentifier: id) } }
        }
    }

    func askName(_ title: String, button: String, initial: String, then done: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "The name shows in the title bar and on notifications."
        let field = NSTextField(string: initial)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            let name = String(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)).trimmingCharacters(in: .whitespaces)
            if response == .alertFirstButtonReturn, !name.isEmpty { done(name) }
        }
    }

    // MARK: toolbar

    let switcherID = NSToolbarItem.Identifier("switcher"), addID = NSToolbarItem.Identifier("add")
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [switcherID, addID] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [switcherID, addID] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        if id == switcherID {
            item.view = switcher
            item.label = "Accounts"
        } else {
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Account")
            item.label = "Add Account"
            item.toolTip = "Add Account (up to \(maxAccounts))"
            item.target = self
            item.action = #selector(addAccount)
            item.isBordered = true
            item.isHidden = accounts.count >= maxAccounts
            addItem = item
        }
        return item
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return false
    }

    // MARK: links, downloads, uploads, microphone

    func isExternalLink(_ url: URL?) -> URL? {
        guard let url, ["http", "https", "mailto"].contains(url.scheme ?? ""), url.host != home.host else { return nil }
        return url
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if action.shouldPerformDownload { return decisionHandler(.download) }
        if action.targetFrame?.isMainFrame == true, let url = isExternalLink(action.request.url) {
            NSWorkspace.shared.open(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    // Links in chats open with target=_blank: send them to the default browser instead of a new web view.
    func webView(_ webView: WKWebView, createWebViewWith config: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = isExternalLink(action.request.url) { NSWorkspace.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    // Save to ~/Downloads, adding " 2", " 3"… instead of overwriting an existing file.
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let safe = suggestedFilename.replacingOccurrences(of: "/", with: "_") // web content picks the name: keep it inside Downloads
        let name = safe as NSString
        var url = dir.appendingPathComponent(safe)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let numbered = "\(name.deletingPathExtension) \(n)"
            url = dir.appendingPathComponent(name.pathExtension.isEmpty ? numbered : "\(numbered).\(name.pathExtension)")
            n += 1
        }
        completionHandler(url)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host == home.host ? .grant : .deny)
    }

    // MARK: notifications

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, (demo != nil && origin.protocol == "file") || (origin.protocol == "https" && origin.host == home.host),
              let web = message.webView, let i = webs.firstIndex(of: web), let body = message.body as? [String: String] else { return }
        let center = UNUserNotificationCenter.current()
        let key = accounts[i].store // ids carry the store, not the position, so renames and removals can't misroute a click
        if let id = body["close"] { return center.removeDeliveredNotifications(withIdentifiers: ["\(key) \(id)"]) }
        let content = UNMutableNotificationContent()
        content.title = body["title"] ?? ""
        content.subtitle = accounts[i].name
        content.body = body["body"] ?? ""
        content.threadIdentifier = "\(key) \(body["tag"] ?? "")" // WhatsApp tags per chat: group per chat, per number
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "\(key) \(body["id"] ?? UUID().uuidString)", content: content, trigger: nil))
        NSApp.requestUserAttention(.informationalRequest) // one Dock bounce; macOS ignores it while the app is in front
    }

    // Clicking a banner opens the app and lets WhatsApp jump to that chat, as in a browser.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
        let key = response.notification.request.identifier.split(separator: " ") // "<account store> <notification id>"
        Task { @MainActor in
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            if key.count == 2, let i = accounts.firstIndex(where: { $0.store == key[0] }) {
                show(i)
                _ = try? await webs[i].callAsyncJavaScript("const n = window.__navyNotifs.get(id); n?.onclick?.(new Event('click')); n?.dispatchEvent(new Event('click'));",
                                                           arguments: ["id": String(key[1])], contentWorld: .page)
            }
            done()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound]) // .list keeps it in Notification Center
    }

    // Self-check: NAVY_SELFTEST=1 prints the live theme token and whether a test notification reached macOS,
    // then every 20 s lists backgrounds that aren't navy (element type only, no message text): after a WhatsApp
    // update, these point at renamed tokens.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard ProcessInfo.processInfo.environment["NAVY_SELFTEST"] != nil, !selfTested else { return }
        selfTested = true // didFinish fires again on every reload
        setvbuf(stdout, nil, _IOLBF, 0) // so the result shows up when stdout goes to a file
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            MainActor.assumeIsolated {
                self.webs[self.switcher.selectedSegment].evaluateJavaScript(leftoverColors) { r, _ in print("not navy:", r ?? "nil") }
                print("titles:", self.webs.map { $0.title ?? "nil" }, "unread:", self.unread)
            }
        }
        webView.evaluateJavaScript("new Notification('WhatsApp+', {body: 'Self-test'}); getComputedStyle(document.body).getPropertyValue('--WDS-surface-default').trim()") { token, _ in
            print("theme token:", token ?? "nil", token as? String == "#0a1325" ? "OK" : "FAIL")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                UNUserNotificationCenter.current().getDeliveredNotifications { list in
                    print("notification:", list.contains { $0.request.content.body == "Self-test" } ? "OK" : "FAIL (allowed in System Settings?)")
                }
            }
        }
    }
}

let leftoverColors = """
(() => {
  const navy = new Set(['rgba(0, 0, 0, 0)', 'rgb(10, 19, 37)', 'rgb(7, 14, 28)', 'rgb(13, 24, 45)', 'rgb(16, 28, 53)', 'rgb(22, 38, 74)',
                        'rgb(26, 45, 90)', 'rgb(34, 58, 113)', 'rgb(79, 131, 255)', 'rgb(127, 168, 255)']);
  const seen = {};
  for (const el of document.querySelectorAll('*')) {
    const bg = getComputedStyle(el).backgroundColor;
    if (navy.has(bg)) continue;
    const hint = el.dataset.icon ? `[data-icon=${el.dataset.icon}]` : el.getAttribute('role') ? `[role=${el.getAttribute('role')}]` : '';
    const key = `${bg} ${el.tagName.toLowerCase()}${hint}`;
    seen[key] = (seen[key] || 0) + 1;
  }
  return JSON.stringify(Object.entries(seen).sort((a, b) => b[1] - a[1]).slice(0, 25));
})()
"""

func menu(_ title: String, _ items: [(String, String, String)]) -> NSMenuItem {
    let sub = NSMenu(title: title)
    for (name, action, key) in items { sub.addItem(NSMenuItem(title: name, action: Selector(action), keyEquivalent: key)) }
    let item = NSMenuItem()
    item.submenu = sub
    return item
}

// Without a main menu, ⌘C, ⌘V, ⌘A and ⌘Q do nothing in an app built without a storyboard.
let mainMenu = NSMenu()
mainMenu.addItem(menu("WhatsApp+", [("Hide WhatsApp+", "hide:", "h"), ("Quit WhatsApp+", "terminate:", "q")]))
mainMenu.addItem(menu("Edit", [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                               ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")]))
mainMenu.addItem(menu("View", [("Reload", "reload:", "r")]))
mainMenu.addItem(menu("Window", [("Minimize", "performMiniaturize:", "m"), ("Close", "performClose:", "w")]))

MainActor.assumeIsolated { // top-level code runs on the main thread
    let app = NSApplication.shared
    let delegate = App() // app.delegate is weak
    app.delegate = delegate
    app.mainMenu = mainMenu
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
}
