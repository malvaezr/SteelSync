# SteelSync - Project Context

## What This Is
A native macOS SwiftUI app for steel erection project management, built from an existing iOS app (JRFV4). All source code is in the `SteelSync/` directory.

## Project Location
`/Users/rubenmalvaez/Documents/Claudy_Projects/SteelSync/`

## How to Build
- Uses **XcodeGen** to generate the .xcodeproj from `project.yml`
- Run `xcodegen generate` then open `SteelSync.xcodeproj` in Xcode
- Or build from CLI: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SteelSync.xcodeproj -scheme SteelSync build`
- No code signing configured yet (runs unsigned for development)
- CloudKit disabled for now (runs with local sample data)

## Architecture
- **SwiftUI** with **MVVM** pattern
- **DataStore** (`Services/DataStore.swift`) — central `@MainActor ObservableObject` holding all state
- **NavigationSplitView** with sidebar → detail layout
- **CloudKit-ready** models using `CKRecord.ID` / `CKRecord.Reference` (container: `iCloud.com.jrsteelwelding.app`)

## File Structure (30 Swift files, ~5,200 LOC)
```
SteelSync/
├── SteelSyncApp.swift              # @main entry, window config, menu commands (Cmd+1-6)
├── Core/
│   ├── Theme/AppTheme.swift        # Colors (#FF6B35 orange, #1B4332 green), typography, spacing
│   ├── Navigation/AppNavigation.swift  # SidebarItem enum, NavigationState
│   └── Extensions/Extensions.swift    # Date (shortDate, adding days) & Decimal (currencyFormatted)
├── Models/
│   ├── Client.swift                # Client + RateType (sub/GC)
│   ├── Project.swift               # Project + ProjectBalanceSummary + ChangeOrder + Payment + PayrollEntry + Cost
│   ├── BidProject.swift            # BidProject + Touchpoint + Attachment
│   ├── Employee.swift              # Employee + EmployeeType + EmployeeStatus
│   ├── TimeEntry.swift             # TimeEntry + Decimal.rounded()
│   ├── WeeklyAssignment.swift      # WeeklyAssignment + token generation
│   ├── TodoItem.swift              # TodoItem + TodoPriority + TodoCategory
│   ├── CalendarEvent.swift         # CalendarEvent + EventType
│   ├── ResourceType.swift          # ResourceType + RateSchedule + ResourceUsage
│   ├── GanttTask.swift             # GanttTask + TaskCategory (10 types) + TaskStatus (6 types) + workday math
│   └── SampleData.swift            # Preview data for all models
├── Services/
│   └── DataStore.swift             # Central state: CRUD for all entities, financial calculations, Gantt tasks
├── Views/
│   ├── ContentView.swift           # NavigationSplitView routing
│   ├── Sidebar/SidebarView.swift   # Sections: Project Mgmt, Operations, Tracking
│   ├── Dashboard/
│   │   ├── DashboardView.swift     # HSplitView: project list + detail, metric cards, filters
│   │   ├── ProjectDetailView.swift # Tabbed: Overview, Change Orders, Payments, Payroll, Costs
│   │   ├── AddProjectView.swift    # Add + Edit project forms
│   │   └── ProjectFormSheets.swift # Add CO, Payment, Payroll, Cost sheets
│   ├── Bidding/
│   │   ├── BiddingView.swift       # HSplitView: bid list + detail, pipeline metrics
│   │   ├── BidDetailView.swift     # Bid info, construction metrics, touchpoints
│   │   └── BidFormViews.swift      # Add/Edit Bid, Add Touchpoint, Convert to Project
│   ├── Timekeeping/
│   │   └── TimekeepingView.swift   # Employee mgmt, crew management tab
│   ├── Gantt/
│   │   ├── GanttChartView.swift    # Main container: task list + scrollable timeline
│   │   ├── GanttViewModel.swift    # Timeline math, zoom, drag/resize logic
│   │   ├── GanttTimelineGridView.swift  # Canvas: grid, weekend shading, month/day headers, today marker
│   │   ├── GanttTaskBarView.swift  # Interactive bars: drag-to-move, drag-to-resize, progress fill
│   │   └── GanttTaskEditSheet.swift # Task create/edit form (category, status, workdays, progress)
│   ├── Clients/
│   │   └── ClientsView.swift          # Client CRUD, Sub/GC type, per-client financials, linked projects/bids
│   ├── Calendar/
│   │   └── CalendarMainView.swift  # (Replaced by Gantt, kept for reference)
│   ├── Todo/
│   │   └── TodoView.swift          # Task list with priority, category, due dates, filters
│   ├── Reports/
│   │   └── ReportsView.swift       # Overview, Projects, Bidding, Financial tabs + CSV export
│   └── Components/
│       └── SharedComponents.swift  # MetricCard, StatusBadge, InfoRow, FilterPill, ProgressBar, EmptyStateView
└── Resources/
    └── SteelSync.entitlements      # Sandbox + network + file access
```

## 7 App Modules

| Sidebar Section | What It Does |
|---|---|
| **Dashboard** | Project list with financials (contract, revenue, costs, profit, margin), change orders, payments, payroll, costs |
| **Clients** | Client management with Sub/GC tracking, contact info, per-client financials, linked projects & bids |
| **Bidding** | Pre-award pipeline: bid tracking, construction metrics (sq ft, beams, columns, tons), touchpoints, convert-to-project |
| **Timekeeping** | Employee management (W2/Contractor/Foreman), crew assignments with token system |
| **Schedule (Gantt)** | Interactive Gantt chart with 10 construction categories, drag/resize bars, zoom, today marker, workday math |
| **To-Do** | Task management with priority (Low→Urgent), category, due dates, overdue tracking |
| **Reports** | Financial summaries, project performance, bid pipeline, client analysis (revenue by type), P&L, CSV export |

## Financial Model
```
Revenue = Contract + Change Orders
Costs = Payroll + Other Costs
Profit = Revenue - Costs
Margin = Profit / Revenue × 100
Remaining = Revenue - Payments Received
```

## Gantt Chart Details
- 10 categories: Lead Time, Fabrication, Delivery, Erection, Inspection, RFI/Submittal, Deadline, Meetings, Pay App, Other
- 6 statuses: Not Started, In Progress, Completed, Delayed, On Hold, Milestone
- Work day calculation (excludes weekends, optional Saturday inclusion)
- Canvas-based grid for performance (weekend shading, day lines, month headers)
- Drag bars to move (snaps to days), drag right edge to resize
- Today marker (red line + badge)
- Zoom in/out (5-100px per day)
- Master view groups tasks by project, or filter to single project

## Reference Projects
- **JRFV4** (original iOS app): `/Users/rubenmalvaez/Downloads/JRFV4/`
- **JRGantt** (Gantt reference): `/Users/rubenmalvaez/Downloads/JRGantt/`

## Equipment Rental Tracking
- EDTX rate sheet with 18 equipment types (scissors, booms, telehandlers, forklifts)
- Daily / Weekly / 4-Week (Monthly) rates with $140/trip delivery charge
- Auto-calculates optimal cost combination (e.g., 2x 4-week + 1x week + 3x day)
- Open rentals show running cost estimate; closing creates a Cost entry automatically
- Equipment tab in Project Detail with active/closed rental views

## What's Not Wired Up Yet
- CloudKit sync (models are ready, entitlements need dev team signing)
- Crew assignment token system (UI scaffold exists)
- Push notifications

## Key Dependencies
- XcodeGen (`brew install xcodegen`) — generates .xcodeproj from project.yml
- macOS 14.0+ deployment target
- Swift 5.9+

## User Preferences
- Security review hooks run after every Edit/Write and before every Bash command (configured in `~/.claude/settings.json`)
- Effort level: max
