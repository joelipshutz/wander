import Foundation
import Combine

@MainActor final class EventsInterestModel: ObservableObject {
    @Published private(set) var interest: EventsInterest?
    @Published private(set) var isSaving = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    private var userID: String?
    private var generation = 0
    private var loaded = false

    var isRegistered: Bool { interest != nil }

    /// Invalidate old-account completions before starting a new account's read.
    func load(userID: String?, repository: (any EventsInterestRepository)?) async {
        if self.userID != userID {
            generation += 1
            self.userID = userID
            interest = nil
            loaded = false
            isSaving = false
            isLoading = false
            errorMessage = nil
        }
        guard userID != nil, !loaded, !isLoading, !isSaving, let repository else { return }
        let request = generation
        isLoading = true
        defer { if request == generation { isLoading = false } }
        do {
            let saved = try await repository.currentInterest()
            try Task.checkCancellation()
            guard request == generation else { return }
            interest = saved
            loaded = true
        } catch {
            // A read failure leaves the orange button usable: registration is
            // idempotent and can confirm an existing record on the next tap.
        }
    }

    func register(repository: (any EventsInterestRepository)?) async {
        guard userID != nil, !isRegistered, !isSaving else { return }
        guard let repository else {
            errorMessage = "Couldn't save that yet. Please try again."
            return
        }
        // Supersede a pending read so its older nil result cannot undo success.
        generation += 1
        let request = generation
        isLoading = false
        isSaving = true
        errorMessage = nil
        defer { if request == generation { isSaving = false } }
        do {
            let saved = try await repository.registerInterest()
            guard request == generation else { return }
            interest = saved
            loaded = true
        } catch {
            guard request == generation else { return }
            errorMessage = "Couldn't save that yet. Please try again."
        }
    }
}
