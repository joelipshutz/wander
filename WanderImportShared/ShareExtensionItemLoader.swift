import Foundation
import UniformTypeIdentifiers

enum ShareExtensionItemLoader {
    private enum ProviderOutput {
        case url(URL, suggestedName: String?)
        case text(String, suggestedName: String?)
        case file(Data, fileName: String, contentTypeIdentifier: String?)
    }

    private final class Callback<Value>: @unchecked Sendable {
        let call: (Value) -> Void

        init(_ call: @escaping (Value) -> Void) {
            self.call = call
        }
    }

    private final class ProviderLoadingState: @unchecked Sendable {
        var outputs: [ProviderOutput] = []
        var firstError: Error?

        func record(_ error: Error) {
            firstError = firstError ?? error
        }
    }

    private final class ItemProviderBox: @unchecked Sendable {
        let value: NSItemProvider

        init(_ value: NSItemProvider) {
            self.value = value
        }
    }

    static func load(
        from contextItems: [Any],
        completion: @escaping (Result<[SharedPlaceImportCaptureInput], Error>) -> Void
    ) {
        let extensionItems = contextItems.compactMap { $0 as? NSExtensionItem }
        let providerCount = extensionItems.reduce(0) { partial, item in
            partial + (item.attachments?.count ?? 0)
        }
        guard !extensionItems.isEmpty else {
            completion(.failure(SharedPlaceImportInboxError.noSupportedContent))
            return
        }
        guard providerCount <= SharedPlaceImportInbox.maximumItemCount else {
            completion(.failure(SharedPlaceImportInboxError.tooManyItems))
            return
        }
        load(items: extensionItems, at: 0, accumulated: [], completion: completion)
    }

    private static func load(
        items: [NSExtensionItem],
        at index: Int,
        accumulated: [SharedPlaceImportCaptureInput],
        completion: @escaping (Result<[SharedPlaceImportCaptureInput], Error>) -> Void
    ) {
        guard index < items.count else {
            let deduplicated = deduplicate(accumulated)
            guard !deduplicated.isEmpty else {
                completion(.failure(SharedPlaceImportInboxError.noSupportedContent))
                return
            }
            guard deduplicated.count <= SharedPlaceImportInbox.maximumItemCount else {
                completion(.failure(SharedPlaceImportInboxError.tooManyItems))
                return
            }
            completion(.success(deduplicated))
            return
        }

        load(item: items[index]) { result in
            switch result {
            case .success(let inputs):
                do {
                    var totalBytes = accumulated.reduce(0) { $0 + payloadBytes($1) }
                    for input in inputs {
                        totalBytes = try SharedPlaceImportPayloadBudget.adding(
                            payloadBytes(input),
                            to: totalBytes
                        )
                    }
                } catch {
                    completion(.failure(error))
                    return
                }
                load(
                    items: items,
                    at: index + 1,
                    accumulated: accumulated + inputs,
                    completion: completion
                )
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func load(
        item: NSExtensionItem,
        completion: @escaping (Result<[SharedPlaceImportCaptureInput], Error>) -> Void
    ) {
        let providers = item.attachments ?? []
        load(providers: providers, at: 0, accumulated: []) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let outputs):
                let title = normalized(item.attributedTitle?.string)
                var textParts = [normalized(item.attributedContentText?.string)].compactMap { $0 }
                var urls: [(URL, String?)] = []
                var files: [SharedPlaceImportCaptureInput] = []

                for output in outputs {
                    switch output {
                    case .url(let url, let suggestedName):
                        if url.isFileURL {
                            switch fileInput(from: url, fileName: suggestedName) {
                            case .success(let input):
                                if let input { files.append(input) }
                            case .failure(let error):
                                completion(.failure(error))
                                return
                            }
                        } else {
                            urls.append((url, normalized(suggestedName) ?? title))
                        }
                    case .text(let text, _):
                        if let text = normalized(text) {
                            let detectedURLs = webURLs(in: text)
                            urls.append(contentsOf: detectedURLs.map { ($0, title) })
                            textParts.append(text)
                        }
                    case .file(let data, let fileName, let contentTypeIdentifier):
                        files.append(
                            .file(
                                data,
                                fileName: fileName,
                                contentTypeIdentifier: contentTypeIdentifier
                            )
                        )
                    }
                }

                let context = normalizedContext(
                    textParts,
                    removing: Set(urls.map { $0.0.absoluteString })
                )
                var inputs = urls.map { url, suggestedName in
                    SharedPlaceImportCaptureInput.sharedLink(
                        url,
                        contextText: context,
                        suggestedName: suggestedName ?? title
                    )
                }
                if urls.isEmpty, let context {
                    inputs.append(.text(context, suggestedName: title))
                }
                inputs.append(contentsOf: files)
                completion(.success(inputs))
            }
        }
    }

    private static func load(
        providers: [NSItemProvider],
        at index: Int,
        accumulated: [ProviderOutput],
        completion: @escaping (Result<[ProviderOutput], Error>) -> Void
    ) {
        guard index < providers.count else {
            completion(.success(accumulated))
            return
        }
        load(provider: providers[index]) { result in
            switch result {
            case .success(let outputs):
                do {
                    var totalBytes = accumulated.reduce(0) { $0 + payloadBytes($1) }
                    for output in outputs {
                        totalBytes = try SharedPlaceImportPayloadBudget.adding(
                            payloadBytes(output),
                            to: totalBytes
                        )
                    }
                } catch {
                    completion(.failure(error))
                    return
                }
                load(
                    providers: providers,
                    at: index + 1,
                    accumulated: accumulated + outputs,
                    completion: completion
                )
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func load(
        provider: NSItemProvider,
        completion: @escaping (Result<[ProviderOutput], Error>) -> Void
    ) {
        loadURL(
            from: ItemProviderBox(provider),
            state: ProviderLoadingState(),
            callback: Callback(completion)
        )
    }

    private static func loadURL(
        from provider: ItemProviderBox,
        state: ProviderLoadingState,
        callback: Callback<Result<[ProviderOutput], Error>>
    ) {
        guard provider.value.hasItemConformingToTypeIdentifier(UTType.url.identifier) else {
            loadText(from: provider, state: state, callback: callback)
            return
        }
        let suggestedName = provider.value.suggestedName
        provider.value.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
            if let error {
                state.record(error)
            } else if let url = url(from: item) {
                state.outputs.append(.url(url, suggestedName: suggestedName))
            }
            loadText(from: provider, state: state, callback: callback)
        }
    }

    private static func loadText(
        from provider: ItemProviderBox,
        state: ProviderLoadingState,
        callback: Callback<Result<[ProviderOutput], Error>>
    ) {
        guard provider.value.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else {
            loadFile(from: provider, state: state, callback: callback)
            return
        }
        let suggestedName = provider.value.suggestedName
        provider.value.loadItem(
            forTypeIdentifier: UTType.plainText.identifier,
            options: nil
        ) { item, error in
            if let error {
                state.record(error)
            } else if let url = webURL(from: item) {
                state.outputs.append(.url(url, suggestedName: suggestedName))
            } else if let text = text(from: item) {
                state.outputs.append(.text(text, suggestedName: suggestedName))
            }
            loadFile(from: provider, state: state, callback: callback)
        }
    }

    private static func loadFile(
        from provider: ItemProviderBox,
        state: ProviderLoadingState,
        callback: Callback<Result<[ProviderOutput], Error>>
    ) {
        guard let typeIdentifier = supportedFileTypeIdentifier(for: provider.value) else {
            finish(state: state, callback: callback)
            return
        }
        let suggestedName = provider.value.suggestedName
        provider.value.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
            if let error {
                state.record(error)
                finish(state: state, callback: callback)
                return
            }
            guard let url else {
                state.record(SharedPlaceImportInboxError.missingAttachment)
                finish(state: state, callback: callback)
                return
            }
            switch fileInput(
                from: url,
                fileName: suggestedName,
                contentTypeIdentifier: typeIdentifier
            ) {
            case .success(let input):
                if let input,
                   case .file(let data, let fileName, let contentTypeIdentifier) = input {
                    state.outputs.append(
                        .file(
                            data,
                            fileName: fileName,
                            contentTypeIdentifier: contentTypeIdentifier
                        )
                    )
                }
            case .failure(let error):
                state.record(error)
            }
            finish(state: state, callback: callback)
        }
    }

    private static func finish(
        state: ProviderLoadingState,
        callback: Callback<Result<[ProviderOutput], Error>>
    ) {
        if state.outputs.isEmpty, let firstError = state.firstError {
            callback.call(.failure(firstError))
        } else {
            callback.call(.success(state.outputs))
        }
    }

    private static func supportedFileTypeIdentifier(for provider: NSItemProvider) -> String? {
        let supportedTypes: [UTType] = [
            .commaSeparatedText,
            .json,
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
            guard data.count <= SharedPlaceImportInbox.maximumFileBytes else {
                throw SharedPlaceImportInboxError.fileTooLarge
            }
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

    private static func payloadBytes(_ output: ProviderOutput) -> Int {
        switch output {
        case .url(let url, _):
            Data(url.absoluteString.utf8).count
        case .text(let text, _):
            Data(text.utf8).count
        case .file(let data, _, _):
            data.count
        }
    }

    private static func payloadBytes(_ input: SharedPlaceImportCaptureInput) -> Int {
        switch input {
        case .text(let text, _):
            Data(text.utf8).count
        case .sharedLink(let url, let contextText, _):
            Data([url.absoluteString, contextText].compactMap { $0 }.joined(separator: "\n").utf8).count
        case .file(let data, _, _):
            data.count
        }
    }

    private static func normalizedContext(_ values: [String], removing urls: Set<String>) -> String? {
        var seen = Set<String>()
        let lines = values
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { line in
                urls.reduce(line) { partial, url in
                    partial.replacingOccurrences(of: url, with: "")
                }
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return normalized(lines.joined(separator: "\n"))
    }

    private static func deduplicate(
        _ inputs: [SharedPlaceImportCaptureInput]
    ) -> [SharedPlaceImportCaptureInput] {
        var seen = Set<String>()
        return inputs.filter { input in
            let key = switch input {
            case .text(let text, _):
                "text:\(text)"
            case .sharedLink(let url, let contextText, _):
                "link:\(url.absoluteString):\(contextText ?? "")"
            case .file(let data, let fileName, _):
                "file:\(fileName):\(data.hashValue)"
            }
            return seen.insert(key).inserted
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let string = item as? String { return URL(string: string) }
        return nil
    }

    private static func webURL(from item: NSSecureCoding?) -> URL? {
        guard let url = url(from: item),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    private static func webURLs(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range).compactMap { match in
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https"
            else { return nil }
            return url
        }
    }

    private static func text(from item: NSSecureCoding?) -> String? {
        if let string = item as? String { return string }
        if let attributed = item as? NSAttributedString { return attributed.string }
        if let data = item as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }
}
