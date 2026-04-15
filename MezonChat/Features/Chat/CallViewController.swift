import UIKit

@MainActor
final class CallViewController: UIViewController {

    private let accountContext: AccountContext
    private let remoteUserName: String
    private let remoteAvatarURL: String?
    private let remoteUserId: Int64
    private let dmChannelId: Int64
    private let isOutgoing: Bool

    init(
        context: AccountContext,
        remoteUserName: String,
        remoteAvatarURL: String?,
        remoteUserId: Int64,
        dmChannelId: Int64,
        isOutgoing: Bool
    ) {
        self.accountContext = context
        self.remoteUserName = remoteUserName
        self.remoteAvatarURL = remoteAvatarURL
        self.remoteUserId = remoteUserId
        self.dmChannelId = dmChannelId
        self.isOutgoing = isOutgoing
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.mezonTertiaryBackground

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = remoteUserName.isEmpty ? "Call" : remoteUserName
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = UIColor.mezonTextStrong

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = isOutgoing ? "Calling…" : "Incoming call"
        subtitle.textAlignment = .center
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = UIColor.mezonTextSecondary

        let endButton = UIButton(type: .system)
        endButton.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 15.0, *) {
            var endCfg = UIButton.Configuration.plain()
            endCfg.title = "End"
            endCfg.baseForegroundColor = .white
            endCfg.background.backgroundColor = UIColor.mezonError
            endCfg.background.cornerRadius = 28
            endCfg.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 32, bottom: 14, trailing: 32)
            endCfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = .systemFont(ofSize: 17, weight: .semibold)
                return out
            }
            endButton.configuration = endCfg
        } else {
            endButton.setTitle("End", for: .normal)
            endButton.setTitleColor(.white, for: .normal)
            endButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            endButton.backgroundColor = UIColor.mezonError
            endButton.layer.cornerRadius = 28
            endButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 32, bottom: 14, right: 32)
        }
        endButton.addTarget(self, action: #selector(endButtonTapped), for: .touchUpInside)

        view.addSubview(titleLabel)
        view.addSubview(subtitle)
        view.addSubview(endButton)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),

            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            subtitle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            endButton.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 48),
            endButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

    }

    @objc private func endButtonTapped() {
        dismiss(animated: true)
    }
}
