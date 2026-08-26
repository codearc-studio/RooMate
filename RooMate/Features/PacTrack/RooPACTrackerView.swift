import SwiftUI

// MARK: - RooPAC data

struct RooPACPlan: Codable, Hashable {
  var isSelected: Bool = false
  var overrideCredits: Int? = nil
  /// Only used by the flexible Other / Custom entry.
  var customTitle: String? = nil
}

enum RooPACGrade: String, CaseIterable, Identifiable, Codable, Hashable {
  case ninth
  case tenth
  case eleventh
  case twelfth

  var id: String { rawValue }

  var title: String {
    switch self {
    case .ninth: "9th Grade"
    case .tenth: "10th Grade"
    case .eleventh: "11th Grade"
    case .twelfth: "12th Grade"
    }
  }

  var shortTitle: String {
    switch self {
    case .ninth: "9th"
    case .tenth: "10th"
    case .eleventh: "11th"
    case .twelfth: "12th"
    }
  }

  /// Official 2026–27 annual RooPAC requirement.
  var requirement: Int {
    switch self {
    case .ninth, .tenth: 5
    case .eleventh: 4
    case .twelfth: 3
    }
  }

  /// Grade derived from a graduation year. RooMate treats July as the next school year.
  static func current(forGraduationYear graduationYear: Int, reference: Date = Date())
    -> RooPACGrade?
  {
    let calendar = Calendar.current
    let year = calendar.component(.year, from: reference)
    let month = calendar.component(.month, from: reference)
    let academicYearEnd = month >= 7 ? year + 1 : year

    switch graduationYear - academicYearEnd {
    case 0: return .twelfth
    case 1: return .eleventh
    case 2: return .tenth
    case 3: return .ninth
    default: return nil
    }
  }

  static func academicYearEnd(reference: Date = Date()) -> Int {
    let calendar = Calendar.current
    let year = calendar.component(.year, from: reference)
    let month = calendar.component(.month, from: reference)
    return month >= 7 ? year + 1 : year
  }

  static func validGraduationYears(reference: Date = Date()) -> [Int] {
    let endingYear = academicYearEnd(reference: reference)
    return Array(endingYear...(endingYear + 3))
  }
}

enum RooPACActivityType: String, CaseIterable, Identifiable, Codable, Hashable {
  case varsityAthletics
  case jvAthletics
  case peWellness
  case yogaDance
  case supportCrew
  case artsTheater
  case roobotics
  case exemptionRequest
  case smallFarms

  /// Flexible fallback for an approved activity RooMate does not list yet.
  /// It also preserves compatibility with older saved `.other` values.
  case other

  var id: String { rawValue }

  static var officialCases: [RooPACActivityType] {
    allCases
  }

  var title: String {
    switch self {
    case .varsityAthletics:
      "Varsity Interscholastic Athletics"
    case .jvAthletics:
      "JV Interscholastic Athletics"
    case .peWellness:
      "Physical Education / Wellness Class"
    case .yogaDance:
      "Yoga / Strength & Conditioning / Dance"
    case .supportCrew:
      "Athletic Department Support / Team Manager / SFR"
    case .artsTheater:
      "Arts / Theater / JMASS / Dance"
    case .roobotics:
      "Roobotics"
    case .exemptionRequest:
      "RooPAC Exemption Request"
    case .smallFarms:
      "Small Farms Course"
    case .other:
      "Other / Custom Activity"
    }
  }

  var shortTitle: String {
    switch self {
    case .varsityAthletics: "Varsity Athletics"
    case .jvAthletics: "JV Athletics"
    case .peWellness: "PE / Wellness"
    case .yogaDance: "Wellness Activities"
    case .supportCrew: "Athletic Support / SFR"
    case .artsTheater: "Arts / Theater"
    case .roobotics: "Roobotics"
    case .exemptionRequest: "Exemption Request"
    case .smallFarms: "Small Farms"
    case .other: "Other / Custom"
    }
  }

  var subtitle: String {
    switch self {
    case .varsityAthletics:
      "Complete three different varsity seasons"
    case .jvAthletics:
      "Complete three different JV seasons"
    case .peWellness:
      "One semester PE / Wellness class"
    case .yogaDance:
      "Yoga, strength sessions, dance, or pep-cheer"
    case .supportCrew:
      "Support crew, team manager, or Student First Responder"
    case .artsTheater:
      "Performance, stage management, JMASS tech, or dance movement"
    case .roobotics:
      "After-school robotics participation"
    case .exemptionRequest:
      "Approved outside activity"
    case .smallFarms:
      "Bee yard or school gardens course work"
    case .other:
      "Add an approved activity RooMate does not list yet"
    }
  }

  var icon: String {
    switch self {
    case .varsityAthletics: "trophy.fill"
    case .jvAthletics: "figure.run"
    case .peWellness: "heart.text.square.fill"
    case .yogaDance: "dumbbell.fill"
    case .supportCrew: "person.3.fill"
    case .artsTheater: "theatermasks.fill"
    case .roobotics: "gearshape.2.fill"
    case .exemptionRequest: "doc.text.fill"
    case .smallFarms: "leaf.fill"
    case .other: "archivebox.fill"
    }
  }

  var commitment: String {
    switch self {
    case .varsityAthletics:
      "Three different seasons. Practices and games take place after school, on weekends, and on days when school is not in session."
    case .jvAthletics:
      "Three different seasons. Practices and games take place after school and on occasional weekends."
    case .peWellness:
      "During the school day. One semester class selected during course registration."
    case .yogaDance:
      "Offered September through May. Strength & Conditioning generally meets after school; yoga is Wednesdays; dance meets Tuesdays and Thursdays."
    case .supportCrew:
      "Three different seasons. Students must be available for practices and games after school, on weekends, and on days when school is not in session."
    case .artsTheater:
      "Multiple productions are available. Rehearsals may take place after school, on weekends, and on days when school is not in session. Dance movement is a semester course."
    case .roobotics:
      "After school, on weekends, and on days when school is not in session."
    case .exemptionRequest:
      "RooPAC value is based on hours committed to the outside activity and the scope of performance intensity."
    case .smallFarms:
      "Students work in the bee yard or school gardens during class time and must meet course expectations."
    case .other:
      "Use this only for an approved activity that is missing from RooMate's built-in list."
    }
  }

  var guidance: String {
    switch self {
    case .varsityAthletics:
      "Coaches take attendance. Student-athletes must complete the season."
    case .jvAthletics:
      "Coaches take attendance. Student-athletes must complete the season."
    case .peWellness:
      "Scheduled by Academic Guidance. Pass/Fail course."
    case .yogaDance:
      "Every 25 one-hour sessions earns 1 RooPAC. Students must sign in; instructors take attendance. Dance can earn 1–2 RooPACs."
    case .supportCrew:
      "Includes game management, facility support, sports photography, team-management duties, or Student First Responder responsibilities."
    case .artsTheater:
      "Must be confirmed by the Arts/Theater Department. JMASS: 60 hours = 1 RooPAC; 120 hours = 2 RooPACs. Dance movement can earn 1–2 RooPACs."
    case .roobotics:
      "Must be confirmed by the Robotics Team Head Coach."
    case .exemptionRequest:
      "Students submit the exemption form each year with activity details and hours. Approval is granted by the Athletics/Wellness Committee."
    case .smallFarms:
      "Students earn the RooPAC after meeting attendance requirements and work expectations."
    case .other:
      "Give the activity a name and enter the RooPAC amount you expect it to count for. Confirm the amount with the school when needed."
    }
  }

  var minCredits: Int {
    switch self {
    case .varsityAthletics: 3
    case .jvAthletics: 2
    case .peWellness: 2
    case .yogaDance: 1
    case .supportCrew: 1
    case .artsTheater: 1
    case .roobotics: 1
    case .exemptionRequest: 3
    case .smallFarms: 1
    case .other: 0
    }
  }

  var maxCredits: Int {
    switch self {
    case .varsityAthletics: 3
    case .jvAthletics: 2
    case .peWellness: 2
    case .yogaDance: 5
    case .supportCrew: 2
    case .artsTheater: 3
    case .roobotics: 2
    case .exemptionRequest: 5
    case .smallFarms: 1
    case .other: 12
    }
  }

  var hasVariableValue: Bool {
    minCredits != maxCredits
  }

  var rangeDescription: String {
    if minCredits == maxCredits {
      return minCredits == 1 ? "1 RooPAC" : "\(minCredits) RooPACs"
    }
    return "\(minCredits)–\(maxCredits) RooPACs"
  }

  var formURL: URL? {
    switch self {
    case .exemptionRequest:
      URL(
        string:
          "https://docs.google.com/forms/d/e/1FAIpQLSddo4yesbk-KMYhG8jzS2NF7KmBqMxaxSE81ae7ICx-YF-zDg/viewform"
      )
    default:
      nil
    }
  }
}

// MARK: - PacTrack dashboard

struct RooPACTrackerView: View {
  @ObservedObject var store: UserScheduleStore

  @State private var showActivityPicker = false
  @State private var showRequirements = false
  @State private var selectedActivity: RooPACActivityType?
  @State private var previewGrade: RooPACGrade?

  private let accent = DesignTokens.Colors.pacTrack
  private let calendarYear = "2026–27"

  private func planBinding(for activity: RooPACActivityType) -> Binding<RooPACPlan> {
    Binding(
      get: { store.rooPacPlans[activity] ?? RooPACPlan() },
      set: { store.rooPacPlans[activity] = $0 }
    )
  }

  private var selectedPlans: [(activity: RooPACActivityType, plan: RooPACPlan)] {
    RooPACActivityType.officialCases.compactMap { activity in
      let plan = store.rooPacPlans[activity] ?? RooPACPlan()
      return plan.isSelected ? (activity, plan) : nil
    }
  }

  private var activeGrade: RooPACGrade {
    previewGrade ?? store.rooPACCurrentGrade
  }

  private var isPreviewingGrade: Bool {
    previewGrade != nil && previewGrade != store.rooPACCurrentGrade
  }

  private var currentRequirement: Int {
    activeGrade.requirement
  }

  private func credits(
    for activity: RooPACActivityType,
    plan: RooPACPlan,
    useMaximum: Bool
  ) -> Int {
    if let exact = plan.overrideCredits {
      return exact
    }
    return useMaximum ? activity.maxCredits : activity.minCredits
  }

  private var minimumPlanned: Int {
    selectedPlans.reduce(0) { partial, item in
      partial
        + credits(
          for: item.activity,
          plan: item.plan,
          useMaximum: false
        )
    }
  }

  private var maximumPlanned: Int {
    selectedPlans.reduce(0) { partial, item in
      partial
        + credits(
          for: item.activity,
          plan: item.plan,
          useMaximum: true
        )
    }
  }

  private var progress: Double {
    guard currentRequirement > 0 else { return 0 }
    return min(Double(minimumPlanned) / Double(currentRequirement), 1)
  }

  private var remainingFromMinimum: Int {
    max(currentRequirement - minimumPlanned, 0)
  }

  private var status: PacTrackStatus {
    guard !selectedPlans.isEmpty else {
      return PacTrackStatus(
        title: "Start your RooPAC plan",
        detail: "Add an activity to compare your plan with this year's requirement.",
        icon: "plus.circle.fill",
        color: accent
      )
    }

    if minimumPlanned >= currentRequirement {
      return PacTrackStatus(
        title: "Requirement covered",
        detail: "Even the minimum value of your selected activities meets this year's requirement.",
        icon: "checkmark.circle.fill",
        color: DesignTokens.Colors.success
      )
    }

    if maximumPlanned >= currentRequirement {
      return PacTrackStatus(
        title: "Your plan could meet it",
        detail:
          "Some selected activities have variable RooPAC values. Set exact amounts as you know them.",
        icon: "circle.lefthalf.filled",
        color: DesignTokens.Colors.warning
      )
    }

    return PacTrackStatus(
      title: "\(remainingFromMinimum) more RooPAC\(remainingFromMinimum == 1 ? "" : "s") needed",
      detail:
        "Add another approved activity or adjust a variable-value activity when you know its amount.",
      icon: "flag.fill",
      color: DesignTokens.Colors.warning
    )
  }

  private var unselectedActivities: [RooPACActivityType] {
    RooPACActivityType.officialCases.filter { activity in
      !(store.rooPacPlans[activity]?.isSelected ?? false)
    }
  }

  var body: some View {
    VStack(spacing: 16) {
      header

      if isPreviewingGrade {
        HStack(spacing: 8) {
          Image(systemName: "calendar.badge.clock")
            .foregroundStyle(accent)
          Text(
            "Planning ahead for \(activeGrade.title). Your Profile and current PacTrack grade are unchanged."
          )
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          Spacer()
          Button("Back to Current") {
            withAnimation(DesignTokens.Animation.snappy) {
              previewGrade = nil
            }
          }
          .buttonStyle(.plain)
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(accent)
          .padding(.horizontal, 10)
          .frame(height: 28)
          .contentShape(Rectangle())
          .background(accent.opacity(0.10), in: Capsule())
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .background(
          DesignTokens.Colors.surface,
          in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(accent.opacity(0.20), lineWidth: 1)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
      }

      HStack(alignment: .top, spacing: 16) {
        ScrollView {
          VStack(spacing: 16) {
            overviewCard
            planCard
            activityGuideCard
            sourceNote
          }
          .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)

        ScrollView {
          VStack(spacing: 14) {
            annualRequirementCard
            whatsLeftCard
            gradeRequirementsCard
            quickActionsCard
          }
        }
        .scrollIndicators(.hidden)
        .frame(width: 304)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 18)
    .padding(.bottom, 16)
    .background { BackgroundView() }
    .sheet(isPresented: $showActivityPicker) {
      RooPACActivityPickerSheet(
        store: store,
        onShowDetails: { activity in
          showActivityPicker = false
          DispatchQueue.main.async {
            selectedActivity = activity
          }
        }
      )
    }
    .sheet(isPresented: $showRequirements) {
      RooPACRequirementsSheet(
        currentGrade: activeGrade,
        onSelectActivity: { activity in
          showRequirements = false
          DispatchQueue.main.async {
            selectedActivity = activity
          }
        }
      )
    }
    .sheet(item: $selectedActivity) { activity in
      RooPACActivityDetailSheet(
        activity: activity,
        plan: planBinding(for: activity)
      )
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("PacTrack")
          .font(DesignTokens.Typography.pageTitle)
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text("Plan and track your RooPACs • \(calendarYear)")
          .font(.system(size: 13))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }

      Spacer()

      HStack(spacing: 8) {
        Menu {
          Button {
            withAnimation(DesignTokens.Animation.snappy) {
              previewGrade = nil
            }
          } label: {
            HStack {
              Text("Current • \(store.rooPACCurrentGrade.title)")
              if previewGrade == nil {
                Image(systemName: "checkmark")
              }
            }
            .contentShape(Rectangle())
          }

          Divider()

          Section("Plan for another grade") {
            ForEach(RooPACGrade.allCases) { grade in
              Button {
                withAnimation(DesignTokens.Animation.snappy) {
                  if grade == store.rooPACCurrentGrade {
                    previewGrade = nil
                  } else {
                    previewGrade = grade
                  }
                }
              } label: {
                HStack {
                  Text("\(grade.title) • \(grade.requirement) RooPACs")
                  if previewGrade == grade {
                    Image(systemName: "checkmark")
                  }
                }
                .contentShape(Rectangle())
              }
            }
          }

          if store.profileGraduationYear == nil {
            Divider()

            Section("Set current grade") {
              ForEach(RooPACGrade.allCases) { grade in
                Button {
                  store.rooPACCurrentGrade = grade
                  previewGrade = nil
                } label: {
                  HStack {
                    Text(grade.title)
                    if grade == store.rooPACCurrentGrade {
                      Image(systemName: "checkmark")
                    }
                  }
                  .contentShape(Rectangle())
                }
              }
            }
          }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: isPreviewingGrade ? "calendar.badge.clock" : "graduationcap.fill")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(isPreviewingGrade ? accent : DesignTokens.Colors.primaryText)

            Text(isPreviewingGrade ? "Plan: \(activeGrade.title)" : activeGrade.title)
              .font(.system(size: 12.5, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)

            Image(systemName: "chevron.down")
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(DesignTokens.Colors.subtleText)
          }
          .padding(.horizontal, 13)
          .frame(height: 38)
          .contentShape(Rectangle())
          .background(
            DesignTokens.Colors.surfaceElevated,
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .strokeBorder(DesignTokens.Colors.borderStrong, lineWidth: 1)
          }
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help("View RooPAC requirements for your current or future grade")

        Button {
          showActivityPicker = true
        } label: {
          HStack(spacing: 7) {
            Image(systemName: "plus")
              .font(.system(size: 11, weight: .bold))
            Text("Add Activity")
              .font(.system(size: 12, weight: .semibold))
          }
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .padding(.horizontal, 13)
          .frame(height: 38)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
          DesignTokens.Colors.surfaceElevated,
          in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(DesignTokens.Colors.borderStrong, lineWidth: 1)
        }
      }
    }
  }

  // MARK: Overview

  private var overviewCard: some View {
    HStack(spacing: 0) {
      HStack(spacing: 20) {
        PacTrackProgressRing(
          progress: progress,
          value: minimumPlanned,
          requirement: currentRequirement,
          color: accent
        )
        .frame(width: 122, height: 122)

        VStack(alignment: .leading, spacing: 6) {
          Text("YOUR PLAN")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(accent)
            .tracking(0.7)

          Text(planRangeText)
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .foregroundStyle(DesignTokens.Colors.primaryText)

          Text(planRangeSubtitle)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Divider()
        .frame(height: 112)
        .opacity(0.32)
        .padding(.horizontal, 22)

      VStack(alignment: .leading, spacing: 8) {
        Text("THIS YEAR")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(DesignTokens.Colors.subtleText)
          .tracking(0.7)

        Text("\(currentRequirement) RooPACs")
          .font(.system(size: 21, weight: .semibold, design: .rounded))
          .foregroundStyle(accent)

        Text("required for \(activeGrade.title)")
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.secondaryText)

        if !selectedPlans.isEmpty {
          Text("\(selectedPlans.count) selected activit\(selectedPlans.count == 1 ? "y" : "ies")")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .padding(.top, 2)
        }
      }
      .frame(width: 170, alignment: .leading)

      Divider()
        .frame(height: 112)
        .opacity(0.32)
        .padding(.horizontal, 22)

      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 8) {
          Image(systemName: status.icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(status.color)

          Text(status.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(status.color)
        }

        Text(status.detail)
          .font(.system(size: 11))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 260, alignment: .leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(20)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg, elevated: true)
  }

  private var planRangeText: String {
    guard !selectedPlans.isEmpty else { return "0 RooPACs" }

    if minimumPlanned == maximumPlanned {
      return "\(minimumPlanned) RooPAC\(minimumPlanned == 1 ? "" : "s")"
    }

    return "\(minimumPlanned)–\(maximumPlanned) RooPACs"
  }

  private var planRangeSubtitle: String {
    guard !selectedPlans.isEmpty else {
      return "Add activities to start your plan"
    }

    if minimumPlanned == maximumPlanned {
      return "exact planned total"
    }

    return "possible total • set exact values when known"
  }

  // MARK: Plan card

  private var planCard: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Your RooPAC Plan")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)

          Text("The annual requirement is a total. These activities are ways to earn toward it.")
            .font(.system(size: 10))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer()

        Text("\(selectedPlans.count) selected")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(accent)
          .padding(.horizontal, 9)
          .frame(height: 26)
          .background(accent.opacity(0.10), in: Capsule())
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)

      Divider().opacity(0.30)

      if selectedPlans.isEmpty {
        VStack(spacing: 10) {
          ZStack {
            Circle()
              .fill(accent.opacity(0.11))
            Image(systemName: "figure.run")
              .font(.system(size: 20, weight: .semibold))
              .foregroundStyle(accent)
          }
          .frame(width: 48, height: 48)

          Text("No activities in your plan yet")
            .font(.system(size: 13, weight: .semibold))

          Text("Add the activities you expect to use toward this year's RooPAC requirement.")
            .font(.system(size: 10))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .multilineTextAlignment(.center)

          Button {
            showActivityPicker = true
          } label: {
            Label("Add Activity", systemImage: "plus")
              .font(.system(size: 11, weight: .semibold))
              .padding(.horizontal, 12)
              .frame(height: 34)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .rooInteractiveGlass(cornerRadius: 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
      } else {
        VStack(spacing: 0) {
          ForEach(selectedPlans, id: \.activity) { item in
            RooPACPlanRow(
              activity: item.activity,
              plan: planBinding(for: item.activity),
              color: tint(for: item.activity),
              onOpenDetails: {
                selectedActivity = item.activity
              }
            )

            if item.activity != selectedPlans.last?.activity {
              Divider()
                .opacity(0.24)
                .padding(.horizontal, 16)
            }
          }
        }
      }

      Divider().opacity(0.30)

      Button {
        showActivityPicker = true
      } label: {
        HStack {
          Image(systemName: "plus")
          Text("Add or Remove Activities")
          Spacer()
          Image(systemName: "chevron.right")
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(DesignTokens.Colors.primaryText)
        .padding(.horizontal, 16)
        .frame(height: 42)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  // MARK: Official activity guide

  private var activityGuideCard: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("2026–27 RooPAC Activity Guide")
            .font(.system(size: 15, weight: .semibold))

          Text("Official values from the RooPAC table")
            .font(.system(size: 10))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer()

        Button("View Requirements") {
          showRequirements = true
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(accent)
        .padding(.horizontal, 5)
        .frame(minHeight: 24)
        .contentShape(Rectangle())
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)

      Divider().opacity(0.30)

      LazyVGrid(
        columns: [
          GridItem(.flexible(), spacing: 10),
          GridItem(.flexible(), spacing: 10),
        ],
        spacing: 10
      ) {
        ForEach(RooPACActivityType.officialCases) { activity in
          Button {
            selectedActivity = activity
          } label: {
            HStack(spacing: 10) {
              ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                  .fill(tint(for: activity).opacity(0.12))

                Image(systemName: activity.icon)
                  .font(.system(size: 12, weight: .semibold))
                  .foregroundStyle(tint(for: activity))
              }
              .frame(width: 34, height: 34)

              VStack(alignment: .leading, spacing: 2) {
                Text(activity.shortTitle)
                  .font(.system(size: 11, weight: .semibold))
                  .foregroundStyle(DesignTokens.Colors.primaryText)
                  .lineLimit(1)

                Text(activity.rangeDescription)
                  .font(.system(size: 9, weight: .medium))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
              }

              Spacer()

              Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.subtleText)
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .background(
            DesignTokens.Colors.selection.opacity(0.35),
            in: RoundedRectangle(cornerRadius: 11)
          )
        }
      }
      .padding(12)
    }
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  // MARK: Right rail

  private var annualRequirementCard: some View {
    VStack(alignment: .leading, spacing: 13) {
      PacTrackSectionLabel("ANNUAL REQUIREMENT", color: accent)

      HStack(alignment: .firstTextBaseline) {
        Text("\(currentRequirement)")
          .font(.system(size: 34, weight: .semibold, design: .rounded))
          .foregroundStyle(accent)

        Text("RooPACs")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.secondaryText)

        Spacer()

        Text(activeGrade.shortTitle)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .padding(.horizontal, 9)
          .frame(height: 26)
          .background(DesignTokens.Colors.selection, in: Capsule())
      }

      ProgressView(value: progress)
        .tint(accent)

      HStack {
        Text("Minimum planned")
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        Spacer()
        Text("\(minimumPlanned) / \(currentRequirement)")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
      }
    }
    .padding(15)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var whatsLeftCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      PacTrackSectionLabel("WHAT'S LEFT", color: status.color)

      if selectedPlans.isEmpty {
        compactMessage(
          icon: "plus.circle",
          title: "Build your plan",
          detail: "Choose activities to see how they compare with your annual requirement."
        )
      } else if minimumPlanned >= currentRequirement {
        compactMessage(
          icon: "checkmark.circle.fill",
          title: "Requirement covered",
          detail: "Your minimum planned total already reaches \(currentRequirement) RooPACs.",
          color: DesignTokens.Colors.success
        )
      } else {
        HStack(alignment: .firstTextBaseline) {
          Text("\(remainingFromMinimum)")
            .font(.system(size: 31, weight: .semibold, design: .rounded))
            .foregroundStyle(status.color)

          Text("RooPAC\(remainingFromMinimum == 1 ? "" : "s")")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Text(
          maximumPlanned >= currentRequirement
            ? "Your variable-value activities could close this gap. Set exact values when you know them."
            : "Choose another approved activity below to close the remaining gap."
        )
        .font(.system(size: 10))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)

        if !unselectedActivities.isEmpty {
          Divider().opacity(0.28)

          Text("WAYS TO EARN")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(DesignTokens.Colors.subtleText)
            .tracking(0.6)

          ForEach(Array(unselectedActivities.prefix(4))) { activity in
            Button {
              var plan = store.rooPacPlans[activity] ?? RooPACPlan()
              plan.isSelected = true
              store.rooPacPlans[activity] = plan
            } label: {
              HStack(spacing: 8) {
                Image(systemName: activity.icon)
                  .font(.system(size: 10, weight: .semibold))
                  .foregroundStyle(tint(for: activity))
                  .frame(width: 18)

                Text(activity.shortTitle)
                  .font(.system(size: 10, weight: .medium))
                  .foregroundStyle(DesignTokens.Colors.primaryText)
                  .lineLimit(1)

                Spacer()

                Text(activity.rangeDescription)
                  .font(.system(size: 9, weight: .semibold))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
              }
              .frame(height: 28)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .padding(15)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var gradeRequirementsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      PacTrackSectionLabel("ROOPACS REQUIRED PER YEAR", color: accent)

      HStack(spacing: 7) {
        ForEach(RooPACGrade.allCases) { grade in
          Button {
            withAnimation(DesignTokens.Animation.snappy) {
              if store.profileGraduationYear == nil {
                store.rooPACCurrentGrade = grade
                previewGrade = nil
              } else {
                previewGrade = grade == store.rooPACCurrentGrade ? nil : grade
              }
            }
          } label: {
            VStack(spacing: 4) {
              Text(grade.shortTitle)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(
                  grade == activeGrade
                    ? accent
                    : DesignTokens.Colors.secondaryText
                )

              Text("\(grade.requirement)")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.primaryText)

              Text("RooPACs")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.subtleText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .background(
            grade == activeGrade
              ? accent.opacity(0.10)
              : DesignTokens.Colors.selection.opacity(0.30),
            in: RoundedRectangle(cornerRadius: 10)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 10)
              .stroke(
                grade == activeGrade
                  ? accent.opacity(0.35)
                  : Color.clear,
                lineWidth: 1
              )
          }
        }
      }
    }
    .padding(15)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var quickActionsCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      PacTrackSectionLabel("QUICK ACTIONS", color: accent)
        .padding(.bottom, 2)

      quickAction(
        title: "Add Activity",
        icon: "plus.circle.fill"
      ) {
        showActivityPicker = true
      }

      quickAction(
        title: "View Full RooPAC Guide",
        icon: "book.closed.fill"
      ) {
        showRequirements = true
      }

      if let url = RooPACActivityType.exemptionRequest.formURL {
        Link(destination: url) {
          HStack(spacing: 9) {
            Image(systemName: "doc.text.fill")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.warning)
              .frame(width: 20)

            Text("RooPAC Exemption Request")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)

            Spacer()

            Image(systemName: "arrow.up.right")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.subtleText)
          }
          .padding(.horizontal, 9)
          .frame(height: 36)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
          DesignTokens.Colors.selection.opacity(0.36),
          in: RoundedRectangle(cornerRadius: 9)
        )
      }
    }
    .padding(15)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private func quickAction(
    title: String,
    icon: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 9) {
        Image(systemName: icon)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(accent)
          .frame(width: 20)

        Text(title)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.subtleText)
      }
      .padding(.horizontal, 9)
      .frame(height: 36)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      DesignTokens.Colors.selection.opacity(0.36),
      in: RoundedRectangle(cornerRadius: 9)
    )
  }

  private var sourceNote: some View {
    HStack(alignment: .top, spacing: 7) {
      Image(systemName: "info.circle")
        .font(.system(size: 9))
        .foregroundStyle(DesignTokens.Colors.subtleText)

      Text(
        "PacTrack is a planning tool. RooPACs are earned only after the attendance, completion, approval, or department-verification requirements for the activity are met."
      )
      .font(.system(size: 9))
      .foregroundStyle(DesignTokens.Colors.subtleText)

      Spacer()
    }
    .padding(.horizontal, 6)
  }

  private func compactMessage(
    icon: String,
    title: String,
    detail: String,
    color: Color? = nil
  ) -> some View {
    VStack(spacing: 7) {
      Image(systemName: icon)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(color ?? accent)

      Text(title)
        .font(.system(size: 12, weight: .semibold))

      Text(detail)
        .font(.system(size: 9))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 7)
  }

  private func tint(for activity: RooPACActivityType) -> Color {
    switch activity {
    case .varsityAthletics: DesignTokens.Colors.pacTrack
    case .jvAthletics: DesignTokens.Colors.schedule
    case .peWellness: DesignTokens.Colors.events
    case .yogaDance: Color(hex: 0x5FB7B0)
    case .supportCrew: DesignTokens.Colors.dining
    case .artsTheater: Color(hex: 0xD7769A)
    case .roobotics: Color(hex: 0x8C7DD1)
    case .exemptionRequest: DesignTokens.Colors.warning
    case .smallFarms: DesignTokens.Colors.athletics
    case .other: DesignTokens.Colors.settings
    }
  }
}

// MARK: - Plan row

private struct RooPACPlanRow: View {
  let activity: RooPACActivityType
  @Binding var plan: RooPACPlan
  let color: Color
  let onOpenDetails: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(color.opacity(0.12))

        Image(systemName: activity.icon)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(color)
      }
      .frame(width: 40, height: 40)

      VStack(alignment: .leading, spacing: 3) {
        if activity == .other {
          TextField(
            "Custom approved activity",
            text: Binding(
              get: { plan.customTitle ?? "" },
              set: { plan.customTitle = $0 }
            )
          )
          .textFieldStyle(.plain)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
        } else {
          Text(activity.shortTitle)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
        }

        Text(activity == .other ? "Custom RooPAC amount" : activity.subtitle)
          .font(.system(size: 9))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if activity.hasVariableValue {
        Menu {
          if activity != .other {
            Button("Use \(activity.rangeDescription)") {
              plan.overrideCredits = nil
            }

            Divider()
          }

          ForEach(activity.minCredits...activity.maxCredits, id: \.self) { value in
            Button {
              plan.overrideCredits = value
            } label: {
              HStack {
                Text("\(value) RooPAC\(value == 1 ? "" : "s")")
                if plan.overrideCredits == value {
                  Image(systemName: "checkmark")
                }
              }
              .contentShape(Rectangle())
            }
          }
        } label: {
          HStack(spacing: 5) {
            Text(
              plan.overrideCredits.map { "\($0)" }
                ?? (activity == .other ? "Set amount" : activity.rangeDescription)
            )
            .font(.system(size: 10, weight: .semibold))
            Image(systemName: "chevron.down")
              .font(.system(size: 7, weight: .bold))
          }
          .foregroundStyle(color)
          .padding(.horizontal, 9)
          .frame(height: 28)
          .background(color.opacity(0.10), in: Capsule())
          .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help("Set an exact RooPAC amount when you know it")
      } else {
        Text(activity.rangeDescription)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(color)
          .padding(.horizontal, 9)
          .frame(height: 28)
          .background(color.opacity(0.10), in: Capsule())
      }

      Button(action: onOpenDetails) {
        Image(systemName: "info.circle")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.subtleText)
          .frame(width: 30, height: 30)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Button {
        plan.isSelected = false
        plan.overrideCredits = nil
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(DesignTokens.Colors.subtleText)
          .frame(width: 30, height: 30)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Remove from plan")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 11)
  }
}

// MARK: - Activity picker

private struct RooPACActivityPickerSheet: View {
  @ObservedObject var store: UserScheduleStore
  let onShowDetails: (RooPACActivityType) -> Void

  @Environment(\.dismiss)
  private var dismiss

  private let accent = DesignTokens.Colors.pacTrack

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Build Your RooPAC Plan")
            .font(.system(size: 18, weight: .semibold))
          Text("Select the approved activities you expect to use this year.")
            .font(.system(size: 11))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer()

        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(DesignTokens.Colors.selection, in: Circle())
      }
      .padding(18)

      Divider().opacity(0.35)

      ScrollView {
        LazyVStack(spacing: 8) {
          ForEach(RooPACActivityType.officialCases) { activity in
            activityRow(activity)
          }
        }
        .padding(14)
      }

      Divider().opacity(0.35)

      HStack {
        Text("Variable-value activities can be left as a range until you know the exact amount.")
          .font(.system(size: 9))
          .foregroundStyle(DesignTokens.Colors.secondaryText)

        Spacer()

        Button("Done") {
          dismiss()
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 14)
        .frame(height: 34)
        .rooInteractiveGlass(cornerRadius: 10)
        .contentShape(Rectangle())
      }
      .padding(14)
    }
    .frame(width: 600, height: 620)
    .background(DesignTokens.Colors.background)
  }

  private func activityRow(_ activity: RooPACActivityType) -> some View {
    let plan = store.rooPacPlans[activity] ?? RooPACPlan()
    let selected = plan.isSelected
    let color = activityColor(activity)

    return Button {
      var updated = plan
      updated.isSelected.toggle()
      if updated.isSelected, activity == .other, updated.overrideCredits == nil {
        updated.overrideCredits = 1
      }
      if !updated.isSelected {
        updated.overrideCredits = nil
      }
      store.rooPacPlans[activity] = updated
    } label: {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(color.opacity(0.12))

          Image(systemName: activity.icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
        }
        .frame(width: 40, height: 40)

        VStack(alignment: .leading, spacing: 3) {
          Text(activity.title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .lineLimit(2)

          Text(activity.subtitle)
            .font(.system(size: 9))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Text(activity.rangeDescription)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(color)
          .padding(.horizontal, 9)
          .frame(height: 26)
          .background(color.opacity(0.10), in: Capsule())

        Button {
          onShowDetails(activity)
        } label: {
          Image(systemName: "info.circle")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.subtleText)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        ZStack {
          Circle()
            .fill(selected ? color : DesignTokens.Colors.selection)
            .frame(width: 23, height: 23)

          if selected {
            Image(systemName: "checkmark")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(.white)
          }
        }
      }
      .padding(.horizontal, 11)
      .frame(minHeight: 64)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      selected
        ? color.opacity(0.06)
        : DesignTokens.Colors.surface,
      in: RoundedRectangle(cornerRadius: 12)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(
          selected ? color.opacity(0.22) : DesignTokens.Colors.border,
          lineWidth: 1
        )
    }
  }

  private func activityColor(_ activity: RooPACActivityType) -> Color {
    switch activity {
    case .varsityAthletics: DesignTokens.Colors.pacTrack
    case .jvAthletics: DesignTokens.Colors.schedule
    case .peWellness: DesignTokens.Colors.events
    case .yogaDance: Color(hex: 0x5FB7B0)
    case .supportCrew: DesignTokens.Colors.dining
    case .artsTheater: Color(hex: 0xD7769A)
    case .roobotics: Color(hex: 0x8C7DD1)
    case .exemptionRequest: DesignTokens.Colors.warning
    case .smallFarms: DesignTokens.Colors.athletics
    case .other: DesignTokens.Colors.settings
    }
  }
}

// MARK: - Activity detail

private struct RooPACActivityDetailSheet: View {
  let activity: RooPACActivityType
  @Binding var plan: RooPACPlan

  @Environment(\.dismiss)
  private var dismiss

  private let accent = DesignTokens.Colors.pacTrack

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top) {
        HStack(spacing: 12) {
          ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .fill(accent.opacity(0.12))

            Image(systemName: activity.icon)
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(accent)
          }
          .frame(width: 46, height: 46)

          VStack(alignment: .leading, spacing: 3) {
            Text(
              activity == .other
                ? ((plan.customTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  ? activity.title
                  : (plan.customTitle ?? activity.title))
                : activity.title
            )
            .font(.system(size: 17, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)

            Text(
              activity == .other
                ? "\(plan.overrideCredits ?? 1) RooPAC\((plan.overrideCredits ?? 1) == 1 ? "" : "s")"
                : activity.rangeDescription
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(accent)
          }
        }

        Spacer()

        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(DesignTokens.Colors.selection, in: Circle())
      }

      Divider().opacity(0.35)

      if activity == .other {
        VStack(alignment: .leading, spacing: 8) {
          Text("CUSTOM ACTIVITY")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(DesignTokens.Colors.subtleText)
            .tracking(0.6)

          TextField(
            "Activity name",
            text: Binding(
              get: { plan.customTitle ?? "" },
              set: { plan.customTitle = $0 }
            )
          )
          .textFieldStyle(.roundedBorder)
        }
      }

      detailBlock(
        title: "Commitment",
        icon: "clock.fill",
        text: activity.commitment
      )

      detailBlock(
        title: "Attendance / verification",
        icon: "checkmark.seal.fill",
        text: activity.guidance
      )

      if activity.hasVariableValue {
        VStack(alignment: .leading, spacing: 8) {
          Text("PLAN AMOUNT")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(DesignTokens.Colors.subtleText)
            .tracking(0.6)

          Picker(
            "Planned RooPAC amount",
            selection: Binding<Int?>(
              get: {
                if activity == .other {
                  return plan.overrideCredits ?? 1
                }
                return plan.overrideCredits
              },
              set: { plan.overrideCredits = $0 }
            )
          ) {
            if activity != .other {
              Text("Use \(activity.rangeDescription)")
                .tag(Optional<Int>.none)
            }

            ForEach(activity.minCredits...activity.maxCredits, id: \.self) { value in
              Text("\(value) RooPAC\(value == 1 ? "" : "s")")
                .tag(Optional(value))
            }
          }
          .pickerStyle(.menu)
        }
      }

      Divider().opacity(0.35)

      HStack(spacing: 10) {
        Button {
          plan.isSelected.toggle()
          if plan.isSelected, activity == .other, plan.overrideCredits == nil {
            plan.overrideCredits = 1
          }
          if !plan.isSelected {
            plan.overrideCredits = nil
          }
        } label: {
          HStack(spacing: 7) {
            Image(systemName: plan.isSelected ? "checkmark.circle.fill" : "plus.circle.fill")
            Text(plan.isSelected ? "In My Plan" : "Add to My Plan")
          }
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(plan.isSelected ? DesignTokens.Colors.success : accent)
          .padding(.horizontal, 12)
          .frame(height: 36)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rooInteractiveGlass(cornerRadius: 10)

        if let url = activity.formURL {
          Link(destination: url) {
            HStack(spacing: 7) {
              Image(systemName: "arrow.up.right")
              Text("Open Exemption Form")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .rooInteractiveGlass(cornerRadius: 10)
        }

        Spacer()
      }
    }
    .padding(20)
    .frame(width: 560)
    .background(DesignTokens.Colors.background)
  }

  private func detailBlock(
    title: String,
    icon: String,
    text: String
  ) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(accent)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 4) {
        Text(title.uppercased())
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(DesignTokens.Colors.subtleText)
          .tracking(0.6)

        Text(text)
          .font(.system(size: 11))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

// MARK: - Full requirements sheet

private struct RooPACRequirementsSheet: View {
  let currentGrade: RooPACGrade
  let onSelectActivity: (RooPACActivityType) -> Void

  @Environment(\.dismiss)
  private var dismiss

  private let accent = DesignTokens.Colors.pacTrack

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("RooPAC Requirements • 2026–27")
            .font(.system(size: 18, weight: .semibold))

          Text("Annual requirements and approved activity values")
            .font(.system(size: 11))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer()

        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(DesignTokens.Colors.selection, in: Circle())
      }
      .padding(18)

      Divider().opacity(0.35)

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 10) {
            Text("ROOPACS REQUIRED PER YEAR")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(accent)
              .tracking(0.7)

            HStack(spacing: 8) {
              ForEach(RooPACGrade.allCases) { grade in
                VStack(spacing: 5) {
                  Text(grade.shortTitle)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(
                      grade == currentGrade
                        ? accent
                        : DesignTokens.Colors.secondaryText
                    )

                  Text("\(grade.requirement)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))

                  Text("RooPACs")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignTokens.Colors.subtleText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 78)
                .background(
                  grade == currentGrade
                    ? accent.opacity(0.09)
                    : DesignTokens.Colors.surface,
                  in: RoundedRectangle(cornerRadius: 11)
                )
                .overlay {
                  RoundedRectangle(cornerRadius: 11)
                    .stroke(
                      grade == currentGrade
                        ? accent.opacity(0.30)
                        : DesignTokens.Colors.border,
                      lineWidth: 1
                    )
                }
              }
            }
          }

          Divider().opacity(0.35)

          VStack(spacing: 8) {
            ForEach(RooPACActivityType.officialCases) { activity in
              Button {
                onSelectActivity(activity)
              } label: {
                HStack(spacing: 11) {
                  ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                      .fill(accent.opacity(0.09))
                    Image(systemName: activity.icon)
                      .font(.system(size: 12, weight: .semibold))
                      .foregroundStyle(accent)
                  }
                  .frame(width: 34, height: 34)

                  VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                      .font(.system(size: 11, weight: .semibold))
                      .foregroundStyle(DesignTokens.Colors.primaryText)

                    Text(activity.subtitle)
                      .font(.system(size: 9))
                      .foregroundStyle(DesignTokens.Colors.secondaryText)
                      .lineLimit(1)
                  }

                  Spacer()

                  Text(activity.rangeDescription)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)

                  Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.subtleText)
                }
                .padding(.horizontal, 10)
                .frame(height: 52)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .background(
                DesignTokens.Colors.surface,
                in: RoundedRectangle(cornerRadius: 11)
              )
              .overlay {
                RoundedRectangle(cornerRadius: 11)
                  .stroke(DesignTokens.Colors.border, lineWidth: 1)
              }
            }
          }
        }
        .padding(18)
      }
    }
    .frame(width: 700, height: 720)
    .background(DesignTokens.Colors.background)
  }
}

// MARK: - Shared PacTrack visuals

private struct PacTrackProgressRing: View {
  let progress: Double
  let value: Int
  let requirement: Int
  let color: Color

  var body: some View {
    ZStack {
      Circle()
        .stroke(DesignTokens.Colors.selection, lineWidth: 10)

      Circle()
        .trim(from: 0, to: max(0.001, progress))
        .stroke(
          color,
          style: StrokeStyle(
            lineWidth: 10,
            lineCap: .round
          )
        )
        .rotationEffect(.degrees(-90))

      VStack(spacing: -1) {
        Text("\(value)")
          .font(.system(size: 27, weight: .semibold, design: .rounded))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text("of \(requirement)")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.secondaryText)

        Text("minimum")
          .font(.system(size: 8, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.subtleText)
      }
    }
  }
}

private struct PacTrackSectionLabel: View {
  let title: String
  let color: Color

  init(_ title: String, color: Color) {
    self.title = title
    self.color = color
  }

  var body: some View {
    HStack(spacing: 7) {
      Circle()
        .fill(color)
        .frame(width: 6, height: 6)

      Text(title)
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .tracking(0.7)
    }
  }
}

private struct PacTrackStatus {
  let title: String
  let detail: String
  let icon: String
  let color: Color
}

#Preview {
  RooPACTrackerView(store: UserScheduleStore())
}
