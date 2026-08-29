import Foundation
import UIKit

final class TextFieldComponent: Component {
    let placeholder: String
    let text: String
    let font: UIFont
    let textColor: UIColor
    let placeholderColor: UIColor
    let backgroundColor: UIColor
    let borderColor: UIColor
    let cornerRadius: CGFloat
    let keyboardType: UIKeyboardType
    let isSecureTextEntry: Bool
    let leftIcon: String?
    let height: CGFloat
    let onTextChanged: (String) -> Void

    init(
        placeholder: String,
        text: String = "",
        font: UIFont = .systemFont(ofSize: 16),
        textColor: UIColor = .mezonTextStrong,
        placeholderColor: UIColor = .loginPlaceholder,
        backgroundColor: UIColor = .loginInputBg,
        borderColor: UIColor = .loginInputBorder,
        cornerRadius: CGFloat = 12,
        keyboardType: UIKeyboardType = .default,
        isSecureTextEntry: Bool = false,
        leftIcon: String? = nil,
        height: CGFloat = 50,
        onTextChanged: @escaping (String) -> Void
    ) {
        self.placeholder = placeholder
        self.text = text
        self.font = font
        self.textColor = textColor
        self.placeholderColor = placeholderColor
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.cornerRadius = cornerRadius
        self.keyboardType = keyboardType
        self.isSecureTextEntry = isSecureTextEntry
        self.leftIcon = leftIcon
        self.height = height
        self.onTextChanged = onTextChanged
    }

    static func == (lhs: TextFieldComponent, rhs: TextFieldComponent) -> Bool {
        return lhs.placeholder == rhs.placeholder && lhs.text == rhs.text && lhs.keyboardType == rhs.keyboardType && lhs.isSecureTextEntry == rhs.isSecureTextEntry && lhs.leftIcon == rhs.leftIcon && lhs.height == rhs.height
    }

    final class View: UIView, UITextFieldDelegate {
        private let container = UIView()
        private let textField = UITextField()
        private var onTextChanged: ((String) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            container.layer.borderWidth = 1
            addSubview(container)

            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.borderStyle = .none
            textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
            container.addSubview(textField)
        }

        required init?(coder: NSCoder) { fatalError() }

        func update(component: TextFieldComponent, availableSize: CGSize) -> CGSize {
            let size = CGSize(width: availableSize.width, height: component.height)
            container.frame = CGRect(origin: .zero, size: size)
            container.backgroundColor = component.backgroundColor
            container.layer.borderColor = component.borderColor.cgColor
            container.layer.cornerRadius = component.cornerRadius

            textField.font = component.font
            textField.textColor = component.textColor
            textField.keyboardType = component.keyboardType
            textField.isSecureTextEntry = component.isSecureTextEntry
            textField.attributedPlaceholder = NSAttributedString(string: component.placeholder, attributes: [.foregroundColor: component.placeholderColor])

            if textField.text != component.text { textField.text = component.text }

            var leftOffset: CGFloat = 16
            if let iconName = component.leftIcon {
                let iv = UIImageView(image: UIImage.mezonSystemImage(iconName))
                iv.tintColor = component.placeholderColor
                iv.contentMode = .scaleAspectFit
                iv.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
                let wrapper = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: component.height))
                wrapper.addSubview(iv)
                iv.center = CGPoint(x: 24, y: component.height / 2)
                textField.leftView = wrapper
                textField.leftViewMode = .always
                leftOffset = 0
            }

            textField.frame = CGRect(x: leftOffset, y: 0, width: size.width - leftOffset - 16, height: size.height)
            onTextChanged = component.onTextChanged
            return size
        }

        @objc private func textChanged() {
            onTextChanged?(textField.text ?? "")
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }

    func makeView() -> View { View(frame: .zero) }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        view.update(component: self, availableSize: availableSize)
    }
}
