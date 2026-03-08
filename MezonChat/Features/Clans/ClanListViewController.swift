import UIKit
import Combine

final class ClanListViewController: BaseViewController {

    private let viewModel: ClanListViewModel
    private let sharedDataStore: ClansStore

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 8.sh
        layout.itemSize = CGSize(width: 48.swh, height: 48.swh)
        layout.sectionInset = UIEdgeInsets(top: 12.sh, left: 0, bottom: 12.sh, right: 0)

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsVerticalScrollIndicator = false
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.register(ClanCell.self, forCellWithReuseIdentifier: ClanCell.reuseID)
        return cv
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.color = .white
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private lazy var themeButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "paintpalette.fill",
                         withConfiguration: UIImage.SymbolConfiguration(pointSize: 20.sf, weight: .medium))
        btn.setImage(img, for: .normal)
        btn.tintColor = UIColor.white.withAlphaComponent(0.7)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var languageButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "globe",
                         withConfiguration: UIImage.SymbolConfiguration(pointSize: 20.sf, weight: .medium))
        btn.setImage(img, for: .normal)
        btn.tintColor = UIColor.white.withAlphaComponent(0.7)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    var onThemeTapped: (() -> Void)?
    var onLanguageTapped: (() -> Void)?


    init(viewModel: ClanListViewModel) {
        self.viewModel = viewModel
        self.sharedDataStore = viewModel.clansStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }


    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.loadClans()
    }


    override func setupUI() {

        view.addSubview(collectionView)
        view.addSubview(loadingIndicator)
        view.addSubview(themeButton)
        view.addSubview(languageButton)

        NSLayoutConstraint.activate([
            languageButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            languageButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12.sh),
            languageButton.widthAnchor.constraint(equalToConstant: 44.swh),
            languageButton.heightAnchor.constraint(equalToConstant: 44.swh),

            themeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            themeButton.bottomAnchor.constraint(equalTo: languageButton.topAnchor, constant: -4.sh),
            themeButton.widthAnchor.constraint(equalToConstant: 44.swh),
            themeButton.heightAnchor.constraint(equalToConstant: 44.swh),

            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8.sw),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8.sw),
            collectionView.bottomAnchor.constraint(equalTo: themeButton.topAnchor, constant: -8.sh),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        collectionView.dataSource = self
        collectionView.delegate = self

        themeButton.addTarget(self, action: #selector(themeButtonTapped), for: .touchUpInside)
        languageButton.addTarget(self, action: #selector(languageButtonTapped), for: .touchUpInside)
    }

    override func applyTheme() {
        let t = UIColor.theme
        view.backgroundColor    = t.tertiary
        loadingIndicator.color  = t.textDisabled
        themeButton.tintColor   = t.channelNormal
        languageButton.tintColor = t.channelNormal
        collectionView.reloadData()
    }

    @objc private func themeButtonTapped() {
        onThemeTapped?()
    }

    @objc private func languageButtonTapped() {
        onLanguageTapped?()
    }

    override func setupBindings() {
        let store = viewModel.clansStore

        store.$clans
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: [Mezon_Api_ClanDesc]) in self?.collectionView.reloadData() }
            .store(in: &cancellables)

        store.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (loading: Bool) in
                if loading { self?.loadingIndicator.startAnimating() }
                else { self?.loadingIndicator.stopAnimating() }
            }
            .store(in: &cancellables)

        store.$selectedClanId
            .receive(on: DispatchQueue.main)
            .scan((previous: Int64?.none, current: Int64?.none)) { acc, newId in
                (previous: acc.current, current: newId)
            }
            .sink { [weak self] (previous: Int64?, current: Int64?) in
                guard let self else { return }
                var paths: [IndexPath] = []
                if let prev = previous,
                   let idx = self.viewModel.clans.firstIndex(where: { $0.clanID == prev }) {
                    paths.append(IndexPath(item: idx, section: 0))
                }
                if let curr = current,
                   let idx = self.viewModel.clans.firstIndex(where: { $0.clanID == curr }) {
                    paths.append(IndexPath(item: idx, section: 0))
                }
                guard !paths.isEmpty else { return }
                UIView.performWithoutAnimation {
                    self.collectionView.reloadItems(at: paths)
                }
            }
            .store(in: &cancellables)
    }
}


extension ClanListViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        viewModel.clans.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ClanCell.reuseID, for: indexPath) as! ClanCell
        let clan = viewModel.clans[indexPath.item]
        let isSelected = clan.clanID == viewModel.selectedClanId
        cell.configure(with: clan, isSelected: isSelected)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        viewModel.select(clan: viewModel.clans[indexPath.item])
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
        UIView.animate(withDuration: 0.2) {
            self.avatarContainer.layer.cornerRadius = cornerRadius
            self.indicatorBar.isHidden = !isSelected
        }

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
