# Play Console App Content Answers

Use this file while completing **Policy and programs > App content** in Play
Console.

Most App content sections are not exposed through the Google Play edits API.
Fill them manually in Play Console using the answers below. The exception is
Data safety: Google provides a separate `applications.dataSafety` API that can
upload the official CSV export/template. Put that CSV at
`store/play/app-content/data-safety.csv` if you want `store/play/scripts/update_play.sh` to
upload it.

## Let us know about the content of your app

- App type: Utility / productivity tool.
- Description: Charge Ledger lets Zaptec users sign in, synchronize EV charging
  sessions, review charging history, filter results, calculate totals and
  estimated costs, and export a PDF.
- Restricted access: Yes, the main functionality requires a Zaptec account.
- Ads: No.
- In-app purchases: No.
- User-generated content: No public user-generated content.
- Location: No.
- Sensitive permissions: No high-risk permissions. Android only declares
  `android.permission.INTERNET`.

## Set privacy policy

- Privacy policy URL: `https://chargeledger.net/privacy.html`

## Sign-in details

- Login required: Yes.
- Login provider: Demo account for review, Zaptec for real users.
- Credentials: `demo` as the account name, empty password.
- Instructions:
  1. Open Charge Ledger.
  2. Enter `demo` as the account name.
  3. Leave the password field empty.
  4. Tap Log in.
  5. Tap Sync.
  6. Review filters, totals, charge history, PDF export, and settings.

## Ads

- Contains ads: No.

## Content rating

- Category: Utility / productivity.
- Violence: No.
- Sexual content: No.
- Profanity: No.
- Controlled substances: No.
- Gambling: No.
- User-generated content: No public user-generated content.
- User interaction: No public user interaction.
- Purchases: No in-app purchases.
- Location sharing: No.

## Target audience

- Target age group: 18 and over.
- Designed for children: No.
- Store listing appeal to children: No.

## Data safety

- Collects or shares user data: Yes.
- Data encrypted in transit: Yes.
- Data deletion available: Yes for hosted web app server data; native Android
  local data can be removed by clearing app storage or uninstalling.
- Email address: collected and shared with Zaptec for authentication and app
  functionality.
- Zaptec password: sent to Zaptec over HTTPS for authentication; not stored by
  Charge Ledger.
- Charger and charge session data: synchronized from Zaptec and stored locally
  on native Android for app functionality.
- App settings/activity: filters, table columns, kWh price, currency, and period
  selection are stored for app functionality.
- Analytics data: Firebase Analytics logs privacy-focused app interaction events
  such as login result, demo login, sync result, filter category changes, and PDF
  export. Events avoid account identifiers, charger names, exact dates, energy
  values, and cost values.
- Ads data: No.
- Location data: No.
- Device IDs: Review in Play Console because Firebase Analytics may use an app
  instance identifier or other analytics-related identifiers depending on
  Firebase configuration and the uploaded Android build.

## Government apps

- Developed by or on behalf of a government: No.

## Financial features

- Provides financial features: No.
- Explanation: The app only estimates charging cost from user-provided kWh price
  and charging energy. It does not provide banking, payments, lending, credit,
  investment, insurance, tax, wallet, crypto, or money-transfer functionality.

## Health

- Has health features: No.
