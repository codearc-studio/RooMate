import SwiftUI

private let eventsSchoolTimeZone = TimeZone(identifier: "America/New_York") ?? .current

private func eventsSchoolCalendar() -> Calendar {
  var calendar = Calendar.current
  calendar.timeZone = eventsSchoolTimeZone
  return calendar
}

struct EventsView: View {
  @ObservedObject var store: EventsStore
  @ObservedObject private var navigation = RooMateNavigationCoordinator.shared

  @State private var selectedSources: Set<CalendarSource>
  @State private var selectedGrouping: CalendarGroupingMode
  @State private var selectedDate = Date()
  @State private var searchText = ""
  @State private var showSourcePicker = false
  @State private var savedOnly = false
  @State private var selectedEvent: CalendarEvent?
  @State private var showCalendar = false

  @AppStorage("RooMateEventBookmarks")
  private var bookmarkedEventKeysRaw = ""

  private let calendar = eventsSchoolCalendar()
  private let eventsColor = DesignTokens.Colors.events

  init(store: EventsStore) {
    self.store = store
    _selectedSources = State(initialValue: store.selectedSources)
    _selectedGrouping = State(initialValue: store.selectedGrouping)
  }

  var body: some View {
    VStack(spacing: 16) {
      eventsHeader
      scopeBar

      Group {
        if showCalendar {
          eventsCalendarWorkspace
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else {
          eventsAgendaWorkspace
            .transition(.opacity)
        }
      }
      .animation(DesignTokens.Animation.navigation, value: showCalendar)
    }
    .padding(.horizontal, 20)
    .padding(.top, 18)
    .padding(.bottom, 16)
    .background { BackgroundView() }
    .onChange(of: selectedSources) { _, newValue in
      store.setSources(newValue)
    }
    .onChange(of: selectedGrouping) { _, newValue in
      store.selectedGrouping = newValue
    }
    .onAppear {
      selectedSources = store.selectedSources
      selectedGrouping = store.selectedGrouping
      if store.events.isEmpty { store.refresh() }
      handleNavigationRequest()
    }
    .onChange(of: navigation.request) { _, _ in handleNavigationRequest() }
    .onChange(of: store.events) { _, _ in handleNavigationRequest() }
    .sheet(item: $selectedEvent) { event in
      EventDetailSheet(
        event: event,
        isBookmarked: bookmarkedEventKeys.contains(stableKey(for: event)),
        onToggleBookmark: { toggleBookmark(event) }
      )
    }
  }

  private func handleNavigationRequest() {
    guard let request = navigation.request,
      case .event(let key) = request.destination,
      let event = store.events.first(where: { RooMateStableKey.event($0) == key })
    else { return }
    selectedDate = event.startDate
    selectedEvent = event
    navigation.consume(request)
  }

  private var eventsAgendaWorkspace: some View {
    HStack(alignment: .top, spacing: 16) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let error = store.lastError, store.events.isEmpty { errorCard(error) }
          if store.isLoading && store.events.isEmpty {
            loadingCard
          } else if groupedVisibleEvents.isEmpty {
            emptyState
          } else {
            ForEach(groupedVisibleEvents) { group in
              EventsDaySection(
                group: group,
                bookmarkedKeys: bookmarkedEventKeys,
                onToggleBookmark: toggleBookmark,
                onOpen: { selectedEvent = $0 }
              )
            }
          }
          sourceNote
        }
        .padding(.bottom, 8)
        .animation(DesignTokens.Animation.content, value: groupedVisibleEvents.map(\.id))
        .animation(DesignTokens.Animation.content, value: store.isLoading)
      }
      .scrollIndicators(.hidden)

      ScrollView {
        VStack(spacing: 14) {
          featuredEventCard
          upcomingOverviewCard
          savedEventsCard
          upcomingCalendarCard
        }
      }
      .scrollIndicators(.hidden)
      .frame(width: 304)
    }
  }

  private var eventsCalendarWorkspace: some View {
    HStack(alignment: .top, spacing: 16) {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text(monthYear(selectedDate))
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
              Text("Select a day to see its events")
                .font(.system(size: 10.5))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
            Spacer()
            Text("\(visibleEvents.count) this month")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(eventsColor)
              .padding(.horizontal, 9)
              .frame(height: 26)
              .background(eventsColor.opacity(0.10), in: Capsule())
          }
          .padding(.horizontal, 2)

          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6
          ) {
            ForEach(["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"], id: \.self) { day in
              Text(day)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(DesignTokens.Colors.subtleText)
                .frame(maxWidth: .infinity)
            }
          }

          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6
          ) {
            ForEach(Array(eventsMonthGridDates.enumerated()), id: \.offset) { _, date in
              if let date { eventsCalendarDayCell(date) } else { Color.clear.frame(minHeight: 104) }
            }
          }

          sourceNote
        }
        .padding(.bottom, 8)
      }
      .scrollIndicators(.hidden)

      ScrollView { selectedCalendarDayCard }
        .scrollIndicators(.hidden)
        .frame(width: 304)
    }
  }

  private func eventsCalendarDayCell(_ date: Date) -> some View {
    let dayEvents = calendarEvents(on: date)
    let selected = calendar.isDate(date, inSameDayAs: selectedDate)
    let today = calendar.isDateInToday(date)

    return Button {
      withAnimation(DesignTokens.Animation.snappy) { selectedDate = date }
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(String(calendar.component(.day, from: date)))
            .font(.system(size: 11.5, weight: selected ? .bold : .semibold))
            .foregroundStyle(selected ? eventsColor : DesignTokens.Colors.primaryText)
          Spacer()
          if today {
            Text("TODAY")
              .font(.system(size: 7.5, weight: .bold))
              .foregroundStyle(eventsColor)
          }
        }
        VStack(alignment: .leading, spacing: 4) {
          ForEach(Array(dayEvents.prefix(3))) { event in
            HStack(spacing: 5) {
              Circle()
                .fill(
                  bookmarkedEventKeys.contains(stableKey(for: event))
                    ? eventsColor : eventsColor.opacity(0.58)
                )
                .frame(width: 5, height: 5)
              Text(event.title)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .lineLimit(1)
            }
          }
          if dayEvents.count > 3 {
            Text("+\(dayEvents.count - 3) more")
              .font(.system(size: 8, weight: .semibold))
              .foregroundStyle(eventsColor)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(9)
      .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      selected ? eventsColor.opacity(0.10) : DesignTokens.Colors.surface,
      in: RoundedRectangle(cornerRadius: 11, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .strokeBorder(
          selected || today
            ? eventsColor.opacity(selected ? 0.34 : 0.22) : DesignTokens.Colors.border, lineWidth: 1
        )
    }
  }

  private var selectedCalendarDayCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(calendarDayTitle(selectedDate))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
          Text(
            "\(selectedCalendarDayEvents.count) event\(selectedCalendarDayEvents.count == 1 ? "" : "s")"
          )
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        Spacer()
        if calendar.isDateInToday(selectedDate) {
          Image(systemName: "calendar.circle.fill").foregroundStyle(eventsColor)
        }
      }
      Divider().overlay(DesignTokens.Colors.border)
      if selectedCalendarDayEvents.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "calendar").font(.system(size: 20)).foregroundStyle(
            DesignTokens.Colors.subtleText)
          Text("Nothing scheduled").font(.system(size: 11.5, weight: .semibold))
          Text("Choose another day in the calendar.").font(.system(size: 9.5)).foregroundStyle(
            DesignTokens.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
      } else {
        VStack(spacing: 8) {
          ForEach(selectedCalendarDayEvents) { event in
            Button {
              selectedEvent = event
            } label: {
              HStack(alignment: .top, spacing: 9) {
                Rectangle().fill(eventsColor).frame(width: 3).clipShape(Capsule())
                VStack(alignment: .leading, spacing: 3) {
                  Text(event.title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(
                    DesignTokens.Colors.primaryText
                  ).lineLimit(2)
                  Text(eventDateLine(event)).font(.system(size: 9)).foregroundStyle(
                    DesignTokens.Colors.secondaryText)
                  if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin").font(.system(size: 8.5)).foregroundStyle(
                      DesignTokens.Colors.subtleText
                    ).lineLimit(1)
                  }
                }
                Spacer()
                if bookmarkedEventKeys.contains(stableKey(for: event)) {
                  Image(systemName: "bookmark.fill").font(.system(size: 9)).foregroundStyle(
                    eventsColor)
                }
              }
              .padding(9)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
              DesignTokens.Colors.selection.opacity(0.34),
              in: RoundedRectangle(cornerRadius: 9, style: .continuous))
          }
        }
      }
    }
    .padding(14)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  // MARK: - Header

  private var eventsHeader: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Events")
          .font(DesignTokens.Typography.pageTitle)
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text(longDate(selectedDate))
          .font(.system(size: 13))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .contentTransition(.opacity)

        RemoteDataStatusLabel(
          lastUpdated: store.lastUpdated,
          usingSavedData: store.isShowingSavedData
        )
      }

      Spacer()

      RooGlassEffectGroup(spacing: 8) {
        HStack(spacing: 8) {
          periodNavigation

          HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(DesignTokens.Colors.secondaryText)

            TextField("Search events", text: $searchText)
              .textFieldStyle(.plain)
              .font(.system(size: 12))
              .frame(width: 230)

            if !searchText.isEmpty {
              Button {
                searchText = ""
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(DesignTokens.Colors.subtleText)
                  .frame(width: 22, height: 22)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, 12)
          .frame(height: 38)
          .rooInteractiveGlass(cornerRadius: 11)

          Button {
            store.refresh()
          } label: {
            Group {
              if store.isLoading {
                ProgressView()
                  .controlSize(.small)
              } else {
                Image(systemName: "arrow.clockwise")
                  .font(.system(size: 11, weight: .semibold))
              }
            }
            .frame(width: 38, height: 38)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .rooInteractiveGlass(cornerRadius: 11)
          .help("Refresh events")
        }
      }
    }
    .zIndex(200)
  }

  private var periodNavigation: some View {
    HStack(spacing: 4) {
      eventIconButton("chevron.left") {
        moveReferenceDate(by: -1)
      }

      Button {
        withAnimation(DesignTokens.Animation.snappy) {
          selectedDate = Date()
        }
      } label: {
        Text(isCurrentPeriod ? currentPeriodLabel : shortPeriodLabel)
          .font(.system(size: 12, weight: .semibold))
          .frame(width: 92, height: 38)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .rooInteractiveGlass(cornerRadius: 10)
      .help(resetButtonHelp)

      eventIconButton("chevron.right") {
        moveReferenceDate(by: 1)
      }
    }
  }

  private func eventIconButton(
    _ systemName: String,
    action: @escaping () -> Void
  ) -> some View {
    Button {
      withAnimation(DesignTokens.Animation.content) {
        action()
      }
    } label: {
      Image(systemName: systemName)
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 38, height: 38)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .rooInteractiveGlass(cornerRadius: 10)
  }

  // MARK: - Scope bar

  private var scopeBar: some View {
    HStack(spacing: 8) {
      ForEach(CalendarGroupingMode.allCases) { mode in
        Button {
          withAnimation(DesignTokens.Animation.navigation) {
            showCalendar = false
            selectedGrouping = mode
          }
        } label: {
          Text(scopeTitle(for: mode))
            .font(
              .system(
                size: 11,
                weight: (selectedGrouping == mode && !showCalendar) ? .semibold : .medium
              )
            )
            .foregroundStyle(
              (selectedGrouping == mode && !showCalendar)
                ? DesignTokens.Colors.primaryText
                : DesignTokens.Colors.secondaryText
            )
            .padding(.horizontal, 14)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
              (selectedGrouping == mode && !showCalendar)
                ? eventsColor.opacity(0.13)
                : DesignTokens.Colors.surface
            )
        }
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
              (selectedGrouping == mode && !showCalendar)
                ? eventsColor.opacity(0.27)
                : DesignTokens.Colors.border,
              lineWidth: 1
            )
        }
      }

      Button {
        withAnimation(.easeOut(duration: 0.14)) {
          showSourcePicker.toggle()
        }
      } label: {
        HStack(spacing: 7) {
          Image(systemName: "calendar")
            .font(.system(size: 11, weight: .semibold))

          Text(store.selectionTitle)
            .font(.system(size: 11, weight: .semibold))

          Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(eventsColor)
        .padding(.horizontal, 13)
        .frame(height: 36)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(eventsColor.opacity(0.09))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(eventsColor.opacity(0.20), lineWidth: 1)
      }
      .overlay(alignment: .topLeading) {
        if showSourcePicker {
          sourcePickerPanel
            .offset(y: 44)
            .transition(
              .opacity.combined(
                with: .scale(scale: 0.97, anchor: .topLeading)
              )
            )
            .zIndex(180)
        }
      }
      .zIndex(showSourcePicker ? 180 : 0)

      Button {
        savedOnly.toggle()
      } label: {
        HStack(spacing: 6) {
          Image(systemName: savedOnly ? "bookmark.fill" : "bookmark")
            .font(.system(size: 10, weight: .semibold))

          Text("Saved")
            .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(
          savedOnly
            ? eventsColor
            : DesignTokens.Colors.secondaryText
        )
        .padding(.horizontal, 12)
        .frame(height: 36)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(
            savedOnly
              ? eventsColor.opacity(0.10)
              : DesignTokens.Colors.surface
          )
      }
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(
            savedOnly
              ? eventsColor.opacity(0.22)
              : DesignTokens.Colors.border,
            lineWidth: 1
          )
      }

      Button {
        withAnimation(DesignTokens.Animation.navigation) {
          selectedGrouping = .month
          showCalendar = true
        }
      } label: {
        Label("Calendar", systemImage: "calendar")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(showCalendar ? eventsColor : DesignTokens.Colors.secondaryText)
          .padding(.horizontal, 12)
          .frame(height: 36)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background(
        showCalendar ? eventsColor.opacity(0.10) : DesignTokens.Colors.surface,
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(
            showCalendar ? eventsColor.opacity(0.24) : DesignTokens.Colors.border, lineWidth: 1)
      }

      Spacer()

      Text("\(visibleEvents.count) event\(visibleEvents.count == 1 ? "" : "s")")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
    }
    .zIndex(180)
  }

  private var sourcePickerPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Calendar")
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 2)

      ForEach(CalendarSource.allCases) { source in
        let isSelected = selectedSources.contains(source)

        Button {
          var updated = selectedSources
          if source == .allEvents {
            updated = [.allEvents]
          } else {
            updated.remove(.allEvents)
            if updated.contains(source) {
              updated.remove(source)
            } else {
              updated.insert(source)
            }
            if updated.isEmpty {
              updated = [.allEvents]
            }
          }
          selectedSources = updated
        } label: {
          HStack(spacing: 9) {
            Image(systemName: source == .allEvents ? "calendar.badge.checkmark" : "calendar")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(
                isSelected
                  ? eventsColor
                  : DesignTokens.Colors.secondaryText
              )
              .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
              Text(source.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
              if source == .allEvents {
                Text("Selects every calendar")
                  .font(.system(size: 8.5, weight: .medium))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
              }
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(isSelected ? eventsColor : DesignTokens.Colors.subtleText)
          }
          .padding(.horizontal, 9)
          .frame(minHeight: 36)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
          isSelected
            ? eventsColor.opacity(0.09)
            : DesignTokens.Colors.selection.opacity(0.30),
          in: RoundedRectangle(cornerRadius: 9)
        )
      }
    }
    .padding(13)
    .frame(width: 238)
    .rooGlass(cornerRadius: 14)
    .rooFloatingShadow()
  }

  // MARK: - Right rail

  private var featuredEventCard: some View {
    VStack(alignment: .leading, spacing: 13) {
      EventsSectionLabel("NEXT UP", color: eventsColor)

      if let event = nextUpcomingEvent {
        ZStack {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(eventsColor.opacity(0.10))

          VStack(spacing: 10) {
            ZStack {
              Circle()
                .fill(eventsColor.opacity(0.14))

              Image(systemName: "calendar")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(eventsColor)
            }
            .frame(width: 52, height: 52)

            Text(event.title)
              .font(.system(size: 17, weight: .semibold))
              .multilineTextAlignment(.center)
              .lineLimit(3)

            Text(eventDateLine(event))
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.secondaryText)

            if let location = cleanLocation(event.location) {
              Label(location, systemImage: "mappin.and.ellipse")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .lineLimit(2)
            }

            if let countdown = countdownText(for: event) {
              Text(countdown)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(eventsColor)
            }

            Button {
              selectedEvent = event
            } label: {
              HStack {
                Text("View Details")
                Spacer()
                Image(systemName: "chevron.right")
              }
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)
              .padding(.horizontal, 11)
              .frame(height: 34)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .rooInteractiveGlass(cornerRadius: 10)
          }
          .padding(14)
        }
      } else {
        compactEmptyState(
          icon: "calendar.badge.checkmark",
          title: "Nothing upcoming",
          subtitle: "There aren’t any future events on this calendar yet."
        )
      }
    }
    .padding(15)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var upcomingOverviewCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      EventsSectionLabel("COMING UP", color: eventsColor)

      overviewMetric(
        title: "Today",
        value: countEvents(in: .day),
        color: DesignTokens.Colors.today
      )

      overviewMetric(
        title: "This Week",
        value: countEvents(in: .week),
        color: eventsColor
      )

      overviewMetric(
        title: "This Month",
        value: countEvents(in: .month),
        color: DesignTokens.Colors.pacTrack
      )

    }
    .padding(15)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private func overviewMetric(
    title: String,
    value: Int,
    color: Color
  ) -> some View {
    HStack(spacing: 9) {
      Circle()
        .fill(color)
        .frame(width: 7, height: 7)

      Text(title)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(DesignTokens.Colors.primaryText)

      Spacer()

      Text("\(value)")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
    }
  }

  private var savedEventsCard: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack {
        EventsSectionLabel("SAVED EVENTS", color: eventsColor)
        Spacer()
        Text("\(bookmarkedEvents.count)")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(eventsColor)
      }

      if bookmarkedEvents.isEmpty {
        compactEmptyState(
          icon: "bookmark",
          title: "Nothing saved yet",
          subtitle: "Use the bookmark button on an event to keep it here."
        )
      } else {
        VStack(spacing: 0) {
          ForEach(Array(bookmarkedEvents.prefix(3))) { event in
            Button {
              selectedEvent = event
            } label: {
              HStack(alignment: .top, spacing: 9) {
                Image(systemName: "bookmark.fill")
                  .font(.system(size: 10, weight: .semibold))
                  .foregroundStyle(eventsColor)
                  .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                  Text(event.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .lineLimit(2)

                  Text(compactEventDate(event))
                    .font(.system(size: 9))
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                }

                Spacer()
              }
              .padding(.vertical, 8)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if event.id != bookmarkedEvents.prefix(3).last?.id {
              Divider().opacity(0.26)
            }
          }
        }
      }
    }
    .padding(15)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var upcomingCalendarCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        EventsSectionLabel("UPCOMING CALENDAR", color: eventsColor)

        Spacer()

        Text("Next 7 Days")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(eventsColor)
      }

      HStack(spacing: 4) {
        ForEach(nextSevenDates, id: \.self) { date in
          Button {
            selectedDate = date
            selectedGrouping = .day
          } label: {
            VStack(spacing: 4) {
              Text(shortWeekday(date))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.subtleText)

              Text(dayNumber(date))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                  calendar.isDate(date, inSameDayAs: selectedDate)
                    ? Color.white
                    : DesignTokens.Colors.primaryText
                )

              Text("\(eventCount(on: date))")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(
                  eventCount(on: date) > 0
                    ? eventsColor
                    : DesignTokens.Colors.subtleText
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 55)
            .background {
              RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                  calendar.isDate(date, inSameDayAs: selectedDate)
                    ? eventsColor
                    : DesignTokens.Colors.selection.opacity(0.30)
                )
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }

      Divider().opacity(0.30)

      HStack {
        Image(systemName: "calendar")
          .foregroundStyle(eventsColor)

        Text("\(nextSevenDayEvents.count) events in the next 7 days")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)

        Spacer()
      }
    }
    .padding(15)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  // MARK: - States

  private var loadingCard: some View {
    HStack(spacing: 10) {
      ProgressView()
        .controlSize(.small)

      Text("Loading school events…")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(DesignTokens.Colors.secondaryText)

      Spacer()
    }
    .padding(16)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private func errorCard(_: Error) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(DesignTokens.Colors.warning)

      VStack(alignment: .leading, spacing: 3) {
        Text("Couldn’t load events")
          .font(.system(size: 12, weight: .semibold))

        Text("Check your connection or try again in a moment.")
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }

      Spacer()

      Button("Try Again") {
        store.refresh()
      }
      .buttonStyle(.plain)
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(eventsColor)
      .frame(minWidth: 44, minHeight: 28)
      .contentShape(Rectangle())
    }
    .padding(16)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: savedOnly ? "bookmark" : "calendar")
        .font(.system(size: 24))
        .foregroundStyle(eventsColor)

      Text(savedOnly ? "No saved events here" : "No events match this view")
        .font(.system(size: 14, weight: .semibold))

      Text(
        savedOnly
          ? "Save an event, or choose another date range."
          : "Try another date, calendar, or search."
      )
      .font(.system(size: 11))
      .foregroundStyle(DesignTokens.Colors.secondaryText)

      if savedOnly || !searchText.isEmpty {
        Button("Clear Filters") {
          savedOnly = false
          searchText = ""
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(eventsColor)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(eventsColor.opacity(0.10), in: Capsule())
        .contentShape(Capsule())
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 54)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var sourceNote: some View {
    HStack(alignment: .top, spacing: 7) {
      Image(systemName: "info.circle")
        .font(.system(size: 9))
        .foregroundStyle(DesignTokens.Colors.subtleText)

      Text(
        selectedSources.contains(.allEvents)
          ? "RooMate is showing the combined school calendar. Some events may not say which school calendar they came from."
          : "Showing events from: \(store.selectionDetail)."
      )
      .font(.system(size: 9))
      .foregroundStyle(DesignTokens.Colors.subtleText)

      Spacer()
    }
    .padding(.horizontal, 6)
  }

  // MARK: - Event data

  private var visiblePeriodInterval: DateInterval {
    periodInterval(for: selectedGrouping, around: selectedDate)
  }

  private var visibleEvents: [CalendarEvent] {
    let query =
      searchText
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    return store.events
      .filter { event in
        guard eventOverlaps(event, interval: visiblePeriodInterval) else {
          return false
        }

        if savedOnly && !bookmarkedEventKeys.contains(stableKey(for: event)) {
          return false
        }

        if !query.isEmpty {
          let searchable = [
            event.title,
            event.location ?? "",
          ]
          .joined(separator: " ")
          .lowercased()

          guard searchable.contains(query) else {
            return false
          }
        }

        return true
      }
      .sorted {
        if $0.startDate == $1.startDate {
          return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        return $0.startDate < $1.startDate
      }
  }

  private var groupedVisibleEvents: [EventsDayGroup] {
    // In Day mode, an event that began on an earlier date but still spans the
    // selected day belongs under the selected day's heading. Grouping only by
    // DTSTART made an event shown on September 2 look like it was somehow in a
    // September 1 section.
    if selectedGrouping == .day {
      guard !visibleEvents.isEmpty else { return [] }
      return [
        EventsDayGroup(
          date: calendar.startOfDay(for: selectedDate),
          events: visibleEvents
        )
      ]
    }

    let grouped = Dictionary(grouping: visibleEvents) {
      calendar.startOfDay(for: $0.startDate)
    }

    return grouped
      .keys
      .sorted()
      .map { date in
        EventsDayGroup(
          date: date,
          events: grouped[date] ?? []
        )
      }
  }

  private var allUpcomingEvents: [CalendarEvent] {
    let now = Date()

    return store.events
      .filter { event in
        effectiveEventEnd(event) >= now
      }
      .sorted {
        $0.startDate < $1.startDate
      }
  }

  private var nextUpcomingEvent: CalendarEvent? {
    allUpcomingEvents.first
  }

  private var bookmarkedEvents: [CalendarEvent] {
    store.events
      .filter {
        bookmarkedEventKeys.contains(stableKey(for: $0))
      }
      .sorted { $0.startDate < $1.startDate }
  }

  private var nextSevenDates: [Date] {
    let start = calendar.startOfDay(for: Date())

    return (0..<7).compactMap {
      calendar.date(byAdding: .day, value: $0, to: start)
    }
  }

  private var nextSevenDayEvents: [CalendarEvent] {
    let start = calendar.startOfDay(for: Date())
    let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start

    return store.events.filter {
      eventOverlaps(
        $0,
        interval: DateInterval(start: start, end: end)
      )
    }
  }

  private var bookmarkedEventKeys: Set<String> {
    Set(
      bookmarkedEventKeysRaw
        .split(separator: "\n")
        .map(String.init)
    )
  }

  // MARK: - Date helpers

  private func periodInterval(
    for mode: CalendarGroupingMode,
    around date: Date
  ) -> DateInterval {
    switch mode {
    case .day:
      return calendar.dateInterval(of: .day, for: date)
        ?? DateInterval(
          start: calendar.startOfDay(for: date),
          duration: 24 * 60 * 60
        )

    case .week:
      return calendar.dateInterval(of: .weekOfYear, for: date)
        ?? DateInterval(
          start: calendar.startOfDay(for: date),
          duration: 7 * 24 * 60 * 60
        )

    case .month:
      return calendar.dateInterval(of: .month, for: date)
        ?? DateInterval(
          start: calendar.startOfDay(for: date),
          duration: 31 * 24 * 60 * 60
        )
    }
  }

  private func eventOverlaps(
    _ event: CalendarEvent,
    interval: DateInterval
  ) -> Bool {
    let end = effectiveEventEnd(event)

    return event.startDate < interval.end
      && end >= interval.start
  }

  private func effectiveEventEnd(_ event: CalendarEvent) -> Date {
    let end = event.endDate ?? event.startDate
    guard isLikelyAllDay(event) else { return end }

    // ICS date-only events are stored with an inclusive final calendar day.
    // Treat that whole final day as active for filtering and overlap checks,
    // instead of letting the event disappear at midnight on its last day.
    let endDay = calendar.startOfDay(for: end)
    return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endDay) ?? end
  }

  private func moveReferenceDate(by amount: Int) {
    let component: Calendar.Component

    switch selectedGrouping {
    case .day:
      component = .day
    case .week:
      component = .weekOfYear
    case .month:
      component = .month
    }

    selectedDate =
      calendar.date(
        byAdding: component,
        value: amount,
        to: selectedDate
      ) ?? selectedDate
  }

  private var isCurrentPeriod: Bool {
    switch selectedGrouping {
    case .day:
      return calendar.isDateInToday(selectedDate)

    case .week:
      guard
        let selectedWeek = calendar.dateInterval(
          of: .weekOfYear,
          for: selectedDate
        ),
        let currentWeek = calendar.dateInterval(
          of: .weekOfYear,
          for: Date()
        )
      else {
        return false
      }

      return selectedWeek.start == currentWeek.start

    case .month:
      return calendar.isDate(
        selectedDate,
        equalTo: Date(),
        toGranularity: .month
      )
    }
  }

  private var currentPeriodLabel: String {
    switch selectedGrouping {
    case .day: "Today"
    case .week: "This Week"
    case .month: "This Month"
    }
  }

  private var shortPeriodLabel: String {
    let formatter = DateFormatter()
    formatter.timeZone = eventsSchoolTimeZone

    switch selectedGrouping {
    case .day:
      formatter.dateFormat = "MMM d"
      return formatter.string(from: selectedDate)

    case .week:
      formatter.dateFormat = "MMM d"
      let interval = visiblePeriodInterval
      let end =
        calendar.date(
          byAdding: .day,
          value: -1,
          to: interval.end
        ) ?? interval.end
      return "\(formatter.string(from: interval.start))–\(formatter.string(from: end))"

    case .month:
      formatter.dateFormat = "MMM yyyy"
      return formatter.string(from: selectedDate)
    }
  }

  private var resetButtonHelp: String {
    switch selectedGrouping {
    case .day: "Return to today"
    case .week: "Return to this week"
    case .month: "Return to this month"
    }
  }

  private func scopeTitle(for mode: CalendarGroupingMode) -> String {
    switch mode {
    case .day: "Today"
    case .week: "This Week"
    case .month: "This Month"
    }
  }

  private func longDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = eventsSchoolTimeZone
    formatter.dateFormat = "EEEE, MMMM d, yyyy"
    return formatter.string(from: date)
  }

  private func shortWeekday(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = eventsSchoolTimeZone
    formatter.dateFormat = "EEE"
    return formatter.string(from: date).uppercased()
  }

  private func dayNumber(_ date: Date) -> String {
    String(calendar.component(.day, from: date))
  }

  private func eventCount(on date: Date) -> Int {
    guard let interval = calendar.dateInterval(of: .day, for: date) else {
      return 0
    }

    return store.events.filter {
      eventOverlaps($0, interval: interval)
    }.count
  }

  private func countEvents(in mode: CalendarGroupingMode) -> Int {
    let interval = periodInterval(for: mode, around: Date())

    return store.events.filter {
      eventOverlaps($0, interval: interval)
    }.count
  }

  private var eventsMonthGridDates: [Date?] {
    guard let interval = calendar.dateInterval(of: .month, for: selectedDate) else { return [] }
    let monthStart = calendar.startOfDay(for: interval.start)
    let weekday = calendar.component(.weekday, from: monthStart)
    let leading = (weekday - calendar.firstWeekday + 7) % 7
    let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0
    var dates = [Date?](repeating: nil, count: leading)
    for offset in 0..<dayCount {
      dates.append(calendar.date(byAdding: .day, value: offset, to: monthStart))
    }
    while dates.count % 7 != 0 { dates.append(nil) }
    return dates
  }

  private func calendarEvents(on date: Date) -> [CalendarEvent] {
    guard let interval = calendar.dateInterval(of: .day, for: date) else { return [] }
    return visibleEvents.filter { eventOverlaps($0, interval: interval) }
  }

  private var selectedCalendarDayEvents: [CalendarEvent] { calendarEvents(on: selectedDate) }

  private func monthYear(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = eventsSchoolTimeZone
    formatter.dateFormat = "MMMM yyyy"
    return formatter.string(from: date)
  }

  private func calendarDayTitle(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = eventsSchoolTimeZone
    formatter.dateFormat = "EEEE, MMMM d"
    return formatter.string(from: date)
  }

  // MARK: - Event helpers

  private func stableKey(for event: CalendarEvent) -> String {
    let timestamp = Int(event.startDate.timeIntervalSince1970)
    let location = event.location ?? ""

    return "\(timestamp)|\(event.title)|\(location)"
      .replacingOccurrences(of: "\n", with: " ")
  }

  private func toggleBookmark(_ event: CalendarEvent) {
    var keys = bookmarkedEventKeys
    let key = stableKey(for: event)

    if keys.contains(key) {
      keys.remove(key)
    } else {
      keys.insert(key)
    }

    bookmarkedEventKeysRaw =
      keys
      .sorted()
      .joined(separator: "\n")

    NotificationCenter.default.post(
      name: .rooMateEventPreferencesDidChange,
      object: nil
    )
  }

  private func cleanLocation(_ value: String?) -> String? {
    guard let value else { return nil }

    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)

    return cleaned.isEmpty ? nil : cleaned
  }

  private func eventDateLine(_ event: CalendarEvent) -> String {
    if isLikelyAllDay(event) {
      let formatter = DateFormatter()
      formatter.timeZone = eventsSchoolTimeZone
      formatter.dateFormat = "EEE, MMM d"

      if event.isMultiDay, let end = event.endDate {
        return "\(formatter.string(from: event.startDate)) – \(formatter.string(from: end)) • All Day"
      }

      formatter.dateFormat = "EEEE, MMM d"
      return "\(formatter.string(from: event.startDate)) • All Day"
    }

    let formatter = DateFormatter()
    formatter.timeZone = eventsSchoolTimeZone
    formatter.dateFormat = "EEE, MMM d • h:mm a"

    if let end = event.endDate {
      let endFormatter = DateFormatter()
      endFormatter.timeZone = eventsSchoolTimeZone

      if calendar.isDate(end, inSameDayAs: event.startDate) {
        endFormatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: event.startDate)) – \(endFormatter.string(from: end))"
      }

      endFormatter.dateFormat = "EEE, MMM d • h:mm a"
      return "\(formatter.string(from: event.startDate)) – \(endFormatter.string(from: end))"
    }

    return formatter.string(from: event.startDate)
  }

  private func compactEventDate(_ event: CalendarEvent) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = eventsSchoolTimeZone
    formatter.dateFormat = "MMM d"

    if isLikelyAllDay(event) {
      if event.isMultiDay, let end = event.endDate {
        return "\(formatter.string(from: event.startDate))–\(formatter.string(from: end)) • All Day"
      }
      return "\(formatter.string(from: event.startDate)) • All Day"
    }

    let time = DateFormatter()
    time.timeZone = eventsSchoolTimeZone
    time.dateFormat = "h:mm a"

    if let end = event.endDate, !calendar.isDate(end, inSameDayAs: event.startDate) {
      return "\(formatter.string(from: event.startDate)) \(time.string(from: event.startDate))–\(formatter.string(from: end)) \(time.string(from: end))"
    }

    return "\(formatter.string(from: event.startDate)) • \(time.string(from: event.startDate))"
  }

  private func isLikelyAllDay(_ event: CalendarEvent) -> Bool {
    let start = calendar.dateComponents(
      [.hour, .minute, .second],
      from: event.startDate
    )

    guard start.hour == 0,
      start.minute == 0,
      start.second == 0
    else {
      return false
    }

    if let end = event.endDate {
      let endComponents = calendar.dateComponents(
        [.hour, .minute, .second],
        from: end
      )

      return endComponents.hour == 0
        && endComponents.minute == 0
        && endComponents.second == 0
    }

    return true
  }

  private func countdownText(for event: CalendarEvent) -> String? {
    let seconds = event.startDate.timeIntervalSinceNow

    guard seconds > 0 else {
      return nil
    }

    let totalMinutes = Int(seconds / 60)
    let days = totalMinutes / (60 * 24)
    let hours = (totalMinutes % (60 * 24)) / 60
    let minutes = totalMinutes % 60

    if days > 0 {
      return "\(days)d \(hours)h away"
    }

    if hours > 0 {
      return "\(hours)h \(minutes)m away"
    }

    return "\(max(minutes, 1))m away"
  }

  private func compactEmptyState(
    icon: String,
    title: String,
    subtitle: String
  ) -> some View {
    VStack(spacing: 7) {
      Image(systemName: icon)
        .font(.system(size: 17))
        .foregroundStyle(DesignTokens.Colors.subtleText)

      Text(title)
        .font(.system(size: 11, weight: .semibold))

      Text(subtitle)
        .font(.system(size: 9))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
  }
}

// MARK: - Event day group

private struct EventsDayGroup: Identifiable {
  let date: Date
  let events: [CalendarEvent]

  var id: Date { date }
}

private struct EventsDaySection: View {
  let group: EventsDayGroup
  let bookmarkedKeys: Set<String>
  let onToggleBookmark: (CalendarEvent) -> Void
  let onOpen: (CalendarEvent) -> Void

  private let calendar = eventsSchoolCalendar()
  private let eventsColor = DesignTokens.Colors.events

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(dayHeader(group.date))
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(eventsColor)

        Spacer()

        Text("\(group.events.count) event\(group.events.count == 1 ? "" : "s")")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
      .padding(.horizontal, 16)
      .frame(height: 44)

      Divider().opacity(0.30)

      ForEach(group.events) { event in
        EventDashboardRow(
          event: event,
          isBookmarked: bookmarkedKeys.contains(stableKey(for: event)),
          onToggleBookmark: { onToggleBookmark(event) },
          onOpen: { onOpen(event) }
        )

        if event.id != group.events.last?.id {
          Divider()
            .opacity(0.24)
            .padding(.horizontal, 16)
        }
      }
    }
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private func dayHeader(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = eventsSchoolTimeZone
    formatter.dateFormat = "EEEE • MMMM d"
    return formatter.string(from: date).uppercased()
  }

  private func stableKey(for event: CalendarEvent) -> String {
    let timestamp = Int(event.startDate.timeIntervalSince1970)
    let location = event.location ?? ""

    return "\(timestamp)|\(event.title)|\(location)"
      .replacingOccurrences(of: "\n", with: " ")
  }
}

// MARK: - Event row

private struct EventDashboardRow: View {
  let event: CalendarEvent
  let isBookmarked: Bool
  let onToggleBookmark: () -> Void
  let onOpen: () -> Void

  private let calendar = eventsSchoolCalendar()
  private let eventsColor = DesignTokens.Colors.events

  var body: some View {
    HStack(spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(eventsColor.opacity(0.12))

        Image(systemName: "calendar")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(eventsColor)
      }
      .frame(width: 44, height: 44)

      VStack(alignment: .leading, spacing: 4) {
        Text(event.title)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .lineLimit(2)

        if let location = cleanLocation {
          Label(location, systemImage: "mappin.and.ellipse")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      VStack(alignment: .leading, spacing: 4) {
        Text(dateText)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text(timeText)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
      .frame(width: 148, alignment: .leading)

      Button(action: onToggleBookmark) {
        Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(
            isBookmarked
              ? eventsColor
              : DesignTokens.Colors.subtleText
          )
          .frame(width: 34, height: 34)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background(
        isBookmarked
          ? eventsColor.opacity(0.10)
          : DesignTokens.Colors.selection.opacity(0.40),
        in: RoundedRectangle(cornerRadius: 9)
      )
      .help(isBookmarked ? "Remove bookmark" : "Save event")

      Button(action: onOpen) {
        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.subtleText)
          .frame(width: 30, height: 34)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .contentShape(Rectangle())
    .onTapGesture(perform: onOpen)
  }

  private var cleanLocation: String? {
    guard
      let value = event.location?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }

    return value
  }

  private var dateText: String {
    let formatter = DateFormatter()
    formatter.timeZone = eventsSchoolTimeZone
    formatter.dateFormat = "EEE, MMM d"

    if event.isMultiDay, let end = event.endDate {
      return "\(formatter.string(from: event.startDate)) – \(formatter.string(from: end))"
    }

    return formatter.string(from: event.startDate)
  }

  private var timeText: String {
    if isLikelyAllDay {
      return "All Day"
    }

    let formatter = DateFormatter()
    formatter.timeZone = eventsSchoolTimeZone
    formatter.dateFormat = "h:mm a"

    if let end = event.endDate,
      calendar.isDate(end, inSameDayAs: event.startDate)
    {
      return "\(formatter.string(from: event.startDate)) – \(formatter.string(from: end))"
    }

    return formatter.string(from: event.startDate)
  }

  private var isLikelyAllDay: Bool {
    let start = calendar.dateComponents(
      [.hour, .minute, .second],
      from: event.startDate
    )

    guard start.hour == 0,
      start.minute == 0,
      start.second == 0
    else {
      return false
    }

    if let end = event.endDate {
      let endComponents = calendar.dateComponents(
        [.hour, .minute, .second],
        from: end
      )

      return endComponents.hour == 0
        && endComponents.minute == 0
        && endComponents.second == 0
    }

    return true
  }
}

// MARK: - Detail sheet

private struct EventDetailSheet: View {
  let event: CalendarEvent
  let isBookmarked: Bool
  let onToggleBookmark: () -> Void

  @Environment(\.dismiss)
  private var dismiss

  private let eventsColor = DesignTokens.Colors.events
  private let calendar = eventsSchoolCalendar()

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top) {
        HStack(spacing: 12) {
          ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .fill(eventsColor.opacity(0.13))

            Image(systemName: "calendar")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(eventsColor)
          }
          .frame(width: 46, height: 46)

          Text(event.title)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
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

      LazyVGrid(
        columns: [
          GridItem(.flexible()),
          GridItem(.flexible()),
        ],
        alignment: .leading,
        spacing: 16
      ) {
        detailMetric(
          title: "Date",
          value: fullDate,
          icon: "calendar"
        )

        detailMetric(
          title: "Time",
          value: timeText,
          icon: "clock"
        )

        if let location = cleanLocation {
          detailMetric(
            title: "Location",
            value: location,
            icon: "mappin.and.ellipse"
          )
        }

        if event.isMultiDay, let end = event.endDate {
          detailMetric(
            title: "Ends",
            value: fullDate(end),
            icon: "calendar.badge.clock"
          )
        }
      }

      Button(action: onToggleBookmark) {
        HStack {
          Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
          Text(isBookmarked ? "Saved" : "Save Event")
          Spacer()
          Image(systemName: isBookmarked ? "checkmark" : "chevron.right")
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(
          isBookmarked
            ? eventsColor
            : DesignTokens.Colors.primaryText
        )
        .padding(.horizontal, 12)
        .frame(height: 38)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .rooInteractiveGlass(cornerRadius: 10)
    }
    .padding(20)
    .frame(width: 500)
    .background(DesignTokens.Colors.background)
  }

  private func detailMetric(
    title: String,
    value: String,
    icon: String
  ) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(eventsColor)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 2) {
        Text(title.uppercased())
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(DesignTokens.Colors.subtleText)

        Text(value)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var fullDate: String {
    fullDate(event.startDate)
  }

  private func fullDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = eventsSchoolTimeZone
    formatter.dateFormat = "EEEE, MMMM d, yyyy"
    return formatter.string(from: date)
  }

  private var timeText: String {
    if isLikelyAllDay {
      return "All Day"
    }

    let formatter = DateFormatter()
    formatter.timeZone = eventsSchoolTimeZone
    formatter.dateFormat = "h:mm a"

    if let end = event.endDate,
      calendar.isDate(end, inSameDayAs: event.startDate)
    {
      return "\(formatter.string(from: event.startDate)) – \(formatter.string(from: end))"
    }

    return formatter.string(from: event.startDate)
  }

  private var cleanLocation: String? {
    guard
      let location = event.location?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !location.isEmpty
    else {
      return nil
    }

    return location
  }

  private var isLikelyAllDay: Bool {
    let start = calendar.dateComponents(
      [.hour, .minute, .second],
      from: event.startDate
    )

    guard start.hour == 0,
      start.minute == 0,
      start.second == 0
    else {
      return false
    }

    if let end = event.endDate {
      let endComponents = calendar.dateComponents(
        [.hour, .minute, .second],
        from: end
      )

      return endComponents.hour == 0
        && endComponents.minute == 0
        && endComponents.second == 0
    }

    return true
  }
}

// MARK: - Local label helper

private struct EventsSectionLabel: View {
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

#Preview {
  EventsView(store: EventsStore())
}
