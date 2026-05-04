import SwiftUI
import Combine

struct DayScheduleView: View {
  let day: Weekday
  let blocks: [BellBlock]
  @ObservedObject var store: UserScheduleStore

  @State private var now: Date = Date()
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  private struct DatedBlock: Identifiable {
      let id = UUID()
      let original: BellBlock
      let startDate: Date
      let endDate: Date
  }

  var body: some View {
      ScrollView {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
              VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                  Text(day.title)
                      .font(DesignTokens.Typography.headline2)
                      .foregroundStyle(.primary)
                  
                  Text("Your Schedule")
                      .font(DesignTokens.Typography.subheadline)
                      .foregroundStyle(.secondary)
              }
              .padding(.horizontal, DesignTokens.Spacing.lg)

               if let currentInfo = currentBlockInfo(on: now) {
                   CurrentBlockHeader(
                       title: currentInfo.title,
                       subtitle: currentInfo.subtitle,
                       color: currentInfo.color,
                       progress: currentInfo.progress,
                       remainingText: currentInfo.remainingText,
                       nextTitle: currentInfo.nextTitle,
                       nextStartText: currentInfo.nextStartText,
                       nextColor: currentInfo.nextColor,
                       nextLevel: currentInfo.nextLevel,
                       nextSpecialLabel: currentInfo.nextSpecialLabel,
                       style: store.cardColorStyle,
                       isCountdownMode: false
                   )
                   .padding(.horizontal, DesignTokens.Spacing.lg)
                   .transition(.scale(scale: 0.95).combined(with: .opacity))
               } else if let countdown = nextCountdownInfo(on: now) {
                   CurrentBlockHeader(
                       title: countdown.headerTitle,
                       subtitle: countdown.headerSubtitle,
                       color: countdown.headerColor,
                       progress: countdown.progress,
                       remainingText: countdown.remainingText,
                       nextTitle: countdown.nextTitle,
                       nextStartText: countdown.nextStartText,
                       nextColor: countdown.nextColor,
                       nextLevel: nil,
                       nextSpecialLabel: countdown.nextSpecialLabel,
                       style: store.cardColorStyle,
                       isCountdownMode: true
                   )
                  .padding(.horizontal, DesignTokens.Spacing.lg)
                  .transition(.scale(scale: 0.95).combined(with: .opacity))
              }

                ForEach(blocks, id: \.id) { (block: BellBlock) in
                    switch block.kind {
                    case .level(let level):
                        let assignment = store.assignment(for: level)
                        ClassCardView(
                           title: assignment.displayTitle(for: level, on: day),
                            teacher: assignment.displayTeacher(on: day),
                            room: assignment.displayRoom(on: day),
                            timeRange: formattedRange(start: block.start, end: block.end),
                            color: assignment.displayColor(on: day),
                            style: store.cardColorStyle,
                            duration: formattedDuration(start: block.start, end: block.end),
                            level: level,
                             specialLabel: nil,
                            isFree: assignment.displayIsFree(on: day)
                        )
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                    case .special(let special):
                        ClassCardView(
                           title: store.displayTitle(for: special),
                            teacher: nil,
                            room: nil,
                            timeRange: formattedRange(start: block.start, end: block.end),
                            color: store.color(for: special),
                            style: store.cardColorStyle,
                            duration: formattedDuration(start: block.start, end: block.end),
                            level: nil,
                            specialLabel: specialBlockLabel(for: special),
                            isFree: false
                        )
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(DesignTokens.Animation.smooth, value: blocks.count)

              Spacer(minLength: DesignTokens.Spacing.lg)
          }
          .padding(.vertical, DesignTokens.Spacing.lg)
      }
      .modifier(SafeAreaTopPadding(4))
      .onReceive(timer) { now = $0 }
  }

  private func datedBlocks(for reference: Date) -> [DatedBlock] {
      let cal = Calendar.current
      let targetWeekday: Int = {
          switch day {
          case .monday: 2
          case .tuesday: 3
          case .wednesday: 4
          case .thursday: 5
          case .friday: 6
          }
      }()

      let startOfDay = cal.startOfDay(for: reference)
      let todayWeekday = cal.component(.weekday, from: startOfDay)
      let dayOffset: Int = {
          var delta = targetWeekday - todayWeekday
          if delta < 0 { delta += 7 }
          return delta
      }()
      let weekdayDate = cal.date(byAdding: .day, value: dayOffset, to: startOfDay) ?? startOfDay

      return blocks.compactMap { block in
          var startComps = cal.dateComponents([.year, .month, .day], from: weekdayDate)
          startComps.hour = block.start.hour
          startComps.minute = block.start.minute
          startComps.second = 0

          var endComps = cal.dateComponents([.year, .month, .day], from: weekdayDate)
          endComps.hour = block.end.hour
          endComps.minute = block.end.minute
          endComps.second = 0

          guard let s = cal.date(from: startComps), let e = cal.date(from: endComps) else { return nil }
          return DatedBlock(original: block, startDate: s, endDate: e)
      }.sorted(by: { $0.startDate < $1.startDate })
  }

    private func blockTitleColorSubtitle(for block: BellBlock) -> (title: String, color: Color, subtitle: String, level: Level?, specialLabel: String?) {
        switch block.kind {
        case .level(let level):
            let a = store.assignment(for: level)
            return (a.displayTitle(for: level, on: day), a.displayColor(on: day), a.displaySubtitle(on: day), level, nil)
        case .special(let sp):
             return (store.displayTitle(for: sp), store.color(for: sp), "", nil, specialBlockLabel(for: sp))
        }
    }
    
    private func specialBlockLabel(for block: SpecialBlock) -> String {
        switch block {
        case .assembly: "Assembly"
        case .officeHours: "Office Hours"
        case .advisory: "Advisory"
        case .worship: "Meeting For Worship"
        case .consciousCommunities: "Conscious Communities"
        case .lunch: "Lunch"
        case .lunchAndClubs: "Lunch & Clubs"
        case .musicClubs: "Music Block + Clubs"
        }
    }

     private func currentBlockInfo(on reference: Date) -> (title: String, subtitle: String, color: Color, progress: Double, remainingText: String, nextTitle: String?, nextStartText: String?, nextColor: Color?, nextLevel: Level?, nextSpecialLabel: String?)? {
       let list = datedBlocks(for: reference)
       guard !list.isEmpty else { return nil }

       var current: DatedBlock?
       var next: DatedBlock?
       for (idx, item) in list.enumerated() {
           if reference >= item.startDate && reference < item.endDate {
               current = item
               if idx + 1 < list.count { next = list[idx + 1] }
               break
           }
           if reference < item.startDate {
               current = nil
               next = item
               break
           }
       }

       guard let current else { return nil }

       let total = current.endDate.timeIntervalSince(current.startDate)
       let elapsed = reference.timeIntervalSince(current.startDate)
       let remaining = max(0, current.endDate.timeIntervalSince(reference))
       let progress = max(0, min(1, elapsed / max(1, total)))

       let (title, color, subtitle, _, _) = blockTitleColorSubtitle(for: current.original)
       let remainingText = "Ends in " + formatDuration(remaining)

        var nextTitle: String?
        var nextStartText: String?
        var nextColor: Color?
        var nextLevel: Level?
        var nextSpecialLabel: String?
        if let next {
            let (ntitle, ncolor, _, nlevel, nspecialLabel) = blockTitleColorSubtitle(for: next.original)
            nextTitle = ntitle
            nextColor = ncolor
            nextLevel = nlevel
            nextSpecialLabel = nspecialLabel
            nextStartText = "Starts at " + timeString(next.startDate)
        }

          return (title, subtitle, color, progress, remainingText, nextTitle, nextStartText, nextColor, nextLevel, nextSpecialLabel)
   }

   private func nextCountdownInfo(on reference: Date) -> (headerTitle: String, headerSubtitle: String, headerColor: Color, progress: Double, remainingText: String, nextTitle: String, nextStartText: String, nextColor: Color, nextSpecialLabel: String?)? {
       let list = datedBlocks(for: reference)
       guard !list.isEmpty else { return nil }

       var future: DatedBlock?
       var previousAnchorTime: Date?
       for (idx, item) in list.enumerated() {
           if reference < item.startDate {
               future = item
               if idx > 0 {
                   previousAnchorTime = list[idx - 1].endDate
               } else {
                   previousAnchorTime = Calendar.current.startOfDay(for: item.startDate)
               }
               break
           }
       }

       guard let next = future, let anchor = previousAnchorTime else {
           return nil
       }

       let remaining = max(0, next.startDate.timeIntervalSince(reference))
       let totalGap = max(1, next.startDate.timeIntervalSince(anchor))
       let elapsedGap = max(0, reference.timeIntervalSince(anchor))
       let progress = max(0, min(1, elapsedGap / totalGap))

       let (ntitle, ncolor, _, _, nspecialLabel) = blockTitleColorSubtitle(for: next.original)

       return (
           headerTitle: "No class right now",
           headerSubtitle: "Starts soon",
           headerColor: .secondary,
           progress: progress,
           remainingText: "Starts in " + formatDuration(remaining),
           nextTitle: ntitle,
           nextStartText: "Starts at " + timeString(next.startDate),
           nextColor: ncolor,
           nextSpecialLabel: nspecialLabel
       )
   }

  private func timeString(_ date: Date) -> String {
      let fmt = DateFormatter()
      fmt.locale = Locale(identifier: "en_US_POSIX")
      fmt.dateFormat = "h:mm a"
      return fmt.string(from: date)
  }

  private func formatDuration(_ interval: TimeInterval) -> String {
      let minutes = Int(interval) / 60
      let seconds = Int(interval) % 60
      if minutes >= 60 {
          let hours = minutes / 60
          let remMin = minutes % 60
          return remMin == 0 ? "\(hours)h" : "\(hours)h \(remMin)m"
      } else if minutes > 0 {
          return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
      } else {
          return "\(seconds)s"
      }
  }

  private func formattedRange(start: DateComponents, end: DateComponents) -> String {
      func format(_ comps: DateComponents) -> String {
          var comps = comps
          comps.second = 0
          let cal = Calendar.current
          guard let date = cal.date(from: comps) else { return "—" }
          let fmt = DateFormatter()
          fmt.locale = Locale(identifier: "en_US_POSIX")
          fmt.dateFormat = "h:mm a"
          return fmt.string(from: date)
      }
      return "\(format(start)) – \(format(end))"
  }

  private func formattedDuration(start: DateComponents, end: DateComponents) -> String {
      let cal = Calendar.current
      var startComps = start
      var endComps = end
      startComps.second = 0
      endComps.second = 0
      
      guard let startDate = cal.date(from: startComps),
            let endDate = cal.date(from: endComps) else { return "—" }
      
      let duration = Int(endDate.timeIntervalSince(startDate))
      let hours = duration / 3600
      let minutes = (duration % 3600) / 60
      
      if hours > 0 && minutes > 0 {
          return "\(hours)h \(minutes)m"
      } else if hours > 0 {
          return "\(hours)h"
      } else if minutes > 0 {
          return "\(minutes)m"
      } else {
          return "—"
      }
  }
}

// Made internal so it can be used by DashboardView too
struct CurrentBlockHeader: View {
    let title: String
    let subtitle: String
    let color: Color
    let progress: Double
    let remainingText: String
    let nextTitle: String?
    let nextStartText: String?
    let nextColor: Color?
    let nextLevel: Level?
    let nextSpecialLabel: String?
    let style: CardColorStyle
    let isCountdownMode: Bool

  var body: some View {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
              HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                  VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                      HStack(spacing: DesignTokens.Spacing.sm) {
                          Image(systemName: isCountdownMode ? "pause.circle.fill" : "clock.fill")
                              .font(.title3)
                              .foregroundStyle(isCountdownMode ? .secondary : color)
                          
                          Text(isCountdownMode ? "Idle" : "Now")
                              .font(DesignTokens.Typography.caption)
                              .foregroundStyle(.secondary)
                      }
                      
                      Text(title)
                          .font(DesignTokens.Typography.headline2)
                          .fontWeight(.bold)
                          .foregroundStyle(.primary)
                      
                      if !subtitle.isEmpty {
                          Text(subtitle)
                              .font(DesignTokens.Typography.body)
                              .foregroundStyle(.secondary)
                      }
                  }
                  
                  Spacer()
                  
                  VStack(alignment: .trailing, spacing: DesignTokens.Spacing.xs) {
                      if !remainingText.isEmpty {
                          Label(remainingText, systemImage: isCountdownMode ? "clock.badge.checkmark.fill" : "hourglass.bottomhalf.fill")
                              .font(DesignTokens.Typography.body)
                              .fontWeight(.semibold)
                              .foregroundStyle(color)
                      }
                  }
              }

              ProgressView(value: progress)
                  .tint(progressTint)
                  .animation(.linear(duration: 0.2), value: progress)
          }
          .padding(DesignTokens.Spacing.lg)
          .background(nowBackground)
          .cornerRadius(DesignTokens.Radius.lg)
          .designShadow(DesignTokens.Shadows.small)

             if let nextTitle, let nextStartText {
                 NextBlockCard(
                     title: nextTitle,
                     startText: nextStartText,
                     color: nextColor ?? .accentColor,
                     style: style,
                     level: nextLevel,
                     specialLabel: nextSpecialLabel
                 )
             }
      }
  }

  private var isNeutral: Bool { style == .none || isCountdownMode }

  private var accentFill: some ShapeStyle {
      if isNeutral {
          return LinearGradient(colors: [Color.secondary.opacity(0.5), Color.secondary.opacity(0.3)], startPoint: .top, endPoint: .bottom)
      } else {
          return LinearGradient(colors: [color.opacity(0.7), color.opacity(0.35)], startPoint: .top, endPoint: .bottom)
      }
  }

  private var progressTint: Color {
      isNeutral ? .accentColor : color
  }

  @ViewBuilder
  private var nowBackground: some View {
      switch style {
      case .none:
          RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
              .fill(compatibleBackgroundSecondary())
              .designShadow(DesignTokens.Shadows.small)
      case .subtle:
          ZStack {
              RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                  .fill((isNeutral ? Color.secondary : color).opacity(0.08))
                  .blur(radius: 12)
                  .scaleEffect(1.01)

              RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                  .fill(LinearGradient(
                      colors: [(isNeutral ? Color.secondary : color).opacity(0.10), (isNeutral ? Color.secondary : color).opacity(0.04)],
                      startPoint: .topLeading,
                      endPoint: .bottomTrailing
                  ))
                  .designShadow(DesignTokens.Shadows.medium)
          }
      case .colors:
          ZStack {
              RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                  .fill((isNeutral ? Color.secondary : color).opacity(0.08))
                  .blur(radius: 10)
                  .scaleEffect(1.005)

              RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                  .fill(LinearGradient(
                      colors: [(isNeutral ? Color.secondary : color).opacity(0.12), (isNeutral ? Color.secondary : color).opacity(0.04)],
                      startPoint: .topLeading,
                      endPoint: .bottomTrailing
                  ))
                  .designShadow(DesignTokens.Shadows.large)
          }
      }
  }
}

struct ClassCardView: View {
  let title: String
  let teacher: String?
  let room: String?
  let timeRange: String
  let color: Color
  let style: CardColorStyle
  let duration: String?
  let level: Level?
  let specialLabel: String?
  let isFree: Bool

  private var hasTeacher: Bool { teacher != nil && !teacher!.isEmpty }
  private var hasRoom: Bool { room != nil && !room!.isEmpty }
  private var hasDetails: Bool { !isFree && (hasTeacher || hasRoom || (duration != nil && !duration!.isEmpty)) }
  private var hasLevel: Bool { level != nil }
  private var hasSpecialLabel: Bool { specialLabel != nil && !specialLabel!.isEmpty }

  private var softGradient: LinearGradient {
      let c = color
      return LinearGradient(
          colors: [c.opacity(0.22), c.opacity(0.12)],
          startPoint: .topLeading, endPoint: .bottomTrailing
      )
  }

  private var softStrokeGradient: LinearGradient {
      LinearGradient(
          colors: [color.opacity(0.7), color.opacity(0.2)],
          startPoint: .topLeading, endPoint: .bottomTrailing
      )
  }

   var body: some View {
       VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
           HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
               VStack(alignment: .leading, spacing: 3) {
                   Text(title)
                       .font(DesignTokens.Typography.title)
                       .fontWeight(.semibold)
                       .foregroundStyle(.primary)
                   
                   if let level = level {
                       Text(level.displayName)
                           .font(DesignTokens.Typography.caption)
                           .foregroundStyle(.secondary)
                   } else if hasSpecialLabel {
                       Text(specialLabel!)
                           .font(DesignTokens.Typography.caption)
                           .foregroundStyle(.secondary)
                   }
               }
               
               Spacer()
               
               Label(timeRange, systemImage: "clock.fill")
                   .font(DesignTokens.Typography.caption)
                   .foregroundStyle(color)
                   .fontWeight(.medium)
                   .labelStyle(.titleAndIcon)
           }

          if hasDetails {
              HStack(spacing: DesignTokens.Spacing.lg) {
                  if hasTeacher {
                      Label(teacher!, systemImage: "person.fill")
                          .font(DesignTokens.Typography.caption)
                          .foregroundStyle(.secondary)
                  }
                  if hasRoom {
                      Label(room!, systemImage: "mappin.and.ellipse")
                          .font(DesignTokens.Typography.caption)
                          .foregroundStyle(.secondary)
                  }
                  Spacer()
                  if let duration, !duration.isEmpty {
                      Label(duration, systemImage: "hourglass.bottomhalf.filled")
                          .font(DesignTokens.Typography.caption)
                          .foregroundStyle(.secondary)
                  }
              }
          }
      }
      .padding(DesignTokens.Spacing.lg)
      .background(backgroundForStyle)
      .overlay(strokeForStyle)
      .overlay(glowForStyle)
      .cornerRadius(DesignTokens.Radius.md)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(title), \(timeRange)\(teacher != nil ? ", with \(teacher!)" : "")\(room != nil ? ", in \(room!)" : "")")
  }

  @ViewBuilder
  private var backgroundForStyle: some View {
      switch style {
      case .none:
          RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
              .fill(compatibleBackgroundSecondary())
              .designShadow(DesignTokens.Shadows.small)
      case .subtle:
          RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
              .fill(compatibleBackgroundSecondary())
              .designShadow(DesignTokens.Shadows.small)
      case .colors:
          ZStack {
              RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                  .fill(color.opacity(0.12))
                  .blur(radius: 10)
                  .scaleEffect(1.01)
              RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                  .fill(softGradient)
                  .designShadow(DesignTokens.Shadows.medium)
          }
      }
  }

  @ViewBuilder
  private var strokeForStyle: some View {
      switch style {
      case .none:
          EmptyView()
      case .subtle:
          RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
              .stroke(softStrokeGradient, lineWidth: 1.2)
      case .colors:
          RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
              .stroke(softStrokeGradient, lineWidth: 1.4)
      }
  }

  @ViewBuilder
  private var glowForStyle: some View {
      switch style {
      case .none:
          EmptyView()
      case .subtle:
          RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
              .stroke(color.opacity(0.10), lineWidth: 4)
              .blur(radius: 7)
      case .colors:
          RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
              .stroke(color.opacity(0.06), lineWidth: 2)
              .blur(radius: 4)
      }
  }
}

