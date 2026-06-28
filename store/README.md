# Store Tooling

This directory keeps store listing content, release notes, assets, and platform
automation together.

- `shared/`: content reused across stores, such as listing text, screenshots,
  graphics, and shared release notes.
- `play/`: Google Play-specific configuration, App content answers, credentials
  location, cache, and publishing scripts.
- `app_store/`: App Store-specific configuration, review notes, privacy notes,
  and release checklist.

## Shared Content

Shared listing text lives in `store/shared/listing/en-US/`:

- `title.txt`
- `promotional-text.txt`
- `keywords.txt`
- `short-description.txt`
- `full-description.txt`
- `keywords-notes.txt`

Shared assets live in `store/shared/assets/`:

- `app-icon.png`
- `feature-graphic.png`
- `phone-screenshots/phone-1.png`
- `phone-screenshots/phone-2.png`
- `7-inch-screenshots/tablet-1.png`
- `7-inch-screenshots/tablet-2.png`
- `10-inch-screenshots/tablet-1.png`
- `10-inch-screenshots/tablet-2.png`

Shared release notes live in `store/shared/release/release-notes-internal.txt`.

## Google Play

Place the Google Play service account key at:

```text
store/play/credentials/google-play-service-account.json
```

Do not commit service account keys. `store/play/credentials/` and
`store/play/.cache/` are ignored by git.

Android release signing uses `android/key.properties`, which is ignored by git.
Create or update that local file with `storePassword`, `keyPassword`,
`keyAlias`, and `storeFile` before publishing.

Useful commands:

```text
store/play/scripts/update_play.sh --dry-run
store/play/scripts/publish_internal.sh
```

Google Play automation settings, app contact details, tester Google Groups, and
shared content paths live in `store/play/play-config.json`.

Most Play Console App content forms are manual-only in Play Console. Use
`store/play/app-content/play-console-answers.md` as the copy/paste source. Data
safety can be uploaded through the Android Publisher API when an official Play
Console CSV is saved at `store/play/app-content/data-safety.csv`.

## App Store

The App Store folder is prepared for store-specific data that cannot be shared
directly with Google Play:

- `store/app_store/app-store-config.json`
- `store/app_store/secrets/app-store-connect-api.json` (local-only, ignored by
  git)
- `store/app_store/secrets/apple-support-contact.json` (local-only, ignored by
  git)
- `store/app_store/app-review/review-notes.txt`
- `store/app_store/app-privacy/privacy-notes.txt`
- `store/app_store/release/release-checklist.txt`

Reuse the shared listing text and assets unless App Store-specific copy or image
sizes are required.
