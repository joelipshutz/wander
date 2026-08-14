# rec.me App Store screenshot capture

Use this pipeline to generate the approved six-panel App Store story from the
exact release-candidate source tree. It does not sign in, query production
accounts, read the local user database, or send analytics.

## Safety boundary

- `-WanderUseStorefrontFixtures` selects a dedicated fictional social graph in
  Debug builds only. Release builds ignore the flag.
- The screenshot graph uses fictional people, venues, notes, and lists.
- Nearby Add suggestions come from `StorefrontPlaceResolver`, not Core Location
  or MapKit search.
- Place photography comes from the existing local capture asset through
  `MapCapturePlacePhotoRepository`.
- The map itself may load Apple map tiles, but the viewport is fixed and no
  device location permission is requested.
- Never replace this fixture with a production export or a real account dump.

## Generate the 6.9-inch set

From the release-candidate branch:

```bash
scripts/capture-app-store-screenshots.sh /tmp/recme-app-store-6.9
```

To reuse the Xcode cache across large and compact captures:

```bash
RECME_CAPTURE_DERIVED_DATA=/tmp/recme-app-store-derived-data \
  scripts/capture-app-store-screenshots.sh /tmp/recme-app-store-6.9
```

The script runs only `AppStoreScreenshotsUITests`, exports the six named XCTest
attachments, creates the 1320 × 2868 opaque panels, and produces the combined
storyboard. The output directory contains both the raw simulator captures and
the final panels.

## Compact-phone QA

Run the same six states on the smaller supported phone before approval:

```bash
scripts/capture-app-store-screenshots.sh \
  /tmp/recme-app-store-compact \
  "iPhone 16e" \
  "18.6"
```

Compact output is visual-QA evidence, not the upload set. Upload the 6.9-inch
panels generated from the final version 1.0 candidate.

## Approval checklist

Before upload, inspect the storyboard and every full-size panel:

1. Every visible person, venue, note, and list is fictional.
2. Frame 1 communicates the social map promise at thumbnail size.
3. Frame 3 shows multiple useful trusted-search results.
4. Frame 5 has useful suggested places and no empty-state banner.
5. Text, images, map labels, status bars, sheets, and bottom navigation are not
   clipped on either simulator.
6. All six final panels are opaque 1320 × 2868 PNGs.
7. The captures came from the exact commit archived as version 1.0.

Do not upload regenerated panels until Joe approves the final storyboard.
