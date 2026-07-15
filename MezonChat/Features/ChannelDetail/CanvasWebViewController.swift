import AsyncDisplayKit
import UIKit
import WebKit

@MainActor
final class CanvasWebViewController: ViewController, WKNavigationDelegate {

    private let pageURL: URL
    private weak var accountContext: AccountContext?
    private let canvasTitle: String

    private var webView: WKWebView?

    private let headerBar = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let headerSeparator = UIView()

    init(pageURL: URL, canvasTitle: String, accountContext: AccountContext) {
        self.pageURL = pageURL
        self.canvasTitle = canvasTitle
        self.accountContext = accountContext
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = UIColor.theme.primary
        displayNode = node
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.primary
        title = canvasTitle
        navigationItem.largeTitleDisplayMode = .never

        setupNavHeader()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)

        Task { await embedWebViewIfPossible() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: ThemeManager.didChangeNotification, object: nil)
    }

    private func setupNavHeader() {
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        backButton.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerSeparator.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = canvasTitle
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.accessibilityLabel = L(L10n.Common.goBack)

        view.addSubview(headerBar)
        headerBar.addSubview(backButton)
        headerBar.addSubview(titleLabel)
        headerBar.addSubview(headerSeparator)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 56),

            backButton.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 4),
            backButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerXAnchor.constraint(equalTo: headerBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerBar.trailingAnchor, constant: -16),

            headerSeparator.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),
            headerSeparator.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        applyNavHeaderTheme()
    }

    @objc private func handleThemeChange() {
        view.backgroundColor = UIColor.theme.primary
        displayNode.backgroundColor = UIColor.theme.primary
        webView?.backgroundColor = UIColor.theme.primary
        webView?.scrollView.backgroundColor = UIColor.theme.primary
        applyNavHeaderTheme()
    }

    private func applyNavHeaderTheme() {
        let t = UIColor.theme
        headerBar.backgroundColor = t.secondary
        titleLabel.textColor = t.textStrong
        backButton.tintColor = t.textStrong
        headerSeparator.backgroundColor = t.border
        backButton.setImage(
            UIImage(systemName: "chevron.left")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)),
            for: .normal)
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    private func embedWebViewIfPossible() async {
        guard let context = accountContext else { return }
        await context.waitForSessionReady()
        guard let session = context.session else {
            Toast.error("Session unavailable")
            navigationController?.popViewController(animated: true)
            return
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        } else {
            config.preferences.javaScriptEnabled = true
        }

        let beforeLoad = Self.authInjectionScript(session: session, themeToken: Self.webThemeToken())
        let afterLoad = Self.canvasChromeHideScript()

        config.userContentController.addUserScript(
            WKUserScript(source: beforeLoad, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.addUserScript(
            WKUserScript(source: afterLoad, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.isOpaque = false
        wv.backgroundColor = UIColor.theme.primary
        wv.scrollView.backgroundColor = UIColor.theme.primary
        wv.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        self.webView = wv
        wv.load(URLRequest(url: pageURL))
    }

    private static func webThemeToken() -> String {
        let c = ThemeManager.shared.current
        switch c {
        case .light: return "light"
        case .system:
            if #available(iOS 13.0, *), UIScreen.main.traitCollection.userInterfaceStyle == .dark {
                return "dark"
            }
            return "light"
        default:
            return "dark"
        }
    }

    private static func escapeForSingleQuotedJS(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            .replacingOccurrences(of: "\0", with: "\\0")
            .replacingOccurrences(of: "</", with: "<\\/")
    }

    private static func authInjectionScript(session: MezonSession, themeToken: String) -> String {
        let sessionData = (try? JSONEncoder().encode(session)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let sessionEscaped = escapeForSingleQuotedJS(sessionData)

        let env = MezonEnvironment.current
        let portStr = env.apiPort.map { String($0) } ?? ""
        let mezonSession: [String: Any] = ["host": env.apiHost, "port": portStr, "ssl": true]
        let mezonData =
            (try? JSONSerialization.data(withJSONObject: mezonSession)).flatMap { String(data: $0, encoding: .utf8) }
            ?? "{}"
        let mezonEscaped = escapeForSingleQuotedJS(mezonData)
        let themeEscaped = escapeForSingleQuotedJS(themeToken)

        return """
        (function(){
          try {
            var sessionStr = '\(sessionEscaped)';
            var mezonSessionStr = '\(mezonEscaped)';
            var sessionData = JSON.parse(sessionStr);
            sessionData.session_id = sessionData.token;
            var authData = {
              loadingStatus: JSON.stringify("loaded"),
              session: JSON.stringify(sessionData),
              isLogin: "true",
              _persist: JSON.stringify({"version":-1,"rehydrated":true})
            };
            localStorage.setItem('persist:auth', JSON.stringify(authData));
            localStorage.setItem('mezon_session', mezonSessionStr);
          } catch (e) {}
        })();
        true;
        (function(){
          try {
            var theme = '\(themeEscaped)';
            var persistAppData = localStorage.getItem('persist:apps');
            if (persistAppData && typeof persistAppData === 'string') {
              var persistApp = JSON.parse(persistAppData);
              if (persistApp && typeof persistApp === 'object') {
                persistApp.theme = JSON.stringify(theme);
                persistApp.themeApp = JSON.stringify(theme);
                localStorage.setItem('persist:apps', JSON.stringify(persistApp));
                localStorage.setItem('current-theme', theme);
              }
            } else {
              throw new Error('persist:apps missing');
            }
          } catch (e) {
            var theme = '\(themeEscaped)';
            var defaultAppData = {
              theme: JSON.stringify(theme),
              themeApp: JSON.stringify(theme)
            };
            localStorage.setItem('persist:apps', JSON.stringify(defaultAppData));
            localStorage.setItem('current-theme', theme);
          }
        })();
        true;
        """
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let targetURL = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = targetURL.scheme?.lowercased() ?? ""
        if scheme == "about" || scheme == "blob" {
            decisionHandler(.allow)
            return
        }
        if (scheme == "https" || scheme == "http"),
           targetURL.host?.lowercased() == pageURL.host?.lowercased() {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    private static func canvasChromeHideScript() -> String {
        """
        (function() {
          var style = document.createElement('style');
          style.innerHTML = `
            .h-heightTopBar { display: none !important; }
            .w-[72px] { width: 72px; display: none; }
          `;
          document.head.appendChild(style);
        })();
        true;
        """
    }
}
