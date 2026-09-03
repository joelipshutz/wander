import UIKit

/// The share extension mirrors the in-app import sheet: the source app fills
/// the link, and the person only confirms Start import. Matching, review,
/// notifications, and final saves remain owned by the containing app.
final class ShareViewController: UIViewController {
    private enum Palette {
        static let canvas = UIColor(red: 243 / 255, green: 223 / 255, blue: 202 / 255, alpha: 1)
        static let surface = UIColor(red: 1, green: 247 / 255, blue: 234 / 255, alpha: 1)
        static let ink = UIColor(red: 44 / 255, green: 33 / 255, blue: 24 / 255, alpha: 1)
        static let muted = UIColor(red: 123 / 255, green: 101 / 255, blue: 85 / 255, alpha: 1)
        static let terracotta = UIColor(red: 212 / 255, green: 111 / 255, blue: 77 / 255, alpha: 1)
        static let border = UIColor(red: 219 / 255, green: 194 / 255, blue: 170 / 255, alpha: 1)
        static let error = UIColor(red: 184 / 255, green: 74 / 255, blue: 58 / 255, alpha: 1)
    }

    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let linkField = UITextField()
    private let startButton = UIButton(type: .system)
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var inputs: [SharedPlaceImportCaptureInput] = []
    private var isSubmitting = false

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard contentStack.superview != nil, contentStack.bounds.width > 0 else { return }
        let contentHeight = contentStack.systemLayoutSizeFitting(
            CGSize(width: contentStack.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height + 26
        // Ask the share host for only the space the form needs. Scroll rather
        // than growing beyond a half sheet at large accessibility text sizes.
        let height = min(contentHeight, (view.window?.screen.bounds.height ?? 852) * 0.55)
        if abs(preferredContentSize.height - height) > 1 {
            preferredContentSize = CGSize(width: view.bounds.width, height: height)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 0, height: 440)
        view.backgroundColor = Palette.canvas
        configureLoadingView()
        loadSharedItems()
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

    private func configureLoadingView() {
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.color = Palette.terracotta
        loadingIndicator.startAnimating()
        loadingIndicator.accessibilityLabel = "Reading shared link"
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func configureImportSheetIfNeeded() {
        guard contentStack.superview == nil else { return }

        let appName = UILabel()
        appName.text = "rec.me"
        appName.font = scaledFont(size: 17, weight: .bold, textStyle: .headline)
        appName.textColor = Palette.ink
        appName.adjustsFontForContentSizeCategory = true
        appName.accessibilityTraits = .header

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = Palette.muted
        closeButton.accessibilityLabel = "Cancel import"
        closeButton.addTarget(self, action: #selector(cancelShare), for: .touchUpInside)
        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        let header = UIStackView(arrangedSubviews: [appName, closeButton])
        header.axis = .horizontal
        header.alignment = .center

        let title = UILabel()
        title.text = "Import places"
        title.font = scaledFont(size: 28, weight: .black, textStyle: .title1)
        title.textColor = Palette.ink
        title.textAlignment = .center
        title.adjustsFontForContentSizeCategory = true

        let iconRow = UIStackView(arrangedSubviews: [
            sourceIcon(assetName: "BrandGoogleMaps"),
            sourceIcon(assetName: "BrandInstagram"),
            sourceIcon(assetName: "BrandTikTok")
        ])
        iconRow.axis = .horizontal
        iconRow.alignment = .center
        iconRow.distribution = .fill
        iconRow.spacing = -9
        iconRow.translatesAutoresizingMaskIntoConstraints = false
        let iconContainer = UIView()
        iconContainer.addSubview(iconRow)
        NSLayoutConstraint.activate([
            iconContainer.heightAnchor.constraint(equalToConstant: 46),
            iconRow.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconRow.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor)
        ])

        let headline = UILabel()
        headline.text = "Bring your places with you"
        headline.font = scaledFont(size: 20, weight: .bold, textStyle: .title3)
        headline.textColor = Palette.ink
        headline.textAlignment = .center
        headline.adjustsFontForContentSizeCategory = true

        let detail = UILabel()
        detail.text = "Your shared link is ready. Matching begins the next time you open rec.me."
        detail.font = .preferredFont(forTextStyle: .body)
        detail.textColor = Palette.muted
        detail.numberOfLines = 0
        detail.textAlignment = .center
        detail.adjustsFontForContentSizeCategory = true

        let linkIcon = UIImageView(image: UIImage(systemName: "link"))
        linkIcon.tintColor = Palette.terracotta
        linkIcon.contentMode = .scaleAspectFit
        linkIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            linkIcon.widthAnchor.constraint(equalToConstant: 24),
            linkIcon.heightAnchor.constraint(equalToConstant: 24)
        ])

        linkField.font = scaledFont(size: 15, weight: .semibold, textStyle: .body)
        linkField.textColor = Palette.ink
        linkField.tintColor = Palette.terracotta
        linkField.clearButtonMode = .whileEditing
        linkField.autocapitalizationType = .none
        linkField.autocorrectionType = .no
        linkField.keyboardType = .URL
        linkField.returnKeyType = .done
        linkField.placeholder = "Shared link"
        linkField.accessibilityLabel = "Import link"
        linkField.accessibilityIdentifier = "share-extension-import-link"
        linkField.addTarget(self, action: #selector(linkEdited), for: .editingChanged)

        let linkContainer = UIStackView(arrangedSubviews: [linkIcon, linkField])
        linkContainer.axis = .horizontal
        linkContainer.alignment = .center
        linkContainer.spacing = 12
        linkContainer.isLayoutMarginsRelativeArrangement = true
        linkContainer.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 10,
            leading: 16,
            bottom: 10,
            trailing: 10
        )
        linkContainer.backgroundColor = .white
        linkContainer.layer.cornerRadius = 16
        linkContainer.layer.borderWidth = 1
        linkContainer.layer.borderColor = Palette.border.cgColor
        linkContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true

        if #available(iOS 26.0, *) {
            startButton.configuration = .prominentGlass()
        } else {
            startButton.configuration = .filled()
        }
        startButton.configuration?.title = "Start import"
        startButton.configuration?.image = UIImage(systemName: "arrow.down.doc.fill")
        startButton.configuration?.imagePadding = 8
        startButton.configuration?.cornerStyle = .capsule
        startButton.configuration?.baseBackgroundColor = Palette.terracotta
        startButton.configuration?.baseForegroundColor = .white
        startButton.titleLabel?.font = scaledFont(size: 16, weight: .black, textStyle: .headline)
        startButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        startButton.addTarget(self, action: #selector(startImport), for: .touchUpInside)
        startButton.accessibilityIdentifier = "share-extension-start-import"

        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.textColor = Palette.error
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.isHidden = true

        retryButton.configuration = .plain()
        retryButton.configuration?.title = "Try again"
        retryButton.configuration?.baseForegroundColor = Palette.terracotta
        retryButton.addTarget(self, action: #selector(retryCapture), for: .touchUpInside)
        retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        retryButton.isHidden = true

        contentStack.addArrangedSubview(header)
        contentStack.addArrangedSubview(title)
        contentStack.addArrangedSubview(iconContainer)
        contentStack.addArrangedSubview(headline)
        contentStack.addArrangedSubview(detail)
        contentStack.addArrangedSubview(linkContainer)
        contentStack.addArrangedSubview(startButton)
        contentStack.addArrangedSubview(errorLabel)
        contentStack.addArrangedSubview(retryButton)
        contentStack.setCustomSpacing(12, after: title)
        contentStack.setCustomSpacing(12, after: iconContainer)
        contentStack.setCustomSpacing(4, after: headline)
        contentStack.setCustomSpacing(18, after: detail)
        contentStack.setCustomSpacing(14, after: linkContainer)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 8
        contentStack.accessibilityIdentifier = "share-extension-import-sheet"

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func sourceIcon(assetName: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .white
        container.layer.cornerRadius = 23
        container.layer.borderWidth = 2
        container.layer.borderColor = Palette.surface.cgColor
        let image = UIImageView(image: UIImage(named: assetName)?.withRenderingMode(.alwaysTemplate))
        image.translatesAutoresizingMaskIntoConstraints = false
        image.tintColor = Palette.ink
        image.contentMode = .scaleAspectFit
        container.addSubview(image)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 46),
            container.heightAnchor.constraint(equalToConstant: 46),
            image.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 22),
            image.heightAnchor.constraint(equalToConstant: 22)
        ])
        return container
    }

    private func loadSharedItems() {
        isSubmitting = false
        loadingIndicator.isHidden = false
        scrollView.isHidden = true
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
                    self.showImportSheet()
                case .failure(let error):
                    self.showError(
                        (error as? LocalizedError)?.errorDescription
                            ?? "rec.me could not read this share. Try copying its public link instead."
                    )
                }
            }
        }
    }

    private func showImportSheet() {
        configureImportSheetIfNeeded()
        linkField.text = sharedLinkString
        startButton.isEnabled = canStartImport
        errorLabel.isHidden = true
        retryButton.isHidden = true
        loadingIndicator.isHidden = true
        scrollView.isHidden = false
        UIAccessibility.post(notification: .screenChanged, argument: linkField)
    }

    private func showError(_ message: String) {
        configureImportSheetIfNeeded()
        loadingIndicator.isHidden = true
        scrollView.isHidden = false
        errorLabel.text = message
        errorLabel.isHidden = false
        retryButton.isHidden = false
        retryButton.isEnabled = true
        startButton.isEnabled = false
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    @objc private func startImport() {
        guard !isSubmitting, canStartImport else { return }
        isSubmitting = true
        startButton.isEnabled = false
        startButton.configuration?.showsActivityIndicator = true

        do {
            let inbox = try SharedPlaceImportInbox.live()
            try inbox.capture(captureInputs)
            completeImportCapture()
        } catch {
            isSubmitting = false
            startButton.configuration?.showsActivityIndicator = false
            showError(
                (error as? LocalizedError)?.errorDescription
                    ?? "rec.me could not start this import. Try again."
            )
        }
    }

    private func completeImportCapture() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    @objc private func retryCapture() {
        retryButton.isEnabled = false
        loadSharedItems()
    }

    @objc private func cancelShare() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        )
    }

    private var sharedLinkString: String? {
        inputs.lazy.compactMap { input -> String? in
            if case .sharedLink(let url, _, _) = input {
                return url.absoluteString
            }
            return nil
        }.first
    }

    @objc private func linkEdited() {
        startButton.isEnabled = !isSubmitting && canStartImport
    }

    private var canStartImport: Bool {
        guard !inputs.isEmpty else { return false }
        guard inputs.count == 1, case .sharedLink = inputs[0] else { return true }
        guard let text = linkField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text),
              let host = url.host, !host.isEmpty,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return false }
        return true
    }

    private var captureInputs: [SharedPlaceImportCaptureInput] {
        guard inputs.count == 1,
              case .sharedLink(let originalURL, let contextText, let suggestedName) = inputs[0],
              let edited = linkField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let editedURL = URL(string: edited),
              ["http", "https"].contains(editedURL.scheme?.lowercased() ?? ""),
              editedURL != originalURL
        else {
            return inputs
        }
        return [.sharedLink(editedURL, contextText: contextText, suggestedName: suggestedName)]
    }
}
