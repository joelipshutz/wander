# Astir onboarding and NUX — copy baseline

Build 174 · September 16, 2026 · 4a9f122c062d04db2f06e7b75226a9e85999169b

## N69 — Opening Astir
01 · Welcome · Active
Static opening/loading artwork. Opening Astir is an accessibility label, not visible copy. Native component layout reference from the approved source package.
Source: LoggedOutCarouselView.swift · OnboardingLaunchView

N69.01 [Artwork] ASTIR
N69.02 [Accessibility label] Opening Astir

## N70 — Loading your map
01 · Welcome · Active
Loading your map… appears below the fixed artwork. Native component layout reference from the approved source package.
Source: LoggedOutCarouselView.swift · OnboardingLaunchView

N70.01 [Artwork] ASTIR
N70.02 [Loading] Loading your map…

## N01 — Your place diary
01 · Welcome · Active
Carousel: auto-advances every 7 seconds; swipe manually. Get started is available from any slide.
Source: LoggedOutCarouselView.swift

N01.01 [Brand] ASTIR · OCEAN PARK
N01.02 [Eyebrow] YOUR PLACE DIARY
N01.03 [Headline] Everywhere you’ve been
N01.04 [Body] Build a map of the places worth remembering — with notes that bring every visit back.
N01.05 [Primary] Get started
N01.06 [Secondary] Already have an account? Log in

## N02 — Stay connected
01 · Welcome · Active
Carousel: auto-advances every 7 seconds; swipe manually. Get started is available from any slide.
Source: LoggedOutCarouselView.swift

N02.01 [Brand] ASTIR · OCEAN PARK
N02.02 [Eyebrow] STAY CONNECTED
N02.03 [Headline] Places your friends love
N02.04 [Body] Follow the people you know and keep their best finds close at hand.
N02.05 [Primary] Get started
N02.06 [Secondary] Already have an account? Log in

## N03 — Trusted discovery
01 · Welcome · Active
Carousel: auto-advances every 7 seconds; swipe manually. Get started is available from any slide.
Source: LoggedOutCarouselView.swift

N03.01 [Brand] ASTIR · OCEAN PARK
N03.02 [Eyebrow] TRUSTED DISCOVERY
N03.03 [Headline] Places through people you trust
N03.04 [Body] Skip anonymous reviews. Discover the spots that matter to people whose taste you know.
N03.05 [Primary] Get started
N03.06 [Secondary] Already have an account? Log in

## N04 — Create your account
02 · Account · Active
Email and Apple / Google are alternative paths; provider UI varies. Native Swift component preview with local fixture data.
Source: NativeAuthFlowView.swift

N04.01 [Headline] Create your account
N04.02 [Body] Keep your places synced and discover recommendations from people you trust.
N04.03 [Apple] Continue with Apple
N04.04 [Google] Continue with Google
N04.05 [Divider] or
N04.06 [Field] Email
N04.07 [Placeholder] you@example.com
N04.08 [Primary] Continue with email
N04.09 [Helper] If Apple or Google returns the same verified email, it connects to your existing Astir account.
N04.10 [Legal] By continuing, you agree to the Terms of Use and Community Guidelines, and acknowledge the Privacy Policy.

## N05 — Verify email
02 · Account · Active
Email route only. {address} is the email entered by the person signing up. Native Swift component preview with local fixture data.
Source: NativeAuthFlowView.swift

N05.01 [Headline] Check your email
N05.02 [Body] Enter the verification code sent to {address}.
N05.03 [Primary] Verify and continue
N05.04 [Resend] Send a new code
N05.05 [Back] Use another sign-in method
N05.06 [Placeholder] Verification code

## N06 — Returning account
02 · Account · Branch
Branch from “Already have an account? Log in”.
Source: NativeAuthFlowView.swift

N06.01 [Headline] Welcome back
N06.02 [Body] Sign in to get back to your saved places and people.
N06.03 [Apple] Sign in with Apple
N06.04 [Google] Sign in with Google
N06.05 [Divider] or
N06.06 [Field] Email
N06.07 [Primary] Continue with email
N06.08 [Secondary] Use a password
N06.09 [Helper] If Apple or Google returns the same verified email, it connects to your existing Astir account.
N06.10 [Legal] By continuing, you agree to the Terms of Use and Community Guidelines, and acknowledge the Privacy Policy.

## N07 — Password sign-in
02 · Account · Branch
Alternative returning-account route.
Source: NativeAuthFlowView.swift

N07.01 [Headline] Sign in with password
N07.02 [Body] Use the email and password for this account.
N07.03 [Email] Email
N07.04 [Password] Password
N07.05 [Primary] Sign in
N07.06 [Back] Use another sign-in method

## N08 — Your profile
03 · Profile & permissions · Active

Source: OnboardingFlowView.swift

N08.01 [Photo] Add a photo
N08.02 [Helper] Optional — you can always do this later.
N08.03 [Name] Name
N08.04 [Username] Username
N08.05 [Hint] 2–39 letters, numbers, or underscores
N08.06 [Primary] Continue
N08.07 [Name placeholder] How friends know you
N08.08 [Username placeholder] your_username

## N09 — Location primer
03 · Profile & permissions · Active
Skipped if already authorized. The system prompt follows Continue.
Source: OnboardingLocationMapPreview.swift

N09.01 [Eyebrow] AROUND YOU
N09.02 [Headline] Find the good stuff nearby
N09.03 [Body] See places your friends recommend and save spots around you without searching for an address.
N09.04 [Privacy] Your location is never shown to friends.
N09.05 [Primary] Continue

## N10 — Contacts primer
03 · Profile & permissions · Active

Source: OnboardingFlowView.swift

N10.01 [Eyebrow] ONE QUICK THING
N10.02 [Headline] Invite your people
N10.03 [Body] Choose someone to invite from your contacts. Your address book stays on this device and is not uploaded.
N10.04 [Benefit1] You choose each person
N10.05 [Benefit2] Invites open in Messages for you to send
N10.06 [Primary] Continue

## N11 — Choose people to follow
03 · Profile & permissions · Active
Successful selection state using fictional demo people. Real recommendations and reasons vary by account. Empty and loading-failure states follow in the conditional section.
Source: OnboardingFlowView.swift

N11.01 [Eyebrow] YOUR TRUSTED MAP
N11.02 [Headline] Astir is better with people
N11.03 [Body] Start with a few people whose taste you’d like to see. You’re always in control of who you follow.
N11.04 [Loading] Finding good people to follow…
N11.05 [Primary] Continue
N11.06 [Selected] Follow {count} person / people
N11.07 [Secondary] Skip
N11.08 [Recommendation reason] suggested for you
N11.09 [Recommendation reason] {count} mutual connections
N11.10 [Recommendation reason] follows you

## N12 — Notifications primer
03 · Profile & permissions · Active
System permission prompt follows. Already-enabled notifications skip this step.
Source: ProductUpsellCoordinator.swift

N12.01 [Eyebrow] STAY IN THE LOOP
N12.02 [Headline] See when your friends check in
N12.03 [Body] Get a heads-up when people you follow save a place or check in somewhere worth knowing.
N12.04 [Primary] Continue

## N13 — Saving a place
04 · First save walkthrough · Active
Advance by tapping the highlighted action.
Source: FirstVisitWalkthrough.swift:147

N13.01 [Headline] Saving a place
N13.02 [Body] Tap + and we’ll show you how a place becomes part of your map

## N14 — Finding a park near you
04 · First save walkthrough · Active
Auto demonstration; advances after its reading interval.
Source: FirstVisitWalkthrough.swift:164 · MapScreen.swift / AddScreen.swift

N14.01 [Headline] Finding a park near you
N14.02 [Body] We’ll choose a popular nearby park and show you how saving works
N14.03 [Sheet title] add a place
N14.04 [Body copy] find it nearby, search, or import
N14.05 [Section] Suggested
N14.06 [Placeholder] Search for a place
N14.07 [Section] Import
N14.08 [Action] Import from

## N15 — Have you been here before?
04 · First save walkthrough · Active
Branches into Check In or Wanna Go. Visited-only controls are skipped for Wanna Go.
Source: FirstVisitWalkthrough.swift:183 · MapScreen.swift / AddScreen.swift

N15.01 [Headline] Have you been here before?
N15.02 [Body] If so, select Check In. If not, select Wanna Go
N15.03 [Choice1] Check in
N15.04 [Choice2] Wanna go
N15.05 [Form prompt] what do you want to do?

## N16 — A date makes it a memory
04 · First save walkthrough · Active
Auto demonstration; advances after its reading interval.
Source: FirstVisitWalkthrough.swift:189 · MapScreen.swift / AddScreen.swift

N16.01 [Headline] A date makes it a memory
N16.02 [Body] We’ll choose one for this demo
N16.03 [Field] when

## N17 — Leave a note for future you
04 · First save walkthrough · Active
Auto demonstration; advances after its reading interval.
Source: FirstVisitWalkthrough.swift:198 · MapScreen.swift / AddScreen.swift

N17.01 [Headline] Leave a note for future you
N17.02 [Body] We’ll add one useful detail you’ll recognize later
N17.03 [Field] a note for future you
N17.04 [Placeholder] what you'll want to remember, who told you...

## N18 — A rating helps future you
04 · First save walkthrough · Active
Auto demonstration; advances after its reading interval.
Source: FirstVisitWalkthrough.swift:207

N18.01 [Headline] A rating helps future you
N18.02 [Body] Watch how a quick score captures how this place felt

## N19 — Add the detail you’ll remember
04 · First save walkthrough · Active
Auto demonstration; advances after its reading interval.
Source: FirstVisitWalkthrough.swift:216 · MapScreen.swift / AddScreen.swift

N19.01 [Headline] Add the detail you’ll remember
N19.02 [Body] A useful tag and short note make this place easier to rediscover
N19.03 [Section] more options
N19.04 [Privacy] stealth mode

## N20 — Why this place fits
04 · First save walkthrough · Active
Auto demonstration; advances after its reading interval.
Source: FirstVisitWalkthrough.swift:225 · MapScreen.swift / AddScreen.swift

N20.01 [Headline] Why this place fits
N20.02 [Body] We’ll choose one useful answer in each section for this park
N20.03 [Question] best for?
N20.04 [Selection] multi
N20.05 [Section] tags

## N21 — Tag it for later
04 · First save walkthrough · Active
Captured during the native automatic tag lesson. The coach extends below the simulator viewport; the full source copy is shown alongside for review.
Source: FirstVisitWalkthrough.swift:234 · MapScreen.swift / AddScreen.swift

N21.01 [Headline] Tag it for later
N21.02 [Body] One accurate tag makes this park easier to rediscover
N21.03 [Section] your tags
N21.04 [Helper] Tap any that fit. Selected tags stay in place so you can review or change them.
N21.05 [Custom] Add your own tag

## N22 — Ready to save
04 · First save walkthrough · Active
Auto demonstration; advances after its reading interval.
Source: FirstVisitWalkthrough.swift:243 · MapScreen.swift / AddScreen.swift

N22.01 [Headline] Ready to save
N22.02 [Body] The highlighted button puts everything you just watched onto your map
N22.03 [Primary action] Check in
N22.04 [Alternative action] Wanna go

## N23 — One more shortcut
04 · First save walkthrough · Active
Advance by tapping the highlighted action.
Source: FirstVisitWalkthrough.swift:148

N23.01 [Headline] One more shortcut
N23.02 [Body] Tap + again and we’ll show you where imports live

## N24 — Bring saves with you
04 · First save walkthrough · Active
Tap Next to continue to the sendoff.
Source: FirstVisitWalkthrough.swift:173

N24.01 [Headline] Bring saves with you
N24.02 [Body] Import your places and lists from Google Maps, Instagram, Tiktok, and more here
N24.03 [Primary] Next

## N25 — Your map is yours now
04 · First save walkthrough · Active
End of the current first-visit journey.
Source: FirstVisitWalkthrough.swift:151

N25.01 [Headline] Your map is yours now
N25.02 [Eyebrow] A thought for the road
N25.03 [Quote] “As you move through this life and this world you change things slightly. You leave marks behind, however small”
N25.04 [Attribution] — Anthony Bourdain
N25.05 [Closing] Keep the places that move you. Your map will remember the rest
N25.06 [Primary] Finish

## N26 — Return visit · Import
05 · Return visits & contextual · Active
Eligible on launch 2 or later, after the primary journey and before completion of this lesson.
Source: FirstVisitWalkthrough.swift:1932

N26.01 [Headline] Bring every saved place with you
N26.02 [Body] Paste one place, a few links, or a whole list from Maps, Instagram, TikTok, or Notes. Choose what to keep and mark each Check In or Wanna before anything reaches your map
N26.03 [Primary] Open import form
N26.04 [Help] Import help

## N27 — Return visit · Device features
05 · Return visits & contextual · Active
Eligible on launch 3 or later; shown once per enrolled account.
Source: FirstVisitWalkthrough.swift:2013

N27.01 [Headline] Astir, one press away
N27.02 [Body] Set these up once for faster saves
N27.03 [Feature1] Action Button + Controls
N27.04 [Instruction1] Choose Astir Check In for a one-press save
N27.05 [Feature2] Home + Lock Screen widgets
N27.06 [Instruction2] Keep Quick Add, Search, Activity, or Nearby in view
N27.07 [Feature3] Share extension
N27.08 [Instruction3] Send places from Maps, Instagram, TikTok, or Safari
N27.09 [Guide] Setup guide
N27.10 [Primary] Got it

## N28 — Notifications · After saving
05 · Return visits & contextual · Conditional
Contextual campaign, gated by notification state and impression limits. Not an extra mandatory onboarding step.
Source: ProductUpsellCoordinator.swift

N28.01 [Eyebrow] STAY IN THE LOOP
N28.02 [Headline] See when your friends check in
N28.03 [Body] Get a heads-up when people you follow save a place or check in somewhere worth knowing.
N28.04 [Primary] Continue

## N29 — Notifications · After following
05 · Return visits & contextual · Conditional
Contextual campaign, gated by notification state and impression limits. Not an extra mandatory onboarding step.
Source: ProductUpsellCoordinator.swift

N29.01 [Eyebrow] STAY IN THE LOOP
N29.02 [Headline] Keep up with people you follow
N29.03 [Body] Get a heads-up when they save a place or check in somewhere worth knowing.
N29.04 [Primary] Continue

## N30 — iOS · Location permission
06 · System & recovery states · System
iOS owns the headline and choices. The purpose string is app-owned.
Source: project.yml:100

N30.01 [Headline] Allow “Astir” to use your location?
N30.02 [Purpose] Astir uses your location to suggest nearby places when you ask and to keep an optional nearby widget useful. It never broadcasts live location.
N30.03 [Option1] Allow Once
N30.04 [Option2] Allow While Using App
N30.05 [Option3] Don’t Allow

## N31 — Location denied
06 · System & recovery states · Conditional
Denied permission: Open Settings / Not now. Restricted permission uses Continue without location.
Source: OnboardingPermissionManagers.swift

N31.01 [Primary] Open Settings
N31.02 [Secondary] Not now
N31.03 [Restricted] Continue without location

## N32 — Notifications denied
06 · System & recovery states · Conditional
 Native Swift component preview with local fixture data.
Source: ProductUpsellScreen.swift

N32.01 [Primary] Open Settings
N32.02 [Secondary] Not now
N32.03 [Working] Turning on notifications…

## N33 — No people yet
06 · System & recovery states · Conditional
 Native Swift component preview with local fixture data.
Source: OnboardingFlowView.swift

N33.01 [Headline] Your people will show up here
N33.02 [Body] Skip for now — we’ll keep finding trusted people as Astir grows.
N33.03 [Primary] Continue
N33.04 [Secondary] Skip

## N34 — People loading failed
06 · System & recovery states · Conditional
The captured demo shows this loading-failure fallback.
Source: OnboardingFlowView.swift

N34.01 [Headline] Suggestions are taking a minute
N34.02 [Body] You can skip this and find people from Discover anytime.
N34.03 [Primary] Continue
N34.04 [Secondary] Skip

## N35 — Username & saving states
06 · System & recovery states · Conditional
Checking-username state shown here. The next three cards show the remaining states separately; these original line references are preserved.
Source: OnboardingFlowView.swift

N35.01 [Checking] Checking username…
N35.02 [Available] Username available
N35.03 [Taken] That username is taken
N35.04 [Saving] Creating your profile…

## N71 — Username · available
06 · System & recovery states · Conditional
Native Swift identity view with this state held for review. Sample name and username are fixture content.
Source: OnboardingFlowView.swift

N71.01 [Status] Username available

## N72 — Username · taken
06 · System & recovery states · Conditional
Native Swift identity view with this state held for review. Sample name and username are fixture content.
Source: OnboardingFlowView.swift

N72.01 [Status] That username is taken

## N73 — Creating your profile
06 · System & recovery states · Conditional
Native Swift identity view with this state held for review. Sample name and username are fixture content.
Source: OnboardingFlowView.swift

N73.01 [Status] Creating your profile…

## N36 — iOS · Contacts purpose
06 · System & recovery states · Conditional
App-owned system permission purpose. Only shown when the related feature is used; not an additional onboarding step. Native Swift component preview with local fixture data. OS dialog rendered by the isolated preview app using the current app purpose string.
Source: project.yml:99

N36.01 [Purpose] Astir reads names and phone numbers on this device so you can choose someone to invite. Your address book is not uploaded; Messages receives only a number you select.
N36.02 [iOS headline] “Astir” would like to access your Contacts.
N36.03 [iOS option] Don’t Allow
N36.04 [iOS option] Continue

## N37 — Camera purpose
06 · System & recovery states · Conditional
App-owned system permission purpose. Only shown when the related feature is used; not an additional onboarding step. Native Swift component preview with local fixture data. OS dialog rendered by the isolated preview app using the current app purpose string.
Source: project.yml:97

N37.01 [Purpose] Astir uses the camera when you choose to take a profile or place photo, such as adding a restaurant photo to a saved place.
N37.02 [iOS headline] “Astir” would like to access the Camera.
N37.03 [iOS option] Don’t Allow
N37.04 [iOS option] Allow

## N38 — Calendar purpose
06 · System & recovery states · Conditional
App-owned system permission purpose. Only shown when the related feature is used; not an additional onboarding step. Native Swift component preview with local fixture data. OS dialog rendered by the isolated preview app using the current app purpose string.
Source: project.yml:98

N38.01 [Purpose] Astir reads restaurant reservations from Apple Calendar to prepare private check-in reminders. It syncs only the matched restaurant and reservation time—not raw calendar titles, notes, guests, URLs, or addresses.
N38.02 [iOS headline] “Astir” would like full access to your Calendar.
N38.03 [iOS option] Allow Full Access
N38.04 [iOS option] Don’t Allow

## N39 — Save to Photos purpose
06 · System & recovery states · Conditional
App-owned system permission purpose. Only shown when the related feature is used; not an additional onboarding step. Native Swift component preview with local fixture data. OS dialog rendered by the isolated preview app using the current app purpose string.
Source: project.yml:101

N39.01 [Purpose] Astir saves a share ticket to your photo library when you choose Save, Instagram Post, or TikTok.
N39.02 [iOS headline] “Astir” would like to add to your Photos.
N39.03 [iOS option] Don’t Allow
N39.04 [iOS option] Allow

## R40 — See your friend's check-ins in real time
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:254

R40.01 [Headline] See your friend's check-ins in real time
R40.02 [Body] Interact with your trusted feed with a like, comment, or share
R40.03 [Primary] Next

## R41 — Ask your circle for a place
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:261

R41.01 [Headline] Ask your circle for a place
R41.02 [Body] Tap search to open Discover and find places through the context your people saved

## R42 — Find people you trust
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:269

R42.01 [Headline] Find people you trust
R42.02 [Body] Search a name or @username to build the circle behind your map and feed
R42.03 [Primary] Next

## R43 — Astir gets better with your circle
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:278

R43.01 [Headline] Astir gets better with your circle
R43.02 [Body] Invite people whose taste you trust. The more people that join from your circle, the more useful your Astir space becomes
R43.03 [Primary] Next

## R44 — Search with the details you remember
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:288

R44.01 [Headline] Search with the details you remember
R44.02 [Body] Try a place name, category, neighborhood, person or @handle—or a saved tag like date night or work-friendly
R44.03 [Primary] Next

## R45 — Search the way you think
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:296

R45.01 [Headline] Search the way you think
R45.02 [Body] Tap an example or type your own search to turn a real-life need into trusted results

## R46 — Results preview
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:304

R46.01 [Headline] 
R46.02 [Body] 

## R47 — Every kind of plan, one tap away
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:317

R47.01 [Headline] Every kind of plan, one tap away
R47.02 [Body] My Lists keeps your plans, Friends shows lists people share, and Collabs keeps shared planning together
R47.03 [Primary] Next

## R48 — Turn saved places into a plan
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:328

R48.01 [Headline] Turn saved places into a plan
R48.02 [Body] Keep trips, date nights, neighborhoods, and anything else you want to revisit together
R48.03 [Primary] Next

## R49 — Three ratings, three jobs
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:344

R49.01 [Headline] Three ratings, three jobs
R49.02 [Body] Your rating is the average of your check-ins. Astir rating averages your network's ratings. And fit score predicts how well this place matches your taste
R49.03 [Primary] Next

## R50 — Everything you need to go
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:352

R50.01 [Headline] Everything you need to go
R50.02 [Body] Directions, Call, Website, and Reservation appear here whenever a place supports them
R50.03 [Primary] Next

## R51 — Every visit stays useful
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:360

R51.01 [Headline] Every visit stays useful
R51.02 [Body] Ever forget if that surf break you saved is left or right breaking? Check-in history captures that experience in memory with dates, ratings, notes, photos, friends, and tags
R51.03 [Primary] Keep going

## R52 — Only your Check Ins and Wanna places
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:381

R52.01 [Headline] Only your Check Ins and Wanna places
R52.02 [Body] 
R52.03 [Primary] Next

## R53 — Narrow in with More
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:382

R53.01 [Headline] Narrow in with More
R53.02 [Body] Filter by category, specific friends in your network, and distinguish between a check-in, wanna go, or both
R53.03 [Primary] Next

## R54 — Search your trusted map
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:390

R54.01 [Headline] Search your trusted map
R54.02 [Body] Try a place, neighborhood, or person
R54.03 [Primary] Next

## R55 — Your places, all connected
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:391

R55.01 [Headline] Your places, all connected
R55.02 [Body] Map, Feed, Lists, and Profile work together to help you find, plan, and remember
R55.03 [Primary] Next

## R56 — Open the place memory
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:399

R56.01 [Headline] Open the place memory
R56.02 [Body] Tap the highlighted place to revisit everything you just saved

## R57 — Make a list
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:425

R57.01 [Headline] Make a list
R57.02 [Body] Tap + to turn saved places into a plan you can use

## R58 — Plans from your people
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:426

R58.01 [Headline] Plans from your people
R58.02 [Body] Switch between your own lists, friends' lists, and shared collabs

## R59 — Open a plan
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:427

R59.01 [Headline] Open a plan
R59.02 [Body] Tap any list to see its places, map, privacy, and collaborators

## R60 — See the whole plan
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:430

R60.01 [Headline] See the whole plan
R60.02 [Body] Open the map to understand how every place fits together

## R61 — A place card at a glance
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:431

R61.01 [Headline] A place card at a glance
R61.02 [Body] The focused card keeps the place type, who saved it, and whether it’s a Check In or Wanna Go together
R61.03 [Primary] Next

## R62 — Name the plan
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:441

R62.01 [Headline] Name the plan
R62.02 [Body] Give this list a title you'll recognize when the moment comes
R62.03 [Primary] Next

## R63 — Plan it together
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:448

R63.01 [Headline] Plan it together
R63.02 [Body] Add collaborators so everyone can keep the list current
R63.03 [Primary] Next

## R64 — Choose who can see it
07 · Retained lessons · disabled · Disabled
Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.
Source: FirstVisitWalkthrough.swift:455

R64.01 [Headline] Choose who can see it
R64.02 [Body] Stealth is the final choice: keep the list private or share it with people who follow you
R64.03 [Primary] Next

## R65 — Featured shows you recommendations based on your taste
07 · Retained lessons · disabled · Disabled
Retained Map exploration lesson. Disabled in the current NUX.
Source: FirstVisitWalkthrough.swift:379; WanderEnums.swift:37

R65.01 [Headline] Featured shows you recommendations based on your taste
R65.02 [Primary] Next

## R66 — All places from everyone you follow
07 · Retained lessons · disabled · Disabled
Retained Map exploration lesson. Disabled in the current NUX.
Source: FirstVisitWalkthrough.swift:379; WanderEnums.swift:37

R66.01 [Headline] All places from everyone you follow
R66.02 [Primary] Next

## N67 — Crop profile photo
06 · System & recovery states · Conditional
Optional branch from Add a photo. Native photo picker precedes crop. Native Swift component preview with local fixture data.
Source: ProfilePhotoCropView.swift

N67.01 [Headline] Crop photo
N67.02 [Instruction] Pinch to zoom. Drag to reposition.
N67.03 [Cancel] Cancel
N67.04 [Primary] Choose
N67.05 [Saving] Saving…

## N68 — Account recovery
06 · System & recovery states · Conditional
Alternative recovery states. Error detail is supplied by the failed request. Continue offline appears only when eligible. Native Swift component preview with local fixture data.
Source: AppEntryView.swift

N68.01 [Headline] Your map is still here
N68.02 [Primary] Try again
N68.03 [Offline] Continue offline
N68.04 [Unavailable] Sign in isn’t available
