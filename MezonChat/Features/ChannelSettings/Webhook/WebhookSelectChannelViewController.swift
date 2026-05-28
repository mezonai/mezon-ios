import UIKit
import AsyncDisplayKit

final class WebhookSelectChannelViewController: BaseViewController {
    private let context: AccountContext
    private let clanId: Int64
    private let currentChannelId: Int64
    private let onSelect: (Mezon_Api_ChannelDescription) -> Void
    private var channels: [Mezon_Api_ChannelDescription] = []

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    init(context: AccountContext, clanId: Int64, currentChannelId: Int64, onSelect: @escaping (Mezon_Api_ChannelDescription) -> Void) {
        self.context = context
        self.clanId = clanId
        self.currentChannelId = currentChannelId
        self.onSelect = onSelect
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) { fatalError() }

    override func setupUI() {
        displayNode.backgroundColor = UIColor.theme.primary
        let t = UIColor.theme

        let header = UIView()
        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44.sh),
        ])

        let titleLabel = UILabel()
        titleLabel.text = L(L10n.Webhook.channel)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textColor = t.textStrong
        header.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        stackView.axis = .vertical
        stackView.spacing = 0
        scrollView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16.sh),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16.sw),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16.sw),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16.sh),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32.sw),
        ])

        loadChannels()
    }

    private func loadChannels() {
        let postbox = context.account.postbox
        let channelListKey = PreferencesKeys.channelList(clanId: clanId)
        if let data = postbox.getPreferenceData(key: channelListKey) {
            let allChannels = ChannelPreferenceListCodec.decode(data)
            channels = allChannels.filter { $0.type == MezonConstants.ChannelType.channel.rawValue && $0.parentID == 0 }
        }

        buildChannelRows()
    }

    private func buildChannelRows() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let container = UIView()
        container.backgroundColor = UIColor.theme.secondary
        container.layer.cornerRadius = 12
        container.clipsToBounds = true

        let innerStack = UIStackView()
        innerStack.axis = .vertical
        innerStack.spacing = 0
        container.addSubview(innerStack)
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: container.topAnchor),
            innerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            innerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            innerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        for (idx, channel) in channels.enumerated() {
            let row = createChannelRow(channel: channel)
            innerStack.addArrangedSubview(row)
            if idx < channels.count - 1 {
                let sep = UIView()
                sep.backgroundColor = UIColor.theme.border
                innerStack.addArrangedSubview(sep)
                sep.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
            }
        }

        stackView.addArrangedSubview(container)
    }

    private func createChannelRow(channel: Mezon_Api_ChannelDescription) -> UIView {
        let button = ChannelRowButton(type: .system)
        button.backgroundColor = .clear
        button.channel = channel
        button.addTarget(self, action: #selector(handleChannelTap(_:)), for: .touchUpInside)

        let iconName = channel.channelListIconAssetName()
        let hashIcon = UIImageView(image: (UIImage(named: iconName) ?? UIImage(systemName: iconName))?.withRenderingMode(.alwaysTemplate))
        hashIcon.tintColor = UIColor.theme.textDisabled
        hashIcon.contentMode = .scaleAspectFit
        button.addSubview(hashIcon)
        hashIcon.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.text = channel.channelLabel
        label.font = .systemFont(ofSize: 15.sf, weight: .medium)
        label.textColor = UIColor.theme.textStrong
        label.isUserInteractionEnabled = false
        button.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            hashIcon.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 16.sw),
            hashIcon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            hashIcon.widthAnchor.constraint(equalToConstant: 18.swh),
            hashIcon.heightAnchor.constraint(equalToConstant: 18.swh),
            
            label.leadingAnchor.constraint(equalTo: hashIcon.trailingAnchor, constant: 8.sw),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -40.sw),
        ])
        
        if channel.channelID == currentChannelId {
            let checkIcon = UIImageView(image: UIImage(systemName: "checkmark")?.withRenderingMode(.alwaysTemplate))
            checkIcon.tintColor = UIColor.theme.bgViolet
            button.addSubview(checkIcon)
            checkIcon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                checkIcon.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -16.sw),
                checkIcon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                checkIcon.widthAnchor.constraint(equalToConstant: 20.swh),
                checkIcon.heightAnchor.constraint(equalToConstant: 20.swh),
            ])
        }

        button.heightAnchor.constraint(equalToConstant: 52.sh).isActive = true
        return button
    }

    @objc private func handleBack() {
        dismiss(animated: true)
    }

    @objc private func handleChannelTap(_ sender: ChannelRowButton) {
        guard let channel = sender.channel else { return }
        onSelect(channel)
        dismiss(animated: true)
    }
}

private final class ChannelRowButton: UIButton {
    var channel: Mezon_Api_ChannelDescription?
}
