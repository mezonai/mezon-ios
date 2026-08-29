import UIKit

final class RoleColorPickerSheetController: UIViewController {

    private let initialColor: String?
    private let onPick: (String) -> Void
    private var selectedHex: String

    private let titleLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let gridStack = UIStackView()
    private let resetButton = UIButton(type: .system)

    init(initialColor: String?, onPick: @escaping (String) -> Void) {
        self.initialColor = initialColor
        self.selectedHex = initialColor ?? ""
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let sheet = sheetPresentationController {
                sheet.detents = [.medium()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 16
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .mezonSecondary
        setupHeader()
        setupGrid()
        setupReset()
        refreshSaveState()
    }

    private func setupHeader() {
        titleLabel.text = L(L10n.ClanRoles.colorPickerTitle)
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        titleLabel.textColor = .mezonTextPrimary
        titleLabel.textAlignment = .center

        cancelButton.setTitle(L(L10n.Common.cancel), for: .normal)
        cancelButton.setTitleColor(UIColor.theme.textDisabled, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .regular)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        saveButton.setTitle(L(L10n.ClanRoles.save), for: .normal)
        saveButton.setTitleColor(UIColor.theme.bgViolet, for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        [titleLabel, cancelButton, saveButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16.sh),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            cancelButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            saveButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor)
        ])
    }

    private func setupGrid() {
        gridStack.axis = .vertical
        gridStack.spacing = 12.sh
        gridStack.alignment = .center
        gridStack.distribution = .fill
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gridStack)

        let colors = RoleColors.palette
        let columns = 5
        var index = 0
        while index < colors.count {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 14.sw
            rowStack.alignment = .center
            for _ in 0..<columns {
                if index < colors.count {
                    rowStack.addArrangedSubview(makeSwatch(hex: colors[index]))
                    index += 1
                }
            }
            gridStack.addArrangedSubview(rowStack)
        }

        NSLayoutConstraint.activate([
            gridStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24.sh),
            gridStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            gridStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw)
        ])
    }

    private func setupReset() {
        resetButton.setTitle(L(L10n.ClanRoles.colorReset), for: .normal)
        resetButton.setTitleColor(.mezonTextPrimary, for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .medium)
        resetButton.backgroundColor = UIColor.theme.tertiary
        resetButton.layer.cornerRadius = 12.swh
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        view.addSubview(resetButton)

        NSLayoutConstraint.activate([
            resetButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            resetButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            resetButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16.sh),
            resetButton.heightAnchor.constraint(equalToConstant: 44.sh)
        ])
    }

    private func swatchCheckmarkImage() -> UIImage? {
        UIImage.mezonSystemImage("checkmark")?
            .mezonWithConfiguration(MezonSymbolConfiguration(pointSize: 14.sf, weight: .bold))?
            .withRenderingMode(.alwaysTemplate)
    }

    private func isSwatchSelected(hex: String) -> Bool {
        !selectedHex.isEmpty && selectedHex.caseInsensitiveCompare(hex) == .orderedSame
    }

    private func applySwatchSelection(_ button: UIButton, hex: String) {
        let sel = isSwatchSelected(hex: hex)
        button.setImage(sel ? swatchCheckmarkImage() : nil, for: .normal)
        button.tintColor = .white
        button.layer.borderWidth = sel ? 2 : 0
        button.layer.borderColor = UIColor.white.cgColor
    }

    private func makeSwatch(hex: String) -> UIView {
        let size: CGFloat = 36.swh
        let swatch = UIButton(type: .custom)
        swatch.backgroundColor = UIColor(hexString: hex)
        swatch.layer.cornerRadius = size / 2
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.widthAnchor.constraint(equalToConstant: size).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: size).isActive = true
        swatch.accessibilityLabel = hex
        applySwatchSelection(swatch, hex: hex)
        swatch.addTarget(self, action: #selector(swatchTapped(_:)), for: .touchUpInside)
        return swatch
    }

    @objc private func swatchTapped(_ sender: UIButton) {
        guard let hex = sender.accessibilityLabel else { return }
        selectedHex = hex
        refreshGrid()
        refreshSaveState()
    }

    private func refreshGrid() {
        for rowView in gridStack.arrangedSubviews {
            guard let row = rowView as? UIStackView else { continue }
            for case let button as UIButton in row.arrangedSubviews {
                if let hex = button.accessibilityLabel {
                    applySwatchSelection(button, hex: hex)
                }
            }
        }
    }

    private func refreshSaveState() {
        let changed = selectedHex.caseInsensitiveCompare(initialColor ?? "") != .orderedSame
        saveButton.isEnabled = changed
        saveButton.alpha = changed ? 1.0 : 0.4
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        let value = selectedHex
        dismiss(animated: true) { [onPick] in
            onPick(value)
        }
    }

    @objc private func resetTapped() {
        selectedHex = ""
        refreshGrid()
        refreshSaveState()
    }
}
