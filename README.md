# RescuePulse 2.0

> **Cloud-Native Disaster Response & Emergency Coordination Platform**  
> Built with Ballerina Swan Lake, Choreo Identity Platform, Open-Meteo, and Google Gemini Intelligence.

---

## 1. Executive Overview

**RescuePulse 2.0** is an enterprise-grade disaster management and tactical coordination platform designed for emergency operations centers, field rescue teams, and citizens. Built specifically to handle crisis management workflows—such as floods, landslides, cyclones, and structural emergencies in disaster-prone regions like Sri Lanka—RescuePulse provides real-time situational awareness, citizen SOS intake, human-in-the-loop verification, responder mission dispatch, and operational telemetry.

### Core Capabilities

- **Citizen Emergency Portal**: Zero-barrier SOS reporting with interactive GPS location picking, offline-capable location estimation, and secure photo evidence upload.
- **Administrator Command Center**: Real-time disaster mapping (Leaflet/OSM), human-in-the-loop report verification, severity categorization, duplicate detection, and automated responder recommendation.
- **Responder Tactical Dashboard**: Mobile-optimized field console for accepting dispatches, logging en-route/on-scene status, recording tactical notes, and filing completion reports.
- **Intelligence Layer**: Dual-mode operational intelligence combining live meteorological telemetry (Open-Meteo API) with server-side disaster analysis and summarization (Google Gemini API) backed by deterministic rule-based fallbacks.
- **Identity & Access Management**: Enterprise authentication powered by Choreo Identity Platform / Asgardeo using OAuth 2.0 / OpenID Connect (OIDC) PKCE flow with local RBAC fallback.

---

## 2. System Architecture

RescuePulse 2.0 is engineered with a decoupled cloud-native architecture. The frontend is built with high-performance vanilla HTML5, CSS3 (tactical dark glass design system), and ECMAScript modules, eliminating heavy framework overhead in low-bandwidth emergency conditions. The backend is an asynchronous, event-driven microservice suite written entirely in **Ballerina Swan Lake**.

```
+-----------------------------------------------------------------------------------+
|                                PRESENTATION LAYER                                 |
|                                                                                   |
|   +---------------------+   +---------------------+   +-----------------------+   |
|   |   Citizen Portal    |   | Responder Dashboard |   | Admin Command Center  |   |
|   |  (SOS & Tracking)   |   | (Missions & Status) |   | (Verification & Maps) |   |
|   +----------+----------+   +----------+----------+   +-----------+-----------+   |
|              |                         |                          |               |
|              +-------------------------+--------------------------+               |
|                                        | HTTP/1.1 (JSON / REST)                   |
+----------------------------------------|------------------------------------------+
                                         v
+-----------------------------------------------------------------------------------+
|                        BALLERINA SWAN LAKE BACKEND SERVICE                        |
|                                                                                   |
|   +---------------------------------------------------------------------------+   |
|   |                 Unified HTTP Listener (:8080) & Router                    |   |
|   +---------------------------------------------------------------------------+   |
|          |                |                |                 |             |      |
|          v                v                v                 v             v      |
|   +-------------+  +-------------+  +-------------+  +---------------+  +-------+ |
|   | Auth Service|  |  Incident   |  |    Admin    |  |  Operations   |  | Web   | |
|   | (RBAC/OIDC) |  |   Service   |  |   Service   |  |  & Responders |  | Static| |
|   +-------------+  +------+------+  +------+------+  +---------------+  +-------+ |
|                           |                |                                      |
|          +----------------+                +-----------------+                    |
|          |                                                   |                    |
|          v                                                   v                    |
|   +-------------+  +-------------+  +-------------+  +---------------+            |
|   | Data Engine |  |Notification |  | Alert Engine|  |Gemini & Weather|           |
|   | (Atomic FS) |  |   Service   |  | & Analytics |  |  Intelligence |            |
|   +------+------+  +-------------+  +-------------+  +-------+-------+            |
|          |                                                   |                    |
+----------|---------------------------------------------------|--------------------+
           |                                                   |
           v                                                   v
+-----------------------+                    +--------------------------------------+
| LOCAL SECURE STORAGE  |                    |         EXTERNAL INTEGRATIONS        |
| - Incident Store      |                    | - Choreo / Asgardeo (OIDC PKCE)      |
| - User Store          |                    | - Google Gemini 2.5 (Disaster AI)    |
| - Audit Trail         |                    | - Open-Meteo (Real-Time Weather)     |
| - Attachment Vault    |                    | - OpenStreetMap / Leaflet Engine     |
+-----------------------+                    +--------------------------------------+
```

---

## 3. Ballerina Backend Implementation

### Why Ballerina Swan Lake?

Ballerina was selected as the backend runtime because of its first-class language support for network primitives, concurrency, and structural data handling:

1. **Network-Native Architecture**: In Ballerina, network listeners, clients, endpoints, and HTTP payloads are native language concepts rather than external third-party libraries.
2. **Structural Type System**: Compile-time schema enforcement allows frictionless JSON transformation into strictly typed domain records (`IncidentRecord`, `UserRecord`, `MissionUpdate`).
3. **Safe Error Handling**: The `check` expression mechanism guarantees explicit error propagation across network boundaries without unhandled runtime exceptions.
4. **Isolated Concurrency**: Thread-safe memory isolation prevents race conditions when updating concurrent disaster records and mission logs.

### Backend Service Breakdown

| Service File | Purpose & Responsibilities |
| :--- | :--- |
| `auth_service.bal` | Handles authentication, session tokens, user registration, role validation (`citizen`, `responder`, `coordinator`), and Choreo OIDC PKCE bridging. Supports both `Bearer` headers and secure query token inspection for binary assets. |
| `incident_service.bal` | Governs the incident submission pipeline, geospatial queries, status filtering, photo attachment handling (magic-byte validation, size limits, directory-traversal protection), and mission state transitions. |
| `admin_service.bal` | Provides incident verification, priority modification, team assignment, mission revocation, and the **Smart Responder Recommendation Algorithm**. |
| `operations_service.bal` | Manages responder roster state, active mission queues, and real-time responder availability toggling. |
| `gemini_service.bal` | Server-side integration with Google Gemini 2.5 Flash for automated disaster priority assessment, duplicate report clustering, hazard briefings, and trend summaries. |
| `ai_service.bal` | Secure REST facade dispatching AI analytics with strict prompt sanitization and deterministic fallbacks when external APIs are unreachable. |
| `data_service.bal` | Atomic file-backed persistence engine with automatic data directory initialization, thread-safe JSON serialization, and immutable audit trail recording. |
| `alert_service.bal` | Generates system-wide broadcast alerts and category-based hazard warnings. |
| `notification_service.bal` | User-targeted notifications for status changes, mission alerts, and verification outcomes. |
| `analytics_service.bal` | Aggregates emergency velocity, district-level incident distributions, and response time KPIs. |
| `web_service.bal` | High-throughput static file server with automatic MIME-type detection for serving frontend assets. |
| `http_listener.bal` | Configures the central HTTP listener with configurable port binding and timeout parameters. |

---

## 4. Choreo Identity Platform & Asgardeo Integration

RescuePulse 2.0 integrates with **Choreo Identity Platform / Asgardeo** to provide identity and access management through **OpenID Connect (OIDC)** with **Proof Key for Code Exchange (PKCE)**.

### OIDC PKCE Authentication Flow

PKCE (RFC 7636) is mandatory for Single-Page Applications (SPAs) because it eliminates the need to store client secrets in client-side code:

```
[ Citizen / Responder / Admin ]       [ RescuePulse SPA ]        [ Choreo Identity Platform ]     [ Ballerina Backend ]
               |                               |                                 |                         |
               |---- 1. Click "Sign In" ------>|                                 |                         |
               |                               |-- 2. Generate code_verifier &   |                         |
               |                               |      code_challenge (SHA-256)   |                         |
               |                               |                                 |                         |
               |<--- 3. Redirect to Choreo ----|-- Redirect to /oauth2/authorize |                         |
               |                               |   with code_challenge --------->|                         |
               |                               |                                 |                         |
               |---- 4. Authenticate & Consent --------------------------------->|                         |
               |                                                                 |                         |
               |<--- 5. Redirect back to /sign-in.html with auth code -----------|                         |
               |                               |                                 |                         |
               |                               |-- 6. POST /oauth2/token ------->|                         |
               |                               |   with code & code_verifier     |                         |
               |                               |                                 |                         |
               |                               |<-- 7. Return ID & Access Token -|                         |
               |                               |                                 |                         |
               |                               |-- 8. Verify Claims & Establish Session ------------------>|
               |                               |      (Map Choreo Identity -> RescuePulse Role)            |
               |                               |                                                           |
               |                               |<-- 9. Issue Authenticated Session Token ------------------|
               |<--- 10. Route to Dashboard ---|
```

### Identity Configuration

Identity parameters are configured in `backend/src/Config.toml`:

```toml
# Choreo / Asgardeo Identity Platform Configuration
choreoClientId = "<YOUR_CHOREO_CLIENT_ID>"
choreoBaseUrl = "https://api.asgardeo.io/t/<YOUR_ORGANIZATION>"
```

The frontend SPA automatically queries `GET /auth/choreo-config` on initialization to discover the active identity provider parameters and configure the OIDC redirect URI dynamically.

---

## 5. Emergency Incident Lifecycle

RescuePulse enforces a finite state machine (FSM) ensuring human oversight over disaster response operations:

```
                  +---------------+
                  |   SUBMITTED   |<-----------------+ (Citizen SOS)
                  +-------+-------+
                          |
             [Admin Verifies Incident]
                          v
                  +---------------+
        +-------->|   VERIFIED    |--------+
        |         +-------+-------+        |
        |                 |                | [Admin Rejection]
[Mission Declined]   [Admin Dispatch]      v
        |                 |         +--------------+
        |                 v         |   REJECTED   |
        |         +---------------+ +--------------+
        +---------|   ASSIGNED    |
                  +-------+-------+
                          |
               [Responder Accepts]
                          v
                  +---------------+
                  |   ACCEPTED    |
                  +-------+-------+
                          |
              [Responder Leaves Base]
                          v
                  +---------------+
                  |   EN_ROUTE    |
                  +-------+-------+
                          |
             [Responder Arrives on Scene]
                          v
                  +---------------+
                  |   ON_SCENE    |
                  +-------+-------+
                          |
             [Rescue Actions Complete]
                          v
                  +---------------+
                  |   COMPLETED   |
                  +-------+-------+
                          |
                [Admin Final Review]
                          v
                  +---------------+
                  |    CLOSED     |
                  +---------------+
```

### Transition Security Matrix

| Current State | Next State | Permitted Role | Preconditions |
| :--- | :--- | :--- | :--- |
| `SUBMITTED` | `VERIFIED` | `coordinator` | Severity and category verified by operator |
| `SUBMITTED` | `REJECTED` | `coordinator` | Reason provided (e.g., spam, false alarm) |
| `VERIFIED` | `ASSIGNED` | `coordinator` | Eligible responder selected |
| `ASSIGNED` | `ACCEPTED` | `responder` | Assigned responder accepts mission |
| `ASSIGNED` | `DECLINED` | `responder` | Responder provides operational reason |
| `ACCEPTED` | `EN_ROUTE` | `responder` | Vehicle/unit departed |
| `EN_ROUTE` | `ON_SCENE` | `responder` | Arrival confirmed at GPS coordinates |
| `ON_SCENE` | `COMPLETED` | `responder` | Mission report logged |
| `COMPLETED` | `CLOSED` | `coordinator` | Final audit approval |

---

## 6. Security & Defense in Depth

1. **Role-Based Access Control (RBAC)**: Strict authorization barriers segment citizen data, responder operational logs, and administrative commands.
2. **Attachment Sanitization**:
   - File uploads are validated via binary **magic bytes** (JPEG `FF D8 FF`, PNG `89 50 4E 47`, WebP `52 49 46 46`).
   - Hard 5 MB payload size limit.
   - Files are stored with random UUID filenames.
   - Canonical path resolution blocks directory traversal (`../`) attacks.
3. **Credential Isolation**: Secrets, tokens, and keys are loaded via Ballerina's configuration engine (`Config.toml`) and environment variables. No secrets are exposed to the client.
4. **Deterministic AI Safeguards**: Generative AI suggestions (Gemini) are strictly advisory. Verification, priority escalation, and team dispatches require explicit human operator confirmation.

---

## 7. Directory Structure

```
RescuePulse-2.0/
├── backend/
│   └── src/
│       ├── tests/                     # Ballerina Automated Test Suites
│       │   └── service_tests.bal      # 17 Unit & Integration Tests
│       ├── admin_service.bal          # Admin & Verification Endpoints
│       ├── ai_service.bal             # AI Operations Bridge
│       ├── alert_service.bal          # Emergency Broadcast Alerts
│       ├── analytics_service.bal      # Telemetry & Operational KPIs
│       ├── auth_service.bal           # OIDC & Local Authentication
│       ├── Ballerina.toml             # Ballerina Package Definition
│       ├── Config.example.toml        # Configuration Template
│       ├── Config.toml                # Active Runtime Configuration
│       ├── data_service.bal           # Atomic Persistence Engine
│       ├── Dependencies.toml          # Locked Dependency Tree
│       ├── gemini_service.bal         # Gemini 2.5 API Client & Logic
│       ├── http_listener.bal          # HTTP Server Definition
│       ├── incident_service.bal       # Core Incident FSM & Media
│       ├── notification_service.bal   # Dispatch & Alert Notifications
│       ├── operations_service.bal     # Responder Roster Management
│       └── web_service.bal            # Static Asset Delivery Engine
├── frontend/
│   ├── assets/
│   │   └── images/                    # UI Assets & Operational Imagery
│   ├── admin-dashboard.html           # Administrator Command Center
│   ├── admin.css                      # Command Center Styling
│   ├── admin.js                       # Map Synchronization & Dispatch Logic
│   ├── auth.js                        # OIDC PKCE & Session Management
│   ├── citizen-portal.html            # Citizen SOS & Incident Tracker
│   ├── citizen.js                     # Location Picker & Report Form
│   ├── dashboard.css                  # Shared Tactical Glass Stylesheet
│   ├── dashboard.html                 # Responder Tactical Dashboard
│   ├── dashboard.js                   # Mission Execution & Notes Handler
│   ├── index.html                     # Public Platform Landing Page
│   ├── rescuepulse-2.css              # Landing & Portal Visual Engine
│   ├── sign-in.html                   # Authenticated Entrypoint
│   └── sign-up.html                   # Citizen Registration Portal
├── .dockerignore                      # Docker Build Exclusions
├── .gitignore                         # Git Repository Hygiene Rules
├── compose.yaml                       # Multi-Container Compose Setup
├── Dockerfile                         # Container Build Specification
├── LICENSE                            # License Specification
├── prepare-runtime.ps1                # Dependency & Tooling Bootstrap
├── README.md                          # Platform Documentation
└── start.ps1                          # Master Orchestration Script
```

---

## 8. Getting Started

### Prerequisites

- **Ballerina Swan Lake**: Version `2201.10.x` or higher (2201.13.x recommended).
- **Java Development Kit**: JDK 17 or JDK 21 (required by Ballerina compiler).
- **Web Browser**: Modern browser supporting Web Cryptography (for PKCE) and HTML5 Geolocation.

### Quick Start (PowerShell)

RescuePulse includes an automated runner script (`start.ps1`):

1. **Clone the Repository**:
   ```powershell
   git clone <REPO_URL>
   cd RescuePulse-2.0
   ```

2. **Configure Environment**:
   Copy the configuration template and populate credentials:
   ```powershell
   Copy-Item backend\src\Config.example.toml backend\src\Config.toml
   ```
   Edit `backend/src/Config.toml` with your administrative credentials, Choreo OIDC client ID, and Gemini API key.

3. **Run the Application**:
   ```powershell
   .\start.ps1
   ```
   The backend compiles, initializes data persistence, and starts the service at:
   - **Public Landing Page**: `http://localhost:8080/index.html`
   - **Authentication**: `http://localhost:8080/sign-in.html`
   - **Citizen SOS Portal**: `http://localhost:8080/citizen-portal.html`
   - **Responder Console**: `http://localhost:8080/dashboard.html`
   - **Command Center**: `http://localhost:8080/admin-dashboard.html`

---

## 9. Testing & Quality Assurance

RescuePulse includes an automated test suite verifying security controls, RBAC enforcement, session integrity, and incident state transitions:

```powershell
.\start.ps1 -Test
```

Or run directly through the Ballerina CLI:

```powershell
cd backend\src
bal test
```

### Verified Test Matrix

The test suite validates:
- [x] Initial admin authentication and session provisioning
- [x] Citizen registration and login validation
- [x] Responder profile generation and credential enforcement
- [x] Unauthenticated access rejection (HTTP 401)
- [x] Cross-role privilege escalation prevention (HTTP 403)
- [x] End-to-end incident submission with location validation
- [x] Administrator incident verification and priority triage
- [x] Mission dispatch and responder assignment
- [x] Full responder lifecycle: `ACCEPTED` -> `EN_ROUTE` -> `ON_SCENE` -> `COMPLETED`
- [x] Administrative incident closure
- [x] Atomic persistence and state recovery across restarts
- [x] Binary magic-byte attachment verification
- [x] Directory traversal vulnerability prevention

---

## 10. Container Deployment

To package RescuePulse as a standalone OCI container:

```bash
# Build the container image
docker build -t rescuepulse:2.0 .

# Run with local volume persistence
docker run -d \
  -p 8080:8080 \
  -v $(pwd)/runtime-data:/app/runtime-data \
  --name rescuepulse-instance \
  rescuepulse:2.0
```

Alternatively, launch using Docker Compose:

```bash
docker compose up -d
```

---

## 11. License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
