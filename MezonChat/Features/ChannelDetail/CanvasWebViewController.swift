import AsyncDisplayKit
import UIKit
import WebKit

@MainActor
final class CanvasWebViewController: ViewController, WKNavigationDelegate {

    private let canvasId: Int64
    private let clanId: Int64
    private let channelId: Int64
    private let channelType: Int32
    private let accountContext: AccountContext
    private var canvasTitle: String
    private var canvasContent: String?
    private var loadTask: Task<Void, Never>?

    private var webView: WKWebView?
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()

    private let headerBar = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let headerSeparator = UIView()

    init(
        canvasId: Int64,
        clanId: Int64,
        channelId: Int64,
        channelType: Int32,
        canvasTitle: String,
        accountContext: AccountContext
    ) {
        self.canvasId = canvasId
        self.clanId = clanId
        self.channelId = channelId
        self.channelType = channelType
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
        setupContentView()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )

        loadTask = Task { [weak self] in
            await self?.loadCanvasDetail()
        }
    }

    deinit {
        loadTask?.cancel()
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

        applyTheme()
    }

    private func setupContentView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = false
        } else {
            config.preferences.javaScriptEnabled = false
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.isHidden = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.font = .systemFont(ofSize: 15)
        errorLabel.isHidden = true
        view.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: webView.centerYAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
            errorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])

        self.webView = webView
        activityIndicator.startAnimating()
        applyTheme()
    }

    private func loadCanvasDetail() async {
        await accountContext.waitForSessionReady()
        guard !Task.isCancelled else { return }

        do {
            guard let token = await accountContext.getToken(), !token.isEmpty else {
                showLoadError()
                return
            }
            let apiClanId =
                (channelType == MezonConstants.ChannelType.dm.rawValue
                    || channelType == MezonConstants.ChannelType.group.rawValue) ? 0 : clanId
            let detail = try await accountContext.account.network.getChannelCanvasDetail(
                canvasId: canvasId,
                clanId: apiClanId,
                channelId: channelId,
                token: token
            )
            guard !Task.isCancelled else { return }

            if !detail.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                canvasTitle = detail.title.replacingOccurrences(of: "\n", with: " ")
                title = canvasTitle
                titleLabel.text = canvasTitle
            }
            canvasContent = detail.content
            renderCanvasContent(detail.content)
        } catch is CancellationError {
        } catch {
            showLoadError()
        }
    }

    private func renderCanvasContent(_ content: String) {
        errorLabel.isHidden = true
        webView?.isHidden = false
        webView?.loadHTMLString(
            CanvasHTMLRenderer.document(
                content: content,
                textColor: Self.cssColor(UIColor.theme.textStrong),
                backgroundColor: Self.cssColor(UIColor.theme.primary),
                linkColor: Self.cssColor(UIColor.theme.textLink),
                codeBackgroundColor: Self.cssColor(UIColor.theme.secondary)
            ),
            baseURL: nil
        )
    }

    private func showLoadError() {
        activityIndicator.stopAnimating()
        webView?.isHidden = true
        errorLabel.text = L(L10n.Error.connectionFailed)
        errorLabel.isHidden = false
    }

    @objc private func handleThemeChange() {
        applyTheme()
        if let canvasContent {
            renderCanvasContent(canvasContent)
        }
    }

    private func applyTheme() {
        let theme = UIColor.theme
        view.backgroundColor = theme.primary
        displayNode.backgroundColor = theme.primary
        headerBar.backgroundColor = theme.secondary
        titleLabel.textColor = theme.textStrong
        backButton.tintColor = theme.textStrong
        headerSeparator.backgroundColor = theme.border
        activityIndicator.color = theme.textStrong
        errorLabel.textColor = theme.textDisabled
        webView?.backgroundColor = theme.primary
        webView?.scrollView.backgroundColor = theme.primary
        backButton.setImage(
            UIImage(systemName: "chevron.left")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)),
            for: .normal
        )
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        showLoadError()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        showLoadError()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = url.scheme?.lowercased()
        if scheme == "http" || scheme == "https" || scheme == "mailto" {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        decisionHandler(.cancel)
    }

    private static func cssColor(_ color: UIColor) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#000000"
        }
        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }
}

private enum CanvasHTMLRenderer {

    static func document(
        content: String,
        textColor: String,
        backgroundColor: String,
        linkColor: String,
        codeBackgroundColor: String
    ) -> String {
        let body = bodyHTML(from: content)
        return """
        <!doctype html>
        <html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: http:; style-src 'unsafe-inline'">
        <style>
        *{box-sizing:border-box}body{margin:0;padding:16px;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:15px;line-height:1.4;color:\(textColor);background:\(backgroundColor);overflow-wrap:anywhere}
        p,h1,h2,h3,h4,h5,h6,blockquote,pre,ul,ol{margin:0 0 12px}li{margin:0 0 8px}ul,ol{padding-left:1.5em}a{color:\(linkColor);text-decoration:underline}code{background:\(codeBackgroundColor);border-radius:4px;padding:1px 4px}pre{background:\(codeBackgroundColor);border-radius:8px;padding:12px;overflow-x:auto}img{max-width:100%;height:auto}
        </style></head><body>\(body)</body></html>
        """
    }

    private static func bodyHTML(from content: String) -> String {
        let normalized = unwrapJSONString(content)
        guard !normalized.isEmpty else { return "<p></p>" }

        if normalized.hasPrefix("<") {
            return sanitize(normalized)
        }

        if let data = normalized.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            if let items = json as? [[String: Any]],
               let value = items.first(where: {
                   let type = ($0["type"] as? String)?.uppercased()
                   return (type == "TEXT" || type == "HTML")
                       && !(($0["value"] as? String)?.isEmpty ?? true)
               })?["value"] as? String {
                return sanitize(value)
            }
            if let root = json as? [String: Any] {
                if root["type"] as? String == "doc" {
                    return renderNodes(root["content"] as? [[String: Any]])
                }
                if let operations = root["ops"] as? [[String: Any]] {
                    return renderQuill(operations)
                }
            }
        }

        return "<p>\(escape(normalized).replacingOccurrences(of: "\n", with: "<br>"))</p>"
    }

    private static func unwrapJSONString(_ content: String) -> String {
        var value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<3 {
            guard value.hasPrefix("\""), value.hasSuffix("\""),
                  let data = value.data(using: .utf8),
                  let unwrapped = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String
            else { break }
            let trimmed = unwrapped.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed != value else { break }
            value = trimmed
        }
        return value
    }

    private static func renderNodes(_ nodes: [[String: Any]]?, inline: Bool = false) -> String {
        nodes?.map { renderNode($0, inline: inline) }.joined() ?? ""
    }

    private static func renderNode(_ node: [String: Any], inline: Bool) -> String {
        let type = node["type"] as? String ?? ""
        if inline {
            if type == "hardBreak" { return "<br>" }
            if type == "text" { return renderText(node) }
        }
        let children = node["content"] as? [[String: Any]]
        switch type {
        case "paragraph":
            return tag("p", renderNodes(children, inline: true), attributes: nodeAlignmentAttribute(node))
        case "heading":
            let level = min(max((node["attrs"] as? [String: Any])?["level"] as? Int ?? 1, 1), 6)
            return tag("h\(level)", renderNodes(children, inline: true), attributes: nodeAlignmentAttribute(node))
        case "bulletList": return tag("ul", renderNodes(children))
        case "orderedList": return tag("ol", renderNodes(children))
        case "listItem": return tag("li", renderNodes(children))
        case "blockquote": return tag("blockquote", renderNodes(children))
        case "codeBlock": return tag("pre", tag("code", escape(plainText(children))))
        case "horizontalRule": return "<hr>"
        case "hardBreak": return "<br>"
        case "image":
            let attrs = node["attrs"] as? [String: Any]
            guard let source = safeURL(attrs?["src"] as? String) else { return "" }
            return "<img src=\"\(escapeAttribute(source))\" alt=\"\(escapeAttribute(attrs?["alt"] as? String ?? ""))\">"
        case "text": return renderText(node)
        default: return renderNodes(children, inline: inline)
        }
    }

    private static func renderText(_ node: [String: Any]) -> String {
        var result = escape(node["text"] as? String ?? "")
        let marks = node["marks"] as? [[String: Any]] ?? []
        for mark in marks.reversed() {
            switch mark["type"] as? String {
            case "bold": result = tag("strong", result)
            case "italic": result = tag("em", result)
            case "underline": result = tag("u", result)
            case "strike": result = tag("s", result)
            case "code": result = tag("code", result)
            case "link":
                if let url = safeURL((mark["attrs"] as? [String: Any])?["href"] as? String) {
                    result = "<a href=\"\(escapeAttribute(url))\">\(result)</a>"
                }
            default: break
            }
        }
        return result
    }

    private struct QuillLine {
        let html: String
        let attributes: [String: Any]
        let isImage: Bool
    }

    private static func renderQuill(_ operations: [[String: Any]]) -> String {
        var lines: [QuillLine] = []
        var buffer = ""

        func flush(_ attributes: [String: Any]) {
            lines.append(QuillLine(html: buffer, attributes: attributes, isImage: false))
            buffer = ""
        }

        for operation in operations {
            let attributes = operation["attributes"] as? [String: Any] ?? [:]
            if let insert = operation["insert"] as? String {
                let parts = insert.components(separatedBy: "\n")
                for (index, part) in parts.enumerated() {
                    if !part.isEmpty { buffer += quillInline(part, attributes: attributes) }
                    if index < parts.count - 1 { flush(attributes) }
                }
            } else if let insert = operation["insert"] as? [String: Any],
                      let source = safeURL(insert["image"] as? String) {
                if !buffer.isEmpty { flush([:]) }
                lines.append(
                    QuillLine(
                        html: "<img src=\"\(escapeAttribute(source))\" alt=\"\">",
                        attributes: [:],
                        isImage: true
                    )
                )
            }
        }
        if !buffer.isEmpty { flush([:]) }

        var output = ""
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.isImage {
                output += line.html
                index += 1
                continue
            }
            let list = line.attributes["list"] as? String
            if list == "bullet" || list == "ordered" || list == "checked" {
                let listTag = list == "ordered" ? "ol" : "ul"
                var items = ""
                while index < lines.count,
                      !lines[index].isImage,
                      lines[index].attributes["list"] as? String == list {
                    items += tag("li", lines[index].html.isEmpty ? "<br>" : lines[index].html)
                    index += 1
                }
                output += tag(listTag, items)
            } else {
                output += quillBlock(line)
                index += 1
            }
        }
        return output
    }

    private static func quillInline(_ text: String, attributes: [String: Any]) -> String {
        var result = escape(text)
        if let url = safeURL(attributes["link"] as? String) {
            result = "<a href=\"\(escapeAttribute(url))\">\(result)</a>"
        }
        if attributes["bold"] as? Bool == true { result = tag("strong", result) }
        if attributes["italic"] as? Bool == true { result = tag("em", result) }
        if attributes["underline"] as? Bool == true { result = tag("u", result) }
        if attributes["strike"] as? Bool == true { result = tag("s", result) }
        if attributes["code"] as? Bool == true { result = tag("code", result) }
        return result
    }

    private static func quillBlock(_ line: QuillLine) -> String {
        let inner = line.html.isEmpty ? "<br>" : line.html
        let alignment = attributesAlignmentAttribute(line.attributes)
        if line.attributes["code-block"] as? Bool == true {
            return tag("pre", tag("code", inner))
        }
        if line.attributes["blockquote"] as? Bool == true {
            return tag("blockquote", inner, attributes: alignment)
        }
        if let level = line.attributes["header"] as? Int, (1...6).contains(level) {
            return tag("h\(level)", inner, attributes: alignment)
        }
        return tag("p", inner, attributes: alignment)
    }

    private static func nodeAlignmentAttribute(_ node: [String: Any]) -> String? {
        attributesAlignmentAttribute(node["attrs"] as? [String: Any] ?? [:])
    }

    private static func attributesAlignmentAttribute(_ attributes: [String: Any]) -> String? {
        guard let alignment = attributes["textAlign"] as? String ?? attributes["align"] as? String,
              ["left", "center", "right", "justify"].contains(alignment) else { return nil }
        return "style=\"text-align:\(alignment)\""
    }

    private static func plainText(_ nodes: [[String: Any]]?) -> String {
        nodes?.map { node in
            switch node["type"] as? String {
            case "text": return node["text"] as? String ?? ""
            case "hardBreak": return "\n"
            default: return plainText(node["content"] as? [[String: Any]])
            }
        }.joined() ?? ""
    }

    private static func sanitize(_ html: String) -> String {
        var result = html
        let patterns = [
            "(?is)<(script|iframe|object|embed|form|style|frame|frameset|applet)[^>]*>.*?</\\1\\s*>",
            "(?is)<(script|iframe|object|embed|input|meta|link|base|frame|applet)[^>]*/?>",
            "(?is)\\s+on[a-z]+\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)",
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    private static func safeURL(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              let scheme = URL(string: value)?.scheme?.lowercased(),
              scheme == "http" || scheme == "https" || scheme == "mailto" else { return nil }
        return value
    }

    private static func tag(_ name: String, _ content: String, attributes: String? = nil) -> String {
        if let attributes, !attributes.isEmpty {
            return "<\(name) \(attributes)>\(content)</\(name)>"
        }
        return "<\(name)>\(content)</\(name)>"
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ text: String) -> String {
        escape(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
