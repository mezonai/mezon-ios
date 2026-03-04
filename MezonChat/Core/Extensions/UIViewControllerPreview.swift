#if DEBUG
import SwiftUI

struct UIViewControllerPreview: UIViewControllerRepresentable {
    let builder: () -> UIViewController

    init(_ builder: @escaping () -> UIViewController) {
        self.builder = builder
    }

    func makeUIViewController(context: Context) -> UIViewController {
        builder()
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {}
}
#endif
