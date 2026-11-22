# Pulse

**Pulse** is a native macOS multisport training and planning desktop application built with Flutter and Dart. It pulls live activity, route, device, and biometric data directly from **Garmin Connect**, enriches workouts with **Strava** social and segment data, and presents everything in a fast, local-first macOS interface.

> Repository: https://github.com/faizaanmadhani/pulse

---

## Features

### Live Data Sync & Enrichment
- **Garmin Connect Sign-In & Full History Backfill**: Native macOS `WKWebView` sign-in handles Garmin SSO and 2FA cleanly, pulls your latest 100 activities immediately, and backfills your full activity history in polite background batches.
- **Strava API Integration & Activity Joining**: Connects via Strava OAuth 2.0 (or personal access token), automatically matches Strava activities to their Garmin equivalents (by timestamp, distance, and sport), and syncs titles, descriptions, kudos, comments, gear, Relative Effort, and segment PRs.
- **Direct Cross-Links**: One-click **View in Garmin** and **View in Strava** buttons on every activity detail page.

### Interactive Maps & Telemetry Scrubber
- **Real Tile Maps (`flutter_map`)**: Renders CartoDB Voyager (Light Mode) and Dark Matter (Dark Mode) map tiles across both the Dashboard GPS Heatmap and individual activity routes.
- **Smart Home-Cluster Centering**: Automatically focuses your Dashboard heatmap on your primary training region instead of zooming out across continents for one-off travel workouts, with a one-click **Home Cluster / Fit All** toggle and sport layer filters (`All Sports`, `Run`, `Bike`, `Swim`).
- **Linked Route & Telemetry Scrubber**: Every GPS activity pairs a **Pace Heat Map** (Blue → Green → Orange → Red normalized to 5th–95th percentile speed) with a synchronized vertical stack of telemetry charts (**Pace/Speed, Elevation, Heart Rate, Cadence, Power, Vertical Oscillation, Ground Contact Time**). Hovering or scrubbing over either the route on the map or any chart moves the live cursor and crosshair across every metric simultaneously.

### Analytics & Training Planning
- **Clickable Training Load KPIs**: **Fitness (CTL)**, **Fatigue (ATL)**, **Form (TSB)**, and **ACWR Ratio** cards each include a built-in mini chart or zone gauge, derivation metrics, and click-to-inspect deep-dive panels showing contributing recent workouts.
- **Performance Management & Volume**: Interactive hoverable **PMC chart** (`4W`, `12W`, `6M`, `1Y`, `ALL`), **12-week Weekly Volume** stacked chart (Distance or Hours by sport), **Personal Records & Best Efforts**, **Performance by Distance** buckets, and **Aerobic Efficiency Trend** (`Speed ÷ Avg HR`).
- **Calendar & Race Goals**: Full **Day / Week / Month** granularity switcher with date navigation, clickable activity pills, and persistent A/B/C race targets with countdowns.
- **Native macOS Experience**: Light & Dark Mode support, global **Imperial (`MI / FT / yd`) / Metric (`KM / M`)** unit switcher in the toolbar, global activity search, and local-first token storage.

---

## Getting Started

### Prerequisites
- macOS (Apple Silicon or Intel)
- [Flutter SDK](https://docs.flutter.dev/get-started/install/macos) (Dart `>=3.4.0 <4.0.0`)
- Xcode (for macOS desktop builds)

### Install & Run
```bash
git clone https://github.com/faizaanmadhani/pulse.git
cd pulse
flutter pub get
flutter run -d macos
```

### Build a Standalone Release `.app`
```bash
flutter build macos --release
./run_app.sh
```
The compiled macOS bundle is written to `build/macos/Build/Products/Release/Pulse Training.app`.

---

## Connecting Your Accounts

### Garmin Connect
1. Open **Pulse** and click **Sign in with Garmin** (Dashboard, Sidebar, or **Garmin & Devices**).
2. Click **Open Garmin Sign-In** to sign in via the native macOS WebKit window (supports 2FA/MFA).
3. Pulse exchanges the session ticket for OAuth tokens, syncs your profile, devices, daily biometrics, and first 100 activities immediately, and backfills older activities in the background.

### Strava (Optional Enrichment)
1. Create a personal API application at https://www.strava.com/settings/api and set **Authorization Callback Domain** to `127.0.0.1`.
2. In Pulse, go to **Garmin & Devices → Connect Strava**.
3. Enter your **Client ID** and **Client Secret** and click **Connect with Strava** (or paste a Strava Access Token directly).
4. Pulse opens Strava's authorization page, captures the callback locally on `127.0.0.1:8765`, and automatically joins your Strava activities with Garmin.

---

## Privacy & Local Storage
- **No external backend**: Pulse communicates directly from your Mac to Garmin Connect, Strava, and CartoDB map tiles.
- **Passwords are never stored**: OAuth tokens and race goals are saved locally under `~/Library/Application Support/pulse_training_hub/` with user-only (`0600`) file permissions.

---

## Project Structure

```text
lib/
├── components/        # macOS HIG UI primitives, interactive charts, flutter_map heatmap, telemetry stack, auth dialogs
├── models/            # Activity, GpsPoint, StravaEnrichment, PerformanceMetrics, TrainingBlock, DeviceStatus
├── services/          # Garmin SSO/OAuth/API, Strava OAuth/API/matcher, native WebKit auth bridge, local stores
├── state/             # AppState (ChangeNotifier) managing sync, backfill, Strava joining, and unit preferences
├── theme/             # macOS Light & Dark Mode color tokens and SF Pro / SF Mono typography
├── utils/             # UnitFormatter (Imperial / Metric conversions & formatting)
└── views/             # Dashboard, Calendar, Analytics, Activities, Activity Detail, Strength, Garmin & Devices
macos/
└── Runner/            # Native NSWindow setup, WKWebView Garmin sign-in channel, and sandbox entitlements
test/                  # Unit & widget tests (Garmin, Strava, UnitFormatter, macOS layouts)
```

---

## Testing & Verification

```bash
flutter analyze
flutter test
```
