import AsyncDisplayKit
import UIKit
import WebKit

@MainActor
final class ChannelAppWebViewController: ViewController, WKNavigationDelegate {

    private let pageURL: URL
    private let appTitle: String
    private var webView: WKWebView?
    private var didInstallSubviews = false

    private let headerBar = UIView()
    private let backButton = UIButton(type: .system)
    private let collapseChromeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let headerSeparator = UIView()
    private let revealChromeButton = UIButton(type: .system)

    private var chromeHeaderExpanded = true
    private var chromeAutoHideTask: Task<Void, Never>?

    init(pageURL: URL, appTitle: String) {
        self.pageURL = pageURL
        self.appTitle = appTitle
        super.init(navigationBarPresentationData: nil)
    }

    override var overlayWantsToBeBelowKeyboard: Bool { true }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = UIColor.theme.primary
        displayNode = node
        displayNodeDidLoad()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installSubviewsIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if chromeHeaderExpanded {
            scheduleChromeAutoHide()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        chromeAutoHideTask?.cancel()
        chromeAutoHideTask = nil
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        layoutWebAndChrome(layout: layout, transition: transition)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isViewLoaded else { return }
        if traitCollection.verticalSizeClass != previousTraitCollection?.verticalSizeClass
            || traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass {
            updateChromeTypography()
            requestLayout(transition: .immediate)
        }
    }

    deinit {
        chromeAutoHideTask?.cancel()
        NotificationCenter.default.removeObserver(self, name: ThemeManager.didChangeNotification, object: nil)
    }

    private func installSubviewsIfNeeded() {
        guard isViewLoaded, !didInstallSubviews else { return }
        didInstallSubviews = true
        view.backgroundColor = UIColor.theme.primary
        setupHeader()
        setupRevealChromeButton()
        embedWebView()
        updateChromeTypography()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
    }

    private func chromeHeaderHeight() -> CGFloat {
        traitCollection.verticalSizeClass == .compact ? 44 : 56
    }

    private func updateChromeTypography() {
        let compact = traitCollection.verticalSizeClass == .compact
        titleLabel.font = .systemFont(ofSize: compact ? 15 : 17, weight: .semibold)
    }

    private func scheduleChromeAutoHide() {
        chromeAutoHideTask?.cancel()
        chromeAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            hideChromeHeader(animated: true)
        }
    }

    private func hideChromeHeader(animated: Bool) {
        chromeAutoHideTask?.cancel()
        chromeAutoHideTask = nil
        guard chromeHeaderExpanded else { return }
        chromeHeaderExpanded = false
        revealChromeButton.isHidden = false
        applyChromeVisibilityLayout(animated: animated)
    }

    private func showChromeHeader(animated: Bool) {
        guard !chromeHeaderExpanded else { return }
        chromeHeaderExpanded = true
        revealChromeButton.isHidden = true
        scheduleChromeAutoHide()
        applyChromeVisibilityLayout(animated: animated)
    }

    private func applyChromeVisibilityLayout(animated: Bool) {
        guard let layout = currentlyAppliedLayout else { return }
        let transition: ContainedViewLayoutTransition =
            animated ? .animated(duration: 0.28, curve: .easeInOut) : .immediate
        layoutWebAndChrome(layout: layout, transition: transition)
    }

    private func layoutWebAndChrome(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        guard isViewLoaded else { return }
        installSubviewsIfNeeded()
        guard headerBar.superview != nil else { return }
        let headerH = chromeHeaderExpanded ? chromeHeaderHeight() : 0
        let top = layout.safeInsets.top
        let left = layout.safeInsets.left
        let right = layout.safeInsets.right
        let bottom = max(layout.safeInsets.bottom, layout.inputHeight ?? 0)
        let innerWidth = max(0, layout.size.width - left - right)
        let headerFrame = CGRect(x: left, y: top, width: innerWidth, height: headerH)
        let webTop = top + headerH
        let webHeight = max(1, layout.size.height - webTop - bottom)
        let webFrame = CGRect(x: left, y: webTop, width: innerWidth, height: webHeight)
        transition.updateFrame(view: headerBar, frame: headerFrame)
        if let wv = webView {
            transition.updateFrame(view: wv, frame: webFrame)
        }
        let revealSize: CGFloat = 44
        let revealFrame = CGRect(
            x: left + (innerWidth - revealSize) / 2,
            y: top + 8,
            width: revealSize,
            height: revealSize)
        transition.updateFrame(view: revealChromeButton, frame: revealFrame)
        revealChromeButton.isHidden = chromeHeaderExpanded
        if let wv = webView {
            view.bringSubviewToFront(wv)
        }
        if chromeHeaderExpanded {
            view.bringSubviewToFront(headerBar)
        } else {
            view.bringSubviewToFront(revealChromeButton)
        }
    }

    private func setupHeader() {
        headerBar.translatesAutoresizingMaskIntoConstraints = true
        headerBar.clipsToBounds = true
        backButton.translatesAutoresizingMaskIntoConstraints = false
        collapseChromeButton.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerSeparator.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = appTitle
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.accessibilityLabel = L(L10n.Common.goBack)

        collapseChromeButton.addTarget(self, action: #selector(collapseChromeTapped), for: .touchUpInside)
        collapseChromeButton.accessibilityLabel = "Hide toolbar"

        view.addSubview(headerBar)
        headerBar.addSubview(backButton)
        headerBar.addSubview(titleLabel)
        headerBar.addSubview(collapseChromeButton)
        headerBar.addSubview(headerSeparator)

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 4),
            backButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            collapseChromeButton.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -4),
            collapseChromeButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            collapseChromeButton.widthAnchor.constraint(equalToConstant: 44),
            collapseChromeButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerXAnchor.constraint(equalTo: headerBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: collapseChromeButton.leadingAnchor, constant: -8),

            headerSeparator.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),
            headerSeparator.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        applyNavHeaderTheme()
    }

    private func setupRevealChromeButton() {
        revealChromeButton.translatesAutoresizingMaskIntoConstraints = true
        revealChromeButton.layer.cornerRadius = 22
        revealChromeButton.clipsToBounds = true
        revealChromeButton.isHidden = true
        revealChromeButton.addTarget(self, action: #selector(revealChromeTapped), for: .touchUpInside)
        revealChromeButton.accessibilityLabel = "Show toolbar"
        view.addSubview(revealChromeButton)
        styleRevealChromeButton()
    }

    private func styleRevealChromeButton() {
        revealChromeButton.backgroundColor = UIColor(white: 0, alpha: 0.45)
        revealChromeButton.tintColor = .white
        revealChromeButton.setImage(
            UIImage(systemName: "chevron.down")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)),
            for: .normal)
    }

    @objc private func collapseChromeTapped() {
        hideChromeHeader(animated: true)
    }

    @objc private func revealChromeTapped() {
        showChromeHeader(animated: true)
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
        headerBar.backgroundColor = t.primary
        titleLabel.textColor = t.textStrong
        backButton.tintColor = t.textStrong
        collapseChromeButton.tintColor = t.textStrong
        headerSeparator.backgroundColor = t.border.withAlphaComponent(0.35)
        backButton.setImage(
            UIImage(systemName: "xmark")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)),
            for: .normal)
        collapseChromeButton.setImage(
            UIImage(systemName: "chevron.up")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)),
            for: .normal)
        styleRevealChromeButton()
    }

    @objc private func backTapped() {
        dismiss()
    }

    private func embedWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        } else {
            config.preferences.javaScriptEnabled = true
        }

        let viewportFix = """
        (function(){
          try {
            var h = document.head || document.getElementsByTagName('head')[0];
            if (!h) return;
            var m = document.querySelector('meta[name="viewport"]');
            if (!m) { m = document.createElement('meta'); m.setAttribute('name','viewport'); h.appendChild(m); }
            m.setAttribute('content','width=device-width, initial-scale=1.0, maximum-scale=5.0, viewport-fit=cover');
          } catch (e) {}
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: viewportFix, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.isOpaque = false
        wv.backgroundColor = UIColor.theme.primary
        wv.scrollView.backgroundColor = UIColor.theme.primary
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.translatesAutoresizingMaskIntoConstraints = true

        view.addSubview(wv)

        webView = wv
        wv.load(URLRequest(url: pageURL))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "https" || scheme == "http" || scheme == "about" || scheme == "blob" {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }
}
