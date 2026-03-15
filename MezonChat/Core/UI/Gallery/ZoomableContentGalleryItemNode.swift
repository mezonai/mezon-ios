import Foundation
import UIKit
import AsyncDisplayKit

open class ZoomableContentGalleryItemNode: GalleryItemNode, ASScrollViewDelegate {

    public let scrollNode: ASScrollNode

    private var ignoreZoom = false
    private var currentSize: CGSize = .zero

    public var zoomableContent: (CGSize, ASDisplayNode)? {
        didSet {
            if oldValue?.1 !== self.zoomableContent?.1 {
                oldValue?.1.view.removeFromSuperview()
                if let node = self.zoomableContent?.1 {
                    self.scrollNode.addSubnode(node)
                }
            }
            self.resetScrollViewContents()
            self.centerScrollViewContents()
        }
    }

    override public init() {
        self.scrollNode = ASScrollNode()
        if #available(iOS 11.0, *) {
            self.scrollNode.view.contentInsetAdjustmentBehavior = .never
        }

        super.init()

        self.scrollNode.view.delegate = self.wrappedScrollViewDelegate
        self.scrollNode.view.showsVerticalScrollIndicator = false
        self.scrollNode.view.showsHorizontalScrollIndicator = false
        self.scrollNode.view.clipsToBounds = false
        self.scrollNode.view.scrollsToTop = false
        self.scrollNode.view.delaysContentTouches = false

        // Double-tap zoom + single-tap toggle
        let tapRecognizer = TapLongTapOrDoubleTapGestureRecognizer(target: self, action: #selector(self.contentTap(_:)))
        tapRecognizer.tapActionAtPoint = { _ in .waitForDoubleTap }
        self.scrollNode.view.addGestureRecognizer(tapRecognizer)

        self.addSubnode(self.scrollNode)
    }

    @objc open func contentTap(_ recognizer: TapLongTapOrDoubleTapGestureRecognizer) {
        if recognizer.state == .ended {
            if let (gesture, location) = recognizer.lastRecognizedGestureAndLocation {
                switch gesture {
                case .tap:
                    self.toggleControlsVisibility()
                case .doubleTap:
                    if let contentView = self.zoomableContent?.1.view,
                       self.scrollNode.view.zoomScale.isLessThanOrEqualTo(self.scrollNode.view.minimumZoomScale) {
                        let pointInView = self.scrollNode.view.convert(location, to: contentView)
                        let newZoomScale = self.scrollNode.view.maximumZoomScale
                        let scrollViewSize = self.scrollNode.view.bounds.size
                        let w = scrollViewSize.width / newZoomScale
                        let h = scrollViewSize.height / newZoomScale
                        let rectToZoomTo = CGRect(x: pointInView.x - w / 2, y: pointInView.y - h / 2, width: w, height: h)
                        self.scrollNode.view.zoom(to: rectToZoomTo, animated: true)
                    } else {
                        self.scrollNode.view.setZoomScale(self.scrollNode.view.minimumZoomScale, animated: true)
                    }
                default:
                    break
                }
            }
        }
    }

    override open func containerLayoutUpdated(_ size: CGSize, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(size, navigationBarHeight: navigationBarHeight, transition: transition)
        let shouldReset = currentSize != size
        currentSize = size
        if shouldReset {
            transition.updateFrame(node: self.scrollNode, frame: CGRect(origin: .zero, size: size))
            self.resetScrollViewContents()
        }
    }

    private func resetScrollViewContents() {
        guard let (contentSize, contentNode) = self.zoomableContent else { return }
        let boundsSize = self.scrollNode.view.bounds.size
        guard contentSize.width > 0, contentSize.height > 0, boundsSize.width > 0, boundsSize.height > 0 else { return }

        self.ignoreZoom = true
        self.scrollNode.view.minimumZoomScale = 1.0
        self.scrollNode.view.maximumZoomScale = 1.0
        self.scrollNode.view.zoomScale = 1.0

        self.scrollNode.view.contentSize = contentSize
        contentNode.transform = CATransform3DIdentity
        contentNode.frame = CGRect(origin: .zero, size: contentSize)

        self.centerScrollViewContents()
        self.ignoreZoom = false

        self.scrollNode.view.zoomScale = self.scrollNode.view.minimumZoomScale
    }

    private func centerScrollViewContents() {
        guard let (contentSize, contentNode) = self.zoomableContent else { return }
        let boundsSize = self.scrollNode.view.bounds.size
        guard contentSize.width > 0, contentSize.height > 0, boundsSize.width > 0, boundsSize.height > 0 else { return }

        let scaleWidth = boundsSize.width / contentSize.width
        let scaleHeight = boundsSize.height / contentSize.height
        let minScale = min(scaleWidth, scaleHeight)
        var maxScale = max(scaleWidth, scaleHeight)
        maxScale = max(maxScale, minScale * 3.0)
        if abs(maxScale - minScale) < 0.01 { maxScale = minScale }

        if !self.scrollNode.view.minimumZoomScale.isEqual(to: minScale) {
            self.scrollNode.view.minimumZoomScale = minScale
        }
        if !self.scrollNode.view.maximumZoomScale.isEqual(to: maxScale) {
            self.scrollNode.view.maximumZoomScale = maxScale
        }

        var contentFrame = contentNode.view.frame
        contentFrame.origin.x = boundsSize.width > contentFrame.width ? (boundsSize.width - contentFrame.width) / 2 : 0
        contentFrame.origin.y = boundsSize.height >= contentFrame.height ? (boundsSize.height - contentFrame.height) / 2 : 0

        if !self.ignoreZoom {
            contentNode.view.frame = contentFrame
        }
    }

    // MARK: - UIScrollViewDelegate

    open func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return self.zoomableContent?.1.view
    }

    open func scrollViewDidZoom(_ scrollView: UIScrollView) {
        if !self.ignoreZoom {
            self.centerScrollViewContents()
        }
        self.scrollNode.view.isScrollEnabled = !scrollView.zoomScale.isEqual(to: scrollView.minimumZoomScale)
    }
}
