import { prepare, layout } from './pretext.js';

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

const icon = (name, className = '') => `<svg class="icon ${className}" aria-hidden="true"><use href="#i-${name}"></use></svg>`;

const profiles = {
  joe: {
    id: 'joe', initials: 'JL', avatar: 'joe', name: 'Joe Lipshutz', handle: '@joelipshutz',
    reason: 'Maya and 2 people you follow follow Joe Lipshutz', city: 'Los Angeles',
    bio: 'Neighborhood restaurants, thoughtful ratings, and places worth bringing friends.'
  },
  maya: {
    id: 'maya', initials: 'MC', avatar: 'maya', name: 'Maya Chen', handle: '@mayamaps',
    reason: 'Follows you', city: 'Los Angeles',
    bio: 'Neighborhood bakeries, desert drives, and last-minute dinner.'
  },
  theo: {
    id: 'theo', initials: 'TB', avatar: 'theo', name: 'Theo Brooks', handle: '@theoeats',
    reason: '2 people you follow follow Theo Brooks', city: 'Los Angeles',
    bio: 'Noodle shops, listening bars, and anywhere with a long counter.'
  },
  priya: {
    id: 'priya', initials: 'PS', avatar: 'priya', name: 'Priya Shah', handle: '@priyaplaces',
    reason: 'Also in Los Angeles', city: 'Los Angeles',
    bio: 'Hikes before breakfast. Natural wine after.'
  },
  noah: {
    id: 'noah', initials: 'NR', avatar: 'noah', name: 'Noah Rivera', handle: '@noahgoes',
    reason: 'Suggested by rec.me', city: 'Pasadena',
    bio: 'Old theaters, great sandwiches, and weekday day trips.'
  },
  sofia: {
    id: 'sofia', initials: 'SL', avatar: 'sofia', name: 'Sofia Lee', handle: '@sofiasaves',
    reason: '1 person you follow follows Sofia Lee', city: 'Los Angeles',
    bio: 'Low-key date spots and big tables for birthdays.'
  },
  jules: {
    id: 'jules', initials: 'JM', avatar: 'jules', name: 'Jules Martinez', handle: '@julesoutside',
    reason: 'Also in Los Angeles', city: 'Los Angeles',
    bio: 'Swimming holes, trail snacks, and no-reservation weekends.'
  }
};

const screenMetadata = {
  'places-populated': {
    kicker: 'Direction A · Journey 01 of 10', title: 'Places home',
    note: 'Default landing: newest-first Activity, then only the recovery shelf the evidence supports.',
    proofs: [
      'Search is available before any feed content loads.',
      'Activity is visually primary and ordered newest first.',
      'Strong foreground evidence earns “may have been” language and direct Been / Wanna Go actions.'
    ]
  },
  'activity-empty': {
    kicker: 'Direction A · Journey 02 of 10', title: 'Activity empty',
    note: 'Empty Activity is a content state, not a different Discover shell. Places / People, search, and the four-tab navigation all stay visible.',
    proofs: [
      'Places remains selected while People stays one tap away.',
      'Search remains available even when the social Activity result is empty.',
      'Find people to follow switches to People without auto-focusing or clearing either mode’s search field.'
    ]
  },
  'people-populated': {
    kicker: 'Direction A · Journey 03 of 10', title: 'People suggestions',
    note: 'A proactive people surface that feels useful, not like a popularity leaderboard.',
    proofs: [
      'Every card names one understandable reason.',
      'Public profile context helps the user judge taste before following.',
      'The value note explains that following unlocks only places the person chose to share.'
    ]
  },
  'people-search': {
    kicker: 'Direction A · Journey 04 of 10', title: 'People search',
    note: 'An active query replaces proactive shelves. Dismissed suggestions may still appear here.',
    proofs: [
      'Search result hierarchy favors identity over recommendation metadata.',
      'Follow remains an independent 44pt action; tapping the row opens the profile.',
      'Clearing the query returns the cached recommendation shelves and scroll position.'
    ]
  },
  'follow-success': {
    kicker: 'Direction A · Journey 05 of 10', title: 'Follow success',
    note: 'The card stays in place as Following for this appearance so the action has an obvious result.',
    proofs: [
      'Exactly one mutation can be sent while the control is in flight.',
      'Success copy names the authorized value that can now appear.',
      'The profile leaves proactive shelves on the next full refresh, not mid-gesture.'
    ]
  },
  'activity-unlocked': {
    kicker: 'Direction A · Journey 06 of 10', title: 'Activity unlocked',
    note: 'Following must produce visible product value. Maya’s latest shared save now leads Activity.',
    proofs: [
      'The new authorized event is first because Activity remains newest-first.',
      'Copy connects the change to the follow without claiming access to private places.',
      'Existing rows and recovery candidates remain stable.'
    ]
  },
  'strong-recovery': {
    kicker: 'Direction A · Journey 07 of 10', title: 'Strong place recovery',
    note: 'A foreground “I’m here” draft supports a may-have-been prompt, but the user still decides.',
    proofs: [
      'The provenance says what rec.me remembered without implying background tracking.',
      'Been and Wanna Go enter the normal save flow rather than creating a silent record.',
      'Dismiss and later Undo stay available.'
    ]
  },
  'weak-recovery': {
    kicker: 'Direction A · Journey 08 of 10', title: 'Weak place recovery',
    note: 'A search/detail open is not presence evidence. The interface says “pick up,” never “you were here.”',
    proofs: [
      'The weak shelf title makes no visit claim.',
      'The only primary action is to continue the normal save flow.',
      'Place evidence stays device-local until the user resolves it.'
    ]
  },
  'profile-open': {
    kicker: 'Direction A · Journey 09 of 10', title: 'Public profile preview',
    note: 'The existing profile opens with enough public context to decide, but no protected place preview.',
    proofs: [
      'Name, handle, city, bio, and reason are public-shell fields.',
      'The locked area explains the access change without leaking names, counts, or categories.',
      'Returning preserves People mode, shelves, and scroll position.'
    ]
  },
  'signed-out': {
    kicker: 'Direction A · Journey 10 of 10', title: 'Signed-out gate',
    note: 'Anonymous users do not receive member search, personalized shelves, or graph reasons.',
    proofs: [
      'The disabled search shape communicates where the capability will live.',
      'The CTA names the interrupted action: find and follow people.',
      'Opening Discover sends no anonymous people query or recommendation request.'
    ]
  },
  'direction-b-home': {
    kicker: 'Direction B · Home', title: 'Social answer engine',
    note: 'Search leads, but People stays above the fold as the first content shelf. Activity becomes supporting evidence instead of the page’s main product.',
    proofs: [
      'One search accepts places, people, vibes, and moments without hiding the Places / People wayfinding.',
      'People worth following keeps the approved horizontal cards and appears before place/activity modules.',
      'Nearby and new-place modules explain which trusted people make each item relevant.'
    ]
  },
  'direction-b-answer': {
    kicker: 'Direction B · Answer', title: 'Provenance-first answer',
    note: 'The result is an answer from Joe, not a generic restaurant list. The interpretation stays editable and every place explains the match.',
    proofs: [
      'Joe is the visible source, so the person never disappears behind filters or ranking.',
      'Favorite means Been plus an explicit Favorite or rating of 4+, sorted by Joe’s rating; Wanna Go never leaks in.',
      'A zero-result answer would stay empty and offer Joe’s visited restaurants instead of silently broadening.'
    ]
  },
  'direction-b-empty': {
    kicker: 'Direction B · No favorites', title: 'Truthful zero result',
    note: '“Joes” resolves to Joe, but the answer remains empty when he has no qualifying favorites. The UI offers a named fallback without changing the query behind the user’s back.',
    proofs: [
      'Apostrophe-less “Joes” resolves against eligible known people and stays visible as the Joe chip.',
      'Zero favorites means zero results; Wanna Go places and merely visited places are not substituted.',
      'The fallback explicitly changes the intent to Joe’s visited restaurants before any broader result appears.'
    ]
  }
};

function editable(text, tag = 'p', className = '') {
  return `<${tag} class="${className}" data-pretext contenteditable="true" spellcheck="false">${text}</${tag}>`;
}

function statusBar() {
  return `<div class="status-bar"><span>9:41</span><div class="status-icons"><span>▮▮▮</span><span>⌁</span><span class="battery">82</span></div></div>`;
}

function rootTabs() {
  return `
    <nav class="tab-bar" aria-label="Primary navigation">
      <button class="root-tab">${icon('map')}<span>Map</span></button>
      <button class="root-tab">${icon('plus')}<span>Add</span></button>
      <button class="root-tab is-active" aria-current="page">${icon('discover')}<span>Discover</span></button>
      <button class="root-tab">${icon('person')}<span>Profile</span></button>
    </nav>`;
}

function modeTabs(active) {
  return `
    <div class="mode-tabs" role="tablist" aria-label="Discover mode">
      <button class="mode-tab ${active === 'places' ? 'is-active' : ''}" data-mode="places" role="tab" aria-selected="${active === 'places'}">${icon('pin')}Places</button>
      <button class="mode-tab ${active === 'people' ? 'is-active' : ''}" data-mode="people" role="tab" aria-selected="${active === 'people'}">${icon('people')}People</button>
    </div>`;
}

function searchField({ value = '', placeholder, disabled = false, loading = false }) {
  return `
    <label class="search-field ${disabled ? 'is-disabled' : ''}">
      ${icon('search')}
      <input aria-label="${placeholder}" value="${value}" placeholder="${placeholder}" ${disabled ? 'disabled' : ''}>
      ${loading ? '<span class="search-spinner" aria-label="Searching"></span>' : ''}
      ${value && !loading ? `<button class="clear-search" aria-label="Clear search">${icon('close')}</button>` : ''}
    </label>`;
}

function sectionHeader(title, link = '') {
  return `<div class="section-header">${editable(title, 'h3')}${link ? `<button class="section-link">${link}</button>` : ''}</div>`;
}

function promptShelf(items, ariaLabel = 'Useful prompts') {
  return `<div class="prompt-shelf" aria-label="${ariaLabel}">${items.map(item => {
    const config = typeof item === 'string' ? { label: item } : item;
    return `<button class="prompt-chip ${config.active ? 'is-active' : ''}" ${config.target ? `data-screen-target="${config.target}"` : ''} ${config.refine ? `data-refine="${config.refine}"` : ''}>${config.label}</button>`;
  }).join('')}</div>`;
}

function nearbyCard({ name, area, distance, profile, proof, tint }) {
  const p = profiles[profile];
  return `
    <button class="nearby-card" aria-label="Open ${name}">
      <span class="nearby-visual" style="--nearby-bg:${tint}"><span class="thumb-mark"></span><span class="distance-pill">${distance}</span></span>
      <span class="nearby-copy">
        <b>${name}</b><small>${area}</small>
        <span class="nearby-proof"><span class="avatar ${p.avatar}">${p.initials}</span><span data-pretext>${proof}</span></span>
      </span>
    </button>`;
}

function answerResult({ name, area, rating, proof, tint }) {
  return `
    <button class="answer-result" aria-label="Open ${name}">
      <span class="place-thumb answer-thumb" style="--thumb-bg:${tint}"><span class="thumb-mark"></span></span>
      <span class="answer-result-copy">
        <span class="answer-result-top"><b>${name}</b><span>Joe ${rating}</span></span>
        <small>${area}</small>
        <span class="match-proof" data-pretext><b>Why it matched:</b> ${proof}</span>
      </span>
      <span class="row-chevron">${icon('chevron')}</span>
    </button>`;
}

function activityRow({ profile, verb, place, meta, rating = '' }) {
  const p = profiles[profile];
  return `
    <button class="activity-row" aria-label="${p.name} ${verb} ${place}">
      <span class="avatar ${p.avatar}">${p.initials}</span>
      <span class="activity-copy">
        <span class="event"><b>${p.name}</b> ${verb}${rating ? ` <b>${rating}</b>` : ''}</span>
        <span class="place" data-pretext>${place}</span>
        <span class="meta">${meta}</span>
      </span>
      <span class="row-chevron">${icon('chevron')}</span>
    </button>`;
}

function candidateCard({ name, area, provenance, weak = false, tint = '#F0C6A8', disabled = false }) {
  return `
    <article class="candidate-card" data-candidate="${name}">
      <div class="place-thumb" style="--thumb-bg:${tint}"><span class="thumb-mark"></span></div>
      <div class="candidate-copy">
        ${editable(name, 'h4')}
        <p class="location">${area}</p>
        ${editable(provenance, 'p', 'provenance')}
      </div>
      <button class="icon-button candidate-dismiss" aria-label="Dismiss ${name}">${icon('close')}</button>
      <div class="candidate-actions">
        ${weak
          ? `<button class="candidate-action is-primary" data-candidate-action="continue" ${disabled ? 'disabled' : ''}>Continue save</button><button class="candidate-action" data-candidate-action="open" ${disabled ? 'disabled' : ''}>Open place</button>`
          : `<button class="candidate-action is-primary" data-candidate-action="been" ${disabled ? 'disabled' : ''}>Been</button><button class="candidate-action" data-candidate-action="wanna" ${disabled ? 'disabled' : ''}>Wanna Go</button>`}
      </div>
    </article>`;
}

function personCard(profileKey, state = 'ready') {
  const p = profiles[profileKey];
  const label = state === 'following' ? 'Following' : state === 'loading' ? 'Following' : 'Follow';
  return `
    <article class="person-card" data-profile="${p.id}">
      <button class="icon-button person-dismiss" aria-label="Dismiss ${p.name}">${icon('close')}</button>
      <button class="avatar ${p.avatar}" aria-label="Open ${p.name} profile">${p.initials}</button>
      <h4 data-pretext contenteditable="true" spellcheck="false">${p.name}</h4>
      <p class="handle">${p.handle}</p>
      <p class="reason" data-pretext contenteditable="true" spellcheck="false">${p.reason}</p>
      <p class="bio" data-pretext contenteditable="true" spellcheck="false">${p.bio}</p>
      <button class="follow-button ${state === 'following' ? 'is-following' : ''} ${state === 'loading' ? 'is-loading' : ''}" data-follow="${p.id}" aria-label="${label} ${p.name}" ${state === 'loading' ? 'disabled' : ''}>${label}</button>
    </article>`;
}

function peopleRow(profileKey, state = 'ready') {
  const p = profiles[profileKey];
  const label = state === 'following' ? 'Following' : state === 'loading' ? 'Following' : 'Follow';
  return `
    <article class="people-row" data-profile="${p.id}">
      <button class="avatar ${p.avatar}" aria-label="Open ${p.name} profile">${p.initials}</button>
      <button class="people-row-copy" aria-label="Open ${p.name} profile">
        <h4>${p.name}</h4><p class="handle">${p.handle}</p><p class="reason" data-pretext>${p.reason}</p>
      </button>
      <button class="follow-button ${state === 'following' ? 'is-following' : ''} ${state === 'loading' ? 'is-loading' : ''}" data-follow="${p.id}" ${state === 'loading' ? 'disabled' : ''}>${label}</button>
    </article>`;
}

function valueNote(copy, variant = '') {
  return `<div class="value-note ${variant}">${icon(variant === 'is-offline' ? 'wifi-off' : variant === 'is-success' ? 'check' : 'people')}<p data-pretext contenteditable="true" spellcheck="false">${copy}</p></div>`;
}

function toast(copy, action = '') {
  return `<div class="screen-toast" role="status"><span>${copy}</span>${action ? `<button data-toast-action="${action.toLowerCase()}">${action}</button>` : ''}</div>`;
}

function emptyPanel({ iconName = 'people', title, copy, action, actionName = '' }) {
  return `
    <section class="empty-panel">
      <div class="empty-icon">${icon(iconName)}</div>
      ${editable(title, 'h3')}
      ${editable(copy, 'p')}
      ${action ? `<button class="primary-action" data-empty-action="${actionName}">${action}</button>` : ''}
    </section>`;
}

function screenFrame({ mode, content, overlay = '', viewerInitials = 'JL' }) {
  return `
    <section class="ios-screen">
      <div>${statusBar()}</div>
      <main class="screen-body">
        <div class="screen-inner">
          <div class="screen-title-row"><h2>Discover</h2><button class="avatar-button" aria-label="Open profile">${viewerInitials}</button></div>
          ${modeTabs(mode)}
          ${content}
        </div>
      </main>
      ${rootTabs()}
      ${overlay}
    </section>`;
}

function placesHome({ unlocked = false } = {}) {
  const topRow = unlocked
    ? activityRow({ profile: 'maya', verb: 'saved', place: 'Bub and Grandma’s', meta: 'Glassell Park · 2m ago' })
    : activityRow({ profile: 'sofia', verb: 'saved', place: 'Dunsmoor', meta: 'Glassell Park · 8m ago' });
  return screenFrame({
    mode: 'places',
    content: `
      ${searchField({ placeholder: 'Search places, vibes, or people' })}
      ${unlocked ? valueNote('<b>Following changed Discover.</b> Maya’s newest shared save is now in your Activity.', 'is-success') : ''}
      <section class="section-block">
        ${sectionHeader('Activity')}
        <div class="activity-list">
          ${topRow}
          ${activityRow({ profile: 'noah', verb: 'rated', place: 'Quarter Sheets', meta: 'Echo Park · 1h ago', rating: '9.2' })}
          ${activityRow({ profile: 'theo', verb: 'wants to go to', place: 'The Ruby Fruit', meta: 'Silver Lake · 3h ago' })}
        </div>
      </section>
      <section class="section-block">
        ${sectionHeader('Places You May Have Been')}
        ${editable('From actions you started in rec.me. Nothing was saved without you.', 'p', 'section-caption')}
        <div class="recovery-list">
          ${candidateCard({ name: 'Bub and Grandma’s', area: 'Glassell Park · Bakery', provenance: 'You started an “I’m here” save Sunday.', tint: '#E7B68B' })}
          ${candidateCard({ name: 'Botanica', area: 'Silver Lake · Restaurant', provenance: 'From a geotagged photo you chose Friday.', tint: '#A7B98F' })}
        </div>
      </section>`,
    overlay: unlocked ? toast('Maya’s shared places are now eligible for Discover.') : ''
  });
}

function activityEmpty() {
  return screenFrame({
    mode: 'places',
    content: `
      ${searchField({ placeholder: 'Search places, vibes, or people' })}
      <section class="section-block">
        ${sectionHeader('Activity')}
        ${emptyPanel({
          title: 'Your Activity starts with people',
          copy: 'Follow people you trust and places they choose to share can show up here.',
          action: 'Find people to follow',
          actionName: 'people'
        })}
      </section>`
  });
}

function peopleHome({ success = false } = {}) {
  return screenFrame({
    mode: 'people',
    content: `
      ${searchField({ placeholder: 'Search name or @handle' })}
      ${valueNote('<b>Follow people whose taste you trust.</b> Places they choose to share can appear in Activity and on your map.')}
      <section class="section-block">
        ${sectionHeader('Suggested for You', 'See all')}
        <div class="people-shelf">
          ${personCard('maya', success ? 'following' : 'ready')}
          ${personCard('theo')}
          ${personCard('sofia')}
        </div>
      </section>
      <section class="section-block">
        ${sectionHeader('More in Los Angeles', 'See all')}
        <div class="people-shelf">
          ${personCard('priya')}
          ${personCard('jules')}
          ${personCard('noah')}
        </div>
      </section>`,
    overlay: success ? toast('Following Maya. Her shared places can now appear in Activity.') : ''
  });
}

function peopleSearch() {
  return screenFrame({
    mode: 'people',
    content: `
      ${searchField({ value: 'maya', placeholder: 'Search name or @handle' })}
      <section class="section-block">
        ${sectionHeader('3 members')}
        <div class="search-result-list">
          ${peopleRow('maya')}
          ${peopleRow('priya')}
          ${peopleRow('sofia', 'following')}
        </div>
      </section>`
  });
}

function strongRecovery() {
  return screenFrame({
    mode: 'places',
    content: `
      ${searchField({ placeholder: 'Search places, vibes, or people' })}
      <section class="section-block">
        ${sectionHeader('Places You May Have Been')}
        ${editable('From actions you started in rec.me. Nothing was saved without you.', 'p', 'section-caption')}
        <div class="recovery-list">
          ${candidateCard({ name: 'Bub and Grandma’s', area: 'Glassell Park · Bakery', provenance: 'You started an “I’m here” save Sunday.', tint: '#E7B68B' })}
          ${candidateCard({ name: 'Botanica', area: 'Silver Lake · Restaurant', provenance: 'From a geotagged photo you chose Friday.', tint: '#A7B98F' })}
        </div>
      </section>`,
    overlay: `
      <div class="bottom-sheet-backdrop">
        <section class="bottom-sheet" aria-modal="true" role="dialog" aria-label="Save Bub and Grandma’s">
          <div class="sheet-handle"></div>
          <div class="sheet-title-row"><div class="place-thumb" style="--thumb-bg:#E7B68B"><span class="thumb-mark"></span></div><div><h3>Bub and Grandma’s</h3><p>Glassell Park · Bakery</p></div></div>
          <p class="sheet-copy" data-pretext>rec.me remembered this because you started an “I’m here” save Sunday. Choose what is true now.</p>
          <div class="sheet-action-grid"><button class="primary-action">I’ve been</button><button class="secondary-action">Wanna go</button></div>
        </section>
      </div>`
  });
}

function weakRecovery() {
  return screenFrame({
    mode: 'places',
    content: `
      ${searchField({ placeholder: 'Search places, vibes, or people' })}
      <section class="section-block">
        ${sectionHeader('Pick Up Where You Left Off')}
        ${editable('Recent places you opened or started saving on this phone.', 'p', 'section-caption')}
        <div class="recovery-list">
          ${candidateCard({ name: 'Maru Coffee', area: 'Arts District · Coffee', provenance: 'You opened this from search yesterday.', weak: true, tint: '#D7B48E' })}
          ${candidateCard({ name: 'Barnsdall Art Park', area: 'East Hollywood · Park', provenance: 'You started a manual save two days ago.', weak: true, tint: '#A7BA93' })}
        </div>
      </section>
      <section class="section-block">
        ${sectionHeader('Activity')}
        <div class="activity-list">${activityRow({ profile: 'sofia', verb: 'saved', place: 'Dunsmoor', meta: 'Glassell Park · 8m ago' })}</div>
      </section>`
  });
}

function profileOpen() {
  const p = profiles.maya;
  return screenFrame({
    mode: 'people',
    content: `
      <button class="section-link" style="padding:0;margin-bottom:2px">‹ Back to People</button>
      <section class="profile-hero">
        <div class="avatar large ${p.avatar}">${p.initials}</div>
        <h3 data-pretext contenteditable="true" spellcheck="false">${p.name}</h3>
        <p class="handle">${p.handle}</p>
        <div class="profile-meta"><span class="meta-pill">${p.city}</span><span class="meta-pill">Follows you</span></div>
        <p class="bio" data-pretext contenteditable="true" spellcheck="false">${p.bio}</p>
        <button class="primary-action" data-follow="${p.id}">Follow Maya</button>
      </section>
      <section class="protected-preview">
        ${icon('lock')}
        <h4>Shared places unlock after you follow</h4>
        <p data-pretext contenteditable="true" spellcheck="false">You’ll only see places Maya chose to share with followers. Private places stay private.</p>
      </section>`
  });
}

function signedOut() {
  return screenFrame({
    mode: 'people',
    content: `
      ${searchField({ placeholder: 'Sign in to search people', disabled: true })}
      ${emptyPanel({ iconName: 'person', title: 'Find people you trust', copy: 'Sign in to search by name or handle, follow people, and see places they choose to share.', action: 'Sign in to find people', actionName: 'signin' })}
      <section class="section-block">
        ${sectionHeader('What following changes')}
        <div class="protected-preview">${icon('lock')}<h4>No anonymous member lookup</h4><p>Your People suggestions and graph reasons are personalized after sign-in.</p></div>
      </section>`
  });
}

function directionBHome() {
  return screenFrame({
    mode: 'places',
    viewerInitials: 'AR',
    content: `
      ${searchField({ placeholder: 'Ask for a place, person, vibe, or moment' })}
      ${promptShelf([
        { label: 'Friends’ favorites', target: 'direction-b-answer' },
        'Coffee + work',
        'Date night',
        'Near me'
      ])}
      <section class="section-block people-first-block">
        ${sectionHeader('People Worth Following', 'See all')}
        <div class="people-shelf">
          ${personCard('joe')}
          ${personCard('maya')}
          ${personCard('theo')}
        </div>
      </section>
      <section class="section-block">
        ${sectionHeader('Nearby From Your People', 'Map')}
        <div class="nearby-shelf">
          ${nearbyCard({ name: 'Dunsmoor', area: 'Glassell Park · Restaurant', distance: '0.8 mi', profile: 'maya', proof: 'Maya rated it 4.7 · great for groups', tint: '#D9A477' })}
          ${nearbyCard({ name: 'Maru Coffee', area: 'Arts District · Coffee', distance: '1.3 mi', profile: 'theo', proof: 'Theo saved it · quiet weekday mornings', tint: '#A9B98E' })}
        </div>
      </section>
      <section class="section-block">
        ${sectionHeader('New From Your People')}
        <div class="activity-list">
          ${activityRow({ profile: 'sofia', verb: 'rated', place: 'Quarter Sheets', meta: 'Echo Park · 1h ago', rating: '4.8' })}
          ${activityRow({ profile: 'noah', verb: 'saved', place: 'Vidiots', meta: 'Eagle Rock · 3h ago' })}
        </div>
      </section>
      <section class="section-block">
        ${sectionHeader('Places You May Have Been')}
        ${candidateCard({ name: 'Botanica', area: 'Silver Lake · Restaurant', provenance: 'From a geotagged photo you chose Friday.', tint: '#A7B98F' })}
      </section>`
  });
}

function directionBAnswer() {
  const joe = profiles.joe;
  return screenFrame({
    mode: 'places',
    viewerInitials: 'AR',
    content: `
      ${searchField({ value: 'Joe’s favorite restaurants', placeholder: 'Ask for a place, person, vibe, or moment' })}
      <div class="interpretation-row"><span>Understood as</span><button>Edit</button></div>
      ${promptShelf([
        { label: 'Joe', active: true },
        { label: 'Restaurants', active: true },
        { label: 'Favorites', active: true },
        { label: 'Los Angeles', active: true }
      ], 'Search interpretation')}
      <section class="answer-summary">
        <div class="answer-source">
          <span class="avatar ${joe.avatar}">${joe.initials}</span>
          <span><b>From ${joe.name}</b><small>${joe.handle} · Following</small></span>
          <button>View</button>
        </div>
        ${editable('4 restaurants Joe visited and loved', 'h3')}
        <p data-pretext contenteditable="true" spellcheck="false">Been only · explicit Favorite or rated 4+ · sorted by Joe’s rating</p>
        <button class="map-answer-action" data-answer-map>${icon('map')}Show 4 on map</button>
      </section>
      ${promptShelf([
        { label: 'Closer', refine: 'Closer' },
        { label: 'Date night', refine: 'Date night' },
        { label: 'Quiet', refine: 'Quiet' },
        { label: 'Show Wanna Go instead', refine: 'Wanna Go' }
      ], 'Refine answer')}
      <section class="section-block answer-results-block">
        ${sectionHeader('Best matches')}
        <div class="answer-results">
          ${answerResult({ name: 'Dunsmoor', area: 'Glassell Park · Restaurant', rating: '4.8', proof: 'Favorite · good for groups', tint: '#D9A477' })}
          ${answerResult({ name: 'Pizzeria Bianco', area: 'Downtown · Pizza', rating: '4.6', proof: 'Favorite · worth the drive', tint: '#D8B36B' })}
          ${answerResult({ name: 'Kismet', area: 'Los Feliz · Restaurant', rating: '4.4', proof: 'Joe rated it 4+ · date night', tint: '#A7B98F' })}
        </div>
      </section>`
  });
}

function directionBEmptyAnswer() {
  const joe = profiles.joe;
  return screenFrame({
    mode: 'places',
    viewerInitials: 'AR',
    content: `
      ${searchField({ value: 'Joes favorite restaurants', placeholder: 'Ask for a place, person, vibe, or moment' })}
      <div class="interpretation-row"><span>Understood as</span><button>Edit</button></div>
      ${promptShelf([
        { label: 'Joe', active: true },
        { label: 'Restaurants', active: true },
        { label: 'Favorites', active: true },
        { label: 'Los Angeles', active: true }
      ], 'Search interpretation')}
      <section class="answer-summary source-only-summary">
        <div class="answer-source">
          <span class="avatar ${joe.avatar}">${joe.initials}</span>
          <span><b>Resolved to ${joe.name}</b><small>${joe.handle} · Following</small></span>
          <button>View</button>
        </div>
      </section>
      ${emptyPanel({
        iconName: 'search',
        title: 'No Joe favorites in Los Angeles',
        copy: 'We kept Favorite strict. No Wanna Go or merely visited places were added to fill the screen.',
        action: 'Show Joe’s visited restaurants',
        actionName: 'visited'
      })}
      <p class="truth-footnote">This changes the query. It never happens silently.</p>`
  });
}

const screenTemplates = {
  'places-populated': () => placesHome(),
  'activity-empty': () => activityEmpty(),
  'people-populated': () => peopleHome(),
  'people-search': () => peopleSearch(),
  'follow-success': () => peopleHome({ success: true }),
  'activity-unlocked': () => placesHome({ unlocked: true }),
  'strong-recovery': () => strongRecovery(),
  'weak-recovery': () => weakRecovery(),
  'profile-open': () => profileOpen(),
  'signed-out': () => signedOut(),
  'direction-b-home': () => directionBHome(),
  'direction-b-answer': () => directionBAnswer(),
  'direction-b-empty': () => directionBEmptyAnswer()
};

function skeletonRows(count = 3) {
  return Array.from({ length: count }, () => `<div class="activity-skeleton"><span class="skeleton"></span><span class="skeleton-lines"><span class="skeleton skeleton-line"></span><span class="skeleton skeleton-line short"></span></span></div>`).join('');
}

function miniSearch(value = '', loading = false) {
  return searchField({ value, placeholder: 'Search', loading });
}

const boards = {
  'places-states': {
    kicker: 'State board A', title: 'Places data states',
    note: 'Loading never flashes empty. Cached content names its age. A failed recovery classifier does not invent a shelf.',
    states: [
      { name: 'Initial loading', code: 'PL-01', explainer: 'Search and mode tabs are usable immediately. Activity gets bounded skeletons. Recovery stays omitted until local classification finishes.', body: `${miniSearch()}${sectionHeader('Activity')}<div class="activity-list">${skeletonRows(3)}</div>` },
      { name: 'Activity empty', code: 'PL-02', explainer: 'Body-only comparison tile. The full screen in Journey 02 keeps the Discover title, Places / People tabs, search, and four-tab navigation. The action switches to People without focusing or clearing either search field.', body: `<div class="board-shell-note">Body detail · full chrome in Journey 02</div>${miniSearch()}${emptyPanel({ title: 'Your Activity starts with people', copy: 'Follow people you trust and places they choose to share can show up here.', action: 'Find people to follow', actionName: 'people' })}` },
      { name: 'Activity thin', code: 'PL-03', explainer: 'One or two valid rows stay visible. The Find People CTA appears before place recovery rather than replacing useful content.', body: `${miniSearch()}${sectionHeader('Activity')}<div class="activity-list">${activityRow({ profile: 'sofia', verb: 'saved', place: 'Dunsmoor', meta: '8m ago' })}</div><div class="inline-cta"><p><b>See more trusted places</b>Follow a few more people.</p><button class="small-action">Find people</button></div>` },
      { name: 'Cached offline', code: 'PL-04', explainer: 'Cached rows remain tappable when their details exist. The banner says Saved earlier and does not imply a fresh sync.', body: `${miniSearch()}${valueNote('<b>You’re offline.</b> Showing Activity saved earlier on this phone.', 'is-offline')}${sectionHeader('Activity')}<div class="activity-list">${activityRow({ profile: 'noah', verb: 'saved', place: 'Quarter Sheets', meta: 'Saved earlier' })}${activityRow({ profile: 'theo', verb: 'saved', place: 'The Ruby Fruit', meta: 'Saved earlier' })}</div>` },
      { name: 'Failure · no cache', code: 'PL-05', explainer: 'Navigation and search remain available. Retry is idempotent. No empty-state coaching appears because the graph state is unknown.', body: `${miniSearch()}${valueNote('<b>Activity couldn’t load.</b> Your places and people tabs are still available.', 'is-error')}<button class="secondary-action">Try again</button>` },
      { name: 'No recovery evidence', code: 'PL-06', explainer: 'There is no blank or disabled Places You May Have Been heading. The section simply does not exist.', body: `${miniSearch()}${sectionHeader('Activity')}<div class="activity-list">${activityRow({ profile: 'sofia', verb: 'saved', place: 'Dunsmoor', meta: '8m ago' })}${activityRow({ profile: 'noah', verb: 'rated', place: 'Quarter Sheets', meta: '1h ago', rating: '9.2' })}</div>` }
    ]
  },
  'people-states': {
    kicker: 'State board B', title: 'People data states',
    note: 'Each shelf settles independently. Search is a separate state machine. Offline recommendations never queue a Follow.',
    states: [
      { name: 'Initial loading', code: 'PE-01', explainer: 'Search stays active. Bounded card skeletons prevent a false empty flash and avoid layout movement.', body: `${miniSearch()}${sectionHeader('Suggested for You')}<div class="activity-list">${skeletonRows(3)}</div>` },
      { name: 'No suggestions', code: 'PE-02', explainer: 'The copy says “No suggestions yet,” not “no people.” Exact handle search remains the escape hatch.', body: `${miniSearch()}${emptyPanel({ title: 'No suggestions yet', copy: 'Try searching a name or exact @handle. New suggestions will appear as your network grows.' })}` },
      { name: 'Partial shelf failure', code: 'PE-03', explainer: 'Successful graph suggestions stay visible. Only the failed city shelf receives retry UI.', body: `${miniSearch()}${sectionHeader('Suggested for You')} ${personCard('maya')}<div style="height:14px"></div>${sectionHeader('More in Los Angeles')}${valueNote('<b>This shelf couldn’t load.</b> Suggested for You is still current.', 'is-error')}<button class="secondary-action">Retry this shelf</button>` },
      { name: 'Offline · cache', code: 'PE-04', explainer: 'Only eligible public-shell cache appears. Follow is disabled with a direct connectivity explanation.', body: `${miniSearch()}${valueNote('<b>Saved earlier.</b> Connect to refresh suggestions and follow.', 'is-offline')}${personCard('priya', 'ready').replace('data-follow="priya"', 'data-follow="priya" disabled')}` },
      { name: 'Search loading', code: 'PE-05', explainer: 'The new query shows progress in the field while prior settled results remain. Stale responses cannot replace this query.', body: `${miniSearch('may', true)}<div class="search-result-list">${peopleRow('maya')}${peopleRow('priya')}</div>` },
      { name: 'Search empty / error', code: 'PE-06', explainer: 'An empty query result gives exact-handle guidance. An error preserves the normalized query, clear control, and Retry.', body: `${miniSearch('@mayax')} ${emptyPanel({ title: 'No members found', copy: 'Check the spelling or try the exact @handle.' })}<div style="height:10px"></div>${valueNote('<b>Search couldn’t load.</b> Your query is still here.', 'is-error')}` }
    ]
  },
  'mutation-states': {
    kicker: 'State board C', title: 'Social mutation states',
    note: 'The card never jumps during a mutation. Rollback is local and visible. Hard blocks evict every affected surface immediately.',
    states: [
      { name: 'Follow ready → in flight', code: 'MU-01', explainer: 'The in-flight control optimistically reads Following, shows progress, and rejects repeat taps.', body: `<div class="mutation-demo"><div class="mutation-row"><span class="avatar maya">MC</span><span class="mutation-copy"><b>Maya Chen</b><small>Follows you</small></span><button class="follow-button">Follow</button></div><div class="mutation-row"><span class="avatar theo">TB</span><span class="mutation-copy"><b>Theo Brooks</b><small>Sending one request…</small></span><button class="follow-button is-loading" disabled>Following</button></div></div>` },
      { name: 'Follow success', code: 'MU-02', explainer: 'Following stays in the same position for this screen appearance. VoiceOver announces success and authorized data refreshes.', body: `${personCard('maya', 'following')}${valueNote('<b>Following Maya.</b> Her shared places can now appear in Activity.', 'is-success')}` },
      { name: 'Follow failure', code: 'MU-03', explainer: 'Rollback restores Follow without losing card position. The error is inline and retryable; no phantom edge remains.', body: `<div class="mutation-demo"><div class="mutation-row"><span class="avatar maya">MC</span><span class="mutation-copy"><b>Maya Chen</b><small>Follows you</small></span><button class="follow-button">Follow</button><span class="inline-error">Couldn’t follow Maya. Try again.</span></div></div>` },
      { name: 'Dismiss + Undo', code: 'MU-04', explainer: 'The card disappears optimistically. Undo restores its stable position. Search remains unaffected by suggestion dismissal.', body: `${valueNote('<b>Suggestion hidden.</b> Maya can still appear in search.', 'is-warning')}<div class="screen-toast" style="position:static"><span>Hidden from suggestions</span><button>Undo</button></div>` },
      { name: 'Unfollow + access change', code: 'MU-05', explainer: 'Unfollow requires existing confirmation. After success, follower-only rows and open details revoke on authorized refresh.', body: `${valueNote('<b>Access updated.</b> Follower-only places from Theo were removed.', 'is-warning')}<div class="mutation-row"><span class="avatar theo">TB</span><span class="mutation-copy"><b>Theo Brooks</b><small>No longer following</small></span><button class="follow-button">Follow</button></div>` },
      { name: 'Hard block', code: 'MU-06', explainer: 'A known block removes the profile, recommendation, search result, Activity rows, map results, and stale detail views immediately.', body: `${emptyPanel({ iconName: 'lock', title: 'Profile unavailable', copy: 'This person and their places are no longer visible.' })}<div class="screen-toast" style="position:static"><span>Blocked profile removed everywhere</span></div>` }
    ]
  },
  'recovery-states': {
    kicker: 'State board D', title: 'Place-recovery states',
    note: 'Evidence strength controls language and actions. Duplicate identity resolution happens before rendering, not after the user sees two cards.',
    states: [
      { name: 'Strong evidence', code: 'RC-01', explainer: 'Foreground “I’m here” or chosen geotagged photo supports may-have-been language and Been / Wanna Go.', body: `${sectionHeader('Places You May Have Been')}${candidateCard({ name: 'Bub and Grandma’s', area: 'Glassell Park', provenance: 'You started an “I’m here” save Sunday.' })}` },
      { name: 'Weak evidence', code: 'RC-02', explainer: 'Search/detail opens use Pick Up Where You Left Off. No Been shortcut and no presence claim.', body: `${sectionHeader('Pick Up Where You Left Off')}${candidateCard({ name: 'Maru Coffee', area: 'Arts District', provenance: 'You opened this from search yesterday.', weak: true })}` },
      { name: 'Duplicate / already saved', code: 'RC-03', explainer: 'Aliases merge to one physical place. If the user already saved the place, the entire candidate is omitted.', body: `${valueNote('<b>Already on your map.</b> Duplicate evidence was resolved silently.', 'is-success')}${sectionHeader('Activity')}<div class="activity-list">${activityRow({ profile: 'maya', verb: 'saved', place: 'Bub and Grandma’s', meta: '2m ago' })}</div>` },
      { name: 'Save in flight', code: 'RC-04', explainer: 'All candidate actions disable while the normal save flow owns the mutation. Repeat taps cannot create duplicates.', body: `${sectionHeader('Places You May Have Been')}${candidateCard({ name: 'Botanica', area: 'Silver Lake', provenance: 'Saving as Been…', disabled: true })}` },
      { name: 'Save failure', code: 'RC-05', explainer: 'The candidate returns with the user’s draft preserved under normal save rules. Failure never makes the card vanish.', body: `${valueNote('<b>Couldn’t save Botanica.</b> Your answers are still here.', 'is-error')}${candidateCard({ name: 'Botanica', area: 'Silver Lake', provenance: 'From a photo you chose Friday.' })}` },
      { name: 'Resolved / dismissed', code: 'RC-06', explainer: 'Success removes all aliases and refreshes the map. Dismiss stores a 90-day device-local exclusion and offers short Undo.', body: `${valueNote('<b>Saved to your map.</b> Botanica won’t be suggested again.', 'is-success')}<div class="screen-toast" style="position:static"><span>Candidate dismissed on this phone</span><button>Undo</button></div>` }
    ]
  },
  'accessibility-states': {
    kicker: 'State board E', title: 'Responsive and accessibility contract',
    note: 'The same information survives 320pt width, largest supported Dynamic Type, VoiceOver, Reduce Motion, keyboard, and long identity strings.',
    states: [
      { name: '320pt phone', code: 'AX-01', explainer: 'Horizontal people shelves remain scrollable. The active tab, card CTA, and dismiss target do not collide.', body: `<div class="a11y-pair"><div class="mini-phone"><div class="mini-phone-screen"><h4>People</h4>${miniSearch()}${personCard('maya')}</div></div><ul class="a11y-list"><li>16pt outer gutters</li><li>44pt actions preserved</li><li>Card width remains readable</li><li>No horizontal screen overflow</li></ul></div>` },
      { name: 'Largest type', code: 'AX-02', explainer: 'Rows grow vertically. Names may wrap before CTAs shrink. Horizontal profile cards become stacked rows if needed.', body: `<div style="font-size:1.35em">${sectionHeader('Suggested for You')}<div class="mutation-row" style="grid-template-columns:42px 1fr"><span class="avatar priya">PS</span><span class="mutation-copy"><b>Priya Venkataraman-Shah</b><small>2 people you follow follow Priya Venkataraman-Shah</small></span><button class="follow-button" style="grid-column:1/-1">Follow Priya</button></div></div>` },
      { name: 'VoiceOver order', code: 'AX-03', explainer: 'Card order is name, handle, reason, bio, then Follow. Dismiss is a separately named action and visual decorations are hidden.', body: `<ol class="a11y-list" style="counter-reset:item"><li>“Maya Chen, @mayamaps”</li><li>“Follows you”</li><li>Public bio</li><li>“Follow Maya Chen, button”</li><li>“Dismiss Maya Chen suggestion, button”</li></ol>` },
      { name: 'Non-color states', code: 'AX-04', explainer: 'Selected tabs use label, underline, and color. Following uses copy and border. Offline and errors use icon plus text.', body: `${valueNote('<b>You’re offline.</b> Connect to follow.', 'is-offline')}<button class="follow-button is-following">Following</button><div style="height:8px"></div>${valueNote('<b>Couldn’t follow.</b> Try again.', 'is-error')}` },
      { name: 'Reduce Motion', code: 'AX-05', explainer: 'Shelf changes use opacity or no animation. Skeleton shimmer stops. Focus and announcements carry state changes.', body: `${sectionHeader('Motion off')}<ul class="a11y-list"><li>No automatic carousel movement</li><li>No card reordering during follow</li><li>Dismiss removes without travel animation</li><li>Success announced via accessibility status</li></ul>` },
      { name: 'Long/localized copy', code: 'AX-06', explainer: 'No culturally unsafe first-name extraction. Display names can wrap. Reason payloads localize from kind + count.', body: `<div class="mutation-row" style="grid-template-columns:42px 1fr"><span class="avatar priya">PS</span><span class="mutation-copy"><b>Priya Venkataraman-Shah</b><small>12 people you follow follow Priya Venkataraman-Shah</small></span><button class="follow-button" style="grid-column:1/-1">Follow</button></div>` }
    ]
  }
};

let currentScreen = 'places-populated';
let currentBoard = 'places-states';
let currentWorkspace = 'journeys';
let currentDirection = 'a';
let resizeObserver;

function renderScreen(name) {
  if (name.startsWith('direction-b')) currentDirection = 'b';
  currentScreen = name;
  const meta = screenMetadata[name];
  $('#screen-kicker').textContent = meta.kicker;
  $('#screen-title').textContent = meta.title;
  $('#screen-note').textContent = meta.note;
  $('#flow-proof').innerHTML = meta.proofs.map(proof => `<li>${proof}</li>`).join('');
  $('#phone-canvas').innerHTML = screenTemplates[name]();
  wireScreenInteractions();
  prepareText($('#phone-canvas'));
}

function renderBoard(name) {
  currentBoard = name;
  const board = boards[name];
  $('#board-kicker').textContent = board.kicker;
  $('#board-title').textContent = board.title;
  $('#board-note').textContent = board.note;
  $('#state-grid').innerHTML = board.states.map(state => `
    <article class="state-card">
      <header class="state-card-head"><b>${state.name}</b><span>${state.code}</span></header>
      <div class="state-surface">${state.body}</div>
      <p class="state-explainer">${state.explainer}</p>
    </article>`).join('');
  prepareText($('#state-grid'));
}

function showToast(copy, action = '') {
  $('.screen-toast', $('#phone-canvas'))?.remove();
  $('.ios-screen', $('#phone-canvas'))?.insertAdjacentHTML('beforeend', toast(copy, action));
}

function wireScreenInteractions() {
  $$('.mode-tab', $('#phone-canvas')).forEach(button => {
    button.addEventListener('click', () => {
      const placesTarget = currentDirection === 'b' ? 'direction-b-home' : 'places-populated';
      renderScreen(button.dataset.mode === 'people' ? 'people-populated' : placesTarget);
    });
  });

  $$('[data-screen-target]', $('#phone-canvas')).forEach(button => {
    button.addEventListener('click', () => renderScreen(button.dataset.screenTarget));
  });

  $$('.follow-button:not(:disabled)', $('#phone-canvas')).forEach(button => {
    button.addEventListener('click', () => {
      if (button.classList.contains('is-following')) {
        showToast('Unfollow uses the existing confirmation flow.');
        return;
      }
      const profile = profiles[button.dataset.follow] || profiles.maya;
      button.classList.add('is-loading');
      button.disabled = true;
      button.textContent = 'Following';
      window.setTimeout(() => {
        button.classList.remove('is-loading');
        button.classList.add('is-following');
        button.disabled = false;
        showToast(`Following ${profile.name}. Shared places can now appear in Activity.`);
      }, 600);
    });
  });

  $$('.person-dismiss, .candidate-dismiss', $('#phone-canvas')).forEach(button => {
    button.addEventListener('click', () => {
      const target = button.closest('.person-card, .candidate-card');
      target?.remove();
      showToast('Hidden from this surface', 'Undo');
    });
  });

  $$('.candidate-action', $('#phone-canvas')).forEach(button => {
    button.addEventListener('click', () => {
      const card = button.closest('.candidate-card');
      const name = card?.dataset.candidate || 'this place';
      showToast(`${button.textContent.trim()} selected for ${name}. The normal save flow opens next.`);
    });
  });

  $('.clear-search', $('#phone-canvas'))?.addEventListener('click', event => {
    event.preventDefault();
    renderScreen(currentScreen === 'direction-b-answer' ? 'direction-b-home' : 'people-populated');
  });

  $('[data-answer-map]', $('#phone-canvas'))?.addEventListener('click', () => showToast('Showing the 4 matched restaurants on your map.'));
  $$('[data-refine]', $('#phone-canvas')).forEach(button => {
    button.addEventListener('click', () => showToast(`${button.dataset.refine} added to this answer.`));
  });

  $('[data-empty-action="signin"]', $('#phone-canvas'))?.addEventListener('click', () => showToast('Sign-in opens for: find and follow people.'));
  $('[data-empty-action="people"]', $('#phone-canvas'))?.addEventListener('click', () => renderScreen('people-populated'));
  $('[data-empty-action="visited"]', $('#phone-canvas'))?.addEventListener('click', () => showToast('Changing the answer to Joe’s visited restaurants.'));

  $('.bottom-sheet-backdrop', $('#phone-canvas'))?.addEventListener('click', event => {
    if (event.target.classList.contains('bottom-sheet-backdrop')) renderScreen('places-populated');
  });
}

async function prepareText(root = document) {
  await document.fonts.ready;
  const elements = $$('[data-pretext]', root);
  for (const element of elements) {
    if (!element.textContent.trim() || element.clientWidth <= 0) continue;
    const style = getComputedStyle(element);
    const handle = prepare(element.textContent, style.font);
    const lineHeight = Number.parseFloat(style.lineHeight) || Number.parseFloat(style.fontSize) * 1.25;
    const result = layout(handle, Math.max(1, element.clientWidth), lineHeight);
    if (result.height > 0) element.style.minHeight = `${Math.ceil(result.height)}px`;
    if (element.contentEditable === 'true' && !element.dataset.pretextWired) {
      element.dataset.pretextWired = 'true';
      new MutationObserver(() => prepareText(element.parentElement || root)).observe(element, { characterData: true, subtree: true, childList: true });
    }
  }
}

function setWorkspace(workspace) {
  currentWorkspace = workspace;
  const isJourneys = workspace === 'journeys';
  $('.journey-workspace').hidden = !isJourneys;
  $('.states-workspace').hidden = isJourneys;
  $('.journey-controls').hidden = !isJourneys;
  $('.state-controls').hidden = isJourneys;
  $('.viewport-controls').hidden = !isJourneys;
  isJourneys ? renderScreen(currentScreen) : renderBoard(currentBoard);
}

$$('[data-workspace]').forEach(button => {
  button.addEventListener('click', () => {
    $$('[data-workspace]').forEach(item => item.classList.toggle('is-active', item === button));
    setWorkspace(button.dataset.workspace);
  });
});

$$('[data-screen]').forEach(button => {
  button.addEventListener('click', () => {
    currentDirection = button.dataset.screen.startsWith('direction-b') ? 'b' : 'a';
    $$('[data-screen]').forEach(item => item.classList.toggle('is-active', item === button));
    renderScreen(button.dataset.screen);
  });
});

$$('[data-board]').forEach(button => {
  button.addEventListener('click', () => {
    $$('[data-board]').forEach(item => item.classList.toggle('is-active', item === button));
    renderBoard(button.dataset.board);
  });
});

$$('[data-width]').forEach(button => {
  button.addEventListener('click', () => {
    $$('[data-width]').forEach(item => item.classList.toggle('is-active', item === button));
    const width = Number(button.dataset.width);
    document.documentElement.style.setProperty('--phone-width', `${width}px`);
    document.documentElement.style.setProperty('--phone-height', `${Math.round(width * 2.164)}px`);
    prepareText($('#phone-canvas'));
  });
});

$$('[data-type]').forEach(button => {
  button.addEventListener('click', () => {
    $$('[data-type]').forEach(item => item.classList.toggle('is-active', item === button));
    document.documentElement.style.setProperty('--type-multiplier', button.dataset.type === 'large' ? '1.32' : '1');
    prepareText($('#phone-canvas'));
  });
});

resizeObserver = new ResizeObserver(() => {
  window.requestAnimationFrame(() => prepareText(currentWorkspace === 'journeys' ? $('#phone-canvas') : $('#state-grid')));
});
resizeObserver.observe($('.preview-stage'));

renderScreen(currentScreen);
