# Astir native onboarding — recording notes

Native build: REC-529 · native iOS review · September 17, 2026
Proposed copy below awaits a Swift revision.

## V01 — Welcome → create account
LoggedOutCarouselView.swift:196

V01.01 [Review focus] Welcome → create account

## W01 — Places benefit
LoggedOutCarouselView.swift:196

W01.01 [Example place] Circuit Coffee
W01.02 [Example category] Coffee · Silver Lake
Proposed: QA-only replacement to verify notes
Notes: QA-only transcript note
W01.03 [Example social detail] Maya + 2 friends · ★ 4.7
W01.04 [Compact-width alternative] 3 friends · ★ 4.7
W01.05 [Eyebrow] Example places
W01.06 [Headline] Keep track of everywhere you’ve been.
W01.07 [Primary] Next
W01.08 [Secondary] Already have an account? Log in

## W02 — People benefit
LoggedOutCarouselView.swift:238

W02.01 [Example actor] Mina
W02.02 [Example place] Marigold Table
W02.03 [Example metadata] Santa Monica · Restaurant
W02.04 [Example note] The patio at golden hour. Get the focaccia!
W02.05 [Eyebrow] Example activity
W02.06 [Headline] Keep up with the people you love.
W02.07 [Primary] Next
W02.08 [Secondary] Already have an account? Log in

## N04 — Create account
NativeAuthFlowView.swift:27

N04.01 [Headline] Create your account
N04.02 [Body] Keep your places synced and discover recommendations from people you trust.
N04.03 [Provider] Continue with Apple
N04.04 [Provider] Continue with Google
N04.05 [Divider] or
N04.06 [Field label] Email
N04.07 [Field placeholder] you@example.com
N04.08 [Primary] Continue with email
N04.09 [Account linking] If Apple or Google returns the same verified email, it connects to your existing Astir account.
N04.10 [Legal] By continuing, you agree to the Terms of Use and Community Guidelines, and acknowledge the Privacy Policy.
N04.11 [Secondary] Already have an account? Log in
N04.12 [Accessibility] Close

## N06 — Log in
NativeAuthFlowView.swift:27

N06.01 [Headline] Welcome back
N06.02 [Body] Sign in to get back to your saved places and people.
N06.03 [Provider] Sign in with Apple
N06.04 [Provider] Sign in with Google
N06.05 [Divider] or
N06.06 [Field label] Email
N06.07 [Field placeholder] you@example.com
N06.08 [Primary] Continue with email
N06.09 [Secondary] Use a password
N06.10 [Account linking] If Apple or Google returns the same verified email, it connects to your existing Astir account.
N06.11 [Legal] By continuing, you agree to the Terms of Use and Community Guidelines, and acknowledge the Privacy Policy.
N06.12 [Accessibility] Close

## N08 — Your profile
OnboardingFlowView.swift:142

N08.01 [Eyebrow] YOUR PROFILE
N08.02 [Name preview · empty fallback] Your name
N08.03 [Photo action · no photo] Add a photo
N08.04 [Photo action · existing photo] Change photo
N08.05 [Handle preview · empty fallback] @your_username
N08.06 [Field label] Name
N08.07 [Field placeholder] How friends know you
N08.08 [Field label] Username
N08.09 [Field prefix] @
N08.10 [Field placeholder] your_username
N08.11 [Username hint] 2–39 letters, numbers, or underscores
N08.12 [Primary] Continue
N08.13 [Primary · saving] Creating your profile…

## N09 — Location introduction
OnboardingLocationMapPreview.swift:4

N09.01 [Example place] Circuit Coffee
N09.02 [Example category] Coffee · Silver Lake
N09.03 [Example social detail] Maya + 2 friends · ★ 4.7
N09.04 [Compact-width alternative] 3 friends · ★ 4.7
N09.05 [Eyebrow] AROUND YOU
N09.06 [Headline] Find the good stuff nearby
N09.07 [Body] See places your friends recommend and save spots around you without searching for an address.
N09.08 [Privacy line · existing source] Your location is never shown to friends.
N09.09 [Primary] Continue
N09.10 [Primary · requesting] Requesting location…

## N10 — Contacts introduction
OnboardingFlowView.swift:56

N10.01 [Eyebrow] ONE QUICK THING
N10.02 [Headline] Invite your people
N10.03 [Body] Choose someone to invite from your contacts. Your address book stays on this device and is not uploaded.
N10.04 [Bullet] You choose each person
N10.05 [Bullet] Invites open in Messages for you to send
N10.06 [Primary] Continue
N10.07 [Primary · requesting] Opening settings…

## N11 — Find and follow people
OnboardingFriendSuggestionsView.swift:3

N11.01 [Eyebrow] YOUR PEOPLE
N11.02 [Headline] Connect with the people you love
N11.03 [Body] Follow a few familiar people. See where life takes them.
N11.04 [Search placeholder] Search name or username
N11.05 [Row action] Follow
N11.06 [Row action · followed] Following
N11.07 [Row error] Couldn’t follow. Tap to retry.
N11.08 [Primary] Continue
N11.09 [Loading] Finding people…
N11.10 [Search loading] Searching…
N11.11 [Search prompt title] Who are you looking for?
N11.12 [Search prompt body] Enter at least two letters of a name or username.
N11.13 [Empty search title] No people found
N11.14 [Empty search body] Try another name or username.
N11.15 [Search error title] Search couldn’t load
N11.16 [Search error body] Check your connection and try again.
N11.17 [Search retry] Try again
N11.18 [Accessibility] Clear search

## V05 — Notification cards arrive
ProductUpsellCoordinator.swift:56

V05.01 [Review focus] Notification cards arrive

## N12 — Notification introduction
ProductUpsellCoordinator.swift:56

N12.01 [Example notification app] ASTIR
N12.02 [Example notification time] now
N12.03 [Example notification title] Ryan checked in
N12.04 [Example notification body] A new place to discover.
N12.05 [Example notification app] ASTIR
N12.06 [Example notification time] now
N12.07 [Example notification title] Your import is ready
N12.08 [Example notification body] Your places are ready to review.
N12.09 [Example notification app] ASTIR
N12.10 [Example notification time] now
N12.11 [Example notification title] Mina followed you
N12.12 [Example notification body] Your circle is growing.
N12.13 [Eyebrow] STAY IN THE LOOP
N12.14 [Headline] See when your friends check in
N12.15 [Body] Get a heads-up when people you follow save a place or check in somewhere worth knowing.
N12.16 [Primary] Continue
N12.17 [Secondary · previously resolved permission] Not now
N12.18 [Primary · working] Turning on notifications…

## V06 — Full native map overview
FirstVisitWalkthrough.swift:152

V06.01 [Review focus] Full native map overview

## M01 — Featured
FirstVisitWalkthrough.swift:152

M01.01 [Map filter] Featured
M01.02 [Map filter] Friends
M01.03 [Map filter] You
M01.04 [Map filter] More
M01.05 [Coach headline] A place to start
M01.06 [Coach body] Featured brings together places chosen for you from check-ins, taste, and your network
M01.07 [Accessibility] Next
M01.08 [Search placeholder] search your map or people...
M01.09 [Navigation] Map
M01.10 [Navigation] Feed
M01.11 [Navigation] Lists
M01.12 [Navigation] Profile

## M02 — Friends
FirstVisitWalkthrough.swift:153

M02.01 [Map filter] Featured
M02.02 [Map filter] Friends
M02.03 [Map filter] You
M02.04 [Map filter] More
M02.05 [Coach headline] See where your people go
M02.06 [Coach body] Friends shows places saved by the people you follow
M02.07 [Accessibility] Next
M02.08 [Search placeholder] search your map or people...
M02.09 [Navigation] Map
M02.10 [Navigation] Feed
M02.11 [Navigation] Lists
M02.12 [Navigation] Profile

## M03 — More filters
FirstVisitWalkthrough.swift:154

M03.01 [Map filter] Featured
M03.02 [Map filter] Friends
M03.03 [Map filter] You
M03.04 [Map filter] More
M03.05 [Coach headline] Make the map your own
M03.06 [Coach body] Filter by category, people, Check Ins, or Wanna Go
M03.07 [Accessibility] Next
M03.08 [Panel title] More filters
M03.09 [Panel subtitle · Friends source] Narrow friends
M03.10 [Section] Categories
M03.11 [Section instruction] Choose one or more
M03.12 [Option] All
M03.13 [Expansion] More categories
M03.14 [Expansion · expanded] Show fewer categories
M03.15 [Section] People
M03.16 [Section instruction] Choose one or more
M03.17 [Option] All
M03.18 [People · empty] People you follow will appear here.
M03.19 [Section] Status
M03.20 [Section instruction] Choose one
M03.21 [Panel explanation] Choices combine across sections. If nothing matches, the map stays empty.
M03.22 [Panel action] Done
M03.23 [Panel action · filters selected] Reset
M03.24 [Navigation] Map
M03.25 [Navigation] Feed
M03.26 [Navigation] Lists
M03.27 [Navigation] Profile

## M04 — Map search
FirstVisitWalkthrough.swift:155

M04.01 [Map filter] Featured
M04.02 [Map filter] Friends
M04.03 [Map filter] You
M04.04 [Map filter] More
M04.05 [Coach headline] Find the place you have in mind
M04.06 [Coach body] Search for a place—or places from your people
M04.07 [Accessibility] Next
M04.08 [Search placeholder] search your map or people...
M04.09 [Navigation] Map
M04.10 [Navigation] Feed
M04.11 [Navigation] Lists
M04.12 [Navigation] Profile

## M05 — Plus
FirstVisitWalkthrough.swift:156

M05.01 [Map filter] Featured
M05.02 [Map filter] Friends
M05.03 [Map filter] You
M05.04 [Map filter] More
M05.05 [Coach headline] Keep a place for later
M05.06 [Coach body] Tap + to save a place or bring in saves from another app
M05.07 [Accessibility] Next
M05.08 [Search placeholder] search your map or people...
M05.09 [Navigation] Map
M05.10 [Navigation] Feed
M05.11 [Navigation] Lists
M05.12 [Navigation] Profile

## M06 — Pin legend
FirstVisitWalkthrough.swift:157

M06.01 [Map filter] Featured
M06.02 [Map filter] Friends
M06.03 [Map filter] You
M06.04 [Map filter] More
M06.05 [Coach headline] Read the rings
M06.06 [Coach body] Solid rings mean Check Ins. Dotted rings mean Wanna Go
M06.07 [Accessibility] Next
M06.08 [Search placeholder] search your map or people...
M06.09 [Legend] Check In
M06.10 [Legend] Wanna Go
M06.11 [Navigation] Map
M06.12 [Navigation] Feed
M06.13 [Navigation] Lists
M06.14 [Navigation] Profile

## N25 — Map finale
FirstVisitWalkthrough.swift:2850

N25.01 [Headline] Your map is yours now
N25.02 [Eyebrow] A thought for the road
N25.03 [Quote] “As you move through this life and this world you change things slightly. You leave marks behind, however small”
N25.04 [Attribution] — Anthony Bourdain
N25.05 [Closing] Keep the places that move you. Your map will remember the rest
N25.06 [Primary] Skip

## C01 — Plus / import hint
FirstVisitWalkthrough.swift:173

C01.01 [Coach headline] Bring saves with you
C01.02 [Coach body] Import places and lists from another app here
C01.03 [Accessibility] Next

## C02 — Feed hint
FirstVisitWalkthrough.swift:247

C02.01 [Coach headline] See what your people are discovering
C02.02 [Coach body] Explore check-ins from people you follow. Like, comment, or share
C02.03 [Accessibility] Next

## C03 — Lists hint
FirstVisitWalkthrough.swift:279

C03.01 [Coach headline] Every kind of plan, one tap away
C03.02 [Coach body] My Lists keeps your plans, Friends shows shared lists, and Collabs keeps shared planning together
C03.03 [Accessibility] Next

## C04 — Place actions hint
FirstVisitWalkthrough.swift:285

C04.01 [Coach headline] Everything you need to go
C04.02 [Coach body] Directions, Call, Website, and Reservation appear here whenever a place supports them
C04.03 [Accessibility] Next

## N27 — Device setup guide
FirstVisitWalkthrough.swift:2082

N27.01 [Headline] Astir, one press away
N27.02 [Body] Set these up once for faster saves
N27.03 [Feature] Action Button + Controls
N27.04 [Instruction] Choose Astir Check In for a one-press save
N27.05 [Feature] Home + Lock Screen widgets
N27.06 [Instruction] Keep Quick Add, Search, Activity, or Nearby in view
N27.07 [Feature] Share extension
N27.08 [Instruction] Send places from Maps, Instagram, TikTok, or Safari
N27.09 [Link] Setup guide
N27.10 [Primary] Got it

## N28 — Notifications after saving
ProductUpsellCoordinator.swift:63

N28.01 [Example notification app] ASTIR
N28.02 [Example notification time] now
N28.03 [Example notification title] Ryan checked in
N28.04 [Example notification body] A new place to discover.
N28.05 [Example notification app] ASTIR
N28.06 [Example notification time] now
N28.07 [Example notification title] Your import is ready
N28.08 [Example notification body] Your places are ready to review.
N28.09 [Example notification app] ASTIR
N28.10 [Example notification time] now
N28.11 [Example notification title] Mina followed you
N28.12 [Example notification body] Your circle is growing.
N28.13 [Eyebrow] STAY IN THE LOOP
N28.14 [Headline] See when your friends check in
N28.15 [Body] Get a heads-up when people you follow save a place or check in somewhere worth knowing.
N28.16 [Primary] Continue
N28.17 [Secondary · previously resolved permission] Not now
N28.18 [Primary · working] Turning on notifications…

## N29 — Notifications after following
ProductUpsellCoordinator.swift:70

N29.01 [Example notification app] ASTIR
N29.02 [Example notification time] now
N29.03 [Example notification title] Ryan checked in
N29.04 [Example notification body] A new place to discover.
N29.05 [Example notification app] ASTIR
N29.06 [Example notification time] now
N29.07 [Example notification title] Your import is ready
N29.08 [Example notification body] Your places are ready to review.
N29.09 [Example notification app] ASTIR
N29.10 [Example notification time] now
N29.11 [Example notification title] Mina followed you
N29.12 [Example notification body] Your circle is growing.
N29.13 [Eyebrow] STAY IN THE LOOP
N29.14 [Headline] Keep up with people you follow
N29.15 [Body] Get a heads-up when they save a place or check in somewhere worth knowing.
N29.16 [Primary] Continue
N29.17 [Secondary · previously resolved permission] Not now
N29.18 [Primary · working] Turning on notifications…

## N33 — No people yet
OnboardingFriendSuggestionsView.swift:82

N33.01 [Eyebrow] YOUR PEOPLE
N33.02 [Headline] Connect with the people you love
N33.03 [Body] Follow a few familiar people. See where life takes them.
N33.04 [Search placeholder] Search name or username
N33.05 [Empty title] Your people will show up here
N33.06 [Empty body] Skip for now — we’ll keep finding trusted people as Astir grows.
N33.07 [Primary] Continue

## N34 — People loading failed
OnboardingFriendSuggestionsView.swift:66

N34.01 [Eyebrow] YOUR PEOPLE
N34.02 [Headline] Connect with the people you love
N34.03 [Body] Follow a few familiar people. See where life takes them.
N34.04 [Search placeholder] Search name or username
N34.05 [Error title] Suggestions are taking a minute
N34.06 [Error body] You can skip this and find people from Discover anytime.
N34.07 [Retry] Try again
N34.08 [Primary] Continue

## N05 — Email verification
NativeAuthFlowView.swift:422

N05.01 [Headline] Check your email
N05.02 [Body · dynamic template] Enter the verification code sent to {address}.
N05.03 [Field placeholder] Verification code
N05.04 [Primary] Verify and continue
N05.05 [Secondary] Send a new code
N05.06 [Secondary] Use another sign-in method
N05.07 [Accessibility] Close

## N07 — Password sign-in
NativeAuthFlowView.swift:297

N07.01 [Headline] Sign in with password
N07.02 [Body] Use the email and password for this account.
N07.03 [Field label] Email
N07.04 [Field placeholder] you@example.com
N07.05 [Field label] Password
N07.06 [Field placeholder] Password
N07.07 [Primary] Sign in
N07.08 [Secondary] Use another sign-in method
N07.09 [Accessibility] Close

## N31 — Location denied / restricted
OnboardingPermissionManagers.swift:13

N31.01 [Example place] Circuit Coffee
N31.02 [Example category] Coffee · Silver Lake
N31.03 [Example social detail] Maya + 2 friends · ★ 4.7
N31.04 [Compact-width alternative] 3 friends · ★ 4.7
N31.05 [Eyebrow] AROUND YOU
N31.06 [Headline] Find the good stuff nearby
N31.07 [Body] See places your friends recommend and save spots around you without searching for an address.
N31.08 [Privacy line · existing source] Your location is never shown to friends.
N31.09 [Primary · denied] Open Settings
N31.10 [Secondary · denied] Not now
N31.11 [Primary · restricted] Continue without location
N31.12 [Primary · requesting] Requesting location…

## N32 — Notifications denied
OnboardingPermissionManagers.swift:51

N32.01 [Example notification app] ASTIR
N32.02 [Example notification time] now
N32.03 [Example notification title] Ryan checked in
N32.04 [Example notification body] A new place to discover.
N32.05 [Example notification app] ASTIR
N32.06 [Example notification time] now
N32.07 [Example notification title] Your import is ready
N32.08 [Example notification body] Your places are ready to review.
N32.09 [Example notification app] ASTIR
N32.10 [Example notification time] now
N32.11 [Example notification title] Mina followed you
N32.12 [Example notification body] Your circle is growing.
N32.13 [Eyebrow] STAY IN THE LOOP
N32.14 [Headline] See when your friends check in
N32.15 [Body] Get a heads-up when people you follow save a place or check in somewhere worth knowing.
N32.16 [Primary] Open Settings
N32.17 [Secondary] Not now
N32.18 [Primary · working] Turning on notifications…

## N35 — Username and profile states
OnboardingFlowView.swift:279

N35.01 [Eyebrow] YOUR PROFILE
N35.02 [Name preview · empty fallback] Your name
N35.03 [Photo action · no photo] Add a photo
N35.04 [Photo action · existing photo] Change photo
N35.05 [Handle preview · empty fallback] @your_username
N35.06 [Field label] Name
N35.07 [Field placeholder] How friends know you
N35.08 [Field label] Username
N35.09 [Field prefix] @
N35.10 [Field placeholder] your_username
N35.11 [Checking] Checking username…
N35.12 [Available] Username available
N35.13 [Taken] That username is taken
N35.14 [Idle hint] 2–39 letters, numbers, or underscores
N35.15 [Primary] Continue
N35.16 [Saving] Creating your profile…
N35.17 [Name validation] Add your name so friends can recognize you.
N35.18 [Name validation] Keep your name to 80 characters or fewer.
N35.19 [Username validation] Use 2–39 lowercase letters, numbers, or underscores.
N35.20 [Photo load error] That photo couldn’t be loaded. Try another one.
N35.21 [Photo upload error] Your photo couldn’t be saved. Check your connection and try again.
N35.22 [Required photo validation] Add a photo so your people can recognize you.

## N67 — Crop profile photo
ProfilePhotoCropView.swift:145

N67.01 [Title] Crop photo
N67.02 [Instruction] Pinch to zoom. Drag to reposition.
N67.03 [Secondary] Cancel
N67.04 [Primary] Choose
N67.05 [Primary · saving] Saving…
N67.06 [Error] That crop couldn’t be saved. Try again.

## N30 — iOS location permission
project.yml:100

N30.01 [App-owned permission purpose] Astir uses your location to suggest nearby places when you ask and to keep an optional nearby widget useful. It never broadcasts live location.

## N36 — iOS Contacts permission
project.yml:99

N36.01 [App-owned permission purpose] Astir reads names and phone numbers on this device so you can choose someone to invite. Your address book is not uploaded; Messages receives only a number you select.

## N37 — Camera purpose
project.yml:97

N37.01 [App-owned permission purpose] Astir uses the camera when you choose to take a profile or place photo, such as adding a restaurant photo to a saved place.

## N38 — Calendar purpose
project.yml:98

N38.01 [App-owned permission purpose] Astir reads restaurant reservations from Apple Calendar to prepare private check-in reminders. It syncs only the matched restaurant and reservation time—not raw calendar titles, notes, guests, URLs, or addresses.

## N39 — Save to Photos purpose
project.yml:101

N39.01 [App-owned permission purpose] Astir saves a share ticket to your photo library when you choose Save, Instagram Post, or TikTok.

## N12-system-permission — iOS notification permission
PushNotificationManager.swift


## N68 — Account recovery
AppEntryView.swift:123

N68.01 [Recoverable-error headline] Your map is still here
N68.02 [Unavailable headline] Sign in isn’t available
N68.03 [Primary] Try again
N68.04 [Conditional secondary] Continue offline

## N69 — Opening Astir
LoggedOutCarouselView.swift:365

N69.01 [Accessibility label] Opening Astir

## N70 — Loading your map
MapScreen.swift:2252

N70.01 [Loading message] Loading your map…

## Native captures pending

N05 — Email verification
N07 — Password sign-in
N31 — Location denied / restricted
N32 — Notifications denied
N35 — Username and profile states
N67 — Crop profile photo
N30 — iOS location permission
N36 — iOS Contacts permission
N37 — Camera purpose
N38 — Calendar purpose
N39 — Save to Photos purpose
N12-system-permission — iOS notification permission
N68 — Account recovery
N69 — Opening Astir
N70 — Loading your map
