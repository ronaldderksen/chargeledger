# Google Play

Google Play-specific release automation and Play Console App content live here.

- `play-config.json`: Google Play automation settings and paths to shared
  listing, release notes, and assets.
- `app-content/`: Play Console App content answers and Data Safety draft.
- `scripts/`: Android Publisher API tooling.
- `credentials/`: local-only service account key location, ignored by git.
- `.cache/`: local-only uploaded asset hash cache, ignored by git.

Run a dry run from the repository root with:

```text
store/play/scripts/update_play.sh --dry-run
```
