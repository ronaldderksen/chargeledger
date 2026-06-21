# Google Play Tooling

This directory is for Google Play release automation and store listing tooling.

- `credentials/`: local-only service account JSON keys. This directory is ignored by git.
- `listing/`: commit-safe Google Play store listing text.
- `app-content/`: commit-safe drafts for Play Console app content declarations.
- `release/`: commit-safe release notes and release checklist.
- `assets/`: commit-safe asset requirements and generated store asset notes.
- `scripts/`: commit-safe scripts for updating Google Play metadata and releases.

Place the Google Play service account key at:

```text
play/credentials/google-play-service-account.json
```

Do not commit service account keys.

Android release signing uses `android/key.properties`, which is ignored by git.
Use `play/android-key.properties.example` as the local template.

Useful commands:

```text
play/scripts/update_play.sh --dry-run
play/scripts/publish_internal.sh
```

Google Play automation settings, app contact details, and tester Google Groups
live in `play/play-config.json`. Tester groups use the local-only
`appDetails.testerGoogleGroups` key; that key is not sent to the Google Play app
details endpoint.

`update_play.sh` also uploads Play listing graphics when changed:

- `play/assets/app-icon.png`
- `play/assets/feature-graphic.png`
- `play/assets/phone-screenshots/phone-1.png`
- `play/assets/phone-screenshots/phone-2.png`
- `play/assets/7-inch-screenshots/tablet-1.png`
- `play/assets/7-inch-screenshots/tablet-2.png`
- `play/assets/10-inch-screenshots/tablet-1.png`
- `play/assets/10-inch-screenshots/tablet-2.png`

Uploaded asset hashes are cached in `play/.cache/`, which is ignored by git.

Most Play Console App content forms are manual-only in Play Console. Use
`play/app-content/play-console-answers.md` as the copy/paste source. Data safety
can be uploaded through the Android Publisher API when an official Play Console
CSV is saved at `play/app-content/data-safety.csv`.
