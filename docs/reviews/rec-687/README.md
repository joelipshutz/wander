# REC-687 snapshot feed evidence

The production postcard renders a synthetic seven-place snapshot with its map cover, snapshot creation label, list icon, and place count. The compact layout wraps attribution without truncation; both sizes keep the card controls visible.

- [iPhone 17 Pro Max, iOS 26.5](snapshot-large.png)
- [iPhone 17e, iOS 26.5](snapshot-compact.png)

Reproduce with `WanderUITests/MapSnapshotFeedUITests/testSnapshotCardShowsCountAndCoverOpensList`. It checks the count, the cover accessibility label, and the cover's list-navigation callback. The fixture uses bundled synthetic map artwork and no remote services. Full validation and deployment results are recorded in [PR #791](https://github.com/joelipshutz/wander/pull/791).
