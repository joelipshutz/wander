import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let captureButton = UIButton(type: .system)
    private var inputs: [SharedPlaceImportCaptureInput] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadSharedItems()
    }

    private func configureView() {
        view.backgroundColor = UIColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1)

        let icon = UIImageView(image: UIImage(systemName: "mappin.and.ellipse"))
        icon.tintColor = UIColor(red: 0.78, green: 0.29, blue: 0.18, alpha: 1)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.text = "Save places to rec.me"
        titleLabel.font = .systemFont(ofSize: 22, weight: .black)
        titleLabel.textColor = UIColor(red: 0.15, green: 0.13, blue: 0.11, alpha: 1)
        titleLabel.adjustsFontForContentSizeCategory = true

        let header = UIStackView(arrangedSubviews: [icon, titleLabel])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12

        statusLabel.text = "Checking what was shared…"
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = UIColor(red: 0.36, green: 0.33, blue: 0.29, alpha: 1)
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.accessibilityIdentifier = "share-extension-status"

        captureButton.configuration = .filled()
        captureButton.configuration?.title = "Add to rec.me"
        captureButton.configuration?.image = UIImage(systemName: "arrow.down.doc.fill")
        captureButton.configuration?.imagePadding = 8
        captureButton.configuration?.baseBackgroundColor = UIColor(
            red: 0.78,
            green: 0.29,
            blue: 0.18,
            alpha: 1
        )
        captureButton.configuration?.baseForegroundColor = .white
        captureButton.configuration?.cornerStyle = .capsule
        captureButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        captureButton.isEnabled = false
        captureButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        captureButton.addTarget(self, action: #selector(captureSharedItems), for: .touchUpInside)
        captureButton.accessibilityIdentifier = "share-extension-capture"

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        cancelButton.tintColor = UIColor(red: 0.36, green: 0.33, blue: 0.29, alpha: 1)
        cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        cancelButton.addTarget(self, action: #selector(cancelShare), for: .touchUpInside)

        let actions = UIStackView(arrangedSubviews: [captureButton, cancelButton])
        actions.axis = .vertical
        actions.spacing = 8

        let content = UIStackView(arrangedSubviews: [header, statusLabel, actions])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 20
        content.setCustomSpacing(28, after: statusLabel)
        view.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -8),
            content.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            content.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            content.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    private func loadSharedItems() {
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
                    self.statusLabel.text = Self.readyMessage(for: inputs)
                    self.captureButton.isEnabled = true
                case .failure(let error):
                    self.showError(
                        (error as? LocalizedError)?.errorDescription
                            ?? "rec.me could not read this share. Try copying its public link instead."
                    )
                }
            }
        }
    }

    @objc
    private func captureSharedItems() {
        captureButton.isEnabled = false
        statusLabel.text = "Adding this to your import inbox…"

        do {
            let inbox = try SharedPlaceImportInbox.live()
            try inbox.capture(inputs)
            statusLabel.text = "Added. Open rec.me to match and review your places."
            captureButton.configuration?.title = "Added to rec.me"
            captureButton.configuration?.image = UIImage(systemName: "checkmark.circle.fill")
            UIAccessibility.post(notification: .announcement, argument: statusLabel.text)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        } catch {
            showError(
                (error as? LocalizedError)?.errorDescription
                    ?? "rec.me could not save this share. Try again."
            )
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
        statusLabel.text = message
        statusLabel.textColor = UIColor(red: 0.66, green: 0.17, blue: 0.13, alpha: 1)
        captureButton.isEnabled = false
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private static func readyMessage(for inputs: [SharedPlaceImportCaptureInput]) -> String {
        let fileCount = inputs.filter {
            if case .file = $0 { return true }
            return false
        }.count
        let textCount = inputs.count - fileCount
        if fileCount > 0, textCount > 0 {
            return "\(textCount) link or text item\(textCount == 1 ? "" : "s") and \(fileCount) file\(fileCount == 1 ? "" : "s") are ready."
        }
        if fileCount > 0 {
            return "\(fileCount) supported file\(fileCount == 1 ? " is" : "s are") ready."
        }
        return "\(textCount) link or text item\(textCount == 1 ? " is" : "s are") ready."
    }
}

private enum ShareExtensionItemLoader {
    private final class Callback<Value>: @unchecked Sendable {
        let call: (Value) -> Void

        init(_ call: @escaping (Value) -> Void) {
            self.call = call
        }
    }

    static func load(
        from contextItems: [Any],
        completion: @escaping (Result<[SharedPlaceImportCaptureInput], Error>) -> Void
    ) {
        let providers = contextItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else {
            completion(.failure(SharedPlaceImportInboxError.noSupportedContent))
            return
        }
        guard providers.count <= SharedPlaceImportInbox.maximumItemCount else {
            completion(.failure(SharedPlaceImportInboxError.tooManyItems))
            return
        }
        load(providers: providers, at: 0, accumulated: [], completion: completion)
    }

    private static func load(
        providers: [NSItemProvider],
        at index: Int,
        accumulated: [SharedPlaceImportCaptureInput],
        completion: @escaping (Result<[SharedPlaceImportCaptureInput], Error>) -> Void
    ) {
        guard index < providers.count else {
            guard !accumulated.isEmpty else {
                completion(.failure(SharedPlaceImportInboxError.noSupportedContent))
                return
            }
            completion(.success(accumulated))
            return
        }

        load(provider: providers[index]) { result in
            switch result {
            case .success(let input):
                load(
                    providers: providers,
                    at: index + 1,
                    accumulated: input.map { accumulated + [$0] } ?? accumulated,
                    completion: completion
                )
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func load(
        provider: NSItemProvider,
        completion: @escaping (Result<SharedPlaceImportCaptureInput?, Error>) -> Void
    ) {
        let callback = Callback(completion)
        let suggestedName = provider.suggestedName

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    callback.call(.failure(error))
                    return
                }
                guard let url = Self.url(from: item) else {
                    callback.call(.success(nil))
                    return
                }
                if url.isFileURL {
                    callback.call(Self.fileInput(from: url, fileName: suggestedName))
                } else {
                    callback.call(
                        .success(
                            .text(url.absoluteString, suggestedName: suggestedName)
                        )
                    )
                }
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(
                forTypeIdentifier: UTType.plainText.identifier,
                options: nil
            ) { item, error in
                if let error {
                    callback.call(.failure(error))
                    return
                }
                guard let text = Self.text(from: item) else {
                    callback.call(.success(nil))
                    return
                }
                callback.call(.success(.text(text, suggestedName: suggestedName)))
            }
            return
        }

        guard let typeIdentifier = supportedFileTypeIdentifier(for: provider) else {
            callback.call(.success(nil))
            return
        }
        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
            if let error {
                callback.call(.failure(error))
                return
            }
            guard let url else {
                callback.call(.failure(SharedPlaceImportInboxError.missingAttachment))
                return
            }
            callback.call(
                Self.fileInput(
                    from: url,
                    fileName: suggestedName,
                    contentTypeIdentifier: typeIdentifier
                )
            )
        }
    }

    private static func supportedFileTypeIdentifier(for provider: NSItemProvider) -> String? {
        let supportedTypes: [UTType] = [
            .commaSeparatedText,
            .json,
            .plainText,
            .rtf,
            UTType(filenameExtension: "md") ?? .plainText
        ]
        return provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return supportedTypes.contains(where: { type.conforms(to: $0) })
        }
    }

    private static func fileInput(
        from url: URL,
        fileName: String?,
        contentTypeIdentifier: String? = nil
    ) -> Result<SharedPlaceImportCaptureInput?, Error> {
        do {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = values?.fileSize,
               fileSize > SharedPlaceImportInbox.maximumFileBytes {
                throw SharedPlaceImportInboxError.fileTooLarge
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return .success(
                .file(
                    data,
                    fileName: fileName ?? url.lastPathComponent,
                    contentTypeIdentifier: contentTypeIdentifier
                )
            )
        } catch {
            return .failure(error)
        }
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let url = item as? NSURL {
            return url as URL
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

    private static func text(from item: NSSecureCoding?) -> String? {
        if let string = item as? String {
            return string
        }
        if let attributed = item as? NSAttributedString {
            return attributed.string
        }
        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}
