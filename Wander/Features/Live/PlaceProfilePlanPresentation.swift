import SwiftUI

/// The place-profile action enters the same checked friend picker and invitation
/// composer used by Live. Opening Plans never creates or sends an invitation.
struct PlaceProfilePlanPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let source: VisiblePlace?
    let onSaveWanna: () -> Void
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @Environment(\.astirBrandMode) private var brand
    @State private var plan: CommonGroundMockPlace?
    @State private var wantsSave = false
    @State private var wantsPeople = false

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: {
            plan = nil
            if wantsSave { wantsSave = false; onSaveWanna() }
            if wantsPeople { wantsPeople = false; pushNotifications.route(to: .people(.friends)) }
        }) {
            NavigationStack {
                Group {
                    if let source {
                        LivePlanPeoplePicker(place: source, onSelect: { plan = $0 }, sourceContext: .placeProfile,
                            onFindPeople: { wantsPeople = true; isPresented = false },
                            onOpenPlace: { _ in wantsSave = true; isPresented = false })
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "calendar.badge.plus").font(.largeTitle)
                            Text("Start with a Wanna").font(AstirTypography.screenTitle)
                            Text("Save this place, then choose a mutual friend who has it in common.")
                                .font(AstirTypography.body).foregroundStyle(brand.secondaryText)
                            Button("Save Wanna") { wantsSave = true; isPresented = false }
                                .font(AstirTypography.control).foregroundStyle(brand.accentText)
                                .frame(minHeight: 44)
                        }
                        .padding(24).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(brand.background)
                        .navigationTitle("Plans").navigationBarTitleDisplayMode(.inline)
                    }
                }
                .navigationDestination(item: $plan) { selected in
                    CommonGroundInvitationMockup(
                        draft: CommonGroundInvitationDraft(place: selected), liveSharing: true,
                        analytics: store.productAnalytics,
                        canShare: { candidate in
                            CommonGroundLiveData.places(store: store, profileID: candidate.partner.id).contains(candidate)
                        }, prepareShare: { draft in
                            try await CommonGroundInvitationSharing.prepare(draft: draft, backend: backend, brand: brand)
                        })
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { isPresented = false }
                    }
                }
            }
        }
        .onChange(of: store.currentUser.id) { _, _ in
            wantsSave = false; wantsPeople = false; plan = nil; isPresented = false
        }
    }
}
