# ChargeLedger Project Documentation

## Overview

ChargeLedger is a Flutter application with an optional Dart/Shelf backend for
tracking Zaptec charger usage. The app authenticates with Zaptec, synchronizes
chargers and charge history, stores the data, and presents filtered charge
session totals and details.

The same Flutter UI is used across platforms, but the storage backend differs:

- Native Flutter platforms use a local SQLite database.
- Flutter Web uses HTTP calls to the ChargeLedger server.
- The ChargeLedger server uses Postgres for persistent storage and serves the
  Flutter Web build under `/app/`.

## Main Components

### Flutter App

The app entry point is `lib/main.dart`.

Responsibilities:

- Creates the platform-specific repository.
- Starts the `ChargeLedgerApp`.
- Renders login, filters, totals, and charge session history.
- Uses `AppController` as the single source of UI state.

Important UI parts:

- `LoginPanel`: native Flutter login form.
- `BrowserLoginRedirect`: used on web to redirect to the server-rendered login.
- `TopControls`: charger, time field, and period filters.
- `TotalsPanel`: total sessions, energy, duration, and cost.
- `HistoryPanel`: charge session table.
- `HistoryColumnsDialog`: lets users reorder and hide charge session columns.
- `SettingsMenu`: settings menu for cost settings, plus web-only server data
  deletion.

### App Controller

Located in `lib/src/ui/app_controller.dart`.

Responsibilities:

- Initializes the repository.
- Loads and stores the active session state.
- Handles login and logout.
- Synchronizes chargers and charge history.
- Applies filters and refreshes visible history.
- Persists charge session column order and visibility.
- Applies the saved kWh price and currency to displayed cost values.
- Exposes loading, busy, message, and error state to the UI.

### Domain Model

Located in `lib/src/domain/models.dart`.

Core models:

- `ZaptecSession`: active Zaptec login session.
- `Charger`: Zaptec charger metadata.
- `ChargeSession`: one charging history record.
- `HistoryFilter`: current filter selection.
- `HistoryTotals`: aggregate values for the current filter.

Period helpers live in `lib/src/domain/history_periods.dart`.
Formatting helpers live in `lib/src/domain/formatters.dart`.

### Zaptec API Client

Located in `lib/src/data/zaptec_api.dart`.

Responsibilities:

- Requests a Zaptec OAuth token from `https://api.zaptec.com/oauth/token`.
- Loads chargers from the Zaptec API.
- Loads charge history from the Zaptec API.
- Normalizes Zaptec response shapes into local domain models.

The current charge history request fetches one page with `PageSize=100` and
`PageIndex=0`.

## Repository Backends

All backends implement `ChargeRepository` from
`lib/src/storage/charge_repository.dart`.

### Platform Factory

Located in `lib/src/storage/repository_factory.dart`.

The app selects the implementation with conditional imports:

- `repository_factory_io.dart` for Dart IO platforms.
- `repository_factory_web.dart` for Flutter Web.
- `repository_factory_stub.dart` as unsupported fallback.

### SQLite Repository

Located in `lib/src/storage/sqlite_charge_repository.dart`.

Used by native Flutter platforms. It stores data in:

```text
chargeledger.sqlite
```

inside the application documents directory.

Responsibilities:

- Creates or updates the local SQLite schema.
- Stores local session state in `schema_state`.
- Stores customers, chargers, and charge history.
- Calls Zaptec directly for login and synchronization.

### HTTP Repository

Located in `lib/src/storage/http_charge_repository.dart`.

Used by Flutter Web. It calls server endpoints such as:

- `GET /api/status`
- `GET /api/session`
- `POST /api/login`
- `POST /api/logout`
- `POST /api/server-data/delete`
- `GET /api/filter`
- `POST /api/filter`
- `GET /api/settings`
- `POST /api/settings`
- `GET /api/chargers`
- `POST /api/chargers/sync`
- `GET /api/history`
- `POST /api/history/sync`
- `GET /api/history/totals`
- `GET /api/history/period-options`

The web client stores the Zaptec access token in browser `sessionStorage`.
Postgres stores only non-secret session metadata. Sync requests send the access
token to the server for that request with the `X-Zaptec-Access-Token` header.
If the browser access token is missing or expired, the web client treats the
user as logged out and clears the server session.
Filter settings are persisted per user through `/api/filter`, so browser
refreshes restore the previous filter state without sharing filters across
users.
The kWh price and currency code are persisted per user through `/api/settings`
and applied to displayed cost values.
Charge session column order and visibility are persisted per user through
`/api/settings`.
Deleting server-side stored data is an explicit web settings action, not part
of logout.

### Postgres Repository

Located in `lib/src/server/postgres_charge_repository.dart`.

Used by the Dart server. It stores sessions and synchronized Zaptec data in
Postgres.

Session metadata is stored in `schema_state` using keys prefixed with the server
session id. Zaptec passwords and access tokens are not stored in Postgres.

## Database Schema

Shared table definitions are located in
`lib/src/storage/schema_definitions.dart`.

Main tables:

- `customers`
- `schema_state`
- `zaptec_chargers`
- `charger_measurements`
- `charge_history`

SQLite schema creation lives in `lib/src/storage/sqlite_schema.dart`.
Postgres schema creation and reconciliation lives in
`lib/src/storage/postgres_schema.dart`.

Important note: the Postgres schema reconciler removes columns that are no
longer present in `schema_definitions.dart`.

## Server

The server entry point is `bin/chargeledger_server.dart`.

Responsibilities:

- Opens a Postgres connection pool.
- Initializes the Postgres schema.
- Serves API routes with Shelf Router.
- Serves a server-rendered HTML login page.
- Serves the Flutter Web build under `/app/`.
- Stores the web session id in an HTTP-only cookie.
- Returns the Zaptec access token to the browser after login so the browser can
  keep it in `sessionStorage`.
- Requires a valid server session for `/app/` and all non-public API routes.
- Sends browser security headers and does not enable broad cross-origin API
  access.
- Deletes server-side stored data only through the explicit settings action,
  not during logout.

The server listens on `PORT`, defaulting to `8912`.

### Server Security

Public server routes are limited to the login flow, logout cleanup,
`GET /api/status`, `GET /api/session`, and `POST /api/login`.
All other `/api/*` routes require a valid `chargeledger_session` cookie before
the route handler is called. The Flutter Web app under `/app/` also requires a
valid server session; unauthenticated requests are redirected to `/`.

The session cookie is `HttpOnly` and `SameSite=Strict`. It is also marked
`Secure` when the external request scheme is HTTPS, based on the forwarded
protocol headers supplied by the ingress or reverse proxy.

The server no longer enables broad CORS headers. Browser responses include
`X-Content-Type-Options`, `Referrer-Policy`, `X-Frame-Options`,
`Content-Security-Policy` frame restrictions, `Permissions-Policy`, and
`Strict-Transport-Security` for HTTPS requests.

### Server Routes

HTML routes:

- `GET /`: shows login page or redirects to `/app/` when logged in.
- `POST /`: handles HTML login.
- `GET /login`: redirects to `/`.
- `POST /login`: handles HTML login.
- `GET /logout`: redirects to `/`.
- `POST /logout`: logs out and clears the session cookie.

API routes:

- `GET /api/status`
- `GET /api/session`
- `POST /api/login`
- `POST /api/logout`
- `POST /api/server-data/delete`
- `GET /api/filter`
- `POST /api/filter`
- `GET /api/settings`
- `POST /api/settings`
- `GET /api/chargers`
- `POST /api/chargers/sync`
- `GET /api/history`
- `POST /api/history/sync`
- `GET /api/history/totals`
- `GET /api/history/period-options`

Static web app:

- `/app/`

### Server Configuration

Configuration can come from environment variables or a YAML file.

Supported environment variables:

- `CHARGELEDGER_CONFIG`
- `ZAPWEB_CONFIG`
- `PORT`
- `POSTGRES_HOST`
- `POSTGRES_PORT`
- `POSTGRES_DB`
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `CHARGELEDGER_WEB_ROOT`

Default config file lookup:

- `/app/info.yaml`
- `info.yaml`

Example YAML shape:

```yaml
postgres:
  host: localhost
  port: 5432
  db: chargeledger
  user: chargeledger
  password: chargeledger
```

## Deployment Files

The repository includes:

- `Dockerfile`: builds Flutter Web and the Dart server CLI bundle.
- `docker-compose.yml`: runs the app and a Postgres database.
- `k8s/chargeledger.yaml`: Kubernetes deployment and service example.

Project instructions state that builds must not be run unless explicitly
requested.

## Login Alignment Requirement

The native Flutter login and the server-rendered HTML login should remain
aligned in:

- Fields
- Labels
- Layout
- Visual styling

This matters because native platforms render `LoginPanel`, while web users can
see the server-rendered login page before entering the Flutter Web app.

## Current Limitations And Risks

- There are currently no test files in the repository.
- Zaptec access tokens are persisted in local SQLite for native clients.
- In web/server mode, Zaptec access tokens are kept in browser
  `sessionStorage` and are not persisted in Postgres.
- User-facing errors can expose raw exception text.
- Charge history synchronization currently fetches only the first Zaptec page.
- The Postgres schema reconciler can drop removed columns.
- Web sessions are cookie-based and use `HttpOnly` and `SameSite=Strict`.
- Cross-site POST requests are rejected when `Origin` or `Referer` does not
  match the external request base URI.

## Development Notes

- Keep UI strings, messages, comments, and code identifiers in English.
- Do not run production builds unless explicitly requested.
- Lightweight checks such as formatting and analyzer commands are acceptable
  when needed for code changes.
- Keep native Flutter login and server-rendered HTML login visually aligned.
