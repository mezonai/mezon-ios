import UIKit

final class TransferSuccessViewController: UIViewController {

    private let context: AccountContext
    private let amountDisplay: String
    private let receiver: String
    private let note: String
    private let dateText: String
    private let onDone: () -> Void
    private let onSendNew: () -> Void

    init(
        context: AccountContext,
        amountDisplay: String,
        receiver: String,
        note: String,
        dateText: String,
        onDone: @escaping () -> Void,
        onSendNew: @escaping () -> Void
    ) {
        self.context = context
        self.amountDisplay = amountDisplay
        self.receiver = receiver
        self.note = note
        self.dateText = dateText
        self.onDone = onDone
        self.onSendNew = onSendNew
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .mezonPrimary
        setupUI()
    }

    private func setupUI() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .onDrag
        scroll.canCancelContentTouches = false
        scroll.delaysContentTouches = false

        let bottomBar = UIView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = .mezonPrimary

        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)

        let receipt = UIView()
        receipt.translatesAutoresizingMaskIntoConstraints = false
        receipt.backgroundColor = .clear

        let checkSize: CGFloat = 58
        let checkBg = UIView()
        checkBg.translatesAutoresizingMaskIntoConstraints = false
        checkBg.backgroundColor = UIColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 1)
        checkBg.layer.cornerRadius = checkSize / 2

        let checkIcon = UIImageView(
            image: UIImage.mezonSystemImage("checkmark", withConfiguration: MezonSymbolConfiguration(pointSize: 22, weight: .bold))
        )
        checkIcon.translatesAutoresizingMaskIntoConstraints = false
        checkIcon.tintColor = .white
        checkIcon.contentMode = .scaleAspectFit
        checkBg.addSubview(checkIcon)

        let successLabel = UILabel()
        successLabel.translatesAutoresizingMaskIntoConstraints = false
        successLabel.font = .systemFont(ofSize: 22, weight: .bold)
        successLabel.textColor = .mezonTextStrong
        successLabel.text = L(L10n.Profile.sendTokenSuccessTitle)
        successLabel.numberOfLines = 0

        let amountLabel = UILabel()
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.font = .systemFont(ofSize: 26, weight: .bold)
        amountLabel.textColor = .mezonTextStrong
        amountLabel.text = "\(amountDisplay) \(MmnMoneyFormat.currencySymbol)"

        let receiverRow = makeInfoRow(title: L(L10n.Profile.sendTokenReceiver), value: receiver, valueFont: .systemFont(ofSize: 17, weight: .bold))
        let noteRow = makeInfoRow(title: L(L10n.Profile.sendTokenNote), value: note, valueFont: .systemFont(ofSize: 14, weight: .medium))
        let dateRow = makeInfoRow(title: L(L10n.Profile.sendTokenDate), value: dateText, valueFont: .systemFont(ofSize: 15, weight: .bold))

        let infoStack = UIStackView(arrangedSubviews: [receiverRow, noteRow, dateRow])
        infoStack.axis = .vertical
        infoStack.spacing = 16
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        receipt.addSubview(checkBg)
        receipt.addSubview(successLabel)
        receipt.addSubview(amountLabel)
        receipt.addSubview(infoStack)

        let actionsRow = UIStackView()
        actionsRow.translatesAutoresizingMaskIntoConstraints = false
        actionsRow.axis = .horizontal
        actionsRow.spacing = 24
        actionsRow.distribution = .fillEqually
        actionsRow.alignment = .center

        let shareWrap = makeActionPill(
            symbolName: "square.and.arrow.up",
            title: L(L10n.Common.share),
            action: #selector(handleShare)
        )
        let newWrap = makeActionPill(
            symbolName: "arrow.left.arrow.right",
            title: L(L10n.Profile.sendTokenSendNew),
            action: #selector(handleSendNew)
        )
        actionsRow.addArrangedSubview(shareWrap)
        actionsRow.addArrangedSubview(newWrap)

        let doneButton = UIButton(type: .system)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle(L(L10n.Profile.sendTokenComplete), for: .normal)
        doneButton.setTitleColor(.mezonPrimary, for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        doneButton.backgroundColor = .mezonTextStrong
        doneButton.layer.cornerRadius = 25
        doneButton.addTarget(self, action: #selector(handleDone), for: .touchUpInside)

        view.addSubview(scroll)
        view.addSubview(bottomBar)
        bottomBar.addSubview(actionsRow)
        bottomBar.addSubview(doneButton)

        content.addSubview(receipt)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: safe.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            actionsRow.topAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.topAnchor, constant: 8),
            actionsRow.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 24),
            actionsRow.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -24),

            doneButton.topAnchor.constraint(equalTo: actionsRow.bottomAnchor, constant: 12),
            doneButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            doneButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            doneButton.bottomAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            doneButton.heightAnchor.constraint(equalToConstant: 50),

            shareWrap.heightAnchor.constraint(equalToConstant: 56),
            newWrap.heightAnchor.constraint(equalToConstant: 56),

            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),

            receipt.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            receipt.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            receipt.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),
            receipt.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),

            checkBg.topAnchor.constraint(equalTo: receipt.topAnchor),
            checkBg.leadingAnchor.constraint(equalTo: receipt.leadingAnchor),
            checkBg.widthAnchor.constraint(equalToConstant: checkSize),
            checkBg.heightAnchor.constraint(equalToConstant: checkSize),

            checkIcon.centerXAnchor.constraint(equalTo: checkBg.centerXAnchor),
            checkIcon.centerYAnchor.constraint(equalTo: checkBg.centerYAnchor),
            checkIcon.widthAnchor.constraint(equalToConstant: 22),
            checkIcon.heightAnchor.constraint(equalToConstant: 18),

            successLabel.topAnchor.constraint(equalTo: checkBg.bottomAnchor, constant: 16),
            successLabel.leadingAnchor.constraint(equalTo: receipt.leadingAnchor),
            successLabel.trailingAnchor.constraint(equalTo: receipt.trailingAnchor),

            amountLabel.topAnchor.constraint(equalTo: successLabel.bottomAnchor, constant: 4),
            amountLabel.leadingAnchor.constraint(equalTo: receipt.leadingAnchor),
            amountLabel.trailingAnchor.constraint(equalTo: receipt.trailingAnchor),

            infoStack.topAnchor.constraint(equalTo: amountLabel.bottomAnchor, constant: 24),
            infoStack.leadingAnchor.constraint(equalTo: receipt.leadingAnchor),
            infoStack.trailingAnchor.constraint(equalTo: receipt.trailingAnchor),
            infoStack.bottomAnchor.constraint(equalTo: receipt.bottomAnchor),
        ])
        view.bringSubviewToFront(bottomBar)
    }

    private func makeActionPill(symbolName: String, title: String, action: Selector) -> UIView {
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let tint = UIColor.mezonTextPrimary
        let cfg = MezonSymbolConfiguration(pointSize: 16, weight: .medium)
        let iv = UIImageView(image: UIImage.mezonSystemImage(symbolName, withConfiguration: cfg))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.tintColor = tint
        iv.contentMode = .scaleAspectFit
        let lab = UILabel()
        lab.translatesAutoresizingMaskIntoConstraints = false
        lab.text = title
        lab.font = .systemFont(ofSize: 14, weight: .medium)
        lab.textColor = tint
        lab.textAlignment = .center
        lab.numberOfLines = 0
        let v = UIStackView(arrangedSubviews: [iv, lab])
        v.axis = .vertical
        v.spacing = 8
        v.alignment = .center
        v.isUserInteractionEnabled = false
        v.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(v)
        let tap = UITapGestureRecognizer(target: self, action: action)
        wrap.addGestureRecognizer(tap)
        NSLayoutConstraint.activate([
            iv.widthAnchor.constraint(equalToConstant: 22),
            iv.heightAnchor.constraint(equalToConstant: 18),
            v.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            v.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            v.leadingAnchor.constraint(greaterThanOrEqualTo: wrap.leadingAnchor),
            v.trailingAnchor.constraint(lessThanOrEqualTo: wrap.trailingAnchor),
        ])
        return wrap
    }

    private func makeInfoRow(title: String, value: String, valueFont: UIFont) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .mezonTextMuted

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = valueFont
        valueLabel.textColor = .mezonTextStrong
        valueLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func fullScreenSnapshotImage() -> UIImage? {
        view.layoutIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { _ in
            view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    @objc private func handleShare() {
        guard let image = fullScreenSnapshotImage(),
              let data = image.jpegData(compressionQuality: 0.92) else { return }
        let name = "transfer-success-\(UUID().uuidString).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            let file = SharingManager.SharedMediaFile(
                path: url.path,
                thumbnail: nil,
                duration: nil,
                type: .image,
                width: nil,
                height: nil
            )
            if #available(iOS 13.0, *) {
                let sharingVC = SharingViewController(context: context, sharedContent: .media([file]))
                sharingVC.modalPresentationStyle = .pageSheet
                present(sharingVC, animated: true)
            }
        } catch {}
    }

    @objc private func handleDone() {
        dismiss(animated: true) { self.onDone() }
    }

    @objc private func handleSendNew() {
        dismiss(animated: true) { self.onSendNew() }
    }
}
