import UIKit
import QuartzCore

@MainActor
final class ClaimLuckyMoneyViewController: BaseViewController {

    private let context: AccountContext
    private let luckyMoneyId: String

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stateStack = UIStackView()

    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let loadingTitleLabel = UILabel()
    private let loadingSubtitleLabel = UILabel()

    private let errorTitleLabel = UILabel()
    private let errorSubtitleLabel = UILabel()
    private let errorCloseButton = UIButton(type: .system)

    private let successCheck = UIImageView()
    private let successTitleLabel = UILabel()
    private let successAmountLabel = UILabel()
    private let noteRowTitle = UILabel()
    private let noteRowValue = UILabel()
    private let dateRowTitle = UILabel()
    private let dateRowValue = UILabel()
    private let claimButton = UIButton(type: .system)
    private let successDoneButton = UIButton(type: .system)
    private let claimSpinner = UIActivityIndicatorView(style: .medium)

    private var previewData: MmnRedEnvelopeClaimAmountData?
    private var isClaiming = false
    private var confettiLayer: CAEmitterLayer?

    init(context: AccountContext, luckyMoneyId: String) {
        self.context = context
        self.luckyMoneyId = luckyMoneyId
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        showState(.loading)
        Task { await loadPreview() }
    }

    override func applyTheme() {
        super.applyTheme()
        applyThemeColors()
    }

    private enum ScreenState {
        case loading
        case error(String)
        case preview(MmnRedEnvelopeClaimAmountData)
        case claimed(MmnRedEnvelopeClaimAmountData)
    }

    override func setupUI() {
        super.setupUI()
        view.backgroundColor = .mezonSecondary

        headerView.translatesAutoresizingMaskIntoConstraints = false
        backButton.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        stateStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerView)
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stateStack)

        headerView.addSubview(backButton)
        headerView.addSubview(titleLabel)

        let backImg = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        backButton.setImage(backImg, for: .normal)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        titleLabel.text = L(L10n.QRScanner.luckyMoneyTitle)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center

        stateStack.axis = .vertical
        stateStack.spacing = 20
        stateStack.alignment = .fill

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingTitleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        loadingTitleLabel.textAlignment = .center
        loadingTitleLabel.numberOfLines = 0
        loadingTitleLabel.text = L(L10n.QRScanner.processing)
        loadingSubtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        loadingSubtitleLabel.textColor = UIColor.theme.textDisabled
        loadingSubtitleLabel.textAlignment = .center
        loadingSubtitleLabel.numberOfLines = 0
        loadingSubtitleLabel.text = L(L10n.QRScanner.luckyMoneyPleaseWait)

        errorTitleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        errorTitleLabel.textAlignment = .center
        errorTitleLabel.numberOfLines = 0
        errorSubtitleLabel.font = .systemFont(ofSize: 16, weight: .regular)
        errorSubtitleLabel.textColor = UIColor.theme.textDisabled
        errorSubtitleLabel.textAlignment = .center
        errorSubtitleLabel.numberOfLines = 0
        errorCloseButton.layer.cornerRadius = 22
        errorCloseButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        errorCloseButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        errorCloseButton.setTitle(L(L10n.Common.close), for: .normal)
        errorCloseButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

        successCheck.translatesAutoresizingMaskIntoConstraints = false
        successCheck.image = UIImage(systemName: "checkmark.circle.fill")?.withRenderingMode(.alwaysTemplate)
        successCheck.tintColor = UIColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 1)
        successCheck.contentMode = .scaleAspectFit
        successTitleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        successTitleLabel.textAlignment = .center
        successTitleLabel.numberOfLines = 0
        successAmountLabel.font = .systemFont(ofSize: 32, weight: .bold)
        successAmountLabel.textAlignment = .center
        successAmountLabel.numberOfLines = 1

        [noteRowTitle, noteRowValue, dateRowTitle, dateRowValue].forEach {
            $0.numberOfLines = 0
        }
        noteRowTitle.font = .systemFont(ofSize: 13, weight: .medium)
        noteRowTitle.textColor = UIColor.theme.textDisabled
        noteRowValue.font = .systemFont(ofSize: 16, weight: .semibold)
        dateRowTitle.font = .systemFont(ofSize: 13, weight: .medium)
        dateRowTitle.textColor = UIColor.theme.textDisabled
        dateRowValue.font = .systemFont(ofSize: 16, weight: .semibold)

        let accent = UIColor(red: 94/255, green: 101/255, blue: 238/255, alpha: 1)
        claimButton.layer.cornerRadius = 22
        claimButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        claimButton.addTarget(self, action: #selector(claimTapped), for: .touchUpInside)
        claimButton.setTitle(L(L10n.QRScanner.luckyMoneyClaimToWallet), for: .normal)
        claimButton.backgroundColor = accent
        claimButton.setTitleColor(.white, for: .normal)

        successDoneButton.layer.cornerRadius = 22
        successDoneButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        successDoneButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        successDoneButton.setTitle(L(L10n.QRScanner.luckyMoneySuccessDone), for: .normal)
        successDoneButton.backgroundColor = accent
        successDoneButton.setTitleColor(.white, for: .normal)

        claimSpinner.hidesWhenStopped = true

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            stateStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            stateStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stateStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stateStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -28),

            successCheck.widthAnchor.constraint(equalToConstant: 88),
            successCheck.heightAnchor.constraint(equalToConstant: 88),
        ])
    }

    private func applyThemeColors() {
        backButton.tintColor = UIColor.theme.textStrong
        titleLabel.textColor = .mezonTextPrimary
        errorTitleLabel.textColor = .mezonTextPrimary
        errorSubtitleLabel.textColor = UIColor.theme.textDisabled
        successTitleLabel.textColor = .mezonTextPrimary
        successAmountLabel.textColor = .mezonTextPrimary
        noteRowValue.textColor = .mezonTextPrimary
        dateRowValue.textColor = .mezonTextPrimary
        loadingTitleLabel.textColor = .mezonTextPrimary
        errorCloseButton.backgroundColor = UIColor.theme.tertiary
        errorCloseButton.setTitleColor(.mezonTextPrimary, for: .normal)
    }

    private func showState(_ state: ScreenState) {
        stopConfetti()
        stateStack.arrangedSubviews.forEach {
            stateStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        switch state {
        case .loading:
            loadingIndicator.startAnimating()
            let v = UIStackView(arrangedSubviews: [loadingIndicator, loadingTitleLabel, loadingSubtitleLabel])
            v.axis = .vertical
            v.spacing = 20
            v.alignment = .center
            stateStack.addArrangedSubview(v)

        case .error(let msg):
            loadingIndicator.stopAnimating()
            errorTitleLabel.text = L(L10n.QRScanner.luckyMoneyClaimFailed)
            errorSubtitleLabel.text = msg
            let icon = UIImageView(image: UIImage(systemName: "xmark.circle.fill"))
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.tintColor = UIColor(red: 239/255, green: 68/255, blue: 68/255, alpha: 1)
            icon.contentMode = .scaleAspectFit
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 88),
                icon.heightAnchor.constraint(equalToConstant: 88),
            ])
            let card = makeCardStack(arrangedSubviews: [icon, errorTitleLabel, errorSubtitleLabel, errorCloseButton], spacing: 18)
            stateStack.addArrangedSubview(card)
            icon.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            icon.alpha = 0
            errorTitleLabel.alpha = 0
            errorSubtitleLabel.alpha = 0
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.4) {
                icon.transform = .identity
                icon.alpha = 1
            }
            UIView.animate(withDuration: 0.3, delay: 0.08, options: [.curveEaseOut]) {
                self.errorTitleLabel.alpha = 1
                self.errorSubtitleLabel.alpha = 1
            }

        case .preview(let data):
            loadingIndicator.stopAnimating()
            previewData = data
            successTitleLabel.text = L(L10n.QRScanner.luckyMoneyCongratulations)
            successCheck.alpha = 1
            successCheck.transform = .identity
            applyRewardDetails(from: data)
            let infoStack = rewardMetaStack()
            let btnWrap = buttonContainer(primary: claimButton, spinner: claimSpinner, height: 50)
            let inner = UIStackView(arrangedSubviews: [successCheck, successTitleLabel, successAmountLabel, infoStack, btnWrap])
            inner.axis = .vertical
            inner.spacing = 22
            inner.alignment = .fill
            inner.setCustomSpacing(12, after: successCheck)
            let card = makeCardStack(arrangedSubviews: [inner], spacing: 0)
            stateStack.addArrangedSubview(card)

        case .claimed(let data):
            loadingIndicator.stopAnimating()
            applyRewardDetails(from: data)
            successTitleLabel.text = L(L10n.QRScanner.luckyMoneyClaimSuccess)
            successCheck.alpha = 0
            successCheck.transform = CGAffineTransform(scaleX: 0.35, y: 0.35)
            successTitleLabel.alpha = 0
            successAmountLabel.alpha = 0
            let infoStack = rewardMetaStack()
            noteRowTitle.alpha = 0
            noteRowValue.alpha = 0
            dateRowTitle.alpha = 0
            dateRowValue.alpha = 0
            let btnWrap = buttonContainer(primary: successDoneButton, spinner: nil, height: 50)
            successDoneButton.alpha = 0
            let inner = UIStackView(arrangedSubviews: [successCheck, successTitleLabel, successAmountLabel, infoStack, btnWrap])
            inner.axis = .vertical
            inner.spacing = 22
            inner.alignment = .fill
            inner.setCustomSpacing(12, after: successCheck)
            let card = makeCardStack(arrangedSubviews: [inner], spacing: 0)
            stateStack.addArrangedSubview(card)
            DispatchQueue.main.async {
                self.view.layoutIfNeeded()
                self.startConfetti(over: card)
            }
            UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.68, initialSpringVelocity: 0.55, options: [.curveEaseOut]) {
                self.successCheck.transform = .identity
                self.successCheck.alpha = 1
            }
            UIView.animate(withDuration: 0.32, delay: 0.12, options: [.curveEaseOut]) {
                self.successTitleLabel.alpha = 1
                self.successAmountLabel.alpha = 1
                self.noteRowTitle.alpha = 1
                self.noteRowValue.alpha = 1
                self.dateRowTitle.alpha = 1
                self.dateRowValue.alpha = 1
                self.successDoneButton.alpha = 1
            }
        }
    }

    private func makeCardStack(arrangedSubviews: [UIView], spacing: CGFloat) -> UIView {
        let wrap = UIView()
        wrap.backgroundColor = UIColor.theme.tertiary
        wrap.layer.cornerRadius = 16
        wrap.layer.masksToBounds = true
        let s = UIStackView(arrangedSubviews: arrangedSubviews)
        s.axis = .vertical
        s.spacing = spacing
        s.alignment = .fill
        s.isLayoutMarginsRelativeArrangement = true
        s.layoutMargins = UIEdgeInsets(top: 24, left: 20, bottom: 24, right: 20)
        s.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(s)
        NSLayoutConstraint.activate([
            s.topAnchor.constraint(equalTo: wrap.topAnchor),
            s.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            s.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            s.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        return wrap
    }

    private func applyRewardDetails(from data: MmnRedEnvelopeClaimAmountData) {
        let amountDisp = MmnMoneyFormat.formatTokenAmount(String(data.amount)).display
        successAmountLabel.text = "+ \(amountDisp) \(MmnMoneyFormat.currencySymbol)"
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy"
        dateRowTitle.text = L(L10n.Profile.sendTokenDate)
        dateRowValue.text = df.string(from: Date())
        if let desc = data.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
            noteRowTitle.text = L(L10n.Profile.sendTokenNote)
            noteRowValue.text = desc
            noteRowTitle.isHidden = false
            noteRowValue.isHidden = false
        } else {
            noteRowTitle.isHidden = true
            noteRowValue.isHidden = true
        }
    }

    private func rewardMetaStack() -> UIStackView {
        let noteBlock = UIStackView(arrangedSubviews: [noteRowTitle, noteRowValue])
        noteBlock.axis = .vertical
        noteBlock.spacing = 6
        let dateBlock = UIStackView(arrangedSubviews: [dateRowTitle, dateRowValue])
        dateBlock.axis = .vertical
        dateBlock.spacing = 6
        let infoStack = UIStackView(arrangedSubviews: [noteBlock, dateBlock])
        infoStack.axis = .vertical
        infoStack.spacing = 18
        return infoStack
    }

    private func buttonContainer(primary: UIButton, spinner: UIActivityIndicatorView?, height: CGFloat) -> UIView {
        let btnWrap = UIView()
        primary.translatesAutoresizingMaskIntoConstraints = false
        btnWrap.addSubview(primary)
        var constraints: [NSLayoutConstraint] = [
            primary.leadingAnchor.constraint(equalTo: btnWrap.leadingAnchor),
            primary.trailingAnchor.constraint(equalTo: btnWrap.trailingAnchor),
            primary.topAnchor.constraint(equalTo: btnWrap.topAnchor),
            primary.heightAnchor.constraint(equalToConstant: height),
            primary.bottomAnchor.constraint(equalTo: btnWrap.bottomAnchor),
        ]
        if let spin = spinner {
            spin.translatesAutoresizingMaskIntoConstraints = false
            btnWrap.addSubview(spin)
            constraints.append(contentsOf: [
                spin.centerXAnchor.constraint(equalTo: primary.centerXAnchor),
                spin.centerYAnchor.constraint(equalTo: primary.centerYAnchor),
            ])
        }
        NSLayoutConstraint.activate(constraints)
        return btnWrap
    }

    private func startConfetti(over host: UIView) {
        stopConfetti()
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: host.bounds.midX, y: host.bounds.minY - 4)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: host.bounds.width + 80, height: 1)
        func cell(color: UIColor, lifetime: Float) -> CAEmitterCell {
            let c = CAEmitterCell()
            c.birthRate = 8
            c.lifetime = lifetime
            c.velocity = 140
            c.velocityRange = 60
            c.emissionLongitude = .pi
            c.emissionRange = .pi / 4
            c.spinRange = 4
            c.scale = 0.07
            c.scaleRange = 0.04
            c.contents = UIImage(systemName: "circle.fill")?.withTintColor(color, renderingMode: .alwaysOriginal).cgImage
            c.color = color.cgColor
            return c
        }
        emitter.emitterCells = [
            cell(color: UIColor(red: 0.98, green: 0.76, blue: 0.18, alpha: 1), lifetime: 3.2),
            cell(color: UIColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1), lifetime: 3),
            cell(color: UIColor(red: 0.37, green: 0.62, blue: 1, alpha: 1), lifetime: 2.8),
            cell(color: UIColor(red: 0.4, green: 0.85, blue: 0.55, alpha: 1), lifetime: 3),
        ]
        host.layer.addSublayer(emitter)
        confettiLayer = emitter
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            emitter.birthRate = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                emitter.removeFromSuperlayer()
                if self?.confettiLayer === emitter {
                    self?.confettiLayer = nil
                }
            }
        }
    }

    private func stopConfetti() {
        confettiLayer?.birthRate = 0
        confettiLayer?.removeFromSuperlayer()
        confettiLayer = nil
    }

    private func loadPreview() async {
        guard let uid = context.currentUser?.id, !uid.isEmpty else {
            showState(.error(L(L10n.QRScanner.luckyMoneyWalletNotReady)))
            return
        }
        do {
            let data = try await MmnRedEnvelopeClient.claimAmount(luckyMoneyId: luckyMoneyId, userId: uid)
            showState(.preview(data))
        } catch {
            showState(.error(error.localizedDescription))
        }
    }

    private func setClaimBusy(_ busy: Bool) {
        isClaiming = busy
        claimButton.isEnabled = !busy
        claimButton.alpha = busy ? 0.55 : 1
        if busy { claimSpinner.startAnimating() } else { claimSpinner.stopAnimating() }
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func claimTapped() {
        guard !isClaiming, let d = previewData, let uid = context.currentUser?.id, !uid.isEmpty else { return }
        setClaimBusy(true)
        Task {
            do {
                try await MmnRedEnvelopeClient.claimRedEnvelope(
                    luckyMoneyId: luckyMoneyId,
                    splitMoneyId: d.split_money_id,
                    userId: uid
                )
                await MainActor.run {
                    setClaimBusy(false)
                    showState(.claimed(d))
                }
            } catch {
                await MainActor.run {
                    setClaimBusy(false)
                    showState(.error(error.localizedDescription))
                }
            }
        }
    }
}
