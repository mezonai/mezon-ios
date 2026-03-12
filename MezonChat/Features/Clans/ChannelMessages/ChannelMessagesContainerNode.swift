import UIKit
import AsyncDisplayKit

struct ChannelMessagesInteraction {
    let onBackTapped: () -> Void
    let onScrolledNearTop: () -> Void
    let onScrolledToBottom: (Bool) -> Void
}

final class ChannelMessagesContainerNode: ASDisplayNode {

    let tableView: UITableView
    private let headerView           = UIView()
    private let backButton           = UIButton(type: .system)
    let channelTitleLabel            = UILabel()
    private let loadingIndicator     = UIActivityIndicatorView(style: .medium)
    private let loadingMoreIndicator = UIActivityIndicatorView(style: .medium)
    let emptyLabel                   = UILabel()

    private(set) var state: ChannelMessagesState = .empty
    private let interaction: ChannelMessagesInteraction
    private let disposables = DisposableSet()

    init(signal: Signal<ChannelMessagesState, NoError>, interaction: ChannelMessagesInteraction) {
        tableView = UITableView(frame: .zero, style: .plain)
        self.interaction = interaction
        super.init()

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                self.state = newState

                let labelText = newState.channelLabel
                let prefix = labelText.hasPrefix("#") ? "" : "#"
                self.channelTitleLabel.text = "\(prefix)\(labelText)"

                if newState.isLoading { self.loadingIndicator.startAnimating() }
                else { self.loadingIndicator.stopAnimating() }
                if newState.isLoadingMore { self.loadingMoreIndicator.startAnimating() }
                else { self.loadingMoreIndicator.stopAnimating() }

                if let msg = newState.errorMessage { Toast.error(msg) }

                self.tableView.reloadData()
                let isEmpty = !newState.isLoading && newState.messages.isEmpty
                self.emptyLabel.isHidden = !isEmpty
            })
        )
    }

    deinit { disposables.dispose() }

    override func didLoad() {
        super.didLoad()

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72.sh
        tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseId)
        tableView.dataSource = self
        tableView.delegate   = self

        var backCfg = UIButton.Configuration.plain()
        backCfg.image = UIImage(systemName: "chevron.left")
        backButton.configuration = backCfg
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        channelTitleLabel.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        loadingIndicator.hidesWhenStopped     = true
        loadingMoreIndicator.hidesWhenStopped = true

        emptyLabel.font = .systemFont(ofSize: 15.sf)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true

        for v in [headerView, tableView, loadingIndicator, loadingMoreIndicator, emptyLabel] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        for v in [backButton, channelTitleLabel] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview(v)
        }
    }

    func updateLayout(layout: ContainerViewLayout, inputBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let headerH: CGFloat = 44.sh
        let headerFrame = CGRect(x: 0, y: layout.safeInsets.top, width: layout.size.width, height: headerH)
        transition.updateFrame(view: headerView, frame: headerFrame)

        let tvFrame = CGRect(
            x: 0, y: headerFrame.maxY,
            width: layout.size.width,
            height: layout.size.height - headerFrame.maxY - inputBarHeight - layout.intrinsicInsets.bottom
        )
        transition.updateFrame(view: tableView, frame: tvFrame)

        let liS: CGFloat = 24.swh
        transition.updateFrame(view: loadingIndicator, frame: CGRect(
            x: (layout.size.width - liS) / 2, y: (layout.size.height - liS) / 2, width: liS, height: liS))
        transition.updateFrame(view: loadingMoreIndicator, frame: CGRect(
            x: (layout.size.width - liS) / 2, y: headerFrame.maxY + 12.sh, width: liS, height: liS))

        let elH: CGFloat = 44.sh
        transition.updateFrame(view: emptyLabel, frame: CGRect(
            x: 0, y: (layout.size.height - elH) / 2, width: layout.size.width, height: elH))

        let btnH: CGFloat = 44.swh
        transition.updateFrame(view: backButton, frame: CGRect(x: 12.sw, y: 0, width: btnH, height: headerH))
        transition.updateFrame(view: channelTitleLabel, frame: CGRect(
            x: 12.sw + btnH + 4.sw, y: 0,
            width: layout.size.width - 12.sw - btnH - 4.sw - 60.sw,
            height: headerH))
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor               = t.primary
        headerView.backgroundColor    = t.secondary
        backButton.tintColor          = t.textStrong
        channelTitleLabel.textColor   = t.textStrong
        loadingIndicator.color        = t.textDisabled
        loadingMoreIndicator.color    = t.textDisabled
        emptyLabel.textColor          = t.textDisabled
        emptyLabel.text               = L(L10n.ChannelMessages.emptyMessages)
    }

    @objc private func backTapped() { interaction.onBackTapped() }
}

extension ChannelMessagesContainerNode: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        state.messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseId, for: indexPath) as! MessageCell
        cell.configure(display: state.messages[indexPath.row])
        return cell
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y < 80 {
            interaction.onScrolledNearTop()
        }
        let atBottom = scrollView.contentOffset.y + scrollView.bounds.height >= scrollView.contentSize.height - 100
        interaction.onScrolledToBottom(atBottom)
    }
}

final class MessageCell: UITableViewCell {

    static let reuseId = "MessageCell"

    private let avatarView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 18.swh
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.backgroundColor = .colorAvatarDefault
        return iv
    }()

    private let avatarPlaceholder: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        l.textAlignment = .center
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let timeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12.sf)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let contentLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf)
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private var contentTopToName: NSLayoutConstraint?
    private var contentTopToView: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(avatarView)
        avatarView.addSubview(avatarPlaceholder)
        contentView.addSubview(nameLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(contentLabel)

        contentTopToName = contentLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2.sh)
        contentTopToView = contentLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4.sh)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12.sw),
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8.sh),
            avatarView.widthAnchor.constraint(equalToConstant: 36.swh),
            avatarView.heightAnchor.constraint(equalToConstant: 36.swh),

            avatarPlaceholder.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarPlaceholder.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10.sw),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8.sh),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8.sw),

            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12.sw),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            contentLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            contentLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12.sw),
            contentLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8.sh)
        ])
        contentTopToName?.isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(display: ChannelMessageDisplay) {
        let t = UIColor.theme
        let isCombine = display.isCombine

        nameLabel.text = display.senderDisplayName
        nameLabel.textColor = t.textRoleLink
        timeLabel.text = formatDate(display.message.createdAt)
        timeLabel.textColor = t.textDisabled
        contentLabel.text = display.message.textContent ?? "[unsupported]"
        contentLabel.textColor = t.textStrong

        avatarView.isHidden = isCombine
        avatarPlaceholder.isHidden = isCombine
        nameLabel.isHidden = isCombine
        timeLabel.isHidden = isCombine

        contentTopToName?.isActive = false
        contentTopToView?.isActive = false
        if isCombine {
            contentTopToView?.isActive = true
        } else {
            contentTopToName?.isActive = true
        }

        if !isCombine {
            if let urlString = display.avatarURL, !urlString.isEmpty, let url = URL(string: urlString) {
                avatarPlaceholder.isHidden = true
                avatarView.image = nil
                URLSession.shared.dataTask(with: url) { [weak avatarView] data, _, _ in
                    guard let data, let img = UIImage(data: data) else { return }
                    DispatchQueue.main.async { avatarView?.image = img }
                }
                .resume()
            } else {
                avatarView.image = nil
                avatarPlaceholder.isHidden = false
                avatarPlaceholder.text = String(display.senderDisplayName.prefix(1)).uppercased()
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        let timeF = DateFormatter()
        timeF.dateFormat = "HH:mm"
        let timeStr = timeF.string(from: date)
        if cal.isDateInToday(date) {
            return String(format: L(L10n.ChannelMessages.todayAt), timeStr)
        }
        if cal.isDateInYesterday(date) {
            return String(format: L(L10n.ChannelMessages.yesterdayAt), timeStr)
        }
        let fullF = DateFormatter()
        fullF.dateFormat = "dd/MM/yyyy, HH:mm"
        return fullF.string(from: date)
    }
}
