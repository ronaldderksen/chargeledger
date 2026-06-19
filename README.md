# ChargeLedger

ChargeLedger helps you view and summarize your Zaptec charging history. Sign in
with your Zaptec account, synchronize your chargers and charge sessions, and use
the filters to inspect energy usage, duration, costs, and individual sessions.

## What You Can Do

- Sign in with a Zaptec account.
- Synchronize Zaptec chargers.
- Fetch recent charge history.
- Filter sessions by charger and time period.
- Reorder and hide charge session columns.
- View totals for sessions, energy, duration, and cost.
- Inspect the latest stored charge sessions in a table.
- Set a custom kWh price and currency for cost calculations.

## App Modes

ChargeLedger can run in two ways.

### Native App

On desktop or mobile Flutter platforms, ChargeLedger stores data locally in a
SQLite database on the device. The app talks directly to the Zaptec API.

### Web App With Server

On the web, ChargeLedger uses a Dart server. The server handles login sessions,
stores synchronized data in Postgres, and serves the Flutter Web app.

By default, the web app is served under:

```text
/app/
```

## Getting Started

### Run The Native Flutter App

Install Flutter and dependencies, then run the app for your target platform:

```sh
flutter pub get
flutter run
```

After the app opens:

1. Enter your Zaptec email and password.
2. Select a charger.
3. Press `Sync` to fetch chargers and charge sessions.
4. Use the filters to inspect stored history.

### Run With Docker Compose

For the web/server setup, create an `info.yaml` file in the project root:

```yaml
postgres:
  host: chargeledger-db
  port: 5432
  db: chargeledger
  user: chargeledger
  password: chargeledger
```

Then start the stack:

```sh
docker compose up -d
```

Open:

```text
http://localhost:8912
```

The server shows the login page first. After login, it redirects to the web app.

## Configuration

The server can be configured with environment variables:

- `PORT`
- `CHARGELEDGER_CONFIG`
- `CHARGELEDGER_WEB_ROOT`
- `POSTGRES_HOST`
- `POSTGRES_PORT`
- `POSTGRES_DB`
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`

If no config path is provided, the server looks for:

- `/app/info.yaml`
- `info.yaml`

## Data Storage

Native app:

- Stores data locally in `chargeledger.sqlite`.
- Keeps the Zaptec session and synchronized history on the device.
- Restores the last selected filters after app restart.
- Restores the charge session column setup after app restart.
- Restores the saved kWh price and currency after app restart.

Web/server app:

- Stores data in Postgres.
- Stores only a server session id in the browser cookie.
- Stores the Zaptec access token in browser `sessionStorage`.
- Does not store Zaptec passwords or access tokens in Postgres.
- Treats a missing browser access token as logged out.
- Lets web users delete stored server-side data from the settings menu.
- Restores each user's last selected filters after refresh or app restart.
- Restores each user's charge session column setup after refresh or app
  restart.
- Restores each user's saved kWh price and currency after refresh or app
  restart.

## Notes

- Charge history synchronization currently fetches the most recent Zaptec page.
- The visible session table shows the latest stored sessions for the selected
  filter.
- Filter settings are persisted and restored for the active user.
- Charge session column order and visibility are persisted and restored for the
  active user.
- If a kWh price is set, displayed costs are calculated from energy and that
  price, using the selected currency code.
- Logging out removes the active session. Web server data can be deleted from
  the settings menu.
- The app requires network access to `api.zaptec.com`.

## Developer Documentation

For architecture, code structure, database details, routes, and implementation
notes, see:

```text
PROJECT_DOCUMENTATION.md
```
