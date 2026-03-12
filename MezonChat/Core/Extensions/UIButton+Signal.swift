import UIKit

private final class ButtonTapTarget: NSObject {
    let onTap: () -> Void

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    @objc func handleTap() {
        onTap()
    }
}

extension UIButton {

    func tapSignal() -> Signal<Void, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            let target = ButtonTapTarget { subscriber.putNext(()) }
            objc_setAssociatedObject(self, &targetKey, target, .OBJC_ASSOCIATION_RETAIN)
            self.addTarget(target, action: #selector(ButtonTapTarget.handleTap), for: .touchUpInside)
            return ActionDisposable { [weak self] in
                self?.removeTarget(target, action: #selector(ButtonTapTarget.handleTap), for: .touchUpInside)
                objc_setAssociatedObject(self, &targetKey, nil, .OBJC_ASSOCIATION_RETAIN)
            }
        }
    }
}

private var targetKey: UInt8 = 0
