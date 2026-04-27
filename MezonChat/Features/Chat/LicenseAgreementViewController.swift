import UIKit

enum LicenseAgreementPolicyStore {
    private static let storageKey = "STORAGE_AGREED_POLICY"

    static var hasAgreed: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }

    static func setAgreed() {
        UserDefaults.standard.set(true, forKey: storageKey)
    }
}

final class LicenseAgreementViewController: UIViewController, UITextViewDelegate {

    private let dimView = UIView()
    private let sheetContainer = UIView()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let agreeButton = UIButton(type: .system)
    private var sheetMaxWidthConstraint: NSLayoutConstraint?

    private static let accent = UIColor(red: 90 / 255, green: 98 / 255, blue: 244 / 255, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        dimView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimView)

        sheetContainer.backgroundColor = .white
        sheetContainer.layer.cornerRadius = 10
        sheetContainer.clipsToBounds = true
        sheetContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sheetContainer)

        let titleLabel = UILabel()
        titleLabel.text = "License Agreement"
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .black
        titleLabel.textAlignment = .center

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        addSection(
            title: "1. License Grant and Restrictions",
            body: "Subject to your compliance with this Agreement, Mezon grants you a limited, non-exclusive, non-transferable license to use the Mezon application. You may not:"
        )
        addBullet("- Reverse engineer, decompile, or disassemble the app.")
        addBullet("- Modify or create derivative works based on the app.")
        addBullet("- Rent, lease, lend, sell, redistribute, or sublicense the app.")

        addSection(
            title: "2. Termination",
            body: "This license is effective until terminated by you or Mezon. Your rights under this license will terminate automatically without notice if you fail to comply with any terms of this Agreement. Upon termination, you shall cease all use of the app and destroy all copies, full or partial, of the app."
        )

        addSection(
            title: "3. No Tolerance for Objectionable Content or Abusive Users",
            body: "Mezon has a zero-tolerance policy for objectionable content or abusive users. Any user found to be engaging in such behavior will be banned from using the app and may be reported to the appropriate authorities."
        )

        addSection(
            title: "4. No Warranty",
            body: "You expressly acknowledge and agree that use of the app is at your sole risk and that the entire risk as to satisfactory quality, performance, accuracy, and effort is with you. To the maximum extent permitted by applicable law, the app is provided \"as is\" and \"as available,\" with all faults and without warranty of any kind."
        )

        addSection(
            title: "5. Governing Law",
            body: "This Agreement shall be governed by and construed in accordance with the laws of [Your Country], excluding its conflicts of law rules."
        )

        addSection(
            title: "6. Contact Information",
            body: nil
        )

        let contactTextView = UITextView()
        contactTextView.isEditable = false
        contactTextView.isScrollEnabled = false
        contactTextView.backgroundColor = .clear
        contactTextView.textContainerInset = .zero
        contactTextView.textContainer.lineFragmentPadding = 0
        contactTextView.delegate = self
        contactTextView.linkTextAttributes = [.foregroundColor: Self.accent]
        let contactFull = "If you have any questions about this Agreement, please contact us at https://mezon.ai"
        let attributed = NSMutableAttributedString(string: contactFull, attributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ])
        if let range = contactFull.range(of: "https://mezon.ai"), let url = URL(string: "https://mezon.ai") {
            let nsRange = NSRange(range, in: contactFull)
            attributed.addAttribute(.link, value: url, range: nsRange)
            attributed.addAttribute(.foregroundColor, value: Self.accent, range: nsRange)
        }
        contactTextView.attributedText = attributed
        contentStack.addArrangedSubview(contactTextView)

        agreeButton.setTitle("Yes, Agree", for: .normal)
        agreeButton.setTitleColor(.white, for: .normal)
        agreeButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        agreeButton.backgroundColor = Self.accent
        agreeButton.layer.cornerRadius = 22
        agreeButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 24, bottom: 10, right: 24)
        agreeButton.addTarget(self, action: #selector(agreeTapped), for: .touchUpInside)
        agreeButton.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = UIStackView(arrangedSubviews: [titleLabel])
        headerStack.axis = .vertical
        headerStack.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        headerStack.isLayoutMarginsRelativeArrangement = true

        let innerStack = UIStackView(arrangedSubviews: [headerStack, scrollView, agreeButton])
        innerStack.axis = .vertical
        innerStack.spacing = 10
        innerStack.alignment = .fill
        innerStack.layoutMargins = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        innerStack.isLayoutMarginsRelativeArrangement = true
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(innerStack)

        let sheetWidth = sheetContainer.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: sheetWidthMultiplier())
        sheetWidth.isActive = true
        sheetMaxWidthConstraint = sheetWidth

        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sheetContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            sheetContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            sheetContainer.heightAnchor.constraint(greaterThanOrEqualTo: view.heightAnchor, multiplier: 0.62),
            sheetContainer.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.88),

            innerStack.topAnchor.constraint(equalTo: sheetContainer.topAnchor, constant: 10),
            innerStack.leadingAnchor.constraint(equalTo: sheetContainer.leadingAnchor),
            innerStack.trailingAnchor.constraint(equalTo: sheetContainer.trailingAnchor),
            innerStack.bottomAnchor.constraint(equalTo: sheetContainer.bottomAnchor, constant: -18),

            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            agreeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    private func sheetWidthMultiplier() -> CGFloat {
        traitCollection.horizontalSizeClass == .regular ? 0.40 : 0.85
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass else { return }
        sheetMaxWidthConstraint?.isActive = false
        let next = sheetContainer.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: sheetWidthMultiplier())
        next.isActive = true
        sheetMaxWidthConstraint = next
    }

    private func addSection(title: String, body: String?) {
        let t = UILabel()
        t.text = title
        t.font = .boldSystemFont(ofSize: 12)
        t.textColor = .black
        t.numberOfLines = 0
        contentStack.addArrangedSubview(t)
        contentStack.setCustomSpacing(12, after: t)
        if let body = body, !body.isEmpty {
            let b = UILabel()
            b.text = body
            b.font = .systemFont(ofSize: 12)
            b.textColor = .black
            b.numberOfLines = 0
            contentStack.addArrangedSubview(b)
            contentStack.setCustomSpacing(12, after: b)
        }
    }

    private func addBullet(_ text: String) {
        let l = UILabel()
        l.text = "    \(text)"
        l.font = .systemFont(ofSize: 12)
        l.textColor = .black
        l.numberOfLines = 0
        contentStack.addArrangedSubview(l)
        contentStack.setCustomSpacing(12, after: l)
    }

    @objc private func agreeTapped() {
        LicenseAgreementPolicyStore.setAgreed()
        dismiss(animated: true)
    }

    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        UIApplication.shared.open(URL)
        return false
    }
}
