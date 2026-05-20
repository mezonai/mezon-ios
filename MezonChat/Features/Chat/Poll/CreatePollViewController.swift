import UIKit

final class CreatePollAnswerTextField: UITextField {
    var onEmojiTapped: (() -> Void)?
    var onRemoveTapped: (() -> Void)?
    
    var emojiId: String? {
        didSet {
            if let id = emojiId, !id.isEmpty {
                emojiBtn.setImage(nil, for: .normal)
                emojiImageView.isHidden = false
                ReactionEmojiImageLoader.loadDataBestEffort(emojiId: id, imgproxyFitSide: 44) { [weak self] data in
                    self?.emojiImageView.setData(data, displayPixelMaxSide: 44)
                }
            } else {
                emojiImageView.isHidden = true
                emojiImageView.reset()
                emojiBtn.setImage(UIImage(systemName: "face.smiling"), for: .normal)
            }
        }
    }
    
    lazy var emojiBtn: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "face.smiling"), for: .normal)
        btn.tintColor = UIColor.theme.iconSecondary
        btn.addTarget(self, action: #selector(emojiBtnTapped), for: .touchUpInside)
        return btn
    }()
    
    lazy var emojiImageView: AnimatedEmojiImageView = {
        let iv = AnimatedEmojiImageView()
        iv.isHidden = true
        iv.isUserInteractionEnabled = false
        return iv
    }()
    
    lazy var removeBtn: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "trash"), for: .normal)
        btn.tintColor = UIColor.theme.iconSecondary
        btn.addTarget(self, action: #selector(removeBtnTapped), for: .touchUpInside)
        return btn
    }()
    
    var showRemoveButton: Bool = false {
        didSet {
            removeBtn.isHidden = !showRemoveButton
            setNeedsLayout()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        addSubview(emojiBtn)
        addSubview(emojiImageView)
        addSubview(removeBtn)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        emojiBtn.frame = CGRect(x: 4, y: (bounds.height - 44)/2, width: 44, height: 44)
        emojiImageView.frame = CGRect(x: 14, y: (bounds.height - 24)/2, width: 24, height: 24)
        removeBtn.frame = CGRect(x: bounds.width - 44, y: (bounds.height - 44)/2, width: 44, height: 44)
    }
    
    override func textRect(forBounds bounds: CGRect) -> CGRect {
        let leftPad: CGFloat = 48
        let rightPad: CGFloat = showRemoveButton ? 40 : 12
        return CGRect(x: leftPad, y: 0, width: bounds.width - leftPad - rightPad, height: bounds.height)
    }
    
    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        return textRect(forBounds: bounds)
    }
    
    @objc private func emojiBtnTapped() {
        onEmojiTapped?()
    }
    
    @objc private func removeBtnTapped() {
        onRemoveTapped?()
    }
}

final class CreatePollViewController: BaseViewController {

    private let channelId: Int64
    private let clanId: Int64

    private var answers: [String] = ["", ""]
    private var answerEmojiIds: [String?] = [nil, nil]
    private var durationHours: Int32 = 24
    private var allowMultiple: Bool = false

    private let maxAnswers = 20

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let context: AccountContext

    init(context: AccountContext, channelId: Int64, clanId: Int64) {
        self.context = context
        self.channelId = channelId
        self.clanId = clanId
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) { fatalError() }

    private lazy var questionLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = L(L10n.CreatePoll.questionLabel)
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        lbl.textColor = UIColor.theme.text
        return lbl
    }()

    private lazy var questionPlaceholderLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = L(L10n.CreatePoll.questionPlaceholder)
        lbl.font = .systemFont(ofSize: 15)
        lbl.textColor = UIColor.theme.textDisabled
        lbl.numberOfLines = 0
        return lbl
    }()
    private lazy var questionCharCountLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = "0/300"
        lbl.font = .systemFont(ofSize: 12)
        lbl.textColor = UIColor.theme.textDisabled
        return lbl
    }()


    private lazy var questionTextView: UITextView = {
        let tv = UITextView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.font = .systemFont(ofSize: 15)
        tv.textColor = .mezonTextPrimary
        tv.backgroundColor = .mezonSecondary
        tv.layer.cornerRadius = 10
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 7, bottom: 28, right: 7)
        tv.delegate = self
        tv.isScrollEnabled = false
        return tv
    }()

    private lazy var questionContainerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var answersLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = L(L10n.CreatePoll.answersLabel)
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        lbl.textColor = UIColor.theme.text
        return lbl
    }()

    private lazy var answersStackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .vertical
        sv.spacing = 8
        return sv
    }()

    private lazy var addAnswerButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle(L(L10n.CreatePoll.addAnswerButton), for: .normal)
        btn.setTitleColor(.mezonIconPrimary, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        btn.contentHorizontalAlignment = .left
        btn.addTarget(self, action: #selector(handleAddAnswer), for: .touchUpInside)
        return btn
    }()

    private lazy var durationLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = L(L10n.CreatePoll.durationLabel)
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        lbl.textColor = UIColor.theme.text
        return lbl
    }()

    private var durationValueLabel: UILabel?

    private lazy var durationContainerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .mezonSecondary
        v.layer.cornerRadius = 10
        v.clipsToBounds = true
        
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = L(L10n.CreatePoll.hours24)
        lbl.font = .systemFont(ofSize: 15)
        lbl.textColor = .mezonTextPrimary
        v.addSubview(lbl)
        self.durationValueLabel = lbl
        
        let arrow = UIImageView(image: UIImage(systemName: "chevron.down"))
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.tintColor = UIColor.theme.iconSecondary
        v.addSubview(arrow)
        
        v.addSubview(durationButton)
        
        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            lbl.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            
            arrow.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            arrow.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 16),
            arrow.heightAnchor.constraint(equalToConstant: 16),
            
            durationButton.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            durationButton.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            durationButton.topAnchor.constraint(equalTo: v.topAnchor),
            durationButton.bottomAnchor.constraint(equalTo: v.bottomAnchor)
        ])
        return v
    }()

    private lazy var durationButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.backgroundColor = .clear
        btn.addTarget(self, action: #selector(durationTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var multipleAnswersSwitch: UISwitch = {
        let sw = UISwitch()
        sw.translatesAutoresizingMaskIntoConstraints = false
        sw.onTintColor = .mezonLink
        sw.addTarget(self, action: #selector(handleMultipleSwitchChanged), for: .valueChanged)
        return sw
    }()

    private lazy var multipleAnswersLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = L(L10n.CreatePoll.multipleAnswersLabel)
        lbl.font = .systemFont(ofSize: 15)
        lbl.textColor = .mezonTextPrimary
        return lbl
    }()

    private lazy var postButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle(L(L10n.CreatePoll.postButton), for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor.theme.bgViolet
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        btn.layer.cornerRadius = 14
        btn.addTarget(self, action: #selector(handlePost), for: .touchUpInside)
        return btn
    }()

    private let bottomBar = UIView()
    private var bottomBarBottomConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        updateAnswersUI()
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardFrameWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func setupUI() {
        view.backgroundColor = .mezonPrimary
        headerView.backgroundColor = .mezonPrimary
        scrollView.backgroundColor = .mezonPrimary
        bottomBar.backgroundColor = .mezonPrimary
        
        view.addSubview(headerView)
        view.addSubview(scrollView)
        view.addSubview(bottomBar)
        scrollView.addSubview(contentStack)
        
        headerView.translatesAutoresizingMaskIntoConstraints = false
        backButton.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        postButton.translatesAutoresizingMaskIntoConstraints = false
        
        headerView.addSubview(backButton)
        headerView.addSubview(titleLabel)
        
        let backImg = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        backButton.setImage(backImg, for: .normal)
        backButton.tintColor = .mezonTextStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        
        titleLabel.text = L(L10n.CreatePoll.title)
        titleLabel.textColor = .mezonTextStrong
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .fill
        
        let multipleContainer = UIView()
        multipleContainer.translatesAutoresizingMaskIntoConstraints = false
        multipleContainer.addSubview(multipleAnswersLabel)
        multipleContainer.addSubview(multipleAnswersSwitch)
        multipleContainer.heightAnchor.constraint(equalToConstant: 44).isActive = true
        
        NSLayoutConstraint.activate([
            multipleAnswersLabel.leadingAnchor.constraint(equalTo: multipleContainer.leadingAnchor),
            multipleAnswersLabel.centerYAnchor.constraint(equalTo: multipleContainer.centerYAnchor),
            multipleAnswersSwitch.trailingAnchor.constraint(equalTo: multipleContainer.trailingAnchor),
            multipleAnswersSwitch.centerYAnchor.constraint(equalTo: multipleContainer.centerYAnchor)
        ])
        
        contentStack.addArrangedSubview(questionLabel)
        contentStack.setCustomSpacing(6, after: questionLabel)
        
        questionContainerView.addSubview(questionTextView)
        questionContainerView.addSubview(questionPlaceholderLabel)
        questionContainerView.addSubview(questionCharCountLabel)
        
        contentStack.addArrangedSubview(questionContainerView)
        
        NSLayoutConstraint.activate([
            questionTextView.topAnchor.constraint(equalTo: questionContainerView.topAnchor),
            questionTextView.leadingAnchor.constraint(equalTo: questionContainerView.leadingAnchor),
            questionTextView.trailingAnchor.constraint(equalTo: questionContainerView.trailingAnchor),
            questionTextView.bottomAnchor.constraint(equalTo: questionContainerView.bottomAnchor),
            
            questionPlaceholderLabel.topAnchor.constraint(equalTo: questionTextView.topAnchor, constant: 12),
            questionPlaceholderLabel.leadingAnchor.constraint(equalTo: questionTextView.leadingAnchor, constant: 12),
            questionPlaceholderLabel.trailingAnchor.constraint(equalTo: questionTextView.trailingAnchor, constant: -12),
            
            questionCharCountLabel.bottomAnchor.constraint(equalTo: questionContainerView.bottomAnchor, constant: -8),
            questionCharCountLabel.trailingAnchor.constraint(equalTo: questionContainerView.trailingAnchor, constant: -12)
        ])
        
        contentStack.addArrangedSubview(answersLabel)
        contentStack.setCustomSpacing(6, after: answersLabel)
        contentStack.addArrangedSubview(answersStackView)
        contentStack.setCustomSpacing(8, after: answersStackView)
        contentStack.addArrangedSubview(addAnswerButton)
        
        contentStack.addArrangedSubview(durationLabel)
        contentStack.setCustomSpacing(6, after: durationLabel)
        contentStack.addArrangedSubview(durationContainerView)
        
        contentStack.addArrangedSubview(multipleContainer)
        
        bottomBar.addSubview(postButton)
        
        let header: CGFloat = 56
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: header),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
            
            questionTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            addAnswerButton.heightAnchor.constraint(equalToConstant: 30),
            durationContainerView.heightAnchor.constraint(equalToConstant: 44),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            postButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            postButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            postButton.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),
            postButton.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -12),
            postButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        let bbBottom = bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        bbBottom.isActive = true
        bottomBarBottomConstraint = bbBottom
    }

    private func updateAnswersUI() {
        let answerHeight: CGFloat = 44
        
        while answersStackView.arrangedSubviews.count < answers.count {
            let tf = CreatePollAnswerTextField()
            tf.backgroundColor = .mezonSecondary
            tf.textColor = .mezonTextPrimary
            tf.font = .systemFont(ofSize: 15)
            tf.layer.cornerRadius = 10
            tf.delegate = self
            tf.addTarget(self, action: #selector(answerChanged(_:)), for: .editingChanged)
            tf.heightAnchor.constraint(equalToConstant: answerHeight).isActive = true
            tf.onRemoveTapped = { [weak self, weak tf] in
                guard let self = self, let tf = tf else { return }
                self.handleRemoveAnswer(tf)
            }
            tf.onEmojiTapped = { [weak self, weak tf] in
                guard let self = self, let tf = tf else { return }
                self.handleEmojiTapped(tf)
            }
            
            answersStackView.addArrangedSubview(tf)
        }
        
        while answersStackView.arrangedSubviews.count > answers.count {
            if let last = answersStackView.arrangedSubviews.last {
                last.removeFromSuperview()
            }
        }
        
        for (index, view) in answersStackView.arrangedSubviews.enumerated() {
            guard let tf = view as? CreatePollAnswerTextField else { continue }
            
            tf.tag = index
            
            tf.attributedPlaceholder = NSAttributedString(
                string: L(L10n.CreatePoll.answerPlaceholder),
                attributes: [.foregroundColor: UIColor.theme.textDisabled]
            )
            
            if tf.text != answers[index] {
                tf.text = answers[index]
            }
            
            tf.emojiId = answerEmojiIds[index]
            tf.showRemoveButton = answers.count > 2
        }
        
        addAnswerButton.isHidden = answers.count >= maxAnswers
        
        self.view.layoutIfNeeded()
        validateForm()
    }

    private func validateForm() {
        let questionText = questionTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let validAnswers = answers.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        let isValid = !questionText.isEmpty && validAnswers.count >= 2
        
        postButton.isEnabled = isValid
        postButton.backgroundColor = isValid ? UIColor.theme.bgViolet : UIColor.theme.textDisabled.withAlphaComponent(0.4)
    }

    @objc private func durationTapped() {
        let options: [(title: String, hours: Int32)] = [
            (L(L10n.CreatePoll.hour1), 1),
            (L(L10n.CreatePoll.hours4), 4),
            (L(L10n.CreatePoll.hours8), 8),
            (L(L10n.CreatePoll.hours24), 24),
            (L(L10n.CreatePoll.days3), 72),
            (L(L10n.CreatePoll.week1), 168)
        ]
        
        let sheet = UIAlertController(title: L(L10n.CreatePoll.selectDuration), message: nil, preferredStyle: .actionSheet)
        for option in options {
            let action = UIAlertAction(title: option.title, style: .default) { [weak self] _ in
                self?.durationHours = option.hours
                self?.durationValueLabel?.text = option.title
            }
            if self.durationHours == option.hours {
                action.setValue(true, forKey: "checked")
            }
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: L(L10n.CreatePoll.cancel), style: .cancel, handler: nil))
        
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = durationContainerView
            popover.sourceRect = durationContainerView.bounds
        }
        
        present(sheet, animated: true)
    }

    @objc private func handleAddAnswer() {
        if answers.count < maxAnswers {
            answers.append("")
            answerEmojiIds.append(nil)
            updateAnswersUI()
        }
    }

    private func handleRemoveAnswer(_ tf: CreatePollAnswerTextField) {
        let index = tf.tag
        if answers.count > 2 && index < answers.count {
            answers.remove(at: index)
            answerEmojiIds.remove(at: index)
            updateAnswersUI()
        }
    }

    private func handleEmojiTapped(_ tf: CreatePollAnswerTextField) {
        let index = tf.tag
        let vc = ReactionEmojiPickerSheetController(engine: context.engine) { [weak self] id, shortname in
            guard let self = self else { return }
            if index < self.answerEmojiIds.count {
                self.answerEmojiIds[index] = id
                self.updateAnswersUI()
            }
        }
        view.endEditing(true)
        if let nav = navigationController as? NavigationController {
            nav.presentOverlay(controller: vc, inGlobal: true)
        } else {
            presentInGlobalOverlay(vc)
        }
        vc.animateIn()
    }

    @objc private func answerChanged(_ textField: UITextField) {
        let index = textField.tag
        if index < answers.count {
            answers[index] = textField.text ?? ""
            validateForm()
        }
    }

    @objc private func handleMultipleSwitchChanged(_ sender: UISwitch) {
        allowMultiple = sender.isOn
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
              let curveValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else { return }
        
        let kb = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - kb.minY)
        bottomBarBottomConstraint?.constant = overlap > 0 ? -overlap : 0
        
        let options = UIView.AnimationOptions(rawValue: curveValue << 16)
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func handlePost() {
        let validAnswers = answers.enumerated().filter { !$1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let questionText = questionTextView.text, !questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard validAnswers.count >= 2 else { return }
        
        let formattedAnswers: [String] = validAnswers.map { idx, answer in
            let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if let emojiId = answerEmojiIds[idx] {
                return "[e:\(emojiId)] \(text)"
            }
            return text
        }
        
        let type: Mezon_Api_PollType = allowMultiple ? .multiple : .single
        
        postButton.isEnabled = false
        postButton.setTitle(L(L10n.Common.loading), for: .normal)
        
        Task { @MainActor in
            guard let token = await self.context.getToken() else {
                Toast.error("No session")
                self.postButton.isEnabled = true
                self.postButton.setTitle(L(L10n.CreatePoll.postButton), for: .normal)
                return
            }
            do {
                _ = try await self.context.account.network.createPoll(
                    channelId: self.channelId,
                    clanId: self.clanId,
                    question: questionText.trimmingCharacters(in: .whitespacesAndNewlines),
                    answers: formattedAnswers,
                    expireHours: durationHours,
                    type: type,
                    token: token
                )
                self.navigationController?.popViewController(animated: true)
            } catch {
                Toast.error(error.localizedDescription)
                self.postButton.isEnabled = true
                self.postButton.setTitle(L(L10n.CreatePoll.postButton), for: .normal)
            }
        }
    }
}

extension CreatePollViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        if textView === questionTextView {
            questionPlaceholderLabel.isHidden = !textView.text.isEmpty
            questionCharCountLabel.text = "\(textView.text.count)/300"
            validateForm()
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let newText = (textView.text as NSString).replacingCharacters(in: range, with: text)
        return newText.count <= 300
    }
}

extension CreatePollViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
