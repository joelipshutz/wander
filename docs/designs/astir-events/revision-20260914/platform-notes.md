# App Clip continuity and download offer

September 14, 2026. Platform notes for the engineering review; none establish that Astir has implemented or shipped these capabilities.

Apple supports recommending the full app from an App Clip using an installation overlay. That supports the approved optional offer after RSVP completes; the overlay is not a reason to require installation for guest-list or RSVP-management access. [Apple: recommending the full app](https://developer.apple.com/documentation/appclip/recommending-your-app-to-app-clip-users), [App Clips design guidance](https://developer.apple.com/design/human-interface-guidelines/app-clips).

Apple documents sharing data between a corresponding App Clip and full app, including shared storage/keychain and Sign in with Apple continuity. This makes an event/account handoff feasible, but does not establish that web cookies, a Google sign-in session, or every installation path automatically transfers. Verify the actual Astir identity provider, associated domains, App Clip invocation and installation return behavior in engineering. [Apple: sharing data between an App Clip and full app](https://developer.apple.com/documentation/appclip/sharing-data-between-your-app-clip-and-your-full-app).

App Clips are temporary experiences. Do not rely on their local data or notification permission as permanent RSVP storage or as the multi-day reminder channel. The approved SMS program remains available before installation. Recover the canonical server-side identity/reservation after expired sessions, removal, or reinstall; a shared event URL alone never proves ownership. [Apple Support: using App Clips](https://support.apple.com/en-us/102093).

The HTML and Swift design studies use local sample state. The installation offer, authentication, SMS, calendar, sharing, QR and recovery controls are illustrations, not connected services. The full public app/Clip release remains a launch prerequisite selected by the user, not an availability claim from this review.
