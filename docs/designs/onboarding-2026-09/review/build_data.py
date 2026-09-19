import json,re,pathlib,subprocess
R=pathlib.Path(__file__).parent
SRC=R.parent/'wander-release-174'
O=SRC/'Wander/Features/Onboarding'
nodes=[]
def add(key,title,group,lines,img=None,note='',state='Active',source='',after=None):
 n=dict(key=key,title=title,group=group,lines=[dict(role=r,text=t) for r,t in lines],image=img,note=note,state=state,source=source,after=after)
 nodes.append(n);return n
def L(**kw):return list(kw.items())
for i,m in enumerate(re.finditer(r'eyebrow: "([^"]+)",\s*title: "([^"]+)",\s*body: "([^"]+)"',(O/'LoggedOutCarouselView.swift').read_text())):
 add('welcome-'+str(i+1),['Your place diary','Stay connected','Trusted discovery'][i],'01 · Welcome',L(Brand='ASTIR · OCEAN PARK',Eyebrow=m[1],Headline=m[2],Body=m[3],Primary='Get started',Secondary='Already have an account? Log in'),f'welcome-{i+1}.png','Carousel: auto-advances every 7 seconds; swipe manually. Get started is available from any slide.',source='LoggedOutCarouselView.swift')
add('signup','Create your account','02 · Account',L(Headline='Create your account',Body='Keep your places synced and discover recommendations from people you trust.',Apple='Continue with Apple',Google='Continue with Google',Divider='or',Field='Email',Placeholder='you@example.com',Primary='Continue with email',Helper='If Apple or Google returns the same verified email, it connects to your existing Astir account.',Legal='By continuing, you agree to the Terms of Use and Community Guidelines, and acknowledge the Privacy Policy.'),note='Email and Apple / Google are alternative paths; provider UI varies.',source='NativeAuthFlowView.swift')
add('verify','Verify email','02 · Account',L(Headline='Check your email',Body='Enter the verification code sent to {address}.',Primary='Verify and continue',Resend='Send a new code',Back='Use another sign-in method'),note='Email route only. {address} is the email entered by the person signing up.',source='NativeAuthFlowView.swift')
add('auth','Returning account','02 · Account',L(Headline='Welcome back',Body='Sign in to get back to your saved places and people.',Apple='Sign in with Apple',Google='Sign in with Google',Divider='or',Field='Email',Primary='Continue with email',Secondary='Use a password',Helper='If Apple or Google returns the same verified email, it connects to your existing Astir account.',Legal='By continuing, you agree to the Terms of Use and Community Guidelines, and acknowledge the Privacy Policy.'),'auth.png',note='Branch from “Already have an account? Log in”.',source='NativeAuthFlowView.swift',state='Branch')
add('password','Password sign-in','02 · Account',L(Headline='Sign in with password',Body='Use the email and password for this account.',Email='Email',Password='Password',Primary='Sign in',Back='Use another sign-in method'),note='Alternative returning-account route.',source='NativeAuthFlowView.swift',state='Branch')
add('identity','Your profile','03 · Profile & permissions',L(Photo='Add a photo',Helper='Optional — you can always do this later.',Name='Name',Username='Username',Hint='2–39 letters, numbers, or underscores',Primary='Continue'),'identity.png',source='OnboardingFlowView.swift')
add('location','Location primer','03 · Profile & permissions',L(Eyebrow='AROUND YOU',Headline='Find the good stuff nearby',Body='See places your friends recommend and save spots around you without searching for an address.',Privacy='Your location is never shown to friends.',Primary='Continue'),'location.png',note='Skipped if already authorized. The system prompt follows Continue.',source='OnboardingLocationMapPreview.swift')
add('contacts','Contacts primer','03 · Profile & permissions',L(Eyebrow='ONE QUICK THING',Headline='Invite your people',Body='Choose someone to invite from your contacts. Your address book stays on this device and is not uploaded.',Benefit1='You choose each person',Benefit2='Invites open in Messages for you to send',Primary='Continue'),'contacts.png',source='OnboardingFlowView.swift')
add('friends','Choose people to follow','03 · Profile & permissions',L(Eyebrow='YOUR TRUSTED MAP',Headline='Astir is better with people',Body='Start with a few people whose taste you’d like to see. You’re always in control of who you follow.',Loading='Finding good people to follow…',Primary='Continue',Selected='Follow {count} person / people',Secondary='Skip'),'friends.png',note='People and reasons vary by account. The captured demo shows the fallback state.',source='OnboardingFlowView.swift')
add('notifications','Notifications primer','03 · Profile & permissions',L(Eyebrow='STAY IN THE LOOP',Headline='See when your friends check in',Body='Get a heads-up when people you follow save a place or check in somewhere worth knowing.',Primary='Continue'),'notifications.png',note='System permission prompt follows. Already-enabled notifications skip this step.',source='ProductUpsellCoordinator.swift')
# Parse actual Swift step content and preserve the display-time punctuation transformation.
text=(O/'FirstVisitWalkthrough.swift').read_text(); allsteps=[]
pat=r'step\(\s*\.(\w+),\s*\.(\w+),\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"'
for m in re.finditer(pat,text):
 start=m.start(); end=text.find(')',m.end()); extras=text[m.end():end]
 surface,target,title,body=m.groups(); body=body.rstrip('.')
 allsteps.append((target,title,body,surface,extras,text[:start].count('\n')+1,start))
lookup={x[0]:x for x in allsteps if x[6]<text.index('static let suppressedMapExplorationSteps')}
active=['mapAdd','addSearch','saveStatus','saveDate','saveNote','saveRating','saveMoreOptions','saveQuestions','saveTags','saveSubmit','mapAddAgain','addImport','mapSendoff']
for target in active:
 _,title,body,surf,extras,line,_=lookup[target]
 lines=L(Headline=title,Body=body)
 if 'advance: .next' in extras: lines.append(('Primary',re.search(r'nextButtonTitle: "([^"]+)"',extras)[1] if 'nextButtonTitle:' in extras else 'Next'))
 note='Auto demonstration; advances after its reading interval.' if 'automaticallyAdvances: true' in extras else 'Advance by tapping the highlighted action.'
 if target=='saveStatus':lines+=L(Choice1='Check In',Choice2='Wanna Go');note='Branches into Check In or Wanna Go. Visited-only controls are skipped for Wanna Go.'
 if target=='mapSendoff':lines=L(Headline=title,Eyebrow='A thought for the road',Quote='“'+body+'”',Attribution='— Anthony Bourdain',Closing='Keep the places that move you. Your map will remember the rest',Primary='Finish');note='End of the current first-visit journey.'
 add(target,title,'04 · First save walkthrough',lines,target+'.png',note,source=f'FirstVisitWalkthrough.swift:{line}')
add('import-lesson','Return visit · Import','05 · Return visits & contextual',L(Headline='Bring every saved place with you',Body='Paste one place, a few links, or a whole list from Maps, Instagram, TikTok, or Notes. Choose what to keep and mark each Check In or Wanna before anything reaches your map',Primary='Open import form',Help='Import help'),'import-lesson.png',note='Eligible on launch 2 or later, after the primary journey and before completion of this lesson.',source='FirstVisitWalkthrough.swift:1932')
add('device-features','Return visit · Device features','05 · Return visits & contextual',L(Headline='Astir, one press away',Body='Set these up once for faster saves',Feature1='Action Button + Controls',Instruction1='Choose Astir Check In for a one-press save',Feature2='Home + Lock Screen widgets',Instruction2='Keep Quick Add, Search, Activity, or Nearby in view',Feature3='Share extension',Instruction3='Send places from Maps, Instagram, TikTok, or Safari',Guide='Setup guide',Primary='Got it'),'device-features.png',note='Eligible on launch 3 or later; shown once per enrolled account.',source='FirstVisitWalkthrough.swift:2013')
for k,title,body in [('place_saved','See when your friends check in','Get a heads-up when people you follow save a place or check in somewhere worth knowing.'),('follow_created','Keep up with people you follow','Get a heads-up when they save a place or check in somewhere worth knowing.')]:
 add(k,'Notifications · '+('After saving' if k=='place_saved' else 'After following'),'05 · Return visits & contextual',L(Eyebrow='STAY IN THE LOOP',Headline=title,Body=body,Primary='Continue'),k+'.png',note='Contextual campaign, gated by notification state and impression limits. Not an extra mandatory onboarding step.',source='ProductUpsellCoordinator.swift',state='Conditional')
add('system-location','iOS · Location permission','06 · System & recovery states',L(Headline='Allow “Astir” to use your location?',Purpose='Astir uses your location to suggest nearby places when you ask and to keep an optional nearby widget useful. It never broadcasts live location.',Option1='Allow Once',Option2='Allow While Using App',Option3='Don’t Allow'),'system-location.png',note='iOS owns the headline and choices. The purpose string is app-owned.',source='project.yml:100',state='System')
for key,title,lines,source in [
 ('location-denied','Location denied',L(Primary='Open Settings',Secondary='Not now',Restricted='Continue without location'),'OnboardingPermissionManagers.swift'),
 ('notification-denied','Notifications denied',L(Primary='Open Settings',Secondary='Not now',Working='Turning on notifications…'),'ProductUpsellScreen.swift'),
 ('friends-empty','No people yet',L(Headline='Your people will show up here',Body='Skip for now — we’ll keep finding trusted people as Astir grows.',Primary='Continue',Secondary='Skip'),'OnboardingFlowView.swift'),
 ('friends-failed','People loading failed',L(Headline='Suggestions are taking a minute',Body='You can skip this and find people from Discover anytime.',Primary='Continue',Secondary='Skip'),'OnboardingFlowView.swift'),
 ('identity-state','Username & saving states',L(Checking='Checking username…',Available='Username available',Taken='That username is taken',Saving='Creating your profile…'),'OnboardingFlowView.swift'),
 ('system-contacts','iOS · Contacts purpose',L(Purpose='Astir reads names and phone numbers on this device so you can choose someone to invite. Your address book is not uploaded; Messages receives only a number you select.'),'project.yml:99'),
 ('system-camera','Camera purpose',L(Purpose='Astir uses the camera when you choose to take a profile or place photo, such as adding a restaurant photo to a saved place.'),'project.yml:97'),
 ('system-calendar','Calendar purpose',L(Purpose='Astir reads restaurant reservations from Apple Calendar to prepare private check-in reminders. It syncs only the matched restaurant and reservation time—not raw calendar titles, notes, guests, URLs, or addresses.'),'project.yml:98'),
 ('system-photos','Save to Photos purpose',L(Purpose='Astir saves a share ticket to your photo library when you choose Save, Instagram Post, or TikTok.'),'project.yml:101')]:
 add(key,title,'06 · System & recovery states',lines,note='Conditional state. Source copy; no matched screenshot.' if not key.startswith('system-') else 'App-owned system permission purpose. Only shown when the related feature is used; not an additional onboarding step.',state='Conditional',source=source)
seen=set()
for target,title,body,surf,extras,line,pos in allsteps:
 if target in active:continue
 signature=(target,title,body)
 if signature in seen:continue
 seen.add(signature)
 add('retained-'+target+('-legacy' if target in [n['key'].removeprefix('retained-') for n in nodes] else ''),title or 'Results preview','07 · Retained lessons · disabled',L(Headline=title,Body=body)+([('Primary','Next')] if 'advance: .next' in extras else []),note='Retained in Swift but suppressed in the current live NUX. Included for completeness; not part of the active route.',state='Disabled',source=f'FirstVisitWalkthrough.swift:{line}')
# Two titles are computed from MapSource, not string literals.
for key,title in [('mapFeatured','Featured shows you recommendations based on your taste'),('mapFriends','All places from everyone you follow')]:
 add('retained-'+key,title,'07 · Retained lessons · disabled',L(Headline=title,Primary='Next'),note='Retained Map exploration lesson. Disabled in the current NUX.',state='Disabled',source='FirstVisitWalkthrough.swift:379; WanderEnums.swift:37')
add('photo-crop','Crop profile photo','06 · System & recovery states',L(Headline='Crop photo',Instruction='Pinch to zoom. Drag to reposition.',Cancel='Cancel',Primary='Choose',Saving='Saving…'),note='Optional branch from Add a photo. Native photo picker precedes crop.',state='Conditional',source='ProfilePhotoCropView.swift')
add('entry-recovery','Account recovery','06 · System & recovery states',L(Headline='Your map is still here',Primary='Try again',Offline='Continue offline',Unavailable='Sign in isn’t available'),note='Alternative recovery states. Error detail is supplied by the failed request. Continue offline appears only when eligible.',state='Conditional',source='AppEntryView.swift')
for n in nodes:
 if n['key']=='retained-placeHistory':
  n['lines'][-1]['text']='Keep going'
 if n['key']=='location-denied':n['image']='location-denied.png'
 if n['key']=='friends-failed':n['image']='friends.png'
 if n['key']=='signup':n['image']='signup.png'
 if n['key']=='password':n['image']='password.png'
 if n['key']=='addImport':n['note']='Tap Next to continue to the sendoff.'

extras={
 'saveStatus': [('Form prompt','what do you want to do?')],
 'saveDate': [('Field','when')],
 'saveNote': [('Field','a note for future you'),('Placeholder',"what you'll want to remember, who told you...")],
 'saveMoreOptions': [('Section','more options'),('Privacy','stealth mode')],
 'saveQuestions': [('Question','best for?'),('Selection','multi'),('Section','tags')],
 'saveTags': [('Section','your tags'),('Helper','Tap any that fit. Selected tags stay in place so you can review or change them.'),('Custom','Add your own tag')],
 'saveSubmit': [('Primary action','Check in'),('Alternative action','Wanna go')],
 'addSearch': [('Sheet title','add a place'),('Body copy','find it nearby, search, or import'),('Section','Suggested'),('Placeholder','Search for a place'),('Section','Import'),('Action','Import from')]
}
for n in nodes:
 if n['key'] in extras:
  n['lines'] += [dict(role=a,text=b) for a,b in extras[n['key']]]
  n['source'] += ' · MapScreen.swift / AddScreen.swift'
 if n['key']=='saveStatus':
  n['lines'][2]['text']='Check in';n['lines'][3]['text']='Wanna go'
 if n['key']=='saveTags':n['note']='Source-defined automatic tag lesson. This timed state was not captured in the demo pass.'
 if n['key']=='location-denied':n['note']='Denied permission: Open Settings / Not now. Restricted permission uses Continue without location.'
 if n['key']=='friends-failed':n['note']='The captured demo shows this loading-failure fallback.'
for i,n in enumerate(nodes):n['id']=('R' if n['state']=='Disabled' else 'N')+str(i+1).zfill(2)
sha=subprocess.check_output(['git','-C',str(SRC),'rev-parse','HEAD'],text=True).strip()
data=dict(title='Astir · Onboarding & NUX',date='September 16, 2026',build='174',commit=sha,nodes=nodes)
(R/'content.json').write_text(json.dumps(data,ensure_ascii=False,indent=2))
print(len(nodes),'screens / states;',sum(len(n['lines']) for n in nodes),'copy lines')
