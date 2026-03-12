import UIKit

extension UITextField {

    func textSignal() -> Signal<String, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            let observer = NotificationCenter.default.addObserver(
                forName: UITextField.textDidChangeNotification,
                object: self,
                queue: .main
            ) { _ in
                subscriber.putNext(self.text ?? "")
            }
            subscriber.putNext(self.text ?? "")
            return ActionDisposable {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
