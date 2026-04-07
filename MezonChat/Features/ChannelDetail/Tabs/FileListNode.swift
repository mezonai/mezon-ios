import AsyncDisplayKit
import UIKit

private struct FileDaySection {
    let year: String
    let dayTs: TimeInterval
    let titleDay: String
    let isFirstOfYear: Bool
    let items: [Mezon_Api_ChannelAttachment]
}

@MainActor
final class FileListNode: ASDisplayNode {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let channelType: Int32

    private var rawAttachments: [Mezon_Api_ChannelAttachment] = []
    private var sections: [FileDaySection] = []
    private var searchQuery: String = ""
    private var isLoading = false
    private var loadFailed = false
    private var filesTabActivated = false

    private let tableNode = ASTableNode()
    private let loadingNode: ASDisplayNode

    init(context: AccountContext, clanId: Int64, channelId: Int64, channelType: Int32) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        self.channelType = channelType

        self.loadingNode = ASDisplayNode(viewBlock: {
            let v = UIActivityIndicatorView(style: .large)
            v.color = UIColor.theme.text
            v.startAnimating()
            return v
        })

        super.init()
        automaticallyManagesSubnodes = true

        tableNode.dataSource = self
        tableNode.delegate = self
        tableNode.backgroundColor = .clear
        tableNode.view.backgroundColor = .clear
        tableNode.view.separatorStyle = .none
        tableNode.view.contentInsetAdjustmentBehavior = .never

        if #available(iOS 15.0, *) {
            tableNode.view.sectionHeaderTopPadding = 0
        }

        loadingNode.style.preferredSize = CGSize(width: 44, height: 44)
    }

    func loadTabDataIfNeeded() {
        guard !filesTabActivated else { return }
        filesTabActivated = true
        fetchFiles()
    }

    override func didLoad() {
        super.didLoad()
        backgroundColor = UIColor.theme.primary
        tableNode.view.backgroundColor = .clear
        installSearchHeader()
    }

    override func layout() {
        super.layout()
        let w = tableNode.bounds.width
        if w > 0, let header = tableNode.view.tableHeaderView, abs(header.frame.width - w) > 0.5 {
            header.frame = CGRect(x: 0, y: 0, width: w, height: header.frame.height)
            tableNode.view.tableHeaderView = header
        }
        updateEmptyFooter()
    }

    private func installSearchHeader() {
        let t = UIColor.theme
        let header = UIView()
        header.backgroundColor = .clear

        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.textColor = t.textStrong
        field.font = .systemFont(ofSize: 15.sf, weight: .regular)
        field.backgroundColor = t.secondary
        field.layer.cornerRadius = 10
        field.layer.masksToBounds = true
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .search
        field.clearButtonMode = .whileEditing
        field.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ChannelDetail.searchFilesPlaceholder),
            attributes: [.foregroundColor: t.textDisabled]
        )

        let icon = UIImageView(
            image: UIImage(systemName: "magnifyingglass")?.withTintColor(
                t.text, renderingMode: .alwaysOriginal))
        icon.contentMode = .scaleAspectFit
        let leftWrap = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        icon.frame = CGRect(x: 10, y: 8, width: 20, height: 20)
        leftWrap.addSubview(icon)
        field.leftView = leftWrap
        field.leftViewMode = .always

        field.addAction(
            UIAction { [weak self] _ in
                self?.searchQuery = field.text ?? ""
                self?.rebuildSectionsAndReload()
            },
            for: .editingChanged
        )

        header.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            field.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            field.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8),
            field.heightAnchor.constraint(equalToConstant: 40),
        ])

        let targetWidth = tableNode.bounds.width > 0 ? tableNode.bounds.width : UIScreen.main.bounds.width
        header.frame = CGRect(x: 0, y: 0, width: targetWidth, height: 56)
        tableNode.view.tableHeaderView = header
    }

    private static func isDocumentAttachment(_ att: Mezon_Api_ChannelAttachment) -> Bool {
        let ft = att.filetype.lowercased()
        if ft == "sticker" { return false }
        if ft.hasPrefix("image/") { return false }
        if ft.hasPrefix("video/") { return false }
        return true
    }

    private func fetchFiles() {
        isLoading = true
        loadFailed = false
        setNeedsLayout()
        Task {
            do {
                let token = await context.getToken() ?? ""
                let targetClanId =
                    (channelType == MezonConstants.ChannelType.dm.rawValue
                        || channelType == MezonConstants.ChannelType.group.rawValue) ? 0 : clanId

                let res = try await context.account.network.listChannelAttachments(
                    clanId: targetClanId,
                    channelId: channelId,
                    fileType: "all",
                    limit: 100,
                    token: token
                )
                let docs = res.attachments.filter { Self.isDocumentAttachment($0) }
                self.rawAttachments = docs
                self.rebuildSectionsAndReload()
            } catch {
                AppLogger.network.error("Fetch files failed: \(error)")
                self.loadFailed = true
                self.rawAttachments = []
                self.sections = []
                await self.tableNode.reloadData()
            }
            self.isLoading = false
            self.setNeedsLayout()
        }
    }

    private func rebuildSectionsAndReload() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [Mezon_Api_ChannelAttachment]
        if q.isEmpty {
            filtered = rawAttachments
        } else {
            filtered = rawAttachments.filter { $0.filename.lowercased().contains(q) }
        }
        sections = Self.groupByYearDay(items: filtered)
        tableNode.reloadData()
        updateEmptyFooter()
    }

    private func updateEmptyFooter() {
        let t = UIColor.theme
        let w = max(tableNode.bounds.width, 280)
        if filesTabActivated, !isLoading, sections.isEmpty {
            let footer = UILabel()
            footer.textAlignment = .center
            footer.font = .systemFont(ofSize: 15.sf, weight: .medium)
            footer.textColor = t.textDisabled
            footer.numberOfLines = 0
            footer.text =
                loadFailed
                ? L(L10n.Error.somethingWentWrong)
                : L(L10n.ChannelDetail.noFilesYet)
            footer.frame = CGRect(x: 0, y: 0, width: w, height: 72)
            tableNode.view.tableFooterView = footer
        } else {
            tableNode.view.tableFooterView = nil
        }
    }

    private static func groupByYearDay(items: [Mezon_Api_ChannelAttachment]) -> [FileDaySection] {
        guard !items.isEmpty else { return [] }
        let cal = Calendar.current
        let sorted = items.sorted { $0.createTimeSeconds > $1.createTimeSeconds }
        var map: [String: [TimeInterval: [Mezon_Api_ChannelAttachment]]] = [:]

        for it in sorted {
            let ts = TimeInterval(it.createTimeSeconds)
            guard ts > 0 else { continue }
            let d = Date(timeIntervalSince1970: ts)
            let y = String(cal.component(.year, from: d))
            let dayStart = cal.startOfDay(for: d).timeIntervalSince1970
            if map[y] == nil { map[y] = [:] }
            map[y]![dayStart, default: []].append(it)
        }

        let yearsNumeric = map.keys.compactMap { Int($0) }.sorted(by: >)
        var result: [FileDaySection] = []

        for yInt in yearsNumeric {
            let year = String(yInt)
            guard let dayDict = map[year] else { continue }
            let dayKeys = dayDict.keys.sorted(by: >)
            for (idx, dayTs) in dayKeys.enumerated() {
                let dayItems = dayDict[dayTs] ?? []
                let date = Date(timeIntervalSince1970: dayTs)
                let title = formatDateHeader(date)
                result.append(
                    FileDaySection(
                        year: year,
                        dayTs: dayTs,
                        titleDay: title,
                        isFirstOfYear: idx == 0,
                        items: dayItems
                    ))
            }
        }
        return result
    }

    private static func formatDateHeader(_ date: Date) -> String {
        let cal = Calendar.current
        let day = cal.component(.day, from: date)
        let month = cal.component(.month, from: date)
        let year = cal.component(.year, from: date)

        switch LanguageManager.shared.current {
        case .vietnamese:
            return String(format: "%02d tháng %02d, %d", day, month, year)
        case .english:
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.setLocalizedDateFormatFromTemplate("dMMMMyyyy")
            return df.string(from: date)
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        tableNode.style.flexGrow = 1
        tableNode.style.flexShrink = 1

        let loadingCentered = ASCenterLayoutSpec(
            centeringOptions: .XY,
            sizingOptions: .minimumXY,
            child: loadingNode
        )
        loadingCentered.style.flexGrow = 1

        if isLoading {
            return ASOverlayLayoutSpec(
                child: ASWrapperLayoutSpec(layoutElement: tableNode),
                overlay: loadingCentered
            )
        }
        return ASWrapperLayoutSpec(layoutElement: tableNode)
    }
}

extension FileListNode: ASTableDataSource, ASTableDelegate {

    func numberOfSections(in tableNode: ASTableNode) -> Int {
        sections.count
    }

    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath)
        -> ASCellNodeBlock
    {
        let att = sections[indexPath.section].items[indexPath.row]
        let ctx = context
        let uploaderName = Self.resolveUploaderName(uploaderId: att.uploader, context: ctx)
        let timeStr = Self.formatTime(createSeconds: att.createTimeSeconds)
        return {
            FileDocumentCellNode(
                attachment: att,
                uploaderDisplayName: uploaderName,
                timeString: timeStr
            )
        }
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForHeaderInSection section: Int)
        -> ASCellNodeBlock
    {
        let sec = sections[section]
        return {
            FileSectionHeaderNode(
                year: sec.year,
                titleDay: sec.titleDay,
                showYear: sec.isFirstOfYear
            )
        }
    }

    func tableNode(_ tableNode: ASTableNode, heightForHeaderInSection section: Int) -> CGFloat {
        sections[section].isFirstOfYear ? 56 : 40
    }

    private static func resolveUploaderName(uploaderId: Int64, context: AccountContext) -> String {
        guard uploaderId != 0 else { return "—" }
        let idStr = String(uploaderId)
        var name = ""
        context.account.postbox.read { tx in
            if let p = tx.getProfile(userId: idStr) {
                if let dn = p.displayName, !dn.isEmpty {
                    name = dn
                } else if !p.username.isEmpty {
                    name = p.username
                }
            }
        }
        return name.isEmpty ? idStr : name
    }

    private static func formatTime(createSeconds: UInt32) -> String {
        guard createSeconds > 0 else { return "" }
        let df = DateFormatter()
        df.timeStyle = .short
        df.dateStyle = .none
        return df.string(from: Date(timeIntervalSince1970: TimeInterval(createSeconds)))
    }
}

private final class FileSectionHeaderNode: ASCellNode {

    private let bgNode = ASDisplayNode()
    private let yearNode = ASTextNode2()
    private let dayNode = ASTextNode2()
    private let showYear: Bool

    init(year: String, titleDay: String, showYear: Bool) {
        self.showYear = showYear
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear

        let t = UIColor.theme
        bgNode.backgroundColor = t.primary

        yearNode.isHidden = !showYear
        if showYear {
            yearNode.attributedText = NSAttributedString(
                string: year,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 16.sf, weight: .bold),
                    .foregroundColor: t.textStrong,
                ]
            )
        }

        dayNode.attributedText = NSAttributedString(
            string: titleDay,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .semibold),
                .foregroundColor: t.text,
            ]
        )
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        var children: [ASLayoutElement] = []
        if showYear { children.append(yearNode) }
        children.append(dayNode)

        let stack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 4,
            justifyContent: .start,
            alignItems: .start,
            children: children
        )
        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 10, left: 10, bottom: 8, right: 10),
            child: stack
        )
        return ASBackgroundLayoutSpec(child: inset, background: bgNode)
    }
}

private final class FileDocumentCellNode: ASCellNode {

    private let card = ASDisplayNode()
    private let iconNode = ASImageNode()
    private let titleNode = ASTextNode2()
    private let sharedNode = ASTextNode2()
    private let timeNode = ASTextNode2()
    private let fileURL: URL?

    init(
        attachment: Mezon_Api_ChannelAttachment,
        uploaderDisplayName: String,
        timeString: String
    ) {
        self.fileURL = URL(string: attachment.url)
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear

        let t = UIColor.theme
        card.backgroundColor = t.secondary
        card.cornerRadius = 8

        let iconName = Self.sfSymbol(for: attachment.filetype)
        iconNode.image = UIImage(systemName: iconName)?.withTintColor(
            t.text, renderingMode: .alwaysOriginal)
        iconNode.contentMode = .scaleAspectFit
        iconNode.style.preferredSize = CGSize(width: 34, height: 34)

        let name = attachment.filename.isEmpty ? "File" : attachment.filename
        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail
        titleNode.attributedText = NSAttributedString(
            string: name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.sf, weight: .medium),
                .foregroundColor: t.bgViolet,
            ]
        )

        sharedNode.maximumNumberOfLines = 1
        sharedNode.truncationMode = .byTruncatingTail
        sharedNode.attributedText = NSAttributedString(
            string: String(format: L(L10n.ChannelDetail.fileSharedBy), uploaderDisplayName),
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf, weight: .regular),
                .foregroundColor: t.text,
            ]
        )

        timeNode.maximumNumberOfLines = 1
        timeNode.attributedText = NSAttributedString(
            string: timeString,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf, weight: .light),
                .foregroundColor: t.textDisabled,
            ]
        )
    }

    override func didLoad() {
        super.didLoad()
        view.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(openLink))
        view.addGestureRecognizer(tap)
    }

    @objc private func openLink() {
        guard let fileURL else { return }
        UIApplication.shared.open(fileURL)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let footerRow = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 10,
            justifyContent: .spaceBetween,
            alignItems: .center,
            children: [sharedNode, timeNode]
        )
        footerRow.style.flexGrow = 1

        let textCol = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 6,
            justifyContent: .start,
            alignItems: .stretch,
            children: [titleNode, footerRow]
        )
        textCol.style.flexGrow = 1
        textCol.style.flexShrink = 1

        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 10,
            justifyContent: .start,
            alignItems: .center,
            children: [iconNode, textCol]
        )

        let padded = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12),
            child: row
        )
        let cardSpec = ASBackgroundLayoutSpec(child: padded, background: card)

        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10),
            child: cardSpec
        )
    }

    private static func sfSymbol(for filetype: String) -> String {
        let ft = filetype.lowercased()
        if ft.contains("pdf") { return "doc.richtext.fill" }
        if ft.contains("audio") || ft.contains("mpeg") || ft.contains("mp3") || ft.contains("wav") {
            return "music.note"
        }
        if ft.contains("zip") || ft.contains("rar") || ft.contains("tar") || ft.contains("gz") {
            return "archivebox.fill"
        }
        if ft.contains("text") || ft.contains("json") || ft.contains("xml") {
            return "doc.plaintext.fill"
        }
        if ft.contains("sheet") || ft.contains("excel") || ft.contains("spreadsheet") {
            return "tablecells.fill"
        }
        return "doc.fill"
    }
}
