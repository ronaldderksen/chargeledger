# App Store

App Store-specific release notes, review details, and privacy notes live here.
Shared listing text, screenshots, and graphics live in `store/shared/`.

The current files are structured for manual App Store Connect entry or future
automation with Fastlane or the App Store Connect API.

## Assets

App Store-specific iPhone screenshots live in:

```text
store/app_store/assets/iphone-screenshots/
```

The current iPhone screenshots are `1284 x 2778` PNG files for the App Store
Connect 6.5-inch portrait screenshot slot.

App Store-specific iPad screenshots live in:

```text
store/app_store/assets/ipad-screenshots/
```

The current iPad screenshots are `2048 x 2732` PNG files for the App Store
Connect 13-inch iPad portrait screenshot slot.

## Credentials

Store App Store Connect API secrets locally in:

```text
store/app_store/secrets/app-store-connect-api.json
```

This directory is ignored by git. Do not commit `.p8` keys, key IDs, or issuer
IDs.

Use this JSON shape:

```json
{
  "key_id": "YOUR_KEY_ID",
  "issuer_id": "YOUR_ISSUER_ID",
  "key_filepath": "store/app_store/secrets/AuthKey_YOUR_KEY_ID.p8"
}
```

`store/app_store/app-store-config.json` points to this local secrets file.

Store Apple support and App Review contact details locally in:

```text
store/app_store/secrets/apple-support-contact.json
```

Use this JSON shape:

```json
{
  "first_name": "YOUR_FIRST_NAME",
  "last_name": "YOUR_LAST_NAME",
  "phone": "+31612345678",
  "phone_local": "0612345678",
  "email": "you@example.com"
}
```

Apple requires the App Review contact phone number in international format,
prefixed with `+` and a country code.

## Description Upload

The App Store description is read from the shared listing text:

```text
store/shared/listing/en-US/full-description.txt
```

The App Store promotional text is read from:

```text
store/shared/listing/en-US/promotional-text.txt
```

The App Store keywords are read from:

```text
store/shared/listing/en-US/keywords.txt
```

Support URL, marketing URL, Privacy Policy URL, copyright, and price tier are
read from:

```text
store/app_store/app-store-config.json
```

When `selectLatestBuild` is `true`, the upload script also selects the latest
processed iOS build for the editable App Store version. The build must already
be uploaded to App Store Connect and have processing state `VALID`.

Export compliance and Content Rights answers are read from
`store/app_store/app-store-config.json`. The current config marks the build as
not using non-exempt encryption and marks the app as not containing third-party
content.

The current price tier is `0`, which is the free App Store price tier.

App Information category and Age Rating answers are also read from
`store/app_store/app-store-config.json`.

App Review sign-in details are also read from `store/app_store/app-store-config.json`.
The current config marks sign-in as required and uses the demo account from:

```text
store/app_store/app-review/review-notes.txt
```

Preview what would be uploaded:

```text
store/app_store/scripts/upload.sh --dry-run
```

Upload the App Store metadata, Content Rights, export compliance, and latest
processed build selection:

```text
store/app_store/scripts/upload.sh
```

The upload script skips binary upload and does not submit for review.

Screenshot upload is disabled in the default metadata upload with
`uploadScreenshots: false` in `store/app_store/app-store-config.json`.
Upload screenshots separately with:

```text
store/app_store/scripts/upload.sh screenshots
```

The screenshot upload uses Fastlane `deliver` so screenshots are classified by
their PNG dimensions: iPhone `1284 x 2778` files go to `APP_IPHONE_65`, and iPad
`2048 x 2732` files go to `APP_IPAD_PRO_3GEN_129`.

Inspect the remote screenshot sets without changing them:

```text
cd store/app_store && fastlane diagnose_screenshots
```

If Fastlane retries create duplicate screenshots, remove duplicate checksums
without uploading new files:

```text
cd store/app_store && fastlane cleanup_screenshots
```

Pricing and App Privacy practices still need to be completed in App Store
Connect by an account with the required permissions.
