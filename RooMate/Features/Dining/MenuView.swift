import SwiftUI

#if canImport(AppKit)
  import AppKit
#endif

struct MenuView: View {
  @ObservedObject var store: MenuStore
  @ObservedObject private var navigation = RooMateNavigationCoordinator.shared

  @State private var searchText = ""
  @State private var collapsedStationIDs: Set<String> = []
  @State private var favoriteRecipeNames: Set<String>
  @State private var showCalendar = false
  @State private var calendarMonth = Date()

  private let favoritesDefaultsKey = "RooMateDiningFavoriteRecipeNames"
  private let rightRailWidth: CGFloat = 300

  init(store: MenuStore) {
    _store = ObservedObject(wrappedValue: store)
    let saved = UserDefaults.standard.stringArray(forKey: "RooMateDiningFavoriteRecipeNames") ?? []
    _favoriteRecipeNames = State(initialValue: Set(saved))
  }

  var body: some View {
    GeometryReader { proxy in
      Group {
        if showCalendar {
          diningCalendarWorkspace
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else {
          let showRightRail = proxy.size.width >= 980
          HStack(alignment: .top, spacing: 16) {
            mainColumn
            if showRightRail {
              rightRail
                .frame(width: rightRailWidth)
                .transition(.opacity)
            }
          }
          .transition(.opacity)
        }
      }
      .animation(DesignTokens.Animation.navigation, value: showCalendar)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .task {
      if store.availableDates.isEmpty || store.isShowingSavedData { store.refresh() }
      calendarMonth = store.selectedDate?.date ?? Date()
      handleNavigationRequest()
    }
    .onChange(of: navigation.request) { _, _ in handleNavigationRequest() }
    .onChange(of: store.availableDates) { _, _ in handleNavigationRequest() }
    .onChange(of: store.currentMenu) { _, _ in handleNavigationRequest() }
    .onChange(of: store.selectedDate?.id) { _, _ in
      if showCalendar, let date = store.selectedDate?.date { calendarMonth = date }
    }
    .onChange(of: favoriteRecipeNames) { _, names in
      UserDefaults.standard.set(Array(names).sorted(), forKey: favoritesDefaultsKey)
    }
  }

  private func handleNavigationRequest() {
    guard let request = navigation.request,
      case .dining(let dateID, let recipeName) = request.destination,
      let entry = store.availableDates.first(where: { $0.id == dateID })
    else { return }

    if store.selectedDate?.id != entry.id {
      store.selectDate(entry)
      return
    }

    searchText = recipeName
    showCalendar = false
    navigation.consume(request)
  }

  private var diningCalendarWorkspace: some View {
    VStack(spacing: 14) {
      header
      HStack(alignment: .top, spacing: 16) {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(diningMonthYear(calendarMonth))
                  .font(.system(size: 19, weight: .semibold))
                  .foregroundStyle(DesignTokens.Colors.primaryText)
                Text("Choose any available menu date")
                  .font(.system(size: 10.5))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
              }
              Spacer()
              Text(
                "\(availableDatesInCalendarMonth.count) menu day\(availableDatesInCalendarMonth.count == 1 ? "" : "s")"
              )
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.dining)
              .padding(.horizontal, 9)
              .frame(height: 26)
              .background(DesignTokens.Colors.dining.opacity(0.10), in: Capsule())
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
              ForEach(Array(diningMonthGridDates.enumerated()), id: \.offset) { _, date in
                if let date {
                  diningCalendarDayCell(date)
                } else {
                  Color.clear.frame(minHeight: 92)
                }
              }
            }

            diningSafetyNote
          }
          .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)

        ScrollView { diningCalendarSelectionCard }
          .scrollIndicators(.hidden)
          .frame(width: 330)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func diningCalendarDayCell(_ date: Date) -> some View {
    let entry = availableMenuEntry(on: date)
    let selected =
      store.selectedDate.map { Calendar.current.isDate($0.date, inSameDayAs: date) } ?? false
    let today = Calendar.current.isDateInToday(date)

    return Button {
      guard let entry else { return }
      withAnimation(DesignTokens.Animation.content) { store.selectDate(entry) }
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text(String(Calendar.current.component(.day, from: date)))
            .font(.system(size: 11.5, weight: selected ? .bold : .semibold))
            .foregroundStyle(
              selected
                ? DesignTokens.Colors.dining
                : (entry == nil ? DesignTokens.Colors.subtleText : DesignTokens.Colors.primaryText))
          Spacer()
          if today {
            Text("TODAY").font(.system(size: 7.5, weight: .bold)).foregroundStyle(
              DesignTokens.Colors.dining)
          }
        }
        if entry != nil {
          HStack(spacing: 5) {
            Image(systemName: "fork.knife").font(.system(size: 8, weight: .semibold))
            Text("Menu available").font(.system(size: 8.5, weight: .semibold)).lineLimit(1)
          }
          .foregroundStyle(
            selected ? DesignTokens.Colors.dining : DesignTokens.Colors.secondaryText)
        } else {
          Text("No menu").font(.system(size: 8.5)).foregroundStyle(
            DesignTokens.Colors.subtleText.opacity(0.75))
        }
        Spacer(minLength: 0)
      }
      .padding(9)
      .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(entry == nil)
    .background(
      selected ? DesignTokens.Colors.dining.opacity(0.10) : DesignTokens.Colors.surface,
      in: RoundedRectangle(cornerRadius: 11, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .strokeBorder(
          selected || today
            ? DesignTokens.Colors.dining.opacity(selected ? 0.34 : 0.20)
            : DesignTokens.Colors.border, lineWidth: 1)
    }
    .opacity(entry == nil ? 0.58 : 1)
  }

  private var diningCalendarSelectionCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center, spacing: 11) {
        ZStack {
          RoundedRectangle(
            cornerRadius: 10,
            style: .continuous
          )
          .fill(DesignTokens.Colors.dining.opacity(0.11))

          Image(systemName: "fork.knife")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.dining)
        }
        .frame(width: 36, height: 36)

        VStack(alignment: .leading, spacing: 2) {
          Text(
            store.selectedDate.map {
              diningCalendarDayTitle($0.date)
            } ?? "Select a menu"
          )
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .lineLimit(1)

          Text(
            store.selectedDate == nil
              ? "Choose an available date"
              : "Selected menu"
          )
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer(minLength: 6)

        if store.isLoading {
          ProgressView()
            .controlSize(.small)
        }
      }

      if !store.mealPeriods.isEmpty {
        calendarMealPeriodPicker
      }

      Divider()
        .overlay(DesignTokens.Colors.border)

      calendarSelectedMenuSummary
    }
    .padding(15)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(
      DesignTokens.Colors.surface,
      in: RoundedRectangle(
        cornerRadius: DesignTokens.Radius.lg,
        style: .continuous
      )
    )
    .overlay {
      RoundedRectangle(
        cornerRadius: DesignTokens.Radius.lg,
        style: .continuous
      )
      .strokeBorder(
        DesignTokens.Colors.border,
        lineWidth: 1
      )
    }
  }

  private var calendarMealPeriodPicker: some View {
    Menu {
      ForEach(store.mealPeriods) { period in
        Button {
          withAnimation(DesignTokens.Animation.snappy) {
            store.selectMealPeriod(period.id)
          }
        } label: {
          if store.selectedMealPeriodID == period.id {
            Label(period.name, systemImage: "checkmark")
          } else {
            Text(period.name)
          }
        }
      }
    } label: {
      HStack(spacing: 9) {
        VStack(alignment: .leading, spacing: 2) {
          Text("MEAL PERIOD")
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(DesignTokens.Colors.subtleText)

          Text(selectedMealPeriodName)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .lineLimit(1)
        }

        Spacer()

        Image(systemName: "chevron.up.chevron.down")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
      .padding(.horizontal, 11)
      .frame(height: 46)
      .contentShape(
        RoundedRectangle(
          cornerRadius: 10,
          style: .continuous
        )
      )
      .background(
        DesignTokens.Colors.hover.opacity(0.28),
        in: RoundedRectangle(
          cornerRadius: 10,
          style: .continuous
        )
      )
      .overlay {
        RoundedRectangle(
          cornerRadius: 10,
          style: .continuous
        )
        .strokeBorder(
          DesignTokens.Colors.border,
          lineWidth: 1
        )
      }
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private var calendarSelectedMenuSummary: some View {
    if store.currentMenu == nil {
      VStack(spacing: 9) {
        ProgressView()
          .controlSize(.small)

        Text("Loading menu…")
          .font(.system(size: 10.5))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 28)
    } else if store.visibleStations.isEmpty {
      VStack(spacing: 9) {
        Image(systemName: "fork.knife")
          .font(.system(size: 20, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.subtleText)

        Text("No menu items for this meal")
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text("Choose another meal above.")
          .font(.system(size: 9.5))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 26)
    } else {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text("MENU")
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.65)
            .foregroundStyle(DesignTokens.Colors.subtleText)

          Spacer()

          Text(
            "\(calendarVisibleRecipeCount) item\(calendarVisibleRecipeCount == 1 ? "" : "s")"
          )
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        ForEach(store.visibleStations) { station in
          calendarStationSummary(station)
        }
      }
    }
  }

  private var calendarVisibleRecipeCount: Int {
    store.visibleStations.reduce(0) {
      $0 + $1.recipes.count
    }
  }

  private func calendarStationSummary(
    _ station: MenuStation
  ) -> some View {
    let accent = stationAccent(station.name)

    return VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 9) {
        ZStack {
          RoundedRectangle(
            cornerRadius: 8,
            style: .continuous
          )
          .fill(accent.opacity(0.11))

          Image(
            systemName: resolvedSymbolName(
              primary: stationSymbol(station.name),
              fallback: "fork.knife"
            )
          )
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(accent)
        }
        .frame(width: 28, height: 28)

        Text(station.name)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .lineLimit(1)

        Spacer(minLength: 6)

        Text("\(station.recipes.count)")
          .font(.system(size: 9.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }

      VStack(alignment: .leading, spacing: 6) {
        ForEach(
          Array(station.recipes.prefix(4))
        ) { recipe in
          HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
              .fill(accent.opacity(0.72))
              .frame(width: 4, height: 4)

            Text(recipe.name)
              .font(.system(size: 10.5))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .lineLimit(2)

            Spacer(minLength: 0)
          }
        }

        if station.recipes.count > 4 {
          Text("+\(station.recipes.count - 4) more")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(accent)
            .padding(.leading, 11)
        }
      }
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      DesignTokens.Colors.hover.opacity(0.22),
      in: RoundedRectangle(
        cornerRadius: 11,
        style: .continuous
      )
    )
    .overlay {
      RoundedRectangle(
        cornerRadius: 11,
        style: .continuous
      )
      .strokeBorder(
        accent.opacity(0.12),
        lineWidth: 1
      )
    }
  }

  // MARK: - Main layout

  private var mainColumn: some View {
    VStack(spacing: 14) {
      header

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          diningHero

          quickDateSelector

          if let error = store.lastError {
            errorCard(error)
          }

          if store.availableDates.isEmpty || store.currentMenu == nil {
            loadingOrEmptyState
          } else if filteredStations.isEmpty {
            emptyResultsState
          } else {
            stationList
          }

          diningSafetyNote
            .padding(.top, 2)
        }
        .padding(.bottom, 8)
        .animation(
          DesignTokens.Animation.content,
          value: store.selectedDate?.id
        )
        .animation(
          DesignTokens.Animation.content,
          value: filteredStations.map(\.id)
        )
      }
      .scrollIndicators(.hidden)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Dining")
          .font(DesignTokens.Typography.pageTitle)
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text(showCalendar ? diningMonthYear(calendarMonth) : selectedHeaderDate)
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
          dateNavigation

          HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(DesignTokens.Colors.secondaryText)

            TextField("Search menu", text: $searchText)
              .textFieldStyle(.plain)
              .font(.system(size: 12))
              .frame(width: 150)

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
            } else {
              Text("⌘K")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.subtleText)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(
                  DesignTokens.Colors.selection,
                  in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
            }
          }
          .padding(.horizontal, 12)
          .frame(height: 36)
          .rooInteractiveGlass(cornerRadius: 11)

          Button {
            withAnimation(DesignTokens.Animation.navigation) {
              showCalendar.toggle()
              if showCalendar { calendarMonth = store.selectedDate?.date ?? Date() }
            }
          } label: {
            Image(systemName: showCalendar ? "list.bullet" : "calendar")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(
                showCalendar ? DesignTokens.Colors.dining : DesignTokens.Colors.primaryText
              )
              .frame(width: 36, height: 36)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .rooInteractiveGlass(cornerRadius: 11)
          .help(showCalendar ? "Show menu list" : "Show dining calendar")

          Button {
            store.reloadSelectedDate()
          } label: {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 11, weight: .semibold))
              .frame(width: 36, height: 36)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .rooInteractiveGlass(cornerRadius: 11)
          .help("Reload menu")
        }
      }
    }
  }

  // MARK: - Hero

  private var diningHero: some View {
    HStack(spacing: 16) {
      ZStack {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .fill(DesignTokens.Colors.dining.opacity(0.12))

        Image(systemName: "fork.knife")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.dining)
      }
      .frame(width: 58, height: 58)

      VStack(alignment: .leading, spacing: 5) {
        Text(heroTitle)
          .font(.system(size: 27, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text(heroSubtitle)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(heroSubtitleColor)

        HStack(spacing: 14) {
          Label(servingTimeText, systemImage: "clock")
          Label("Dining Hall", systemImage: "mappin")
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .padding(.top, 2)
      }

      Spacer(minLength: 12)
    }
    .padding(18)
    .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
        .fill(DesignTokens.Colors.surface)
    }
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
        .stroke(DesignTokens.Colors.dining.opacity(0.14), lineWidth: 1)
    }
  }

  // MARK: - Date navigation

  private var dateNavigation: some View {
    HStack(spacing: 4) {
      if showCalendar {
        Button {
          withAnimation(DesignTokens.Animation.content) {
            calendarMonth =
              Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth
          }
        } label: {
          Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)).frame(
            width: 34, height: 34
          ).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rooInteractiveGlass(cornerRadius: 10)

        Button {
          withAnimation(DesignTokens.Animation.content) { calendarMonth = Date() }
        } label: {
          Text(diningMonthShort(calendarMonth)).font(.system(size: 11.5, weight: .semibold)).frame(
            width: 92, height: 34
          ).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rooInteractiveGlass(cornerRadius: 10)
        .help("Return to this month")

        Button {
          withAnimation(DesignTokens.Animation.content) {
            calendarMonth =
              Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth
          }
        } label: {
          Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).frame(
            width: 34, height: 34
          ).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rooInteractiveGlass(cornerRadius: 10)
      } else {
        dateArrow("chevron.left", offset: -1)
        Button {
          withAnimation(DesignTokens.Animation.content) { selectTodayIfAvailable() }
        } label: {
          HStack(spacing: 6) {
            if store.selectedDate?.isToday == false {
              Circle().fill(DesignTokens.Colors.dining).frame(width: 5, height: 5)
            }
            Text(store.selectedDate?.isToday == true ? "Today" : compactSelectedDate).font(
              .system(size: 12, weight: .semibold))
          }
          .frame(width: 82, height: 34)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rooInteractiveGlass(cornerRadius: 10)
        .help("Return to today's menu")
        dateArrow("chevron.right", offset: 1)
      }
    }
  }

  private func dateArrow(_ symbol: String, offset: Int) -> some View {
    Button {
      withAnimation(DesignTokens.Animation.content) {
        selectRelativeDate(offset)
      }
    } label: {
      Image(systemName: symbol)
        .font(.system(size: 10, weight: .semibold))
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .rooInteractiveGlass(cornerRadius: 10)
    .disabled(relativeDate(offset) == nil)
    .opacity(relativeDate(offset) == nil ? 0.45 : 1)
  }

  private var quickDateSelector: some View {
    HStack(spacing: 6) {
      ForEach(quickDateEntries) { entry in
        let selected = store.selectedDate?.id == entry.id

        Button {
          withAnimation(DesignTokens.Animation.content) {
            store.selectDate(entry)
          }
        } label: {
          Text(quickDateLabel(entry))
            .font(.system(size: 11, weight: selected ? .semibold : .medium))
            .foregroundStyle(
              selected
                ? DesignTokens.Colors.primaryText
                : DesignTokens.Colors.secondaryText
            )
            .frame(minWidth: 90)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background {
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                  selected
                    ? DesignTokens.Colors.dining.opacity(0.13)
                    : DesignTokens.Colors.selection.opacity(0.35)
                )
            }
            .overlay {
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                  selected
                    ? DesignTokens.Colors.dining.opacity(0.22)
                    : DesignTokens.Colors.border,
                  lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
      }

      Spacer()

      if store.isLoading {
        ProgressView()
          .scaleEffect(0.72)
      }
    }
  }

  private var mealPeriodSelector: some View {
    HStack(spacing: 6) {
      ForEach(store.mealPeriods) { period in
        let selected = store.selectedMealPeriodID == period.id

        Button {
          withAnimation(DesignTokens.Animation.snappy) {
            store.selectMealPeriod(period.id)
          }
        } label: {
          Text(period.name)
            .font(.system(size: 11, weight: selected ? .semibold : .medium))
            .foregroundStyle(
              selected
                ? DesignTokens.Colors.primaryText
                : DesignTokens.Colors.secondaryText
            )
            .padding(.horizontal, 12)
            .frame(height: 32)
            .contentShape(Rectangle())
            .background(
              selected
                ? DesignTokens.Colors.dining.opacity(0.13)
                : DesignTokens.Colors.selection.opacity(0.32),
              in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
      }

      Spacer()
    }
  }

  // MARK: - Stations

  private var stationList: some View {
    LazyVStack(alignment: .leading, spacing: 28) {
      ForEach(filteredStations) { station in
        diningStationSection(station)
      }
    }
    .padding(.top, 2)
  }

  private func diningStationSection(_ station: MenuStation) -> some View {
    let accent = stationAccent(station.name)

    return VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(accent.opacity(0.13))

          Image(
            systemName: resolvedSymbolName(
              primary: stationSymbol(station.name),
              fallback: "fork.knife"
            )
          )
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(accent)
        }
        .frame(width: 38, height: 38)

        VStack(alignment: .leading, spacing: 1) {
          Text(station.name)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)

          Text("\(station.recipes.count) \(station.recipes.count == 1 ? "item" : "items")")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Rectangle()
          .fill(accent.opacity(0.42))
          .frame(height: 1)
          .padding(.leading, 6)
      }

      LazyVGrid(
        columns: [
          GridItem(.flexible(), spacing: 12),
          GridItem(.flexible(), spacing: 12),
        ],
        alignment: .leading,
        spacing: 10
      ) {
        ForEach(station.recipes) { recipe in
          DiningRecipeDetailRow(
            recipe: recipe,
            accent: accent,
            isFavorite: favoriteRecipeNames.contains(recipe.name),
            onFavorite: { toggleFavorite(recipe.name) }
          )
        }
      }
    }
  }

  // MARK: - Right rail

  private var rightRail: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        favoritesCard
        filtersCard
        lookingAheadCard
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .padding(.bottom, 8)
    }
    .scrollIndicators(.hidden)
  }

  private func diningRailCard<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var favoritesCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        DiningSectionLabel("FAVORITES")
        Spacer()

        if !favoriteRecipeNames.isEmpty {
          Button("Clear") {
            favoriteRecipeNames.removeAll()
          }
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.dining)
          .buttonStyle(.plain)
          .padding(.horizontal, 5)
          .frame(minHeight: 24)
          .contentShape(Rectangle())
        }
      }

      if favoriteRecipeNames.isEmpty {
        VStack(spacing: 9) {
          Image(systemName: "heart")
            .font(.system(size: 22))
            .foregroundStyle(DesignTokens.Colors.subtleText)

          Text("No favorites yet")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)

          Text("Click the heart next to a menu item to save it here.")
            .font(.system(size: 10))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
      } else {
        VStack(spacing: 4) {
          ForEach(Array(favoriteRecipeNames).sorted(), id: \.self) { name in
            HStack(spacing: 9) {
              ZStack {
                Circle()
                  .fill(DesignTokens.Colors.dining.opacity(0.12))
                  .frame(width: 28, height: 28)

                Image(systemName: "fork.knife")
                  .font(.system(size: 10, weight: .semibold))
                  .foregroundStyle(DesignTokens.Colors.dining)
              }

              Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .lineLimit(2)

              Spacer()

              Button {
                toggleFavorite(name)
              } label: {
                Image(systemName: "heart.fill")
                  .foregroundStyle(DesignTokens.Colors.dining)
                  .frame(width: 24, height: 24)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
            .padding(.vertical, 3)
          }
        }
      }
    }
    .padding(15)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg, elevated: false, border: true)
  }

  private var filtersCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        DiningSectionLabel("FILTERS")
        Spacer()

        if store.filters.isFiltering {
          Button("Clear") {
            withAnimation(.easeOut(duration: 0.14)) {
              store.filters = MenuFilterState()
            }
          }
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.dining)
          .buttonStyle(.plain)
          .padding(.horizontal, 5)
          .frame(minHeight: 24)
          .contentShape(Rectangle())
        }
      }

      Text("Dietary preferences")
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(DesignTokens.Colors.subtleText)

      VStack(spacing: 5) {
        ForEach(MenuLifestyleTag.allCases) { tag in
          filterToggleRow(.lifestyle(tag))
        }
      }

      Divider().opacity(0.28)

      Text("Avoid")
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(DesignTokens.Colors.subtleText)

      VStack(spacing: 5) {
        ForEach(MenuCoreAllergen.allCases) { allergen in
          filterToggleRow(.allergen(allergen))
        }
      }
    }
    .padding(15)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg, elevated: false, border: true)
  }

  private func filterToggleRow(_ item: MenuFilterItem) -> some View {
    let isOn = store.filters.contains(item)
    let tint = filterTint(for: item)

    return Button {
      withAnimation(.easeOut(duration: 0.13)) {
        store.filters.toggle(item)
      }
    } label: {
      HStack(spacing: 9) {
        Image(systemName: resolvedSymbolName(primary: item.symbol, fallback: "circle"))
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(isOn ? tint : DesignTokens.Colors.secondaryText)
          .frame(width: 17)

        Text(item.title)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Spacer()

        ZStack(alignment: isOn ? .trailing : .leading) {
          Capsule()
            .fill(isOn ? tint : DesignTokens.Colors.selection)
            .frame(width: 32, height: 18)

          Circle()
            .fill(Color.white)
            .frame(width: 14, height: 14)
            .padding(2)
        }
        .frame(width: 32, height: 18)
      }
      .padding(.horizontal, 7)
      .frame(height: 30)
      .contentShape(Rectangle())
      .background(
        isOn ? tint.opacity(0.07) : Color.clear,
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
    }
    .buttonStyle(.plain)
  }

  private var lookingAheadCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      DiningSectionLabel("UPCOMING MENUS")

      if let next = relativeDate(1) {
        Button {
          store.selectDate(next)
        } label: {
          HStack(spacing: 11) {
            ZStack {
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignTokens.Colors.dining.opacity(0.12))

              Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.dining)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
              Text(lookingAheadTitle(next))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)

              Text("View the next available menu")
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            Spacer()

            Image(systemName: "chevron.right")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.subtleText)
          }
          .padding(.horizontal, 10)
          .frame(height: 58)
          .contentShape(Rectangle())
          .background(
            DesignTokens.Colors.selection.opacity(0.45),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
          )
        }
        .buttonStyle(.plain)
      } else {
        Text("No later menu is available yet.")
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .padding(.vertical, 8)
      }
    }
    .padding(15)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg, elevated: false, border: true)
  }

  // MARK: - States and footer

  private func errorCard(_: Error) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(DesignTokens.Colors.warning)

      VStack(alignment: .leading, spacing: 2) {
        Text("Menu couldn't be updated")
          .font(.system(size: 11, weight: .semibold))
        Text(store.isShowingSavedData ? "Your saved menu is still available." : "Check your connection or try again in a moment.")
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .lineLimit(2)
      }

      Spacer()

      Button("Try Again") {
        store.reloadSelectedDate()
      }
      .buttonStyle(.plain)
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(DesignTokens.Colors.dining)
      .frame(minWidth: 44, minHeight: 28)
      .contentShape(Rectangle())
    }
    .padding(12)
    .background(DesignTokens.Colors.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(DesignTokens.Colors.warning.opacity(0.16), lineWidth: 1)
    }
  }

  private var loadingOrEmptyState: some View {
    VStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(DesignTokens.Colors.dining.opacity(0.11))
          .frame(width: 62, height: 62)

        if store.isLoading {
          ProgressView()
            .scaleEffect(0.9)
        } else {
          Image(systemName: "fork.knife")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.dining)
        }
      }

      Text(store.isLoading ? "Loading today's menu…" : "No menu is available")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(DesignTokens.Colors.primaryText)

      Text("Try another available date or reload the dining menu.")
        .font(.system(size: 11))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 46)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var emptyResultsState: some View {
    VStack(spacing: 11) {
      Image(systemName: "line.3.horizontal.decrease.circle")
        .font(.system(size: 23))
        .foregroundStyle(DesignTokens.Colors.dining)

      Text("No menu items match")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(DesignTokens.Colors.primaryText)

      Text(
        searchText.isEmpty
          ? "Try changing your dietary filters." : "Try a different search or clear your filters."
      )
      .font(.system(size: 11))
      .foregroundStyle(DesignTokens.Colors.secondaryText)

      Button("Clear filters and search") {
        searchText = ""
        store.filters = MenuFilterState()
      }
      .buttonStyle(.plain)
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(DesignTokens.Colors.dining)
      .padding(.horizontal, 12)
      .frame(height: 30)
      .background(DesignTokens.Colors.dining.opacity(0.10), in: Capsule())
      .contentShape(Capsule())
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 42)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var diningSafetyNote: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "info.circle")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(DesignTokens.Colors.subtleText)
        .padding(.top, 1)

      Text(
        "Menu items, nutrition details, and allergen information can change. If you have food allergies or specific dietary concerns, check with dining staff for the most up-to-date information."
      )
      .font(.system(size: 9))
      .foregroundStyle(DesignTokens.Colors.subtleText)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 4)
  }

  // MARK: - Data helpers

  private var filteredStations: [MenuStation] {
    guard let menu = store.currentMenu else { return [] }

    let query =
      searchText
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    var order: [String] = []
    var firstStationForKey: [String: MenuStation] = [:]
    var recipesForKey: [String: [MenuRecipe]] = [:]

    for station in menu.stations {
      let key = station.name
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

      if firstStationForKey[key] == nil {
        firstStationForKey[key] = station
        order.append(key)
      }

      let stationNameMatches =
        !query.isEmpty
        && station.name.lowercased().contains(query)

      let matchingRecipes = station.recipes.filter { recipe in
        guard store.filters.matches(recipe) else { return false }

        if query.isEmpty || stationNameMatches {
          return true
        }

        return recipe.name.lowercased().contains(query)
          || recipe.labels.contains(where: {
            $0.lowercased().contains(query)
          })
          || recipeDetailSearchText(recipe).contains(query)
      }

      recipesForKey[key, default: []].append(contentsOf: matchingRecipes)
    }

    return order.compactMap { key in
      guard let base = firstStationForKey[key] else { return nil }

      var seen = Set<String>()
      let uniqueRecipes = (recipesForKey[key] ?? []).filter { recipe in
        let recipeKey =
          recipe.id.isEmpty
          ? "\(recipe.stationName)|\(recipe.name)"
          : recipe.id
        return seen.insert(recipeKey).inserted
      }

      guard !uniqueRecipes.isEmpty else { return nil }

      return MenuStation(
        id: base.id,
        name: base.name,
        mealPeriodID: base.mealPeriodID,
        recipes: uniqueRecipes
      )
    }
  }

  private func recipeDetailSearchText(_ recipe: MenuRecipe) -> String {
    recipeDetailItems(recipe)
      .map(\.title)
      .joined(separator: " ")
      .lowercased()
  }

  private var diningMonthGridDates: [Date?] {
    guard let interval = Calendar.current.dateInterval(of: .month, for: calendarMonth) else {
      return []
    }
    let monthStart = Calendar.current.startOfDay(for: interval.start)
    let weekday = Calendar.current.component(.weekday, from: monthStart)
    let leading = (weekday - Calendar.current.firstWeekday + 7) % 7
    let dayCount = Calendar.current.range(of: .day, in: .month, for: monthStart)?.count ?? 0
    var dates = [Date?](repeating: nil, count: leading)
    for offset in 0..<dayCount {
      dates.append(Calendar.current.date(byAdding: .day, value: offset, to: monthStart))
    }
    while dates.count % 7 != 0 { dates.append(nil) }
    return dates
  }

  private var availableDatesInCalendarMonth: [MenuDateEntry] {
    store.availableDates.filter {
      Calendar.current.isDate($0.date, equalTo: calendarMonth, toGranularity: .month)
    }
  }

  private func availableMenuEntry(on date: Date) -> MenuDateEntry? {
    store.availableDates.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
  }

  private func diningMonthYear(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM yyyy"
    return formatter.string(from: date)
  }

  private func diningMonthShort(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM yyyy"
    return formatter.string(from: date)
  }

  private func diningCalendarDayTitle(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMMM d"
    return formatter.string(from: date)
  }

  private var selectedMealPeriodName: String {
    guard let id = store.selectedMealPeriodID else { return "Lunch" }
    return store.mealPeriods.first(where: { $0.id == id })?.name ?? "Lunch"
  }

  private var selectedHeaderDate: String {
    guard let selected = store.selectedDate else { return "Loading menus" }
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMMM d, yyyy"
    return formatter.string(from: selected.date)
  }

  private var compactSelectedDate: String {
    guard let selected = store.selectedDate else { return "Menu" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: selected.date)
  }

  private var quickDateEntries: [MenuDateEntry] {
    guard !store.availableDates.isEmpty else { return [] }
    guard let selected = store.selectedDate,
      let index = store.availableDates.firstIndex(where: { $0.id == selected.id })
    else {
      return Array(store.availableDates.prefix(3))
    }

    let lower = max(0, min(index - 1, store.availableDates.count - 3))
    let upper = min(store.availableDates.count, lower + 3)
    return Array(store.availableDates[lower..<upper])
  }

  private func quickDateLabel(_ entry: MenuDateEntry) -> String {
    if entry.isToday { return "Today" }
    if Calendar.current.isDateInTomorrow(entry.date) { return "Tomorrow" }

    let formatter = DateFormatter()
    formatter.dateFormat = "EEE, MMM d"
    return formatter.string(from: entry.date)
  }

  private func selectRelativeDate(_ offset: Int) {
    guard let entry = relativeDate(offset) else { return }
    store.selectDate(entry)
  }

  private func relativeDate(_ offset: Int) -> MenuDateEntry? {
    guard let selected = store.selectedDate,
      let index = store.availableDates.firstIndex(where: { $0.id == selected.id })
    else {
      return nil
    }

    let newIndex = index + offset
    guard store.availableDates.indices.contains(newIndex) else { return nil }
    return store.availableDates[newIndex]
  }

  private func selectTodayIfAvailable() {
    if let today = store.availableDates.first(where: { $0.isToday }) {
      store.selectDate(today)
    }
  }

  private func lookingAheadTitle(_ entry: MenuDateEntry) -> String {
    if Calendar.current.isDateInTomorrow(entry.date) { return "Tomorrow" }
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMM d"
    return formatter.string(from: entry.date)
  }

  private func toggleFavorite(_ name: String) {
    if favoriteRecipeNames.contains(name) {
      favoriteRecipeNames.remove(name)
      TelemetryTracker.trackDiningFavoriteChanged(
        isFavorite: false,
        favoriteCount: favoriteRecipeNames.count
      )
    } else {
      favoriteRecipeNames.insert(name)
      TelemetryTracker.trackDiningFavoriteChanged(
        isFavorite: true,
        favoriteCount: favoriteRecipeNames.count
      )
    }
  }

  // MARK: - Serving status

  private var heroTitle: String {
    guard let selected = store.selectedDate else { return "Lunch menu" }
    guard selected.isToday, let window = lunchWindow(for: selected.date) else {
      return "Lunch menu"
    }

    let now = Date()
    if now < window.start {
      return "Lunch at \(timeString(window.start))"
    } else if now < window.end {
      return "Serving now"
    } else {
      return "Lunch is over"
    }
  }

  private var heroSubtitle: String {
    guard let selected = store.selectedDate else { return "" }
    guard selected.isToday, let window = lunchWindow(for: selected.date) else {
      return "Menu for \(selected.displayTitle)"
    }

    let now = Date()
    if now < window.start {
      return "Starts in \(minutesBetween(now, window.start)) min"
    } else if now < window.end {
      return "Closes in \(minutesBetween(now, window.end)) min"
    } else {
      return "See what was served today"
    }
  }

  private var heroSubtitleColor: Color {
    guard let selected = store.selectedDate, selected.isToday,
      let window = lunchWindow(for: selected.date)
    else {
      return DesignTokens.Colors.secondaryText
    }

    let now = Date()
    return now >= window.start && now < window.end
      ? DesignTokens.Colors.dining
      : DesignTokens.Colors.secondaryText
  }

  private var servingTimeText: String {
    guard let selected = store.selectedDate, let window = lunchWindow(for: selected.date) else {
      return "Check menu"
    }
    return "\(timeString(window.start)) – \(timeString(window.end))"
  }

  private func lunchWindow(for date: Date) -> (start: Date, end: Date)? {
    let weekdayIndex = Calendar.current.component(.weekday, from: date)
    guard let weekday = Weekday.allCases.first(where: { $0.calendarWeekdayIndex == weekdayIndex }),
      let block = BellSchedule.weekly[weekday]?.first(where: { block in
        guard case .special(let special) = block.kind else { return false }
        return special == .lunch || special == .lunchAndClubs
      }),
      let start = makeDate(on: date, components: block.start),
      let end = makeDate(on: date, components: block.end)
    else {
      return nil
    }

    return (start, end)
  }

  private func makeDate(on day: Date, components: DateComponents) -> Date? {
    var dayComponents = Calendar.current.dateComponents([.year, .month, .day], from: day)
    dayComponents.hour = components.hour
    dayComponents.minute = components.minute
    return Calendar.current.date(from: dayComponents)
  }

  private func timeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
  }

  private func minutesBetween(_ start: Date, _ end: Date) -> Int {
    max(1, Int(ceil(end.timeIntervalSince(start) / 60)))
  }

  // MARK: - Station appearance

  private func stationAccent(_ name: String) -> Color {
    let normalized = name.lowercased()

    if normalized.contains("daily feature") { return DesignTokens.Colors.dining }
    if normalized.contains("seoul") { return Color(hex: 0xD98267) }
    if normalized.contains("green") { return DesignTokens.Colors.athletics }
    if normalized.contains("deli") { return Color(hex: 0xC77A9E) }
    if normalized.contains("flame") { return DesignTokens.Colors.destructive }
    if normalized.contains("sauce") || normalized.contains("stone") {
      return DesignTokens.Colors.warning
    }
    if normalized.contains("soup") { return DesignTokens.Colors.events }
    return DesignTokens.Colors.dining
  }

  private func stationSymbol(_ name: String) -> String {
    let normalized = name.lowercased()

    if normalized.contains("daily feature") { return "takeoutbag.and.cup.and.straw.fill" }
    if normalized.contains("seoul") { return "globe.asia.australia.fill" }
    if normalized.contains("green") { return "leaf.fill" }
    if normalized.contains("deli") { return "bag.fill" }
    if normalized.contains("flame") { return "flame.fill" }
    if normalized.contains("sauce") || normalized.contains("stone") {
      return "circle.grid.2x2.fill"
    }
    if normalized.contains("soup") { return "cup.and.saucer.fill" }
    return "fork.knife"
  }
}

private struct DiningSectionLabel: View {
  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title.capitalized)
      .font(.system(size: 11.5, weight: .semibold))
      .foregroundStyle(DesignTokens.Colors.secondaryText)
  }
}

// MARK: - Recipe details

private struct DiningRecipeDetail: Identifiable, Hashable {
  enum Kind: String, Hashable {
    case lifestyle
    case allergen
    case source
  }

  let title: String
  let symbol: String
  let kind: Kind

  var id: String {
    "\(kind.rawValue)-\(title)-\(symbol)"
  }
}

private struct DiningRecipeDetailRow: View {
  let recipe: MenuRecipe
  let accent: Color
  let isFavorite: Bool
  let onFavorite: () -> Void

  private var lifestyleDetails: [DiningRecipeDetail] {
    recipe.displayBadges.compactMap { badge in
      guard badge.kind == .lifestyle else { return nil }
      return DiningRecipeDetail(
        title: badge.title,
        symbol: badge.symbol,
        kind: .lifestyle
      )
    }
  }

  private var allergenNames: [String] {
    recipe.coreAllergens
      .sorted { $0.sortOrder < $1.sortOrder }
      .map(\.displayName)
  }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Rectangle()
        .fill(accent)
        .frame(width: 3)
        .clipShape(Capsule())
        .padding(.vertical, 3)

      VStack(alignment: .leading, spacing: 6) {
        Text(recipe.name)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .fixedSize(horizontal: false, vertical: true)

        if !lifestyleDetails.isEmpty {
          HStack(spacing: 5) {
            ForEach(lifestyleDetails) { detail in
              DiningLifestylePill(detail: detail)
            }
          }
        }

        if !allergenNames.isEmpty {
          Text("Contains: \(allergenNames.joined(separator: " · "))")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .help("Contains " + allergenNames.joined(separator: ", "))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: onFavorite) {
        Image(systemName: isFavorite ? "heart.fill" : "heart")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(
            isFavorite
              ? DesignTokens.Colors.dining
              : DesignTokens.Colors.subtleText
          )
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(isFavorite ? "Remove from favorites" : "Add to favorites")
    }
    .padding(.vertical, 9)
    .padding(.horizontal, 11)
    .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
    .background {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(DesignTokens.Colors.surface)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(accent.opacity(0.13), lineWidth: 1)
    }
  }
}

private struct DiningLifestylePill: View {
  let detail: DiningRecipeDetail

  var body: some View {
    let tint = detailTint(detail)

    HStack(spacing: 4) {
      Image(
        systemName: resolvedSymbolName(
          primary: detail.symbol,
          fallback: "circle.fill"
        )
      )
      .font(.system(size: 7, weight: .bold))

      Text(detail.title)
        .font(.system(size: 8.5, weight: .semibold))
        .lineLimit(1)
    }
    .foregroundStyle(tint)
    .padding(.horizontal, 7)
    .frame(height: 20)
    .background(tint.opacity(0.10), in: Capsule())
    .overlay {
      Capsule()
        .stroke(tint.opacity(0.14), lineWidth: 1)
    }
  }
}

private struct DiningRecipeDetailChip: View {
  let detail: DiningRecipeDetail

  var body: some View {
    let tint = detailTint(detail)

    HStack(spacing: 4) {
      Image(
        systemName: resolvedSymbolName(
          primary: detail.symbol,
          fallback: "circle.fill"
        )
      )
      .font(.system(size: 7, weight: .bold))

      Text(detail.title)
        .font(.system(size: 8, weight: .semibold))
        .lineLimit(1)
    }
    .foregroundStyle(tint)
    .padding(.horizontal, 6)
    .frame(height: 20)
    .background(
      tint.opacity(0.10),
      in: Capsule()
    )
    .overlay {
      Capsule()
        .stroke(tint.opacity(0.14), lineWidth: 1)
    }
    .help(detail.title)
  }
}

private func recipeDetailItems(_ recipe: MenuRecipe) -> [DiningRecipeDetail] {
  var result: [DiningRecipeDetail] = []
  var usedTitles = Set<String>()

  for badge in recipe.displayBadges {
    let kind: DiningRecipeDetail.Kind =
      badge.kind == .lifestyle
      ? .lifestyle
      : .allergen

    let normalized = normalizedDiningDetailTitle(badge.title)

    if usedTitles.insert(normalized).inserted {
      result.append(
        DiningRecipeDetail(
          title: badge.title,
          symbol: badge.symbol,
          kind: kind
        )
      )
    }
  }

  return result
}

private func normalizedDiningDetailTitle(_ value: String) -> String {
  value
    .lowercased()
    .replacingOccurrences(
      of: "[^a-z0-9]+",
      with: "",
      options: .regularExpression
    )
}

private func readableDiningSourceLabel(_ raw: String) -> String? {
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }

  if trimmed.count > 42 { return nil }

  if trimmed.range(
    of: #"^[0-9a-fA-F-]{16,}$"#,
    options: .regularExpression
  ) != nil {
    return nil
  }

  var value =
    trimmed
    .replacingOccurrences(of: "_", with: " ")
    .replacingOccurrences(of: "-", with: " ")

  value = value.replacingOccurrences(
    of: #"([a-z])([A-Z])"#,
    with: "$1 $2",
    options: .regularExpression
  )

  value =
    value
    .split(whereSeparator: \.isWhitespace)
    .map(String.init)
    .joined(separator: " ")

  guard !value.isEmpty else { return nil }

  let knownAcronyms: [String: String] = [
    "vegan": "Vegan",
    "vegetarian": "Vegetarian",
    "bewell": "BeWell",
    "gluten": "Gluten",
    "milk": "Milk",
    "soy": "Soy",
    "eggs": "Eggs",
    "egg": "Egg",
    "fish": "Fish",
    "shellfish": "Shellfish",
    "sesame": "Sesame",
    "peanuts": "Peanuts",
    "peanut": "Peanut",
    "wheat": "Wheat",
  ]

  return
    value
    .split(separator: " ")
    .map { word in
      knownAcronyms[word.lowercased()]
        ?? (word.prefix(1).uppercased() + word.dropFirst())
    }
    .joined(separator: " ")
}

private func detailTint(_ detail: DiningRecipeDetail) -> Color {
  switch detail.kind {
  case .lifestyle:
    return DesignTokens.Colors.athletics
  case .allergen:
    return DesignTokens.Colors.warning
  case .source:
    return DesignTokens.Colors.events
  }
}

// MARK: - Shared dining appearance helpers

private func resolvedSymbolName(primary: String, fallback: String) -> String {
  #if canImport(AppKit)
    if NSImage(systemSymbolName: primary, accessibilityDescription: nil) != nil {
      return primary
    }
    return fallback
  #else
    return primary
  #endif
}

private func filterTint(for item: MenuFilterItem) -> Color {
  switch item {
  case .lifestyle(let tag):
    switch tag {
    case .vegetarian: return DesignTokens.Colors.athletics
    case .vegan: return Color(hex: 0x72BE77)
    case .beWell: return DesignTokens.Colors.warning
    }

  case .allergen(let allergen):
    switch allergen {
    case .eggs: return DesignTokens.Colors.warning
    case .milk: return DesignTokens.Colors.events
    case .soy: return DesignTokens.Colors.athletics
    case .wheat: return Color(hex: 0xB8996A)
    case .treeNuts: return Color(hex: 0xC1875D)
    case .peanuts: return DesignTokens.Colors.dining
    case .fish: return Color(hex: 0x6FAACB)
    case .shellfish: return DesignTokens.Colors.destructive
    case .sesameSeeds: return DesignTokens.Colors.pacTrack
    case .gluten: return Color(hex: 0x7D88C9)
    }
  }
}

private func badgeTint(for badge: MenuBadge) -> Color {
  switch badge.kind {
  case .lifestyle:
    switch badge.title {
    case "Vegetarian": return DesignTokens.Colors.athletics
    case "Vegan": return Color(hex: 0x72BE77)
    case "BeWell": return DesignTokens.Colors.warning
    default: return DesignTokens.Colors.dining
    }

  case .allergen:
    switch badge.title {
    case "Eggs": return DesignTokens.Colors.warning
    case "Milk": return DesignTokens.Colors.events
    case "Soy": return DesignTokens.Colors.athletics
    case "Wheat": return Color(hex: 0xB8996A)
    case "Tree Nuts": return Color(hex: 0xC1875D)
    case "Peanuts": return DesignTokens.Colors.dining
    case "Fish": return Color(hex: 0x6FAACB)
    case "Shellfish": return DesignTokens.Colors.destructive
    case "Sesame Seeds": return DesignTokens.Colors.pacTrack
    case "Gluten": return Color(hex: 0x7D88C9)
    default: return DesignTokens.Colors.secondaryText
    }
  }
}
