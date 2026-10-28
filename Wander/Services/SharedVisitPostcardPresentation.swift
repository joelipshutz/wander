import Foundation

/// One presentation of authorized originals. Invite identities are separate
/// from contributions: a pending profile can never add a note or photo.
struct SharedVisitPostcardPresentation {
    let context: ActivityEngagementContext
    let posts: [FeedActivity]
    let companions: [ProfileShell]

    init?(collection: SharedVisitPostCollection, viewerID: String,
          permits: (ProfileShell) -> Bool) {
        guard let target = collection.commentTarget, permits(target.actor),
              let original = target.activityEngagementContext else { return nil }
        posts = collection.posts.filter { permits($0.actor) }
        var seenProfiles: Set<String> = [target.actor.id]
        var profiles = posts.compactMap { post in
            seenProfiles.insert(post.actor.id).inserted ? post.actor : nil
        }
        for companion in collection.companions where permits(companion.profile) {
            let permittedStatus = companion.status == .owner || companion.status == .accepted
                || (companion.status == .pending && target.actor.id == viewerID)
            if permittedStatus, seenProfiles.insert(companion.profile.id).inserted {
                profiles.append(companion.profile)
            }
        }
        companions = profiles
        var seenMedia = Set<String>()
        let media = posts.flatMap { $0.activityEngagementContext?.media ?? [] }
            .filter { seenMedia.insert($0.id).inserted }
        context = ActivityEngagementContext(activityID: original.activityID, actor: original.actor,
            placeName: original.placeName, placeServerID: original.placeServerID, placeDetail: original.placeDetail,
            ticketKind: original.ticketKind, occurredAt: original.occurredAt, plannedDate: original.plannedDate,
            sourceUserPlaceID: original.sourceUserPlaceID, note: original.note, rating: original.rating,
            ticketEyebrow: original.ticketEyebrow, attributionAction: original.attributionAction,
            listContext: original.listContext, media: media)
    }

    var mediaAuthors: [String: ProfileShell] {
        var authors: [String: ProfileShell] = [:]
        for post in posts {
            for media in post.activityEngagementContext?.media ?? [] where authors[media.id] == nil {
                authors[media.id] = post.actor
            }
        }
        return authors
    }

    var attribution: String {
        let names = companions.map(\.displayName)
        guard !names.isEmpty else { return "\(context.actor.displayName) Checked-In" }
        return "\(context.actor.displayName) Checked-In With \(ListFormatter.localizedString(byJoining: names))"
    }
}

/// Missing and authoritatively empty membership differ. Only the involved visits
/// invalidate a shared surface; sorted, length-prefixed fields avoid ambiguous keys.
enum SharedVisitMembershipSnapshot {
    static func key(visitIDs: [String], cache: [String: [SharedVisitCompanion]]) -> String {
        func field(_ value: String) -> String { "\(value.utf8.count):\(value)" }
        return Set(visitIDs).sorted().map { visitID in
            guard let members = cache[visitID] else { return field(visitID) + "missing" }
            let identities = members.map { member in
                [member.userID, member.handle, member.displayName, member.avatarURL ?? ""].map(field).joined()
            }.sorted().map(field).joined()
            return field(visitID) + "loaded" + field(identities)
        }.map(field).joined()
    }
}
