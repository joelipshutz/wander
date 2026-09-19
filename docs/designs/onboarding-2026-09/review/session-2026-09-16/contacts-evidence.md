# Contacts: behavior, review history, and the N10/N11/N36 change

Original evidence recorded September 16, 2026 as a read-only investigation. Native implementation checkpoint added September 17; the historical evidence below is retained.

## September 17 implemented native copy

The user explicitly requested the concise high-level connection wording now implemented in the REC-529 review branch:

- N10 headline: **Connect with your people**
- N10 body: **Use your contacts to connect with people you know.**
- N36 purpose: **Astir uses your contacts to help you connect with people you know.**

The old no-upload and Messages details are removed from these two surfaces. This language describes connection through the existing Contacts-assisted invitation flow without claiming automatic matching to Astir accounts. The data flow, privacy behavior and native permission sequencing are unchanged. Real backend member search and immediate per-row Follow are implemented independently; automatic Contacts matching remains a separate functional dependency. The historical Apple record below does not mandate the exact prior disclaimer. The new purpose still needs verification in the regenerated app and a fresh system dialog; this source change is not a new App Review approval.

Source: [native Contacts primer](</Users/joelipshutz/Documents/ChatGPT/New project/wander-native-onboarding-review/Wander/Features/Onboarding/OnboardingFlowView.swift:56>) and [native system purpose](</Users/joelipshutz/Documents/ChatGPT/New project/wander-native-onboarding-review/project.yml:99>). The rest of this document describes the September 16 baseline investigation unless stated otherwise.

## Decision supported by the evidence — September 16 baseline

The requested direction is clear: N10 should introduce finding people; N11 should let someone search, follow existing members immediately, or invite a nonmember; N36 should explain that purpose concisely. **The current app does not yet match device contacts to existing Astir members.** Treat the find/follow promise as a product change with a functional dependency, not a copy-only correction.

The long no-upload/Messages disclosure was added to resolve a real September 8 App Review concern. The records show an internal response to that concern, not an Apple instruction requiring those exact sentences. Concise copy is possible, but the actual data flow must match the purpose, and the historical local-only explanation must be updated if matching changes that flow.

## Verified baseline behavior — September 16

Source inspected: `wander-release-174`, HEAD `4a9f122c062d04db2f06e7b75226a9e85999169b`. Relevant files had no difference against locally available `origin/main` `4937033a99175b2b22b48440a1376b644f6ad8e6`. This was a local source comparison, not a fresh remote fetch or new live-device/network test.

| Surface | Current behavior | Evidence |
|---|---|---|
| N10 Contacts primer | “Invite your people”; a neutral Continue requests native Contacts permission, then advances to friend suggestions. | [OnboardingFlowView.swift:56](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Onboarding/OnboardingFlowView.swift:56>) |
| Contacts data provider | Reads local contact identifier, formatted name, organization, and phone numbers. Uses the first nonempty phone number; excludes contacts without one. Every real row gets `handle: nil`, `userID: nil`, and false follow flags. | [ContactProvider.swift:86](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/ContactProvider.swift:86>), [ContactProvider.swift:119](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/ContactProvider.swift:119>) |
| Existing-member classification | A row is treated as an Astir member only when both handle and user ID exist. Real native contact rows therefore become contact-only rows; fake fixture rows can depict members. | [InviteFramework.swift:242](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Invites/InviteFramework.swift:242>) |
| Social contact rail | Filters out any contact without a user ID. The real provider's rows cannot populate it as matched members. | [WanderLocalStore.swift:5829](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/WanderLocalStore.swift:5829>) |
| N11 people suggestions | Loads backend profile recommendations, selects the first three, then follows the selected set on continuation. It does not load/match the address book. | [OnboardingFriendSuggestionsModel.swift:23](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Onboarding/OnboardingFriendSuggestionsModel.swift:23>), [OnboardingFlowView.swift:595](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Onboarding/OnboardingFlowView.swift:595>) |
| Invitation delivery | Sends selected numbers to the system Messages composer one recipient at a time; generic flow falls back to a share sheet if Messages cannot address the recipients. This is not automatic sending. The walkthrough-specific flow instead shows an error if Messages is unavailable. | [ContactInviteSheet.swift:976](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Invites/ContactInviteSheet.swift:976>), [ContactInviteSheet.swift:1393](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Invites/ContactInviteSheet.swift:1393>) |
| N36 iOS purpose | “Astir reads names and phone numbers on this device so you can choose someone to invite. Your address book is not uploaded; Messages receives only a number you select.” | [project.yml:99](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/project.yml:99>) |

The provider contains no network call. That supports the local-only implementation finding; it is not a replacement for an exact-candidate network inspection.

## App Review history

1. **REC-185, privacy audit, July–August.** The original issue said to remove Contacts until real contact matching existed, or implement the promised behavior. An August 13 comment expressly marked that removal instruction stale because native invitation selection had shipped as a local-only flow. It did **not** claim member matching had shipped. [Issue and comments](https://linear.app/recme/issue/REC-185/complete-app-store-privacy-manifests-labels-and-permission-audit).
2. **REC-396, September 1 rejection, build 156.** Apple objected to location's “Use my location” CTA and a pre-system “Not now” dismissal. The fix extended neutral Continue/Next and no pre-system skip across permission primers. A September 1 approval comment explicitly says **no explanatory body or Info.plist purpose-string changes** were in that permission fix. This issue does not explain or require the later no-upload/Messages text. [Issue and comments](https://linear.app/recme/issue/REC-396/fix-app-review-location-pre-prompt-and-audit-all-permission-flows).
3. **REC-469 / REC-470, September 8 rejection, build 169.** The review record reports Guideline 5.1.2: Apple believed Contacts were uploaded without clear notice or consent. The former string was “rec.me uses contacts only to help you find people you already know. It never messages anyone.” The internal remediation prescribed a more explicit local-only purpose, primer, and reviewer note. [Parent review issue](https://linear.app/recme/issue/REC-469/resolve-september-8-app-review-rejection-for-astir-10-169), [Contacts issue](https://linear.app/recme/issue/REC-470/clarify-local-only-contacts-handling-for-app-review).
4. **September 10 implementation.** REC-470's comment records the new no-upload/selected-number purpose string, an on-device primer, and reviewer notes. It also records clean-install granted/network checks as outstanding at that checkpoint. The local [before/after record](</Users/joelipshutz/Documents/ChatGPT/New project/app-review-before-after/README.md>) shows the actual wording change.
5. **September 14 review package.** Repository [reviewer notes](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/docs/app-store/reviewer-notes.txt:19>) and the local App Store Connect readback `app-review-validation/asc-inspection-sep14.json` repeat the local-only explanation. The workspace release checkpoint records build 173 resubmitted September 14. That does not establish that Apple approved the exact Contacts wording.

**Evidence limit:** I inspected the source, local before/after record, local review-note readback, and the four live Linear issues/comments. I did not retrieve the original Apple message directly from App Store Connect in this pass. The evidence supports “added to answer a specific Apple concern,” not “Apple mandated this exact text,” and it does not prove that a particular shorter replacement will pass review.

## Historical September 16 copy exploration

These drafts follow the transcript. Label the find/follow version **proposed behavior — requires contact matching** until implemented.

| Screen | Recommended draft | State |
|---|---|---|
| N10 headline | Find your people | Proposed |
| N10 body | Find people you know on Astir. | Proposed; requires matching |
| N10 primary | Continue | Retain the reviewed neutral permission action |
| N11 headline option A | Connect with the people you love | Transcript callback option |
| N11 headline option B | Create your Astir circle | Transcript option |
| N11 search | Search name or username | Requires search wiring |
| N11 row actions | Follow → Following; Invite for nonmembers | Requires new immediate-action behavior and matched/nonmember results |
| N36 purpose | Astir uses your contacts to help you find and follow people you know. | Concise proposed purpose; requires actual matching |

The no-upload and Messages implementation details can leave the proposed N10/N36 copy exploration as requested. Preserve the review evidence in this document and the implementation task; do not present the new language as current shipping behavior. The purpose still identifies the resource and concrete benefit without those disclaimers.

If copy must ship before matching exists, the truthful shorter purpose is: **“Astir uses contact names and phone numbers so you can choose people to invite.”** This is an interim implementation-aligned alternative, not the product direction selected in the transcript.

## Functional tasks required by N10/N11/N36

- [ ] Build real contact-to-member discovery. Define which identifier is matched, phone normalization, treatment of multiple numbers, limited Contacts access, and member discoverability rules. Existing fake `ContactMatch` member fixtures must not be mistaken for production support.
- [ ] Specify matching's data flow before finalizing the shipped permission copy: what stays on device, what is sent (if anything), the explicit user action, and retention. Update the existing privacy/reviewer descriptions to match the actual implementation. The old “address book stays on device” statement is only reusable if still true.
- [ ] Replace N11's preselected/multiselect batch follow with an immediate Follow/Following button per member row. Preserve individual failure/retry behavior without losing the list.
- [ ] Add name/username search and combine member results with unmatched contacts and distinct Invite actions, as requested. Rank using real available signals; do not describe fabricated “frequently contacted” or mutual labels.
- [ ] Keep invitation composition as a separate action. Explicit tap opens a populated system composer; handle cancellation, unavailable Messages, and returned-to-app state. Never imply the app silently sent an invitation.
- [ ] Verify the exact new experience for full/limited/denied Contacts, no contacts, no matches, already-followed users, search, follow failure, invitation cancellation, and network failure.
- [ ] Verify exact-candidate network behavior and synchronize N10, N36, contextual Contacts copy, settings trust copy, reviewer notes, and privacy disclosures with the implemented flow. Existing Settings copy already loosely says “find people you know”; do not use that loose wording as proof of matching.

## Work status

The September 16 evidence task was read-only. The September 17 native review branch now has concise N10/N36 connect copy, actual member search and per-row Follow; see the current checkpoint above. Automatic contact matching remains unimplemented. No production deployment, account/settings change or new App Review approval is asserted.
