import Cocoa
import FlutterMacOS
import WebKit

class MainFlutterWindow: NSWindow {
  private var activeAuthController: GarminWebAuthController?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 1400, height: 900)
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 1100, height: 750)
    self.title = "Pulse Training"
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)

    let authChannel = FlutterMethodChannel(
      name: "com.pulse.training/garmin_auth",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    authChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "UNAVAILABLE", message: "Main window unavailable.", details: nil))
        return
      }
      if call.method == "signInWithWebView" {
        let args = call.arguments as? [String: Any]
        let domain = (args?["domain"] as? String) ?? "garmin.com"
        self.presentGarminWebSignIn(domain: domain, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  private func presentGarminWebSignIn(domain: String, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      self.activeAuthController?.cancelAndClose()
      let controller = GarminWebAuthController(domain: domain, parentWindow: self) { [weak self] outcome in
        self?.activeAuthController = nil
        switch outcome {
        case .success(let ticket):
          result(ticket)
        case .cancelled:
          result(FlutterError(code: "CANCELLED", message: "Sign-in was cancelled.", details: nil))
        case .failure(let message):
          result(FlutterError(code: "AUTH_ERROR", message: message, details: nil))
        }
      }
      self.activeAuthController = controller
      controller.show()
    }
  }
}

private enum GarminWebAuthOutcome {
  case success(String)
  case cancelled
  case failure(String)
}

private class GarminWebAuthController: NSObject, WKNavigationDelegate, NSWindowDelegate {
  private let domain: String
  private weak var parentWindow: NSWindow?
  private var completion: ((GarminWebAuthOutcome) -> Void)?
  private var authWindow: NSWindow?
  private var webView: WKWebView?
  private var finished = false

  init(domain: String, parentWindow: NSWindow, completion: @escaping (GarminWebAuthOutcome) -> Void) {
    self.domain = domain
    self.parentWindow = parentWindow
    self.completion = completion
    super.init()
  }

  func show() {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()

    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 680), configuration: config)
    webView.navigationDelegate = self
    self.webView = webView

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 680),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Sign in to Garmin Connect"
    window.contentView = webView
    window.delegate = self
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 420, height: 560)
    self.authWindow = window

    let ssoEmbed = "https://sso.\(domain)/sso/embed"
    var comps = URLComponents(string: "https://sso.\(domain)/sso/signin")!
    comps.queryItems = [
      URLQueryItem(name: "id", value: "gauth-widget"),
      URLQueryItem(name: "embedWidget", value: "true"),
      URLQueryItem(name: "gauthHost", value: ssoEmbed),
      URLQueryItem(name: "service", value: ssoEmbed),
      URLQueryItem(name: "source", value: ssoEmbed),
      URLQueryItem(name: "redirectAfterAccountLoginUrl", value: ssoEmbed),
      URLQueryItem(name: "redirectAfterAccountCreationUrl", value: ssoEmbed),
    ]

    if let url = comps.url {
      webView.load(URLRequest(url: url))
    } else {
      finish(.failure("Invalid Garmin sign-in URL."))
      return
    }

    if let parent = parentWindow {
      let parentFrame = parent.frame
      let x = parentFrame.origin.x + (parentFrame.size.width - 480) / 2
      let y = parentFrame.origin.y + (parentFrame.size.height - 680) / 2
      window.setFrameOrigin(NSPoint(x: x, y: y))
    } else {
      window.center()
    }
    window.makeKeyAndOrderFront(nil)
  }

  func cancelAndClose() {
    finish(.cancelled)
  }

  private func extractTicket(from text: String) -> String? {
    let unescaped = text.replacingOccurrences(of: "\\/", with: "/")
    guard let regex = try? NSRegularExpression(pattern: "ticket=(ST-[A-Za-z0-9._\\-]+)", options: []) else {
      return nil
    }
    let nsRange = NSRange(unescaped.startIndex..<unescaped.endIndex, in: unescaped)
    guard let match = regex.firstMatch(in: unescaped, options: [], range: nsRange),
          match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: unescaped) else {
      return nil
    }
    return String(unescaped[range])
  }

  private func finish(_ outcome: GarminWebAuthOutcome) {
    guard !finished else { return }
    finished = true
    let cb = completion
    completion = nil
    authWindow?.delegate = nil
    authWindow?.close()
    authWindow = nil
    webView?.navigationDelegate = nil
    webView = nil
    cb?(outcome)
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    if let urlString = navigationAction.request.url?.absoluteString,
       let ticket = extractTicket(from: urlString) {
      decisionHandler(.cancel)
      finish(.success(ticket))
      return
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    if let urlString = webView.url?.absoluteString,
       let ticket = extractTicket(from: urlString) {
      finish(.success(ticket))
      return
    }

    webView.evaluateJavaScript("document.documentElement ? document.documentElement.innerHTML : ''") { [weak self] value, _ in
      guard let self = self, !self.finished, let html = value as? String else { return }
      if let ticket = self.extractTicket(from: html) {
        self.finish(.success(ticket))
      }
    }
  }

  func windowWillClose(_ notification: Notification) {
    finish(.cancelled)
  }
}
