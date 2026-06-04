# Geofenced Clock-In / Clock-Out — Design (not yet implemented)

Status: **design only.** No location code exists in SteelSync today — `Project`/`Client`
store address as plain text, there are no location entitlements, and no CoreLocation
usage anywhere. This document is the plan to add jobsite geofencing to the foreman
time clock **without** ever stranding a crew or punishing a legitimate material run.

## Thesis: warn-and-flag, not lockout

Geofencing here is an **audit aid for the PM**, not a gate. Steel sites have poor signal,
large footprints, and foremen legitimately leave to pick up materials. A hard block that
prevents clock-out when GPS is off or the foreman is at the supply yard would lose real
hours and erode trust. So every enforcement point is **advisory**: it warns, records a
reason, and flags the shift for PM review — it never blocks the clock or auto-edits hours.

## 1. Data model additions

### Project
- `latitude: Double?`, `longitude: Double?` — jobsite coordinates.
- `geofenceRadiusMeters: Double` — default **150 m** (construction sites are large and GPS
  drifts; 100–200 m is the sane floor).
- Coordinates are **geocoded once** from the existing address string on project save
  (MapKit `CLGeocoder`, Apple ToS, no API key). A **manual map-pin override** is required
  for sites with no street address (a tap-to-drop-pin MapKit sheet).
- All three ride CloudKit on the `SS_Project` record so every device + the web agree.

### ClockInSession (already per-member after the lunch rework)
- `presence: Presence` — `inZone | outOfZone | onMaterialRun`.
- `zoneEvents: [ZoneEvent]` — append-only log; each event = `{ kind, timestamp, lat, lon }`,
  `kind ∈ enter | exit | materialRunStart | materialRunEnd | clockInLocation | clockOutLocation`.
- These persist in the existing UserDefaults session blob (decode-if-present, same back-compat
  pattern used for the per-member/lunch fields).

### TimesheetEntry
- `flaggedForReview: Bool` + `reviewReason: String` (optional, CloudKit-backed) — set when a
  shift had an out-of-zone clock without a material run, or a material run that ran long.
  Surfaces in a **"Needs Review"** filter in native Timekeeping; never blocks payroll.

## 2. Platform & permissions

- **Phone target only.** iPad/Mac are office tools — geofencing is compiled out there
  (`#if STEELSYNC_PHONE` / iOS-only).
- Add `NSLocationWhenInUseUsageDescription`. **When-In-Use is the default ask.** Background
  exit detection (geofence crossing while the app is closed) needs `Always` + the
  `location` background mode — request that **only** if we decide ongoing exit alerts are
  worth the battery/privacy cost; otherwise do a **foreground location check at clock-in
  and clock-out only** (much simpler, covers the main need).
- Recommended middle path: `CLLocationManager.startMonitoring(for:)` with a single
  `CLCircularRegion` per active session (fires enter/exit even backgrounded *if* the user
  granted Always; degrades to foreground-only checks under When-In-Use).
- **Monitor only while a session is active.** Stop all monitoring at clock-out — no
  always-on tracking (battery + privacy).
- **Graceful degradation:** if permission is denied or unavailable, geofencing becomes
  purely advisory — the clock still works, nothing is blocked, and the shift is noted as
  "location unavailable" rather than flagged as suspicious.

## 3. Enforcement points (all soft)

- **Clock-in:** if outside the project's geofence, show a non-blocking warning and require a
  one-tap reason (`Not at site yet` / `GPS off` / `Other`). Record `clockInLocation` and set
  `flaggedForReview` on the resulting entries. The crew still clocks in.
- **Clock-out:** same — warn + flag if out of zone, **never** silently auto-clock-out. Record
  `clockOutLocation`.
- **Ongoing (optional, Always only):** a zone **exit** while on the clock and **not** on a
  material run posts a local notification ("You've left the Harrison site — going for
  materials?") and, if unresolved, flags the shift. Re-entry logs an `enter` event.

## 4. The material-run escape hatch (the core requirement)

A foreman who leaves for materials must not be penalized and the crew must stay on the clock.

- Active-shift button **"Going for materials"** → `presence = onMaterialRun`, logs
  `materialRunStart`. Optionally captures a one-line reason ("Lowe's — anchor bolts") into
  the audit log so the PM has a paper trail.
- While `onMaterialRun`, geofence **exit does not flag** the shift and the crew stays clocked
  in. **"Back on site"** (or auto on zone re-entry) logs `materialRunEnd`, `presence = inZone`.
- **Guardrails against abuse:**
  - Material runs are **time-bounded** — default **90 min**, PM-configurable. Exceeding it
    notifies the foreman and **flags the shift for PM review** (`flaggedForReview = true`)
    rather than auto-resolving or auto-clocking-anyone-out.
  - Only the **foreman's** device is tracked (crew don't carry the app), so a material run
    pauses zone enforcement for the whole session by design.
  - The crew-on-clock state is **always preserved** — a material run never deducts crew hours.

## 5. PM visibility

- `zoneEvents` + material-run reasons sync to CloudKit on the shift's materialized entries.
- Per shift the PM sees: clock-in location ✓/✗ vs the geofence, any out-of-zone-without-a-run
  flags, and material-run durations.
- Flagged entries appear in a **"Needs Review"** filter in Timekeeping; the PM signs off
  before flagged hours are considered final. **No flagged-hours change happens automatically.**

## 6. Edge cases to handle in implementation

- **GPS spoofing / inaccuracy:** treat location as advisory; require PM sign-off before any
  flagged hours hit payroll. Use a generous radius to absorb drift.
- **Offline / dead-zone:** queue `zoneEvents` locally and sync on reconnect (offline-first).
  A foreman in a signal hole must still be able to clock out.
- **Project location changed mid-week:** geofence updates apply on the **next** clock-in, not
  retroactively to in-flight or past shifts.
- **Cross-midnight shifts:** the per-member `weekStart(for: memberStart)` already added in the
  clock rework handles week/day attribution; zone events just timestamp independently.
- **Permission revoked mid-shift:** detected via `CLLocationManager` delegate → fall back to
  advisory, surface a banner, never block clock-out.

## 7. Suggested build order (when greenlit)

1. `Project` coordinates + radius + geocode-on-save + manual map-pin override (+ CloudKit).
2. `CLLocationManager` wrapper service (phone-only): permission flow, one-shot location,
   single-region monitoring for the active session, graceful degradation.
3. Clock-in/out foreground location checks → warn + reason + flag (no blocking).
4. Material-run button + timer + 90-min guardrail + audit reason.
5. `flaggedForReview` plumbing + the "Needs Review" filter in native Timekeeping.
6. (Optional) Always-permission background exit monitoring + notifications.

## 8. Open decisions for Ruben

- Geofence radius default — **150 m** OK, or per-project always?
- Material-run limit — **90 min** default; on overage just **warn**, or **require PM approval**
  before those minutes count?
- `Always` location + background exit alerts, or **foreground checks only** at clock-in/out?
- Geocoding source — **MapKit CLGeocoder** (recommended, no key) vs Google (needs billing)?
- Is a manual map-pin override **required** for address-less sites (recommended yes)?
