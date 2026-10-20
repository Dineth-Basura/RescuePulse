# RescuePulse

RescuePulse is a disaster response workspace for Sri Lanka. Responders record observations and field updates, while administrators manage incident priorities, assignments and account access.

This repository contains Dineth Basura's work on RescuePulse, developed with Team Innovators for the WSO2 Ballerina Hackathon 2025.

## Features

### Responder workspace

- Report incidents by location, category and severity.
- View reports you created or were assigned.
- Add response notes and follow the incident's activity history.
- Update assigned incidents as work moves from Open to Acknowledged to Resolved.
- Search and filter reports by status, priority, ownership and archive state.
- Export matching reports as CSV, including results on other pages.
- Save weather observations and review a district risk index.
- Read workspace notifications and mark them as read.
- Change your password and sign out of your sessions.

### Admin control center

Administrators have a separate dashboard. It focuses on oversight and access control rather than weather input or report creation.

- Review active, unassigned, overdue and high-priority incidents.
- Assign responders, set deadlines, change priorities and manage incident status.
- Apply assignment, status, priority, archive or restore actions to selected reports, up to 50 per batch.
- Compare responder workloads and identify assignments held by suspended accounts.
- Create responder and administrator accounts.
- Change account roles, suspend or reactivate access, and end another user's sessions.
- Open or close public registration.
- Enable or disable Gemini assistance and set the workspace's hourly request limit.
- Publish notifications to the workspace or an individual account.
- Review account, policy and incident activity in the audit trail.
- Export the incident queue and audit results as CSV.

Suspension revokes an account's sessions. The current administrator and the primary `admin` account are protected against suspension and role changes from the dashboard. Incident and policy edits use revision checks to prevent overwriting changes made by someone else.

### Gemini assistance

Gemini runs through the Ballerina backend. The browser never receives the API key.

- **Explain assessment:** summarizes manually entered weather observations and identifies information to verify.
- **Generate briefing:** produces an incident summary, suggested coordination steps, missing information and a handover draft.
- **Use handover as note draft:** copies the draft into the note form for review and editing before it is posted.

Requests are made only when someone selects an AI action. An incident briefing sends the report details and up to five recent notes to Gemini; dedicated account names and internal activity metadata are excluded. Free-text reports may still contain personal information, so avoid including sensitive details.

AI output does not change incident records, assign responders or dispatch anyone. Responses are checked before display, and incomplete or blocked responses produce an error instead of a partial briefing. Requests are limited per account and across the workspace; Google's own access and quota limits also apply.

## Tech stack

| Component | Technology |
| --- | --- |
| Backend | Ballerina Swan Lake 2201.13.6 |
| Frontend | HTML, CSS and JavaScript |
| API | REST over HTTP |
| AI integration | Google Gemini API; configurable model, default `gemini-3.8-flash` |
| Authentication | BCrypt password hashing and server-side bearer sessions |
| Storage | Local JSON files |
| Runtime | Java 21 |
| Container setup | Docker and Docker Compose |

The current web app does not require a Python service or a separate frontend server. The `ai/` directory contains earlier Python model scripts and data; these are not started by the application.

## Run locally

Install [Ballerina Swan Lake 2201.13.6](https://ballerina.io/downloads/) and Java 21. Make sure `bal` and `java` are available in your terminal.

From the project root on Windows:

```powershell
.\start.cmd
```

Open [http://localhost:8080](http://localhost:8080).

The launcher builds the backend and runs its executable. Ballerina serves the frontend and API from the same address. Stop the application with `Ctrl+C`.

For the installed Windows distribution, the launcher also handles the missing bundled HTTP/JSON dependency by rebuilding the installed HTTP source into a project-local cache. It does not change the Ballerina installation.

### Configure the administrator and Gemini

Create the local configuration file if it does not already exist:

```powershell
if (-not (Test-Path .\backend\src\Config.toml)) {
    Copy-Item .\backend\src\Config.example.toml .\backend\src\Config.toml
}
```

Edit `backend/src/Config.toml`. Keep any settings you already use, and replace the example values below:

```toml
port = 8080
dataDir = "runtime-data"
adminPassword = "replace-with-your-own-password"
geminiApiKey = "your-gemini-api-key"
geminiModel = "gemini-3.8-flash"
geminiMaxRequestsPerHour = 60
```

- Sign in with username `admin` and the password you set in `adminPassword`.
- Passwords must contain at least 8 characters and fit within 72 bytes.
- Leave `geminiApiKey` empty to run without Gemini assistance.
- `geminiMaxRequestsPerHour` supplies the initial AI limit. Once workspace settings are saved, the administrator's saved policy takes precedence.
- Restart after changing `Config.toml`. Changes made in the admin settings page apply without a restart.

`Config.toml` is excluded from Git and Docker build uploads. Do not put a real API key or password in frontend files or in `Config.example.toml`.

Users can register while public registration is open. When it is closed, an administrator can create accounts from People and access. Sign-in routes administrators and responders to their respective dashboards.

### Other platforms

With a complete Ballerina installation, run the package directly:

```sh
cd backend/src
bal run
```

The default port is `8080`. The frontend is served by Ballerina; opening the HTML files directly will not provide API access.

## Build and test

From the project root on Windows:

```powershell
.\start.cmd -Build
.\start.cmd -Test
```

With a complete Ballerina installation, the equivalent package commands are:

```sh
cd backend/src
bal build
bal test
```

Tests cover authentication, weather ingestion, risk scoring, incident workflows, revision conflicts, administrator permissions, account controls, workspace policies and Gemini response parsing. The test configuration uses a separate data directory and disables external Gemini calls.

HTTP tests start a listener on port `8080`; stop any running application instance before testing. The test environment must allow local socket connections.

## Docker

From PowerShell in the project root:

```powershell
$env:RESCUEPULSE_ADMIN_PASSWORD = "replace-with-your-own-password"
$env:GEMINI_API_KEY = "your-gemini-api-key"
docker compose up --build
```

Open [http://localhost:8080](http://localhost:8080). `GEMINI_API_KEY` is optional. Set `GEMINI_MODEL` if your account uses a different supported model.

The Compose configuration runs one Ballerina application container and stores its JSON data in the `rescuepulse-data` volume. Stop it with:

```sh
docker compose down
```

The named data volume remains available for the next start.

## Data storage

There is no MySQL, PostgreSQL or MongoDB server in this version. The backend reads and writes JSON files under `backend/src/runtime-data/` when started with the default local configuration.

| File | Contents |
| --- | --- |
| `users.json` | Accounts, BCrypt password hashes, access status and sign-in metadata |
| `incidents.json` | Reports, assignments, deadlines, notes, revisions and activity history |
| `weather.json` | Saved weather observations |
| `notifications.json` | In-app notifications and read status |
| `administration.json` | Workspace policy and administrative audit records |

These files are created as the relevant data is saved. Accounts and operational records persist across restarts. Login sessions stay in memory, expire after eight hours and end when the application restarts. The current hourly AI request counter also resets on restart.

The application retains up to 1,000 weather observations, 1,000 notifications and 1,000 administrative audit records. Incident activity remains with its report. Back up the data directory if you need to preserve the workspace.

## Risk index

The weather risk index is calculated in Ballerina using a weighted heuristic:

```text
score = 0.35 * (rainMm / 200)
      + 0.25 * (windKph / 120)
      + 0.15 * ((40 - tempC) / 40)
      + 0.10 * (humidityPct / 100)
      + 0.15 * (soilSatPct / 100)
```

The score is clamped to 0-1 and displayed as an index out of 100.

| Index | Level |
| --- | --- |
| Below 40 | Low |
| 40 to below 65 | Moderate |
| 65 and above | High |

This index is separate from Gemini assistance. It is not a trained forecast, a probability of disaster or an official warning. Weather observations are entered manually, and notifications are delivered within the app. RescuePulse does not contact emergency services or send SMS messages.

## Main API routes

Protected requests use `Authorization: Bearer <token>`. Administrator routes also check the account's current role.

| Route | Purpose |
| --- | --- |
| `POST /auth/signup`, `POST /auth/login` | Register and sign in |
| `GET /auth/me`, `POST /auth/logout`, `PUT /auth/password` | Account and session actions |
| `GET /auth/registration` | Check whether public registration is open |
| `GET /incident/list`, `GET /incident/{id}` | Read accessible reports |
| `POST /incident/create`, `PATCH /incident/{id}` | Create or update a report |
| `POST /incident/{id}/notes` | Add a response note |
| `POST /data/ingest`, `POST /data/ingestBatch` | Save weather observations |
| `GET /data/all`, `GET /data/stats` | Read stored observations and statistics |
| `POST /ai/predict` | Calculate the weighted risk index |
| `GET /assistant/status` | Check Gemini configuration and availability policy |
| `POST /assistant/weather/explain` | Request an explanation of weather observations |
| `POST /assistant/incidents/{id}/brief` | Request an incident briefing |
| `GET /notify/list`, `PUT /notify/read/{id}` | Read notifications and update read status |
| `POST /notify/publish` | Publish an in-app notification, subject to recipient permissions |
| `GET /admin/overview`, `GET /admin/users` | Workspace totals and account information |
| `POST /admin/users` | Create an account as an administrator |
| `PUT /admin/users/{username}/role` | Change an account role |
| `PUT /admin/users/{username}/status` | Suspend or reactivate an account |
| `POST /admin/users/{username}/revoke` | End another account's sessions |
| `GET /admin/settings`, `PUT /admin/settings` | Read or update workspace policy |
| `GET /admin/audit` | Read administrative and incident activity |

## Repository layout

| Path | Purpose |
| --- | --- |
| `backend/src/` | Ballerina package, services and configuration |
| `backend/src/tests/` | Ballerina tests and test configuration |
| `frontend/` | Landing page, sign-in, dashboards and Help center |
| `frontend/assets/` | Images and icons |
| `ai/` | Earlier Python model scripts and datasets |
| `start.cmd`, `start.ps1` | Windows startup, build and test commands |
| `prepare-runtime.ps1` | Local workaround for the Windows distribution dependency issue |
| `Dockerfile`, `compose.yaml` | Container build and runtime configuration |

## License

See [LICENSE](LICENSE).
