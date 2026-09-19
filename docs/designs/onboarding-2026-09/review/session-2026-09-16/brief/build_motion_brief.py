from pathlib import Path
from html import escape
import json

root = Path(__file__).resolve().parent.parent
t01 = (root / 'transcripts/T01.txt').read_text()
t07 = (root / 'transcripts/T07.txt').read_text()
t08 = (root / 'transcripts/T08-opening-refinements.txt').read_text()

def excerpt(text, start, end):
    a = text.index(start)
    b = text.index(end, a) + len(end)
    return text[a:b]

quotes = [
    ('Latest refinement: casing, color, three rows and spacing', 'T08-opening-refinements.txt', t08.split('every time we do')[0].strip()),
    ('The final three-row phrase and slide', 'T08-opening-refinements.txt', excerpt(t08, "it's not sliding.", 'those three rows of flip boards.')),
    ('Actual place preview, anchored benefit board, and both sides of the slide', 'T08-opening-refinements.txt', excerpt(t08, 'also circuit coffee:', 'okay here we’re good.') if 'okay here we’re good.' in t08 else excerpt(t08, 'also circuit coffee:', "okay here we're good.")),
    ('Selected description placement and keeping archives', 'T08-opening-refinements.txt', t08[t08.index('little leon bridges'):]),
    ('Two supporting-text entrances', 'T07.txt', excerpt(t07,
        "Maybe we do one where it's on screen",
        "Let's think of a couple.")),
    ('What is on top, what enters below, and what slides away', 'T07.txt', excerpt(t07,
        'maybe fuck fuck first slide is just the ticker tape',
        'And then we get into the mechanical.')),
    ('The whole headline becomes “a local experiment”', 'T01.txt', excerpt(t01,
        'what if you just say "a local experiment"?',
        "okay chat, you're going to fuck this animation up i think.")),
    ('The account link and the transition to account creation', 'T07.txt', excerpt(t07,
        'Okay, I think we kill get started.',
        'Okay, no change to this.')),
    ('The old-sign flicker · September 17', None,
        "I can show you, like a ticker flicker, like those old signs where it would, like, flick flick flick flick flick flick flick flick flick and go to the next one. Flick flick flick flick flick flick flick and go to the next one. I can show you a video of that, but that's the animation."),
    ('Flicker and slide are separate · September 17', None,
        "Well, there's the flick, flick, flick and the slide. They both exist. The flick, flick, flick is for the change of the words, and then there's the slide for when you move to the next thing."),
    ('Letters use split-flap displays · latest clarification', None,
        'what we mean is split-flap displays or flip boards for those letters. then the slide in'),
]

states = [
    dict(number='01', title='The opening phrase',
         top='“Connect with your” stays fixed. The changing word occupies a stable position beneath it: community → people → places → loved ones. This order is the sequence in the current takes.',
         bottom='In the delayed version, the explanatory text has not entered yet. The immediate alternative has that text visible from the beginning.',
         entrance='The opening composition appears. There is no instruction in the transcript locking its first entrance to a specific fade or slide.',
         within='Each changing letter flips around its middle hinge to reveal the next character, like a split-flap display. The word stays in place and the fixed lead-in remains steady. Simple opacity blinking does not match this letter movement.',
         exit='The headline remains on screen as the supporting text enters; this is not yet the transition to a new screen.'),
    dict(number='02', title='The explanation joins it',
         top='The fixed lead-in and changing words remain in the upper part of the screen.',
         bottom='A short explanation of the app slides into the lower copy area. It sits beneath the headline while the word sequence continues. The transcript requests an immediate version and a delayed version.',
         entrance='Slide the supporting text in after the ticker has had a moment. The direction, distance and exact delay were not locked in the recording.',
         within='Individual letters continue their hinged split-flap changes. The explanatory text holds once it has arrived. Its slide-in is separate from the letter animation.',
         exit='Keep the same scene until the headline’s closing transformation.'),
    dict(number='03', title='The entire headline changes',
         top='The complete “Connect with your [word]” headline participates in the per-letter split-flap treatment, then resolves to the standalone phrase “a local experiment”. It does not read “Connect with your a local experiment”.',
         bottom='The transcript does not explicitly settle whether the explanatory text holds or disappears during this change. The current Swift take removes it with the headline. This is an interpretation to review.',
         entrance='Extend the same hinged letter-flap movement across the whole headline. The letters change within the same scene; the horizontal move to the next screen comes afterward.',
         within='Let “a local experiment” resolve and be readable. The exact hold duration is a timing choice, not a transcript requirement.',
         exit='Then slide the entire opening composition away to move to the native UI benefit slide.'),
    dict(number='04', title='The native UI takes over',
         top='Actual app UI replaces the opening typography in the upper area. The first benefit shows places; the next benefit shows people/activity.',
         bottom='“Keep track of everywhere you’ve been.” Then, on the following slide, “Keep up with the people you love.” “Make plans together” was also proposed; its UI/placement remains a separate exploration.',
         entrance='The whole slide moves sideways: opening copy exits and the native UI plus its benefit copy enter as the next composition.',
         within='Any animation inside that native UI is separate from the split-flap letter changes. The native UI should show the actual app.',
         exit='Slide again between benefit screens, then slide the entire composition into “Create your account”.'),
]

# September 17 refinement supersedes the earlier layout alternatives.
states[0].update(
    top='A centered three-row board sits lower on screen. Row 1: CONNECT WITH YOUR. Row 2: COMMUNITY → PEOPLE → PLACES → LOVED ONES, centered. Row 3 is blank until the final phrase. Every cell has a full split-flap face; letters remain Signal coral in light and dark mode.',
    bottom='The selected A.03 description has not entered yet. Pagination, Next and Log in are visible.',
    within='Each changed cell makes two physical hinged flips over 0.6 seconds, after a 1.8-second readable hold. Equal-width cells preserve spacing. Blank cells stay part of the same board.')
states[1].update(
    top='The same three-row board continues its uppercase word changes without moving.',
    bottom='Keep track of everywhere you’ve been. Keep up with the people you love. This is the selected A.03 line, centered directly above pagination and Next.',
    entrance='The description slides in from the right at 3.6 seconds. It holds once it arrives; its entrance is separate from the hinged letter animation.')
states[2].update(
    top='All affected cells flip to three centered rows: A / LOCAL / EXPERIMENT. The board keeps the same footprint and cell sizes.',
    bottom='A.03 stays in place above pagination. Keeping it through this hold is the current implementation choice for review.',
    within='The final phrase settles at 9.6 seconds and holds for 2.4 seconds.',
    exit='At 12 seconds, the full opening composition slides left. The actual Places UI and its lower flip board enter together from the right over 0.65 seconds.')
states[3].update(
    top='The Places square uses the actual production Hotchkiss Park preview, including the real photo returned by Astir’s place-photo service. The photo and original attribution are cached locally so this signed-out introduction needs no account. The following square uses the actual ActivityPostcardView.',
    bottom='Places: KEEP TRACK OF / EVERYWHERE / YOU’VE BEEN. People: KEEP UP WITH / THE PEOPLE / YOU LOVE. Both use the same three-row flip board and Signal letters.',
    entrance='The first benefit board slides in with the Places UI and flips from blank cells to its words.',
    within='Places → People slides ONLY the upper UI. The lower board stays anchored and physically flips its letters to the People benefit during that same transition. Example places/activity labels are removed.',
    exit='After People, the entire outgoing composition slides left while Create your account slides in from the right. Each benefit has a seven-second reading interval. Next advances early; rapid taps are retained.')

summary = 'Three uniform rows, uppercase Signal letters, light or dark flap faces. The letters flip individually, like hinged split-flap displays or flip boards. The separate slide brings supporting copy into place, then moves the whole composition to the next screen. Simple opacity blinking is not the requested letter motion.'
controls = 'The recording says to remove “Get started”, considers a subtle “Already have an account? Log in” entrance around slide three or four, and repeats Log in on account creation. It also debates no-skip versus returning-user speed. The exact opening footer and login reveal point were not fully settled. Current Swift shows Next and Log in from the first state; that is a review difference, not a recovered requirement.'
split_flap_ready = (root / 'native-captures' / 'split-flap-review-ready.json').exists()
gap = 'The live A/B/C recordings and the four frames in this brief show the preceding opacity-flicker pass. They predate the requested per-letter split-flap revision. Updated native Swift recordings are being prepared. The supporting-text slide and whole-screen transitions are already shown, but the existing blinking letters do not demonstrate the requested hinged letter motion.'
frame_status = 'Earlier native pass · layout reference only. These frames predate the per-letter split-flap revision.'
if split_flap_ready:
    gap = 'The latest native Swift recordings show the uppercase three-row board, two-flip cadence, the selected A.03 description near Next, and both sides of the slides. The park preview uses the production card and the real retrieved Hotchkiss Park photo. Light and dark recordings are available together. Prior copy and motion explorations remain accessible in Archives. This is ready for creative feedback; it does not claim final creative approval or a release.'
    frame_status = 'Current native Swift recording · dark mode · four states. Play the recordings to review the motion in either appearance.'

lead = 'The literal lead-in used here is the previously confirmed “Connect with your”. The later spoken “connect two” is retained as a transcription ambiguity, not silently substituted into the app copy.'

# Current clarification: keep the external header, restore three visible rows,
# and run every cell through eight physical turns in the same flutter interval.
quotes[0] = ('Earlier refinement: casing, color, three rows and spacing', *quotes[0][1:])
quotes.insert(0, ('Earlier refinement: separate header, longer flutter and haptics',
                  'T09-analog-flutter-excerpts.txt', (root / 'transcripts/T09-analog-flutter-excerpts.txt').read_text().strip()))
quotes.insert(0, ('Earlier refinement: full screens, three rows, eight flips',
                  'T10-full-board-excerpt.txt', (root / 'transcripts/T10-full-board-excerpt.txt').read_text().strip()))
states[0].update(
    top='“Connect with your” is plain text above a centered, permanently visible three-row board. COMMUNITY → PEOPLE → PLACES → LOVED ONES sits in the middle row; the outer rows settle to blank faces. Ten equal-width cells in each row preserve the natural uppercase Signal letters.',
    within='Every one of the 30 cells runs eight physical flips over 1.5 seconds after a 1.8-second readable hold. This includes blank cells and letters that match the previous word. Column starts stagger slightly, with fixed hinges, falling leaves and a small landing rebound. Four light native haptic impacts punctuate each opening flutter. Eight turns is the latest requested cadence; the other numeric values remain implementation choices for review.')
states[1].update(top='The external lead-in and all three board rows stay in place as every cell participates in the uppercase word changes.')
states[2].update(
    top='The external “Connect with your” fades out quickly over 180ms. The three already-visible rows then flutter to A / LOCAL / EXPERIMENT. Every cell runs eight turns, including spaces. Header space, cell sizes and board position stay fixed.',
    entrance='Fade the plain-text lead-in first, then flip the board to the final phrase. The scene slide follows after the phrase is readable.',
    within='The final phrase settles at 13.2 seconds and holds for 2.4 seconds.',
    exit='At 15.6 seconds the full opening slides left while the actual Places UI and its lower board slide in from the right over 0.6 seconds.')
summary='Three visible rows in every finish, with “Connect with your” outside and above the board. Eight hinged turns per cell during each opening word change; blank and repeated-letter cells also turn. The final board reads A / LOCAL / EXPERIMENT. Full phone recordings show the top, bottom and complete transitions without a lettering crop.'
gap='The current Swift pass implements the external header, three visible rows, eight flips for every opening cell and four haptic impacts. All three finishes are recorded in both appearances through account creation. Native motion remains the source of the videos. The park preview uses the real retrieved Hotchkiss Park photo. Previous takes remain in Archives; physical haptic feel still needs an iPhone review.'
frame_status='Current native Swift recording · dark mode · four full-phone states. Use the complete recordings to judge timing and motion.'

quotes.insert(0, ('Earlier color clarification: contrasting flap faces (superseded below)',
                  'T11-contrasting-flaps-excerpt.txt', (root / 'transcripts/T11-contrasting-flaps-excerpt.txt').read_text().strip()))
states[0]['top'] += ' In light mode the faces are black; in dark mode they are white or off-white. The letters stay Signal in both appearances.'
states[3]['bottom'] += ' These benefit faces use the same contrasting appearance rule.'
summary += ' Black flaps on the light screen; white or off-white flaps on the dark screen. Signal letters in both.'

current_manifest = json.loads((root / 'native-finishes.json').read_text())
quotes.insert(0, ('Latest correction: faster independent flutter and matching face colors',
                  'T12-independent-flutter-excerpt.txt', (root / 'transcripts/T12-independent-flutter-excerpt.txt').read_text().strip()))
states[0]['top'] = '“Connect with your” stays outside and above the three-row board. COMMUNITY → PEOPLE → PLACES → LOVED ONES appears centered in its middle row. All rows remain visible. Dark faces sit on dark app screens; light faces on light app screens. Caps remain Signal, with their natural monospaced proportions.'
states[0]['within'] = 'Every cell, including blanks and repeated letters, has independent start timing, flip durations, letter path and landing. The new implementation uses 12–16 faster physical turns per cell inside the existing 1.5-second flutter, following a 1.8-second readable hold. This range is the implementation choice for Joe’s latest “faster” direction, superseding exactly eight synchronized turns. Four light haptic impacts punctuate the opening change.'
states[2]['top'] = 'The external “Connect with your” fades quickly over 180ms. All three rows then flutter independently into A / LOCAL / EXPERIMENT. Header space, cell sizes and board position stay fixed.'
states[3]['bottom'] = states[3]['bottom'].replace('These benefit faces use the same contrasting appearance rule.', 'These benefit faces follow the same matching appearance rule: dark on dark, light on light, with Signal letters.')
summary = 'Three full rows, an external lead-in, and faster individual cell motion. Each cell has a different rhythm and letter path; cells settle at different moments into the exact words. Dark faces match dark app screens; light faces match light app screens. Full-phone Swift recordings preserve every screen and transition.'
current_media_ready = current_manifest.get('motionRevision') == 'independent-v1'
gap = ('The current gallery contains all six verified full-phone Swift recordings of the independent-flutter revision through account creation. Every cell runs 12–16 faster turns with its own timing and character path. Matching dark/light face colors are restored. Physical haptic feel still needs an iPhone review.' if current_media_ready else 'The new Swift code implements independent per-cell flutter and matching dark/light face colors. Build and replacement full-phone recordings are in progress. The gallery still shows the preceding revision until these replacements are verified.')

quotes[0] = ('Earlier correction: independent flutter and matching face colors', *quotes[0][1:])
quotes.insert(0, ('Latest correction: physical leaves, final slowdown, font and longer transitions',
                  'T13-physical-flaps-and-transitions.txt', (root / 'transcripts/T13-physical-flaps-and-transitions.txt').read_text().strip()))
states[0]['top'] = states[0]['top'].replace('natural monospaced proportions', 'natural Avenir Next Bold proportions')
states[0]['within'] = 'Individual cells rattle quickly, then visibly brake across their final three leaves. Every leaf has a physical lip, hinge, moving shadow and a continuous half-turn rather than an opacity swap. There are still 12–16 independent turns inside the 1.5-second flutter, after a 1.8-second readable hold. Printed Avenir Next Bold caps are centered in equal cells without stretching. This font is the current interpretation of Joe’s font correction, not a newly approved typeface choice. Four light haptic impacts accompany each opening change.'
states[2]['exit'] = 'At 15.6 seconds the full opening slides left while the actual Places UI and its lower board enter from the right. Both the slide and the separate linear board clock take 1.5 seconds.'
states[3]['entrance'] = 'The benefit board and Places UI slide in over 1.5 seconds. Its letters flutter on a separate linear 1.5-second clock, with the same turn budget and final slowdown as the opening.'
states[3]['within'] = 'Places → People slides only the upper UI over 1.5 seconds. The lower board stays anchored, fluttering for 1.5 seconds on an independent clock so the eased slide cannot rush its turns. Every finish has actual face depth and visible hinge details.'
summary = 'Physical split-flap leaves with thickness, fixed hinges, moving cast shadows and independent chatter that brakes onto the exact word. Avenir Next Bold replaces SF Mono for this review. Upper benefit slides and benefit-letter flutters each last 1.5 seconds, matching the opening flutter. Faces still match the surrounding app appearance and letters remain Signal.'
current_media_ready = current_manifest.get('motionRevision') == 'physical-v1'
gap = ('All six current recordings show this physical-leaf revision in Swift, with brand caps and slower 1.5-second benefit transitions. Native motion and copy are the source of the media. Physical haptic sensation and final creative approval remain for review.' if current_media_ready else 'The new physical-leaf Swift revision is being built and checked. Current gallery recordings still show the preceding independent-flutter revision until replacements are verified.')

quotes[0] = ('Earlier correction: physical leaves and longer transitions', *quotes[0][1:])
quotes.insert(0, ('Latest feedback: large caps approved, benefit readability and serif lead-in',
                  'T14-benefit-readability-and-serif.txt', (root / 'transcripts/T14-benefit-readability-and-serif.txt').read_text().strip()))
states[0]['top'] += ' The large PLACES treatment is approved in T14. Keep its Avenir caps; the separate Connect with your lead-in now uses Astir’s native editorial serif.'
states[0]['within'] = states[0]['within'].replace('This font is the current interpretation of Joe’s font correction, not a newly approved typeface choice.', 'Joe approved the large PLACES lettering in T14; this treatment stays unchanged.')
states[3]['bottom'] += ' Use 13 columns instead of 17, fitting the longest approved line without rewriting it. This makes the benefit caps roughly one-third larger at the same board width, while keeping three rows and the upper preview size.'
summary += ' Latest T14 correction: preserve the approved large PLACES caps, set the external lead-in in editorial serif, and enlarge the benefit lettering by removing four unnecessary blank columns.'
current_media_ready = current_manifest.get('motionRevision') == 'physical-v2'
gap = ('All six full-phone native recordings include the serif lead-in and larger 13-column benefit copy. The approved large opening lettering and physical motion are retained. Full and compact light/dark layouts are verified; physical haptic sensation remains for iPhone review.' if current_media_ready else 'The first Station review page shows the physical motion and large caps Joe has now approved. The serif lead-in and larger benefit copy are being built and recorded; the main gallery still shows the preceding revision until verified replacements are published.')

# T15 supersedes all physical treatments. Keep previous excerpts as history.
quotes = [('Earlier / superseded: ' + title.replace('Latest feedback: ', '').replace('Latest correction: ', ''), file, quote) for title,file,quote in quotes]
quotes.insert(0, ('Current launch blocker: one plain Signal text slide', 'T15-signal-slide.txt', (root / 'transcripts/T15-signal-slide.txt').read_text().strip()))
states = [
 dict(number='01', title='Words slide as complete labels',
 top='Connect with your stays above the changing word in Astir’s native editorial serif. COMMUNITY → PEOPLE → PLACES → LOVED ONES uses plain Avenir Next Bold uppercase Signal-orange text with natural spacing.',
 bottom='Pagination, Next and Log in remain visible. The supporting description has not entered yet.',
 entrance='COMMUNITY slides in from the right over 1.5 seconds, then holds for 1.8 seconds. The initial entrance does not consume its reading hold.',
 within='The complete outgoing word slides left at the same time the complete incoming word slides from the right. Both use the same 1.5-second eased motion and travel distance. No boards, individual tiles, texture, flutter or flap haptics are active.',
 exit='The word sequence continues while the description enters below.'),
 dict(number='02', title='Supporting copy slides in below',
 top='The serif lead-in remains steady while the Signal words continue sliding as whole labels.',
 bottom='Keep track of everywhere you’ve been. Keep up with the people you love. This exact supporting copy appears above the pagination and account actions.',
 entrance='At 5.1 seconds from opening entry, the supporting text slides from the right using the same 1.5-second easing.',
 within='The supporting copy holds once it lands. Word changes continue above it.',
 exit='Preserve this layout until the final headline change.'),
 dict(number='03', title='A local experiment',
 top='The serif Connect with your fades quickly over 180ms, just before LOVED ONES slides out and the complete three-line phrase A / LOCAL / EXPERIMENT slides in. It is plain Signal text, with no board.',
 bottom='The supporting description remains above pagination and Next; this remains an implementation choice for review.',
 entrance='Lead-out fade at 13.02–13.20s; final phrase slides in over 1.5 seconds and settles at 14.7s.',
 within='Hold the settled final phrase for 2.4 seconds.',
 exit='At 17.1 seconds, the whole opening composition slides left while the real Places UI and its benefit phrase enter from the right over 1.5 seconds.'),
 dict(number='04', title='Native UI and complete benefit phrases',
 top='Actual Hotchkiss Park preview with its retrieved photo, followed by the native activity postcard.',
 bottom='KEEP TRACK OF / EVERYWHERE / YOU’VE BEEN. Then KEEP UP WITH / THE PEOPLE / YOU LOVE. Plain, naturally spaced Avenir Next Bold Signal text.',
 entrance='The first native preview and benefit phrase enter as one composition after the opening.',
 within='Places → People moves the upper native preview and lower complete phrase together. The outgoing UI and text remain until the incoming ones land. Both use the same 1.5-second easing; no per-letter effect remains.',
 exit='Each native benefit holds for 7 seconds before advancing. Account entry follows the last benefit. Next, reverse swipes and Log in remain available.')
]
summary='One native exploration: plain Signal-orange sans-serif words and phrases slide as complete pieces, with the outgoing and incoming labels moving simultaneously. The serif Connect with your stays steady until its quick final fade. The same 1.5-second slide language applies to words, benefit text, upper app UI and the full opening composition.'
current_media_ready = current_manifest.get('motionRevision') == 'signal-slide-v2'
gap=('The one current treatment is recorded from Swift in light and dark mode through account creation. This is the launch-blocker checkpoint for Joe/Ryan feedback. The events-placeholder style is explicitly deferred; its other-chat context has not been searched or inspected.' if current_media_ready else 'The one Swift text-slide treatment is being built and recorded. Previous physical captures are archived and must not be represented as this new treatment. The events-placeholder style is deferred.')
frame_status='Current native Swift · one Signal slide treatment · four complete dark-mode phone states.'

# T16 approval and final typography supersede the prior checkpoint.
quotes.insert(0, ('Approved opening: final size and spacing', 'T16-approved-opening-final-spacing.txt', (root / 'transcripts/T16-approved-opening-final-spacing.txt').read_text().strip()))
states[0]['top'] += ' The stable serif lead-in is slightly larger and closer to the orange word, whose center stays fixed.'
gap = 'The approved Swift opening now includes the final heading size and spacing. Native dark/light recordings show this exact implementation. Static accessibility retains the complete message. Events remains the next separate pass.'

md = ['# Opening motion brief', '', 'September 17, 2026 · Joe + Ryan', '',
      '## Relevant transcript excerpts', '',
      'These are the relevant excerpts, not the full hour-long transcript. Original wording is retained. The four numbered states below are my reconstruction of the sequence; you did not number them this way in the recording.', '']
for title, file, quote in quotes:
    md += ['### ' + title, '', '> ' + quote.replace('\n', '\n> '), '']
    if file: md += [f'[Original transcript](../transcripts/{file})', '']
md += ['## My understanding', '', summary, '', lead, '']
for state in states:
    md += ['### State ' + state['number'] + ' · ' + state['title'], '']
    for key, label in [('top','Top'),('bottom','Bottom'),('entrance','Animation in'),('within','Within the state'),('exit','Animation out / transition')]:
        md += [f'**{label}:** {state[key]}', '']
md += ['## Footer and controls', '', controls, '', '## Current Swift versus the brief', '', gap, '',
       '## Still open for review', '',
       '- Whole-word slide timing, simultaneous handoff and readable holds.',
       '- The selected A.03 entrance timing and lower placement.',
       '- Whether supporting copy stays through the “a local experiment” change.',
       '- Final phrase hold, footer controls and returning-user link entrance.', '',
       '[Current native opening takes](../opening-explorations.html) · [Full native board](../) · [Overall task ledger](../TASKS.md)', '']
(root / 'brief' / 'opening-motion-brief.md').write_text('\n'.join(md))

quote_html = ''.join(f'<article class="quote"><h3>{escape(title)}</h3><blockquote>{escape(quote)}</blockquote>' + (f'<a href="../transcripts/{file}">Original transcript ↗</a>' if file else '') + '</article>' for title,file,quote in quotes)
state_html = ''
for state in states:
    rows = ''.join(f'<div class="row"><span>{label}</span><p>{escape(state[key])}</p></div>' for key,label in [('top','Top of screen'),('bottom','Bottom of screen'),('entrance','Animation in'),('within','Within the state'),('exit','Out / transition')])
    state_html += f'<article class="state"><header><b>{state["number"]}</b><h3>{escape(state["title"])}</h3></header>{rows}</article>'
frames = ''
if current_media_ready and all((root / 'native-captures' / f'opening-state-{state["number"]}.png').exists() for state in states):
    frames = '<p class="frame-status">' + escape(frame_status) + '</p><div class="native-frames">' + ''.join(
        f'<figure style="margin:0"><a href="../native-captures/opening-state-{state["number"]}.png"><img style="width:100%;height:auto;border:1px solid #c9cebd;border-radius:8px" src="../native-captures/opening-state-{state["number"]}.png" alt="Actual Swift state {state["number"]}"></a><figcaption style="font-size:14px">{state["number"]} · {escape(state["title"])}</figcaption></figure>' for state in states) + '</div>'
html = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Opening motion brief · Astir</title><style>
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#f6f3eb;color:#222a20;font:19px/1.55 system-ui,sans-serif}nav{position:sticky;top:0;background:#182316;color:#faf5e8;display:flex;gap:25px;align-items:center;padding:17px 4vw;z-index:2}nav a{color:inherit;font-size:15px}nav b{margin-right:auto}nav button{background:none;border:1px solid #72806c;border-radius:7px;padding:8px 12px;color:inherit;cursor:pointer}main{max-width:1400px;margin:auto;padding:55px 42px 90px}h1{font:60px/1.08 Georgia,serif;margin:12px 0 20px}h2{font:38px/1.15 Georgia,serif;margin:0 0 24px}h3{font-size:20px;line-height:1.3;margin:0 0 12px}.eyebrow{font-size:13px;letter-spacing:.15em;text-transform:uppercase;color:#a34a2f}.intro{max-width:950px}.section{margin-top:65px;scroll-margin-top:100px}.quote{border-top:1px solid #cecfc2;padding:24px 0}.quote blockquote{margin:0 0 12px;max-width:1180px;white-space:pre-line;font-size:19px}.quote a,a{color:#814027}.quote a{font-size:14px}.rule{font:30px/1.3 Georgia,serif;background:#e6e8db;border-left:6px solid #da613e;padding:25px 30px}.muted{color:#63705e;font-size:16px}.native-frames{grid-column:1/-1;display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:18px;margin:0 0 30px}.native-frames figure{min-width:0}.frame-status{grid-column:1/-1;margin:8px 0 0;padding:16px 20px;border-left:4px solid #da613e;background:#ede0cc;font-size:16px}.states{display:grid;grid-template-columns:1fr 1fr;gap:22px}.state{border:1px solid #c9cebd;background:#fffdf6;border-radius:12px;overflow:hidden}.state header{display:flex;align-items:center;gap:18px;background:#263420;color:#fcf6e9;padding:22px}.state header b{font:42px Georgia,serif;color:#f17c52}.state header h3{font-size:24px;margin:0}.row{display:grid;grid-template-columns:130px 1fr;gap:18px;padding:18px 23px;border-bottom:1px solid #e2e4d8}.row span{font-size:12px;text-transform:uppercase;letter-spacing:.08em;color:#8b4c35;padding-top:5px}.row p{margin:0;font-size:17px;line-height:1.5}.difference{background:#ede0cc;padding:28px;border-radius:12px}footer{border-top:1px solid #c9cebd;margin-top:60px;padding-top:25px;display:flex;gap:28px;flex-wrap:wrap} @media(max-width:1000px){.native-frames{grid-template-columns:repeat(2,minmax(0,1fr))}.states{grid-template-columns:1fr}main{padding:30px 22px}h1{font-size:44px}nav{gap:12px;flex-wrap:wrap}nav b{width:100%}}@media print{nav{position:static}.states{display:block}.state{break-inside:avoid;margin-bottom:20px}body{font-size:12pt}main{padding:0}.section{margin-top:30px}}</style>
<nav><b>Astir · Opening motion brief</b><a href="#transcript">Transcript</a><a href="#states">Four states</a><a href="#difference">Current vs brief</a><a href="../opening-explorations.html">Light / dark recordings ↗</a><a href="../archives.html">Archives ↗</a><button onclick="document.documentElement.requestFullscreen()">Full screen</button></nav><main><div class="eyebrow">Joe + Ryan · September 17</div><h1>One language: the slide.</h1><p class="intro">Relevant transcript first, then my understanding of the screen states. This is a motion brief for reviewing the actual Swift work.</p>
<section class="section" id="transcript"><h2>What you said</h2><p class="muted">Original excerpts from this part of the conversation. Not the full session.</p>QUOTES</section>
<section class="section" id="states"><h2>My understanding · four states</h2><p class="rule">SUMMARY</p><p class="muted">These four state numbers are my reconstruction of your sequence, not numbers used in the transcript. LEAD</p><div class="states">STATES</div></section>
<section class="section"><h2>Footer and controls</h2><p>CONTROLS</p></section>
<section class="section difference" id="difference"><h2>Current Swift versus the brief</h2><p>GAP</p></section>
<section class="section"><h2>Still open for review</h2><ul><li>Whole-word slide timing, simultaneous handoff and readable holds.</li><li>The selected A.03 entrance timing and lower placement.</li><li>Whether supporting copy stays through the closing headline change.</li><li>Final phrase hold, footer controls and returning-user link entrance.</li></ul></section><footer><a href="opening-motion-brief.md">Download / read Markdown ↗</a><a href="../opening-explorations.html">Current native opening takes ↗</a><a href="../">Full native board ↗</a><a href="../TASKS.md">Overall task ledger ↗</a></footer></main></html>'''
for key,value in [('QUOTES',quote_html),('SUMMARY',escape(summary)),('LEAD',escape(lead)),('STATES',frames + state_html),('CONTROLS',escape(controls)),('GAP',escape(gap))]: html=html.replace(key,value)
(root / 'brief' / 'opening-motion-brief.html').write_text(html)
print('Wrote opening motion brief: transcript excerpts + four states + current implementation gap')
