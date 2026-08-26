# PacTrack Architecture & File Structure

## Component Hierarchy

```
RooMate App
├── ContentView
│   └── PacTrackView
│       ├── Header Section
│       ├── Grade Selector (Segmented Picker)
│       ├── Progress Visualizer (Circular Progress)
│       ├── Seasonal Activities Section
│       │   ├── SeasonActivityCard (Fall)
│       │   ├── SeasonActivityCard (Winter)
│       │   └── SeasonActivityCard (Spring)
│       ├── Additional Credits Section (Stepper)
│       └── PacTrackFooter
│           ├── Success State (Requirement Met)
│           └── Warning State (Short on Credits + Exemption Link)
└── PacTrackStore (StateObject)
    └── Persisted Data (UserDefaults)
```

## Files Added

### 1. PacTrackModels.swift (227 lines)
**Purpose**: Data models and business logic

**Key Types**:
- `enum PacTrackGrade` - Grade levels with credit requirements
- `enum ActivityType` - All activity options with credit values
- `enum PacTrackSeason` - Fall/Winter/Spring organization
- `struct SeasonalActivity` - Individual activity slot
- `struct PacTrackPlan` - Complete plan with calculations

**Key Calculations**:
```swift
totalCredits: Int → Sum of all activities (with Robotics special case)
creditsRemaining: Int → Target - Current (min 0)
requirementMet: Bool → totalCredits >= target
progressPercentage: Double → Current / Target (capped at 1.0)
```

### 2. PacTrackStore.swift (85 lines)
**Purpose**: State management & persistence

**Key Responsibilities**:
- Manages current `PacTrackPlan`
- Saves/loads from UserDefaults under key `"pactrack_plans"`
- Provides update methods for each activity slot
- Handles custom credit input for exemptions
- Auto-saves after every change

**Public Methods**:
- `savePlan()` - Encodes and saves to UserDefaults
- `loadPlan()` - Decodes from UserDefaults
- `updateGrade()` - Changes selected grade
- `updateFallActivity()`, `updateWinterActivity()`, `updateSpringActivity()` - Activity selection
- `updateAdditionalCredits()` - Manual credit input
- `reset()` - Resets plan while keeping grade

### 3. PacTrackView.swift (338 lines)
**Purpose**: Complete UI implementation

**View Structure**:
1. **Header** - Title and description
2. **Grade Selection** - Segmented picker with target info
3. **Progress Circle** - 140x140 circular progress indicator
4. **Activity Pickers** - Three seasonal cards with:
   - Season emoji/icon
   - Dropdown to select activity
   - Credit badge display
   - Custom credit input for exemptions
5. **Additional Credits** - Stepper for extra credits
6. **Footer** - Dynamic success/warning message + exemption link

**Sub-components**:
- `SeasonActivityCard` - Reusable seasonal slot
- `Badge` - Credit display component
- `PacTrackFooter` - Status footer with CTA

### 4. ContentView.swift (Updated)
**Changes Made**:
- Added `.pactrack` case to `Tab` enum
- Added title: "PacTrack"
- Added systemImage: "badge.plus.radiowaves.right"
- Added macOS detail view case for PacTrackView
- Added iOS content switch case for PacTrackView
- Added tab to ModernTabBar iOS tab list

## Data Flow

```
User Action (e.g., selects activity)
    ↓
PacTrackView updates @State binding
    ↓
Calls PacTrackStore method (e.g., updateFallActivity)
    ↓
PacTrackStore updates @Published currentPlan
    ↓
PacTrackStore calls savePlan() → UserDefaults
    ↓
UI automatically re-renders with new calculations
```

## Calculation Engine

### Total Credits Algorithm
```swift
func totalCredits() -> Int {
  var total = additionalCredits
  
  for activity in [fallActivity, winterActivity, springActivity] {
    if activity.isRobotics {
      return grade.requiredCredits  // Special case: satisfies all
    }
    total += activity.creditValue
  }
  
  return total
}
```

### Progress Percentage
```swift
progressPercentage = min(totalCredits / requiredCredits, 1.0)
```

This caps at 100% even if user exceeds requirement.

## State Management Pattern

```
@StateObject var store = PacTrackStore()
  ↓
store.currentPlan: PacTrackPlan
  ├── grade: PacTrackGrade
  ├── fallActivity: SeasonalActivity
  ├── winterActivity: SeasonalActivity
  ├── springActivity: SeasonalActivity
  └── additionalCredits: Int
```

All changes trigger:
1. `@Published` notification
2. UI re-evaluation
3. Automatic save to UserDefaults

## Design System Integration

**Uses DesignTokens for**:
- Colors: primary, accent, success, warning
- Typography: headline2, title, body, caption
- Spacing: xs, sm, md, lg, xl, xxl
- Radius: sm, md, lg, xl
- Shadows: subtle, small, medium, large

**Uses Helper Functions**:
- `compatibleBackgroundSecondary()` - Platform-aware backgrounds
- `designShadow()` - Apply design shadows
- `SecondaryForeground()` - Compatibility modifier

## Persistence Strategy

**Key**: `"pactrack_plans"`
**Format**: JSON (Codable)
**Scope**: Local device only
**Lifecycle**: Survives app close/reopen until user resets

**Saved Structure**:
```json
{
  "grade": "10th Grade",
  "fallActivity": {
    "season": "fall",
    "activityType": "varsityJVSports",
    "customCredits": 0
  },
  "winterActivity": {...},
  "springActivity": {...},
  "additionalCredits": 2
}
```

## Error Handling

- **Decoding Failure**: Falls back to blank `PacTrackPlan()`
- **Encoding Failure**: Prints error, changes still in memory
- **No Data**: Starts with fresh plan
- **Invalid Activity**: Picker prevents invalid selections

## Extensibility Points

1. **Add New Activity Type**: Add to `ActivityType` enum
2. **Add Season**: Add to `PacTrackSeason` enum
3. **Change Credit Rules**: Modify `Activity.creditValue`
4. **Add Export**: Extend `PacTrackStore` with export methods
5. **Add Planning Scenarios**: Create multiple `PacTrackPlan` objects

