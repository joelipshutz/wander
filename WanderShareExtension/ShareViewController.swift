import UIKit

final class ShareViewController: UIViewController {
    private enum Palette {
        static let canvas = UIColor(red: 243 / 255, green: 223 / 255, blue: 202 / 255, alpha: 1)
        static let ink = UIColor(red: 44 / 255, green: 33 / 255, blue: 24 / 255, alpha: 1)
        static let muted = UIColor(red: 123 / 255, green: 101 / 255, blue: 85 / 255, alpha: 1)
        static let terracotta = UIColor(red: 212 / 255, green: 111 / 255, blue: 77 / 255, alpha: 1)
        static let terracottaDark = UIColor(red: 169 / 255, green: 79 / 255, blue: 53 / 255, alpha: 1)
        static let border = UIColor(red: 219 / 255, green: 194 / 255, blue: 170 / 255, alpha: 1)
        static let error = UIColor(red: 184 / 255, green: 74 / 255, blue: 58 / 255, alpha: 1)
    }

    private static let countdownDuration: TimeInterval = 5

    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let composerScrollView = UIScrollView()
    private let composerContent = UIStackView()
    private let errorScrollView = UIScrollView()
    private let errorContent = UIStackView()
    private let captureTitleLabel = UILabel()
    private let captureDetailLabel = UILabel()
    private let modeControl = UISegmentedControl(items: ["Wanna", "Check In"])
    private let ratingContent = UIStackView()
    private let ratingButtons = UIStackView()
    private let primaryContainer = UIView()
    private let primaryFillView = UIView()
    private let primaryButton = UIButton(type: .system)
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var primaryFillWidth: NSLayoutConstraint?
    private var countdownWorkItem: DispatchWorkItem?
    private var inputs: [SharedPlaceImportCaptureInput] = []
    private var ratingScore: Int?
    private var isSubmitting = false

    private var requiresExplicitSubmission: Bool {
        UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    }

    private func scaledFont(
        size: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle
    ) -> UIFont {
        UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: .systemFont(ofSize: size, weight: weight)
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.canvas
        configureLoadingView()
        loadSharedItems()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        primaryContainer.layer.cornerRadius = primaryContainer.bounds.height / 2
        primaryFillView.layer.cornerRadius = primaryContainer.bounds.height / 2
    }

    private func configureLoadingView() {
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.color = Palette.terracotta
        loadingIndicator.startAnimating()
        loadingIndicator.accessibilityLabel = "Reading shared post"
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func configureComposerIfNeeded() {
        guard composerContent.superview == nil else { return }

        let eyebrow = UILabel()
        eyebrow.text = "ADD TO REC.ME"
        eyebrow.font = scaledFont(size: 12, weight: .black, textStyle: .caption2)
        eyebrow.textColor = Palette.terracottaDark
        eyebrow.adjustsFontForContentSizeCategory = true

        let title = UILabel()
        title.text = "Save this place"
        title.font = scaledFont(size: 27, weight: .black, textStyle: .title1)
        title.textColor = Palette.ink
        title.adjustsFontForContentSizeCategory = true

        captureTitleLabel.font = scaledFont(size: 17, weight: .bold, textStyle: .headline)
        captureTitleLabel.textColor = Palette.ink
        captureTitleLabel.numberOfLines = 0
        captureTitleLabel.adjustsFontForContentSizeCategory = true

        captureDetailLabel.font = .preferredFont(forTextStyle: .subheadline)
        captureDetailLabel.textColor = Palette.muted
        captureDetailLabel.numberOfLines = 0
        captureDetailLabel.adjustsFontForContentSizeCategory = true

        let preview = UIStackView(arrangedSubviews: [captureTitleLabel, captureDetailLabel])
        preview.axis = .vertical
        preview.spacing = 5
        preview.isLayoutMarginsRelativeArrangement = true
        preview.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        preview.backgroundColor = .white
        preview.layer.cornerRadius = 16
        preview.layer.borderWidth = 1
        preview.layer.borderColor = Palette.border.cgColor

        modeControl.selectedSegmentIndex = 0
        modeControl.selectedSegmentTintColor = Palette.ink
        modeControl.setTitleTextAttributes([.foregroundColor: Palette.muted], for: .normal)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        modeControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        modeControl.accessibilityIdentifier = "share-extension-save-mode"

        let ratingLabel = UILabel()
        ratingLabel.text = "Rating (optional)"
        ratingLabel.font = scaledFont(size: 13, weight: .bold, textStyle: .caption1)
        ratingLabel.textColor = Palette.muted

        ratingButtons.axis = .horizontal
        ratingButtons.distribution = .fillEqually
        ratingButtons.spacing = 2
        for score in 1...5 {
            let button = UIButton(type: .system)
            button.tag = score
            button.setImage(UIImage(systemName: "star"), for: .normal)
            button.tintColor = Palette.terracotta
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.addTarget(self, action: #selector(ratingTapped(_:)), for: .touchUpInside)
            button.accessibilityLabel = "\(score) star\(score == 1 ? "" : "s")"
            ratingButtons.addArrangedSubview(button)
        }

        ratingContent.axis = .vertical
        ratingContent.spacing = 4
        ratingContent.addArrangedSubview(ratingLabel)
        ratingContent.addArrangedSubview(ratingButtons)
        ratingContent.isHidden = true

        primaryContainer.translatesAutoresizingMaskIntoConstraints = false
        primaryContainer.backgroundColor = Palette.terracotta.withAlphaComponent(0.72)
        primaryContainer.clipsToBounds = true
        primaryContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        primaryFillView.translatesAutoresizingMaskIntoConstraints = false
        primaryFillView.backgroundColor = Palette.terracotta
        primaryContainer.addSubview(primaryFillView)
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.setTitleColor(.white, for: .normal)
        primaryButton.titleLabel?.font = scaledFont(size: 17, weight: .black, textStyle: .headline)
        primaryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        primaryButton.addTarget(self, action: #selector(submitNow), for: .touchUpInside)
        primaryButton.accessibilityIdentifier = "share-extension-primary"
        primaryContainer.addSubview(primaryButton)
        let fillWidth = primaryFillView.widthAnchor.constraint(equalToConstant: 0)
        primaryFillWidth = fillWidth
        NSLayoutConstraint.activate([
            primaryFillView.leadingAnchor.constraint(equalTo: primaryContainer.leadingAnchor),
            primaryFillView.topAnchor.constraint(equalTo: primaryContainer.topAnchor),
            primaryFillView.bottomAnchor.constraint(equalTo: primaryContainer.bottomAnchor),
            fillWidth,
            primaryButton.leadingAnchor.constraint(equalTo: primaryContainer.leadingAnchor),
            primaryButton.trailingAnchor.constraint(equalTo: primaryContainer.trailingAnchor),
            primaryButton.topAnchor.constraint(equalTo: primaryContainer.topAnchor),
            primaryButton.bottomAnchor.constraint(equalTo: primaryContainer.bottomAnchor)
        ])

        let helper = UILabel()
        helper.text = "We’ll match and save it automatically. If you’re signed out, it stays safely queued."
        helper.font = .preferredFont(forTextStyle: .footnote)
        helper.textColor = Palette.muted
        helper.numberOfLines = 0
        helper.textAlignment = .center
        helper.adjustsFontForContentSizeCategory = true

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = scaledFont(size: 16, weight: .semibold, textStyle: .body)
        cancelButton.titleLabel?.adjustsFontForContentSizeCategory = true
        cancelButton.tintColor = Palette.muted
        cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        cancelButton.addTarget(self, action: #selector(cancelShare), for: .touchUpInside)

        composerContent.addArrangedSubview(eyebrow)
        composerContent.addArrangedSubview(title)
        composerContent.addArrangedSubview(preview)
        composerContent.addArrangedSubview(modeControl)
        composerContent.addArrangedSubview(ratingContent)
        composerContent.addArrangedSubview(primaryContainer)
        composerContent.addArrangedSubview(helper)
        composerContent.addArrangedSubview(cancelButton)
        composerContent.setCustomSpacing(4, after: eyebrow)
        composerContent.setCustomSpacing(18, after: title)
        composerContent.setCustomSpacing(14, after: preview)
        composerContent.translatesAutoresizingMaskIntoConstraints = false
        composerContent.axis = .vertical
        composerContent.spacing = 10
        composerContent.accessibilityIdentifier = "share-extension-composer"
        composerScrollView.translatesAutoresizingMaskIntoConstraints = false
        composerScrollView.alwaysBounceVertical = false
        view.addSubview(composerScrollView)
        composerScrollView.addSubview(composerContent)

        NSLayoutConstraint.activate([
            composerScrollView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 8),
            composerScrollView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -8),
            composerScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            composerScrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            composerContent.leadingAnchor.constraint(equalTo: composerScrollView.contentLayoutGuide.leadingAnchor),
            composerContent.trailingAnchor.constraint(equalTo: composerScrollView.contentLayoutGuide.trailingAnchor),
            composerContent.topAnchor.constraint(equalTo: composerScrollView.contentLayoutGuide.topAnchor, constant: 18),
            composerContent.bottomAnchor.constraint(equalTo: composerScrollView.contentLayoutGuide.bottomAnchor, constant: -10),
            composerContent.widthAnchor.constraint(equalTo: composerScrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func configureErrorIfNeeded() {
        guard errorContent.superview == nil else { return }
        let title = UILabel()
        title.text = "Couldn’t save to rec.me"
        title.font = scaledFont(size: 22, weight: .black, textStyle: .title2)
        title.textColor = Palette.ink
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true

        errorLabel.font = .preferredFont(forTextStyle: .body)
        errorLabel.textColor = Palette.error
        errorLabel.numberOfLines = 0
        errorLabel.accessibilityIdentifier = "share-extension-status"

        retryButton.configuration = .filled()
        retryButton.configuration?.title = "Try again"
        retryButton.configuration?.baseBackgroundColor = Palette.terracotta
        retryButton.configuration?.cornerStyle = .capsule
        retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        retryButton.addTarget(self, action: #selector(retryCapture), for: .touchUpInside)

        errorContent.addArrangedSubview(title)
        errorContent.addArrangedSubview(errorLabel)
        errorContent.addArrangedSubview(retryButton)
        errorContent.translatesAutoresizingMaskIntoConstraints = false
        errorContent.axis = .vertical
        errorContent.spacing = 16
        errorScrollView.translatesAutoresizingMaskIntoConstraints = false
        errorScrollView.alwaysBounceVertical = false
        view.addSubview(errorScrollView)
        errorScrollView.addSubview(errorContent)
        NSLayoutConstraint.activate([
            errorScrollView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 8),
            errorScrollView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -8),
            errorScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            errorScrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            errorContent.leadingAnchor.constraint(equalTo: errorScrollView.contentLayoutGuide.leadingAnchor),
            errorContent.trailingAnchor.constraint(equalTo: errorScrollView.contentLayoutGuide.trailingAnchor),
            errorContent.topAnchor.constraint(equalTo: errorScrollView.contentLayoutGuide.topAnchor, constant: 18),
            errorContent.bottomAnchor.constraint(equalTo: errorScrollView.contentLayoutGuide.bottomAnchor, constant: -10),
            errorContent.widthAnchor.constraint(equalTo: errorScrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func loadSharedItems() {
        countdownWorkItem?.cancel()
        isSubmitting = false
        loadingIndicator.isHidden = false
        composerScrollView.isHidden = true
        composerContent.isHidden = true
        errorScrollView.isHidden = true
        errorContent.isHidden = true
        guard let extensionContext else {
            showError(SharedPlaceImportInboxError.noSupportedContent.localizedDescription)
            return
        }
        ShareExtensionItemLoader.load(from: extensionContext.inputItems) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let inputs):
                    self.inputs = inputs
                    self.showComposer()
                case .failure(let error):
                    self.showError(
                        (error as? LocalizedError)?.errorDescription
                            ?? "rec.me could not read this share. Try copying its public link instead."
                    )
                }
            }
        }
    }

    private func showComposer() {
        configureComposerIfNeeded()
        let summary = captureSummary
        captureTitleLabel.text = summary.title
        captureDetailLabel.text = summary.detail
        loadingIndicator.isHidden = true
        composerScrollView.isHidden = false
        errorContent.isHidden = true
        errorScrollView.isHidden = true
        composerContent.isHidden = false
        updateModeUI()
        view.layoutIfNeeded()
        startCountdown()
        UIAccessibility.post(notification: .screenChanged, argument: captureTitleLabel)
    }

    private func startCountdown() {
        guard !isSubmitting else { return }
        countdownWorkItem?.cancel()
        primaryFillView.layer.removeAllAnimations()
        primaryFillWidth?.constant = 0
        view.layoutIfNeeded()
        if requiresExplicitSubmission {
            primaryContainer.backgroundColor = Palette.terracotta
            primaryFillWidth?.constant = primaryContainer.bounds.width
            view.layoutIfNeeded()
            return
        }
        primaryContainer.backgroundColor = Palette.terracotta.withAlphaComponent(0.72)
        primaryFillWidth?.constant = primaryContainer.bounds.width
        UIView.animate(
            withDuration: Self.countdownDuration,
            delay: 0,
            options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.view.layoutIfNeeded()
        }
        let workItem = DispatchWorkItem { [weak self] in self?.captureSharedItems() }
        countdownWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.countdownDuration, execute: workItem)
    }

    private func captureSharedItems() {
        guard !isSubmitting else { return }
        isSubmitting = true
        countdownWorkItem?.cancel()
        primaryFillView.layer.removeAllAnimations()
        primaryButton.isEnabled = false
        modeControl.isEnabled = false
        ratingButtons.isUserInteractionEnabled = false
        do {
            let mode: SharedPlaceImportSaveMode = modeControl.selectedSegmentIndex == 1
                ? .checkIn
                : .wanna
            let intent = SharedPlaceImportSaveIntent(
                mode: mode,
                ratingScore: ratingScore.map(Double.init)
            )
            let inbox = try SharedPlaceImportInbox.live()
            try inbox.capture(inputs, saveIntent: intent)
            completeCapture(intent: intent)
        } catch {
            isSubmitting = false
            primaryButton.isEnabled = true
            modeControl.isEnabled = true
            ratingButtons.isUserInteractionEnabled = true
            showError(
                (error as? LocalizedError)?.errorDescription
                    ?? "rec.me could not save this share. Try again."
            )
        }
    }

    private func completeCapture(intent: SharedPlaceImportSaveIntent) {
        primaryFillWidth?.constant = primaryContainer.bounds.width
        primaryContainer.backgroundColor = Palette.terracotta
        primaryButton.setImage(UIImage(systemName: "checkmark.circle.fill"), for: .normal)
        primaryButton.setTitle(intent.mode == .checkIn ? " Check In saved" : " Added to Wanna", for: .normal)
        let announcement = intent.mode == .checkIn ? "Check In queued" : "Wanna queued"
        UIAccessibility.post(notification: .announcement, argument: announcement)
        let delay = UIAccessibility.isVoiceOverRunning ? 1.2 : 0.28
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func showError(_ message: String) {
        configureErrorIfNeeded()
        loadingIndicator.isHidden = true
        composerScrollView.isHidden = true
        composerContent.isHidden = true
        errorLabel.text = message
        retryButton.isEnabled = true
        errorScrollView.isHidden = false
        errorContent.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    @objc private func modeChanged() {
        ratingScore = nil
        updateModeUI()
        startCountdown()
    }

    private func updateModeUI() {
        let isCheckIn = modeControl.selectedSegmentIndex == 1
        ratingContent.isHidden = !isCheckIn
        primaryButton.setTitle(isCheckIn ? "Check In" : "Add to Wanna", for: .normal)
        updateRatingButtons()
    }

    @objc private func ratingTapped(_ sender: UIButton) {
        ratingScore = ratingScore == sender.tag ? nil : sender.tag
        updateRatingButtons()
        startCountdown()
    }

    private func updateRatingButtons() {
        for case let button as UIButton in ratingButtons.arrangedSubviews {
            let isFilled = button.tag <= (ratingScore ?? 0)
            button.setImage(UIImage(systemName: isFilled ? "star.fill" : "star"), for: .normal)
            button.accessibilityValue = isFilled ? "Selected" : nil
        }
    }

    @objc private func submitNow() {
        captureSharedItems()
    }

    @objc private func retryCapture() {
        retryButton.isEnabled = false
        loadSharedItems()
    }

    @objc private func cancelShare() {
        countdownWorkItem?.cancel()
        extensionContext?.cancelRequest(
            withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        )
    }

    private var captureSummary: (title: String, detail: String) {
        guard inputs.count == 1, let input = inputs.first else {
            return ("\(inputs.count) shared items", "We’ll find the places and keep them together for verification.")
        }
        switch input {
        case .sharedLink(let url, let contextText, _):
            let host = url.host?.lowercased() ?? ""
            let source = host.contains("instagram")
                ? "Instagram post"
                : (host.contains("tiktok") ? "TikTok post" : "Shared link")
            let detail = contextText?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (source, detail?.isEmpty == false ? detail! : url.host ?? url.absoluteString)
        case .text(let text, _):
            return ("Shared places", text)
        case .file(_, let fileName, _):
            return (fileName, "We’ll import the places in this file.")
        }
    }
}
