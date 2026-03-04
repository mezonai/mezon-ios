#if DEBUG
import SwiftUI

struct UIViewPreview: UIViewRepresentable {
    let builder: () -> UIView

    init(_ builder: @escaping () -> UIView) {
        self.builder = builder
    }

    func makeUIView(context: Context) -> UIView {
        builder()
    }

    func updateUIView(_ view: UIView, context: Context) {
        view.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
    }
}
#endif
