import UIKit
import AsyncDisplayKit

struct ClanListInteraction {
    let onSelectClan: (Mezon_Api_ClanDesc) -> Void
    let onMessagesTapped: () -> Void
    let onProfileTapped: () -> Void
    let onThemeTapped: () -> Void
    let onLanguageTapped: () -> Void
}

final class ClanListContainerNode: ASDisplayNode {

    private let collectionView: UICollectionView
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let messagesButton = UIButton(type: .system)
    private let profileButton  = UIButton(type: .system)
    private let themeButton    = UIButton(type: .system)
    private let languageButton = UIButton(type: .system)

    private var state: ClanListState = .empty
    private let interaction: ClanListInteraction
    private let disposables = DisposableSet()

    init(signal: Signal<ClanListState, NoError>, interaction: ClanListInteraction) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 8.sh
        layout.itemSize = CGSize(width: 48.swh, height: 48.swh)
        layout.sectionInset = UIEdgeInsets(top: 12.sh, left: 0, bottom: 12.sh, right: 0)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.interaction = interaction
        super.init()

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                let prevClanId = self.state.selectedClanId
                let wasLoading = self.state.isLoading
                self.state = newState

                if newState.isLoading != wasLoading {
                    if newState.isLoading { self.loadingIndicator.startAnimating() }
                    else { self.loadingIndicator.stopAnimating() }
                }

                if newState.clans.count != self.collectionView.numberOfItems(inSection: 0) {
                    self.collectionView.reloadData()
                } else if prevClanId != newState.selectedClanId {
                    var paths: [IndexPath] = []
                    if let prev = prevClanId, let idx = newState.clans.firstIndex(where: { $0.clanID == prev }) {
                        paths.append(IndexPath(item: idx, section: 0))
                    }
                    if let curr = newState.selectedClanId, let idx = newState.clans.firstIndex(where: { $0.clanID == curr }) {
                        paths.append(IndexPath(item: idx, section: 0))
                    }
                    if !paths.isEmpty {
                        UIView.performWithoutAnimation { self.collectionView.reloadItems(at: paths) }
                    }
                }
            })
        )
    }

    deinit { disposables.dispose() }

    override func didLoad() {
        super.didLoad()

        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(ClanCell.self, forCellWithReuseIdentifier: ClanCell.reuseID)
        collectionView.dataSource = self
        collectionView.delegate   = self

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        for (btn, icon) in [
            (messagesButton, "bubble.left.and.bubble.right"),
            (profileButton,  "person.crop.circle"),
            (themeButton,    "paintpalette.fill"),
            (languageButton, "globe")
        ] as [(UIButton, String)] {
            btn.setImage(
                UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20.sf, weight: .medium)),
                for: .normal
            )
            btn.translatesAutoresizingMaskIntoConstraints = false
        }

        messagesButton.addTarget(self, action: #selector(messagesButtonTapped), for: .touchUpInside)
        profileButton.addTarget(self, action: #selector(profileButtonTapped), for: .touchUpInside)
        themeButton.addTarget(self, action: #selector(themeButtonTapped), for: .touchUpInside)
        languageButton.addTarget(self, action: #selector(languageButtonTapped), for: .touchUpInside)

        view.addSubview(collectionView)
        view.addSubview(loadingIndicator)
        view.addSubview(messagesButton)
        view.addSubview(profileButton)
        view.addSubview(themeButton)
        view.addSubview(languageButton)
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        let btnSize: CGFloat = 44.swh
        let btmInset = layout.intrinsicInsets.bottom + 8.sh

        let langY    = layout.size.height - btmInset - btnSize
        let themeY   = langY - 4.sh - btnSize
        let profileY = themeY - 4.sh - btnSize
        let msgY     = profileY - 4.sh - btnSize
        let centerX  = layout.size.width / 2 - btnSize / 2

        transition.updateFrame(view: languageButton, frame: CGRect(x: centerX, y: langY, width: btnSize, height: btnSize))
        transition.updateFrame(view: themeButton,    frame: CGRect(x: centerX, y: themeY, width: btnSize, height: btnSize))
        transition.updateFrame(view: profileButton,  frame: CGRect(x: centerX, y: profileY, width: btnSize, height: btnSize))
        transition.updateFrame(view: messagesButton, frame: CGRect(x: centerX, y: msgY, width: btnSize, height: btnSize))

        let cvFrame = CGRect(
            x: 8.sw,
            y: layout.safeInsets.top,
            width: layout.size.width - 16.sw,
            height: msgY - layout.safeInsets.top - 8.sh
        )
        transition.updateFrame(view: collectionView, frame: cvFrame)

        let liSize: CGFloat = 24
        transition.updateFrame(
            view: loadingIndicator,
            frame: CGRect(x: (layout.size.width - liSize) / 2, y: (layout.size.height - liSize) / 2, width: liSize, height: liSize)
        )
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor          = t.tertiary
        loadingIndicator.color   = t.textDisabled
        messagesButton.tintColor = t.channelNormal
        profileButton.tintColor  = t.channelNormal
        themeButton.tintColor    = t.channelNormal
        languageButton.tintColor = t.channelNormal
        collectionView.reloadData()
    }

    @objc private func messagesButtonTapped() { interaction.onMessagesTapped() }
    @objc private func profileButtonTapped()  { interaction.onProfileTapped() }
    @objc private func themeButtonTapped()    { interaction.onThemeTapped() }
    @objc private func languageButtonTapped() { interaction.onLanguageTapped() }
}

extension ClanListContainerNode: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        state.clans.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ClanCell.reuseID, for: indexPath) as! ClanCell
        let clan = state.clans[indexPath.item]
        cell.configure(with: clan, isSelected: clan.clanID == state.selectedClanId)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        interaction.onSelectClan(state.clans[indexPath.item])
    }
}

private final class ClanCell: UICollectionViewCell {

    static let reuseID = "ClanCell"

    private let indicatorBar: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.layer.cornerRadius = 2
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let avatarContainer: UIView = {
        let v = UIView()
        v.clipsToBounds = true
        v.layer.cornerRadius = 24
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let initialsLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        l.textColor = .white
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let badgeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10.sf, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.backgroundColor = .systemRed
        l.layer.cornerRadius = 9
        l.clipsToBounds = true
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isHidden = true
        return l
    }()

    private var imageTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(indicatorBar)
        contentView.addSubview(avatarContainer)
        avatarContainer.addSubview(avatarImageView)
        avatarContainer.addSubview(initialsLabel)
        contentView.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            indicatorBar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            indicatorBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: -8.sw),
            indicatorBar.widthAnchor.constraint(equalToConstant: 4.sw),
            indicatorBar.heightAnchor.constraint(equalToConstant: 20.swh),

            avatarContainer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            avatarContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarContainer.widthAnchor.constraint(equalToConstant: 48.swh),
            avatarContainer.heightAnchor.constraint(equalToConstant: 48.swh),

            avatarImageView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),

            initialsLabel.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),

            badgeLabel.topAnchor.constraint(equalTo: avatarContainer.topAnchor, constant: -4.swh),
            badgeLabel.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor, constant: 4.swh),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18.swh),
            badgeLabel.heightAnchor.constraint(equalToConstant: 18.swh),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        avatarImageView.image = nil
        initialsLabel.text = nil
        badgeLabel.isHidden = true
    }

    func configure(with clan: Mezon_Api_ClanDesc, isSelected: Bool) {
        let cornerRadius: CGFloat = isSelected ? 16.swh : 24.swh
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        avatarContainer.layer.cornerRadius = cornerRadius
        CATransaction.commit()
        indicatorBar.isHidden = !isSelected

        avatarContainer.backgroundColor = colorFor(name: clan.clanName)
        initialsLabel.text = initials(for: clan.clanName)

        if !clan.logo.isEmpty, let url = URL(string: clan.logo) {
            avatarImageView.isHidden = false
            initialsLabel.isHidden = true
            loadImage(url: url)
        } else {
            avatarImageView.isHidden = true
            initialsLabel.isHidden = false
        }

        let count = clan.badgeCount
        if count > 0 {
            badgeLabel.text = count > 99 ? "99+" : "\(count)"
            badgeLabel.isHidden = false
        } else {
            badgeLabel.isHidden = true
        }
    }

    private func loadImage(url: URL) {
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.avatarImageView.image = image
            }
        }
        imageTask?.resume()
    }

    private func initials(for name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first }.map { String($0).uppercased() }.joined()
    }

    private func colorFor(name: String) -> UIColor {
        let colors: [UIColor] = [
            UIColor(red: 0.36, green: 0.36, blue: 0.82, alpha: 1),
            UIColor(red: 0.23, green: 0.56, blue: 0.42, alpha: 1),
            UIColor(red: 0.72, green: 0.26, blue: 0.26, alpha: 1),
            UIColor(red: 0.75, green: 0.52, blue: 0.18, alpha: 1),
            UIColor(red: 0.32, green: 0.52, blue: 0.78, alpha: 1),
            UIColor(red: 0.55, green: 0.28, blue: 0.68, alpha: 1),
        ]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}
