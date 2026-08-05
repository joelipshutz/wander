import UIKit

final class ShareViewController: UIViewController {
    private enum State {
        case loading
        case saved
        case failed
    }

    private let sourceLabel = UILabel()
    private let previewLabel = UILabel()
    private let statusLabel = UILabel()
    private let primaryButton = UIButton(type: .system)
    private var inputs: [SharedPlaceImportCaptureInput] = []
    private var state: State = .loading

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadAndCaptureSharedItems()
    }

    private func configureView() {
        view.backgroundColor = UIColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1)

        let icon = UIImageView(image: UIImage(systemName: "mappin.and.ellipse"))
        icon.tintColor = UIColor(red: 0.78, green: 0.29, blue: 0.18, alpha: 1)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.text = "Saving to rec.me"
        titleLabel.font = .systemFont(ofSize: 22, weight: .black)
        titleLabel.textColor = UIColor(red: 0.15, green: 0.13, blue: 0.11, alpha: 1)
        titleLabel.adjustsFontForContentSizeCategory = true

        let header = UIStackView(arrangedSubviews: [icon, titleLabel])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12

        sourceLabel.text = "Reading shared post…"
        sourceLabel.font = .systemFont(ofSize: 16, weight: .bold)
        sourceLabel.textColor = UIColor(red: 0.15, green: 0.13, blue: 0.11, alpha: 1)
        sourceLabel.numberOfLines = 1
        sourceLabel.adjustsFontForContentSizeCategory = true

        previewLabel.text = "We’ll keep the link and any caption the app shared."
        previewLabel.font = .preferredFont(forTextStyle: .subheadline)
        previewLabel.textColor = UIColor(red: 0.36, green: 0.33, blue: 0.29, alpha: 1)
        previewLabel.numberOfLines = 3
        previewLabel.adjustsFontForContentSizeCategory = true

        let previewStack = UIStackView(arrangedSubviews: [sourceLabel, previewLabel])
        previewStack.axis = .vertical
        previewStack.spacing = 5
        previewStack.isLayoutMarginsRelativeArrangement = true
        previewStack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        previewStack.backgroundColor = .white
        previewStack.layer.cornerRadius = 16
        previewStack.layer.borderWidth = 1
        previewStack.layer.borderColor = UIColor(red: 0.88, green: 0.84, blue: 0.76, alpha: 1).cgColor

        statusLabel.text = "Saving privately as Wanna…"
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = UIColor(red: 0.36, green: 0.33, blue: 0.29, alpha: 1)
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.accessibilityIdentifier = "share-extension-status"

        primaryButton.configuration = .filled()
        primaryButton.configuration?.title = "Saving…"
        primaryButton.configuration?.showsActivityIndicator = true
        primaryButton.configuration?.baseBackgroundColor = UIColor(
            red: 0.78,
            green: 0.29,
            blue: 0.18,
            alpha: 1
        )
        primaryButton.configuration?.baseForegroundColor = .white
        primaryButton.configuration?.cornerStyle = .capsule
        primaryButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        primaryButton.isEnabled = false
        primaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        primaryButton.addTarget(self, action: #selector(primaryAction), for: .touchUpInside)
        primaryButton.accessibilityIdentifier = "share-extension-primary"

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        cancelButton.tintColor = UIColor(red: 0.36, green: 0.33, blue: 0.29, alpha: 1)
        cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        cancelButton.addTarget(self, action: #selector(cancelShare), for: .touchUpInside)

        let actions = UIStackView(arrangedSubviews: [primaryButton, cancelButton])
        actions.axis = .vertical
        actions.spacing = 8

        let content = UIStackView(arrangedSubviews: [header, previewStack, statusLabel, actions])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 16
        content.setCustomSpacing(20, after: statusLabel)
        view.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -8),
            content.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            content.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            content.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    private func loadAndCaptureSharedItems() {
        state = .loading
        primaryButton.isEnabled = false
        primaryButton.configuration?.title = "Saving…"
        primaryButton.configuration?.showsActivityIndicator = true
        statusLabel.text = "Saving privately as Wanna…"
        statusLabel.textColor = UIColor(red: 0.36, green: 0.33, blue: 0.29, alpha: 1)

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
                    self.showPreview(for: inputs)
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

    private func showPreview(for inputs: [SharedPlaceImportCaptureInput]) {
        let summary = SharedPlaceImportCaptureSummary(inputs: inputs)
        sourceLabel.text = summary.title
        previewLabel.text = summary.detail ?? "Public link captured"
    }

    private func captureSharedItems() {
        do {
            let inbox = try SharedPlaceImportInbox.live()
            try inbox.capture(inputs)
            state = .saved
            statusLabel.text = "Saved to rec.me. We’ll match it as Wanna when you open the app—or hold it safely until you log in."
            primaryButton.configuration?.title = "Done"
            primaryButton.configuration?.image = UIImage(systemName: "checkmark.circle.fill")
            primaryButton.configuration?.imagePadding = 8
            primaryButton.configuration?.showsActivityIndicator = false
            primaryButton.isEnabled = true
            UIAccessibility.post(notification: .announcement, argument: statusLabel.text)
        } catch {
            showError(
                (error as? LocalizedError)?.errorDescription
                    ?? "rec.me could not save this share. Try again."
            )
        }
    }

    @objc
    private func primaryAction() {
        switch state {
        case .saved:
            extensionContext?.completeRequest(returningItems: nil)
        case .failed:
            loadAndCaptureSharedItems()
        case .loading:
            break
        }
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
        state = .failed
        statusLabel.text = message
        statusLabel.textColor = UIColor(red: 0.66, green: 0.17, blue: 0.13, alpha: 1)
        primaryButton.configuration?.title = "Try again"
        primaryButton.configuration?.image = UIImage(systemName: "arrow.clockwise")
        primaryButton.configuration?.imagePadding = 8
        primaryButton.configuration?.showsActivityIndicator = false
        primaryButton.isEnabled = true
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
