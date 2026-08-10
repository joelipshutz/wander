import UIKit

final class ShareViewController: UIViewController {
    private let errorContent = UIStackView()
    private let successContent = UIStackView()
    private let captureTitleLabel = UILabel()
    private let captureDetailLabel = UILabel()
    private let statusLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var inputs: [SharedPlaceImportCaptureInput] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        loadAndCaptureSharedItems()
    }

    private func configureErrorViewIfNeeded() {
        guard errorContent.superview == nil else { return }

        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.circle.fill"))
        icon.tintColor = UIColor(red: 0.66, green: 0.17, blue: 0.13, alpha: 1)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.text = "Couldn’t save to rec.me"
        titleLabel.font = .systemFont(ofSize: 22, weight: .black)
        titleLabel.textColor = UIColor(red: 0.15, green: 0.13, blue: 0.11, alpha: 1)
        titleLabel.adjustsFontForContentSizeCategory = true

        let header = UIStackView(arrangedSubviews: [icon, titleLabel])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12

        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = UIColor(red: 0.66, green: 0.17, blue: 0.13, alpha: 1)
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.accessibilityIdentifier = "share-extension-status"

        retryButton.configuration = .filled()
        retryButton.configuration?.title = "Try again"
        retryButton.configuration?.image = UIImage(systemName: "arrow.clockwise")
        retryButton.configuration?.imagePadding = 8
        retryButton.configuration?.baseBackgroundColor = UIColor(
            red: 0.78,
            green: 0.29,
            blue: 0.18,
            alpha: 1
        )
        retryButton.configuration?.baseForegroundColor = .white
        retryButton.configuration?.cornerStyle = .capsule
        retryButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        retryButton.addTarget(self, action: #selector(retryCapture), for: .touchUpInside)
        retryButton.accessibilityIdentifier = "share-extension-primary"

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        cancelButton.tintColor = UIColor(red: 0.36, green: 0.33, blue: 0.29, alpha: 1)
        cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        cancelButton.addTarget(self, action: #selector(cancelShare), for: .touchUpInside)

        let actions = UIStackView(arrangedSubviews: [retryButton, cancelButton])
        actions.axis = .vertical
        actions.spacing = 8

        errorContent.addArrangedSubview(header)
        errorContent.addArrangedSubview(statusLabel)
        errorContent.addArrangedSubview(actions)
        errorContent.translatesAutoresizingMaskIntoConstraints = false
        errorContent.axis = .vertical
        errorContent.spacing = 16
        errorContent.setCustomSpacing(20, after: statusLabel)
        view.addSubview(errorContent)

        NSLayoutConstraint.activate([
            errorContent.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 8),
            errorContent.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -8),
            errorContent.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            errorContent.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            errorContent.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    private func configureSuccessViewIfNeeded() {
        guard successContent.superview == nil else { return }

        let icon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        icon.tintColor = UIColor(red: 0.20, green: 0.56, blue: 0.39, alpha: 1)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 31, weight: .bold)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.text = "Captured for rec.me"
        titleLabel.font = .systemFont(ofSize: 22, weight: .black)
        titleLabel.textColor = UIColor(red: 0.15, green: 0.13, blue: 0.11, alpha: 1)
        titleLabel.adjustsFontForContentSizeCategory = true

        let header = UIStackView(arrangedSubviews: [icon, titleLabel])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12

        captureTitleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        captureTitleLabel.textColor = UIColor(red: 0.15, green: 0.13, blue: 0.11, alpha: 1)
        captureTitleLabel.numberOfLines = 2
        captureTitleLabel.adjustsFontForContentSizeCategory = true

        captureDetailLabel.font = .preferredFont(forTextStyle: .subheadline)
        captureDetailLabel.textColor = UIColor(red: 0.36, green: 0.33, blue: 0.29, alpha: 1)
        captureDetailLabel.numberOfLines = 3
        captureDetailLabel.adjustsFontForContentSizeCategory = true

        let preview = UIStackView(arrangedSubviews: [captureTitleLabel, captureDetailLabel])
        preview.axis = .vertical
        preview.spacing = 5
        preview.isLayoutMarginsRelativeArrangement = true
        preview.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        preview.backgroundColor = .white
        preview.layer.cornerRadius = 14
        preview.layer.borderWidth = 1
        preview.layer.borderColor = UIColor(red: 0.86, green: 0.82, blue: 0.75, alpha: 1).cgColor

        let footer = UILabel()
        footer.text = "Open rec.me to review the match before anything is saved."
        footer.font = .preferredFont(forTextStyle: .footnote)
        footer.textColor = UIColor(red: 0.36, green: 0.33, blue: 0.29, alpha: 1)
        footer.numberOfLines = 0
        footer.adjustsFontForContentSizeCategory = true

        successContent.addArrangedSubview(header)
        successContent.addArrangedSubview(preview)
        successContent.addArrangedSubview(footer)
        successContent.translatesAutoresizingMaskIntoConstraints = false
        successContent.axis = .vertical
        successContent.spacing = 16
        successContent.accessibilityIdentifier = "share-extension-captured"
        view.addSubview(successContent)

        NSLayoutConstraint.activate([
            successContent.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 8),
            successContent.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -8),
            successContent.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            successContent.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            successContent.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    private func loadAndCaptureSharedItems() {
        errorContent.isHidden = true
        successContent.isHidden = true
        view.backgroundColor = .clear

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
                    self.captureSharedItems()
                case .failure(let error):
                    self.showError(
                        (error as? LocalizedError)?.errorDescription
                            ?? "rec.me could not read this share. Try copying its public link instead."
                    )
                }
            }
        }
    }

    private func captureSharedItems() {
        do {
            let inbox = try SharedPlaceImportInbox.live()
            try inbox.capture(inputs)
            showCaptured()
        } catch {
            showError(
                (error as? LocalizedError)?.errorDescription
                    ?? "rec.me could not save this share. Try again."
            )
        }
    }

    @objc
    private func retryCapture() {
        retryButton.isEnabled = false
        loadAndCaptureSharedItems()
    }

    @objc
    private func cancelShare() {
        extensionContext?.cancelRequest(
            withError: NSError(
                domain: NSCocoaErrorDomain,
                code: NSUserCancelledError
            )
        )
    }

    private func showError(_ message: String) {
        view.backgroundColor = UIColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1)
        configureErrorViewIfNeeded()
        statusLabel.text = message
        retryButton.isEnabled = true
        errorContent.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func showCaptured() {
        configureSuccessViewIfNeeded()
        let summary = captureSummary
        captureTitleLabel.text = summary.title
        captureDetailLabel.text = summary.detail
        errorContent.isHidden = true
        successContent.isHidden = false
        view.backgroundColor = UIColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1)
        UIAccessibility.post(
            notification: .announcement,
            argument: "Captured for rec.me. Open rec.me to review before saving."
        )
        let delay = UIAccessibility.isVoiceOverRunning ? 3.5 : 1.4
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private var captureSummary: (title: String, detail: String) {
        guard inputs.count == 1, let input = inputs.first else {
            return (
                "\(inputs.count) items captured",
                "They’ll appear together for review when you open rec.me."
            )
        }
        switch input {
        case .sharedLink(let url, let contextText, _):
            let host = url.host?.lowercased() ?? ""
            let source = host.contains("instagram")
                ? "Instagram post"
                : (host.contains("tiktok") ? "TikTok post" : "Shared link")
            return (
                source,
                contextText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? contextText!
                    : "We captured the public link and will match its place in rec.me."
            )
        case .text(let text, _):
            return ("Shared places", text)
        case .file(_, let fileName, _):
            return (fileName, "The file is ready to review in rec.me.")
        }
    }
}
