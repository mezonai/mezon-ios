import UIKit

final class ChannelBannerView: UIView {

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private var currentURL: String?
    private let heightConstraint: NSLayoutConstraint
    private var imageTask: URLSessionDataTask?

    override init(frame: CGRect) {
        heightConstraint = imageView.heightAnchor.constraint(equalToConstant: 140.sh)
        super.init(frame: frame)
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint,
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func loadBanner(urlString: String) {
        guard urlString != currentURL else { return }
        currentURL = urlString
        imageTask?.cancel()

        if let cached = ImageCache.shared.cachedImage(forURL: urlString) {
            imageView.image = cached
            return
        }

        imageView.image = nil
        imageTask = ImageCache.shared.loadImage(urlString: urlString) { [weak self] image in
            guard let self, self.currentURL == urlString else { return }
            self.imageView.image = image
        }
    }

    func clearBanner() {
        currentURL = nil
        imageTask?.cancel()
        imageView.image = nil
    }
}
