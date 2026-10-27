import SwiftUI

@MainActor
final class RecentPlaceListAddController: ObservableObject {
    @Published var pickerTarget: MapPlaceListTarget?
    @Published private(set) var isAdding = false
    @Published private(set) var toast: String?
    @Published private(set) var allowsChange = false
    private var target: MapPlaceListTarget?
    private var accountID: String?
    private var requestID = UUID()
    private var lastAutomaticListID: String?
    private var replacingAutomaticListID: String?
    private var toastTask: Task<Void, Never>?
    var analyticsSurface = "map"

    func add(_ target: MapPlaceListTarget, store: WanderStore, backend: WanderBackend,
             analyticsSurface: String = "map") {
        guard !isAdding else { return }
        self.analyticsSurface = analyticsSurface
        self.target = target
        accountID = store.currentUser.id
        lastAutomaticListID = nil; replacingAutomaticListID = nil
        toast = nil
        guard let list = RecentPlaceListChoice.shared.resolve(accountID: store.currentUser.id,
                lists: store.visiblePlaceLists.filter(store.canAddPlaces)) else {
            pickerTarget = target
            return
        }
        let viewerID = store.currentUser.id
        let request = UUID(); requestID = request
        let notificationPolicy = RecentPlaceListChoice.shared.notificationPolicy
        isAdding = true
        Task { @MainActor [weak self] in
            let result = await target.add(to: list, store: store, backend: backend,
                analyticsSurface: analyticsSurface, keepNewCompanionPrivate: list.visibility == .stealth,
                senderNotificationPolicy: notificationPolicy)
            guard let self, self.requestID == request, store.currentUser.id == viewerID else { return }
            self.isAdding = false
            switch result.outcome {
            case .added:
                self.lastAutomaticListID = list.localID
                RecentPlaceListChoice.shared.remember(list, accountID: viewerID,
                    notificationPolicy: notificationPolicy)
                self.showToast(self.additionMessage(for: target, list: list, store: store), allowsChange: true)
            case .alreadyInList:
                self.showToast(self.additionMessage(for: target, list: list, store: store, alreadyAdded: true), allowsChange: true)
            case .permissionDenied:
                RecentPlaceListChoice.shared.clear()
                self.showToast("Couldn’t add this place. Choose a list to try again.", allowsChange: true)
            }
        }
    }

    func change() {
        guard let target, !isAdding else { return }
        replacingAutomaticListID = lastAutomaticListID
        pickerTarget = target
        toastTask?.cancel(); toast = nil
    }

    func completed(_ result: MapPlaceListPickerResult, store: WanderStore, backend: WanderBackend) {
        guard accountID == store.currentUser.id else { reset(); return }
        pickerTarget = nil
        let destinations = store.visiblePlaceLists.filter { result.destinationListIDs.contains($0.id) }
        let newListIDs = Set(destinations.map(\.localID))
        let previous = replacingAutomaticListID.flatMap { previousID in
            store.visiblePlaceLists.first { $0.localID == previousID }
        }
        replacingAutomaticListID = nil
        // Each toast owns only the membership this action actually created.
        // Carry that identity forward through repeated Change actions, without
        // ever treating an already-existing destination as removable.
        let replaceableID = RecentPlaceListReplacementPolicy.replaceableDestinationID(
            destinationIDs: result.destinationListIDs, newlyAddedIDs: result.newlyAddedListIDs)
        lastAutomaticListID = destinations.first { $0.id == replaceableID }?.localID
        let text: String
        if destinations.count == 1, let target {
            text = additionMessage(for: target, list: destinations[0], store: store)
        } else {
            text = result.message
        }
        guard let previous, !newListIDs.isEmpty, !newListIDs.contains(previous.localID), let target else {
            showToast(text, allowsChange: result.addedCount > 0)
            return
        }
        guard result.deniedCount == 0, destinations.allSatisfy({
            membershipState(for: target, list: $0, store: store) == .synced
        }) else {
            showToast("\(text). Also kept in \(previous.name) because the new addition hasn’t synced.", allowsChange: true)
            return
        }
        guard store.canManage(previous) else {
            // Collaborators can add but only a list owner can remove membership.
            showToast("\(text). Also kept in \(previous.name).", allowsChange: true)
            return
        }
        // Change only undoes this controller's just-created addition, after a
        // replacement succeeds. Cancelling, existing membership, and another
        // account's additions can never be removed by this convenience.
        guard let membership = membershipPlace(for: target, list: previous, store: store) else {
            showToast("\(text). The previous list could not be updated.", allowsChange: true)
            return
        }
        let viewerID = store.currentUser.id
        let request = requestID
        isAdding = true
        Task { @MainActor [weak self] in
            // Search candidates can resolve to a different canonical place ID.
            // Remove the actual existing membership, never the provider input ID.
            let removed = await store.removePlace(placeID: membership.place.id, visiblePlaceID: membership.id,
                from: previous, backend: backend)
            guard let self, self.requestID == request, store.currentUser.id == viewerID else { return }
            self.isAdding = false
            self.showToast(removed && store.lastRemoteError == nil ? text
                : "\(text). The previous list could not be updated.", allowsChange: true)
        }
    }

    func reset() {
        requestID = UUID(); toastTask?.cancel(); pickerTarget = nil
        target = nil; accountID = nil; toast = nil; isAdding = false; allowsChange = false
        lastAutomaticListID = nil; replacingAutomaticListID = nil
    }

    private func membershipPlace(for target: MapPlaceListTarget, list: LocalPlaceList,
                                 store: WanderStore) -> VisiblePlace? {
        store.visiblePlaces(in: list).first { member in
            switch target {
            case .visiblePlace(let place): VisiblePlaceGrouping.matches(member, place)
            case .candidate(let candidate): VisiblePlaceGrouping.matches(member, candidate: candidate)
            }
        }
    }

    private func membershipState(for target: MapPlaceListTarget, list: LocalPlaceList,
                                 store: WanderStore) -> RecentPlaceListMembershipState {
        guard let member = membershipPlace(for: target, list: list, store: store) else { return .missing }
        let currentList = store.visiblePlaceLists.first { $0.localID == list.localID } ?? list
        let placeIDs = Set([member.place.id, member.place.localID, member.place.serverID].compactMap { $0 })
        let listIDs = Set([currentList.id, currentList.localID, currentList.serverID].compactMap { $0 })
        let items = store.placeListItems.filter {
            listIDs.contains($0.listID) && placeIDs.contains($0.placeID) && $0.deletedAt == nil
        }
        return RecentPlaceListMembershipState.resolve(list: currentList, items: items)
    }

    private func additionMessage(for target: MapPlaceListTarget, list: LocalPlaceList,
                                 store: WanderStore, alreadyAdded: Bool = false) -> String {
        switch membershipState(for: target, list: list, store: store) {
        case .synced: return "\(alreadyAdded ? "Already in" : "Added to") \(list.name)"
        case .pending: return "Added to \(list.name) on this phone · waiting to sync"
        case .failed: return "Added to \(list.name) on this phone · couldn’t sync"
        case .missing: return "Couldn’t confirm the addition to \(list.name). Try again."
        }
    }

    private func showToast(_ message: String, allowsChange: Bool) {
        toastTask?.cancel()
        toast = message; self.allowsChange = allowsChange
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}

private struct RecentPlaceListAddPresentation: ViewModifier {
    @ObservedObject var controller: RecentPlaceListAddController
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.astirBrandMode) private var brand

    func body(content: Content) -> some View {
        content
            .sheet(item: $controller.pickerTarget) { target in
                MapPlaceListPickerSheet(target: target, analyticsSurface: controller.analyticsSurface) { result in
                    controller.completed(result, store: store, backend: backend)
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = controller.toast {
                    HStack(spacing: 12) {
                        Text(toast).font(AstirTypography.bodySmall).foregroundStyle(brand.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if controller.allowsChange {
                            Button("Change", action: controller.change)
                                .font(AstirTypography.control).foregroundStyle(brand.accentText)
                                .underline().frame(minWidth: 44, minHeight: 44)
                                .accessibilityIdentifier("place-list.quick-add.change")
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 16).padding(.bottom, 12)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("place-list.quick-add.toast")
                }
            }
            .onChange(of: store.currentUser.id) { _, _ in
                controller.reset(); RecentPlaceListChoice.shared.clear()
            }
            .onChange(of: auth.isSignedIn) { _, signedIn in
                if !signedIn { controller.reset(); RecentPlaceListChoice.shared.clear() }
            }
    }
}

extension View {
    func recentPlaceListAddPresentation(_ controller: RecentPlaceListAddController) -> some View {
        modifier(RecentPlaceListAddPresentation(controller: controller))
    }
}
