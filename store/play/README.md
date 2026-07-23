# Google Play

Google Play-specific release configuration and Play Console App content live
here. Reusable publishing automation lives in
`/Users/ronald/Synced/git/dev-scripts`.

- `play-config.json`: Google Play automation settings and paths to shared
  listing, release notes, and assets.
- `app-content/`: Play Console App content answers and Data Safety draft.
- `credentials/`: local-only service account key location, ignored by git.
- `.cache/`: local-only uploaded asset hash cache, ignored by git.

Run a dry run from the repository root with:

```text
play-update --dry-run
```
