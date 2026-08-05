import UIKit

final class ShareViewController: UIViewController {
    private let errorContent = UIStackView()
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

    private func loadAndCaptureSharedItems() {
        errorContent.isHidden = true
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
            extensionContext?.completeRequest(returningItems: nil)
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
}
