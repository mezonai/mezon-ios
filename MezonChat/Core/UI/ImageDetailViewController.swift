import UIKit

final class ImageDetailViewController: UIViewController {

    private let image: UIImage
    private weak var sourceView: UIView?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let closeButton = UIButton(type: .system)
    private let backgroundView = UIView()

    init(image: UIImage, sourceView: UIView?) {
        self.image = image
        self.sourceView = sourceView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        backgroundView.backgroundColor = .black
        backgroundView.frame = view.bounds
        backgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backgroundView)

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrollView)

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.frame = view.bounds
        scrollView.addSubview(imageView)

        let closeConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: closeConfig), for: .normal)
        closeButton.tintColor = .white
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        let panDismiss = UIPanGestureRecognizer(target: self, action: #selector(handlePanDismiss(_:)))
        panDismiss.delegate = self
        scrollView.addGestureRecognizer(panDismiss)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateImageFrame()
    }

    override var prefersStatusBarHidden: Bool { true }

    private func updateImageFrame() {
        let imageSize = image.size
        let boundsSize = scrollView.bounds.size
        guard imageSize.width > 0, imageSize.height > 0, boundsSize.width > 0 else { return }

        let widthRatio = boundsSize.width / imageSize.width
        let heightRatio = boundsSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        imageView.frame = CGRect(
            x: max(0, (boundsSize.width - scaledSize.width) / 2),
            y: max(0, (boundsSize.height - scaledSize.height) / 2),
            width: scaledSize.width,
            height: scaledSize.height
        )
        scrollView.contentSize = scaledSize
    }

    private func centerImageInScrollView() {
        let boundsSize = scrollView.bounds.size
        let contentSize = scrollView.contentSize

        let offsetX = max(0, (boundsSize.width - contentSize.width) / 2)
        let offsetY = max(0, (boundsSize.height - contentSize.height) / 2)

        imageView.center = CGPoint(
            x: contentSize.width / 2 + offsetX,
            y: contentSize.height / 2 + offsetY
        )
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func handleSingleTap() {
        UIView.animate(withDuration: 0.2) {
            self.closeButton.alpha = self.closeButton.alpha > 0.5 ? 0 : 1
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let zoomScale = min(scrollView.maximumZoomScale, 3.0)
            let width = scrollView.bounds.width / zoomScale
            let height = scrollView.bounds.height / zoomScale
            let rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
            scrollView.zoom(to: rect, animated: true)
        }
    }

    private var panStartPoint: CGPoint = .zero
    private var panStartCenter: CGPoint = .zero

    @objc private func handlePanDismiss(_ gesture: UIPanGestureRecognizer) {
        guard scrollView.zoomScale <= scrollView.minimumZoomScale else { return }

        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .began:
            panStartCenter = imageView.center
        case .changed:
            let progress = abs(translation.y) / (view.bounds.height / 2)
            let alpha = max(0.3, 1 - progress)
            backgroundView.alpha = alpha
            imageView.center = CGPoint(x: panStartCenter.x, y: panStartCenter.y + translation.y)
        case .ended, .cancelled:
            let shouldDismiss = abs(translation.y) > 100 || abs(velocity.y) > 800
            if shouldDismiss {
                UIView.animate(withDuration: 0.25, animations: {
                    self.backgroundView.alpha = 0
                    self.imageView.alpha = 0
                    let targetY = translation.y > 0 ? self.view.bounds.height : -self.view.bounds.height
                    self.imageView.center = CGPoint(x: self.panStartCenter.x, y: targetY)
                }) { _ in
                    self.dismiss(animated: false)
                }
            } else {
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
                    self.backgroundView.alpha = 1
                    self.imageView.center = self.panStartCenter
                }
            }
        default: break
        }
    }
}

extension ImageDetailViewController: UIScrollViewDelegate {

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageInScrollView()
    }
}

extension ImageDetailViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return scrollView.zoomScale <= scrollView.minimumZoomScale
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = pan.velocity(in: view)
            return abs(velocity.y) > abs(velocity.x) && scrollView.zoomScale <= scrollView.minimumZoomScale
        }
        return true
    }
}
