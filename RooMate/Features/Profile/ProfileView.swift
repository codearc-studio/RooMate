import SwiftUI

enum ProfileAvatarChoice: String, CaseIterable, Identifiable, Codable, Hashable {
  case initials
  case person
  case graduationCap
  case book
  case star
  case headphones
  case gameController
  case paintbrush
  case globe
  case atom
  case music
  case leaf
  case camera
  case airplane
  case bolt
  case moon
  case sun
  case laptop
  case pawprint
  case coffee
  case running
  case waveform
  case heart
  case lightbulb
  case trophy
  case film
  case map

  var id: String { rawValue }

  var title: String {
    switch self {
    case .initials: "Initials"
    case .person: "Person"
    case .graduationCap: "Graduate"
    case .book: "Book"
    case .star: "Star"
    case .headphones: "Music"
    case .gameController: "Games"
    case .paintbrush: "Creative"
    case .globe: "World"
    case .atom: "Science"
    case .music: "Notes"
    case .leaf: "Nature"
    case .camera: "Camera"
    case .airplane: "Travel"
    case .bolt: "Energy"
    case .moon: "Night"
    case .sun: "Sun"
    case .laptop: "Tech"
    case .pawprint: "Animals"
    case .coffee: "Coffee"
    case .running: "Running"
    case .waveform: "Audio"
    case .heart: "Heart"
    case .lightbulb: "Ideas"
    case .trophy: "Achievement"
    case .film: "Film"
    case .map: "Explore"
    }
  }

  var systemImage: String? {
    switch self {
    case .initials: nil
    case .person: "person.fill"
    case .graduationCap: "graduationcap.fill"
    case .book: "book.closed.fill"
    case .star: "star.fill"
    case .headphones: "headphones"
    case .gameController: "gamecontroller.fill"
    case .paintbrush: "paintbrush.fill"
    case .globe: "globe.americas.fill"
    case .atom: "atom"
    case .music: "music.note"
    case .leaf: "leaf.fill"
    case .camera: "camera.fill"
    case .airplane: "airplane"
    case .bolt: "bolt.fill"
    case .moon: "moon.stars.fill"
    case .sun: "sun.max.fill"
    case .laptop: "laptopcomputer"
    case .pawprint: "pawprint.fill"
    case .coffee: "cup.and.saucer.fill"
    case .running: "figure.run"
    case .waveform: "waveform"
    case .heart: "heart.fill"
    case .lightbulb: "lightbulb.fill"
    case .trophy: "trophy.fill"
    case .film: "film.fill"
    case .map: "map.fill"
    }
  }
}

enum ProfileAccentChoice: String, CaseIterable, Identifiable, Codable, Hashable {
  case orange, blue, cyan, green, purple, pink, red, gold

  var id: String { rawValue }
  var title: String { rawValue.capitalized }

  var color: Color {
    switch self {
    case .orange: DesignTokens.Colors.primary
    case .blue: DesignTokens.Colors.schedule
    case .cyan: DesignTokens.Colors.events
    case .green: DesignTokens.Colors.athletics
    case .purple: DesignTokens.Colors.pacTrack
    case .pink: DesignTokens.Colors.accent
    case .red: DesignTokens.Colors.destructive
    case .gold: DesignTokens.Colors.warning
    }
  }
}

struct ProfileAvatarView: View {
  @Environment(\.colorScheme) private var colorScheme

  let name: String
  let avatar: ProfileAvatarChoice
  let accentColor: Color
  var size: CGFloat = 64

  private var initials: String {
    let pieces =
      name
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: " ")
      .prefix(2)

    let value =
      pieces
      .compactMap(\.first)
      .map(String.init)
      .joined()
      .uppercased()

    return value.isEmpty ? "R" : value
  }

  var body: some View {
    ZStack {
      RoundedRectangle(
        cornerRadius: max(12, size * 0.27),
        style: .continuous
      )
      .fill(
        accentColor.opacity(
          colorScheme == .light ? 0.10 : 0.17
        )
      )

      RoundedRectangle(
        cornerRadius: max(12, size * 0.27),
        style: .continuous
      )
      .strokeBorder(
        accentColor.opacity(
          colorScheme == .light ? 0.28 : 0.38
        ),
        lineWidth: 1
      )

      if let symbol = avatar.systemImage {
        Image(systemName: symbol)
          .font(
            .system(
              size: size * 0.37,
              weight: .semibold
            )
          )
          .foregroundStyle(accentColor)
      } else {
        Text(initials)
          .font(
            .system(
              size: size * 0.30,
              weight: .bold,
              design: .rounded
            )
          )
          .foregroundStyle(accentColor)
      }
    }
    .frame(width: size, height: size)
    .accessibilityLabel(
      name.isEmpty
        ? "Profile avatar"
        : "\(name) profile avatar"
    )
  }
}

struct ProfileView: View {
  @ObservedObject var store: UserScheduleStore

  @Environment(\.colorScheme) private var colorScheme
  @State private var showClearProfileConfirmation = false

  private var accent: Color { store.profileAccentColor }
  private var grade: RooPACGrade? { store.profileCurrentGrade }
  private var graduationYears: [Int] { RooPACGrade.validGraduationYears() }

  private var trimmedName: String {
    store.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var heroName: String {
    trimmedName.isEmpty ? "Your profile" : store.profileDisplayName
  }

  private var configuredClassCount: Int {
    let levels: [Level] = [
      .level1,
      .level2,
      .level3,
      .level4,
      .level5,
      .level6,
      .level7,
    ]

    return levels.filter { level in
      let assignment = store.assignment(for: level)
      let title = assignment.title
        .trimmingCharacters(in: .whitespacesAndNewlines)

      return assignment.isFree
        || (!title.isEmpty && title != level.displayName)
    }
    .count
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: 20) {
        pageHeader
        hero

        LazyVGrid(
          columns: [
            GridItem(
              .adaptive(
                minimum: 350,
                maximum: 520
              ),
              spacing: 18,
              alignment: .top
            )
          ],
          alignment: .leading,
          spacing: 18
        ) {
          identityPanel
          classYearPanel
          avatarPanel
          connectedPanel
        }

        privacyFooter
      }
      .frame(maxWidth: 1040, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(.horizontal, 26)
      .padding(.vertical, 22)
    }
    .background {
      BackgroundView()
    }
    .navigationTitle("Profile")
    .alert(
      "Clear Profile?",
      isPresented: $showClearProfileConfirmation
    ) {
      Button("Cancel", role: .cancel) {}

      Button("Clear Profile", role: .destructive) {
        withAnimation(DesignTokens.Animation.snappy) {
          store.clearProfile()
        }
      }
    } message: {
      Text(
        "This clears your name, graduation year, avatar, and profile color. Your classes, PacTrack plan, favorites, and other RooMate data stay intact."
      )
    }
    .onAppear {
      store.refreshProfileDerivedData()
    }
  }

  // MARK: - Page shell

  private var pageHeader: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Profile")
          .font(.system(size: 27, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text("Choose how RooMate greets you and shows your profile.")
          .font(DesignTokens.Typography.subheadline)
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }

      Spacer()

      if store.hasProfile {
        Button {
          showClearProfileConfirmation = true
        } label: {
          HStack(spacing: 7) {
            Image(systemName: "arrow.counterclockwise")
              .font(.system(size: 11, weight: .semibold))

            Text("Clear Profile")
              .font(.system(size: 12.5, weight: .semibold))
          }
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .padding(.horizontal, 12)
          .frame(height: 32)
          .contentShape(
            RoundedRectangle(
              cornerRadius: 9,
              style: .continuous
            )
          )
          .background(
            DesignTokens.Colors.hover.opacity(0.42),
            in: RoundedRectangle(
              cornerRadius: 9,
              style: .continuous
            )
          )
          .overlay {
            RoundedRectangle(
              cornerRadius: 9,
              style: .continuous
            )
            .strokeBorder(
              DesignTokens.Colors.border,
              lineWidth: 1
            )
          }
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var hero: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .center, spacing: 16) {
        ProfileAvatarView(
          name: store.profileName,
          avatar: store.profileAvatar,
          accentColor: store.profileAccentColor,
          size: 76
        )

        VStack(alignment: .leading, spacing: 6) {
          Text(heroName)
            .font(.system(size: 23, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .lineLimit(1)

          Text(profileSubtitle)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)

          HStack(spacing: 7) {
            profileBadge(
              icon: "person.crop.circle",
              title: trimmedName.isEmpty
                ? "Name not set"
                : "Name set",
              tint: accent
            )

            profileBadge(
              icon: "graduationcap.fill",
              title: grade?.shortTitle ?? "Class year not set",
              tint: DesignTokens.Colors.schedule
            )
          }
        }

        Spacer(minLength: 10)

        VStack(alignment: .trailing, spacing: 4) {
          Text("LOCAL")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(DesignTokens.Colors.athletics)

          Text("Your profile stays on this Mac")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
      }

      Divider()
        .overlay(DesignTokens.Colors.border)

      HStack(spacing: 0) {
        heroStat(
          icon: "rectangle.grid.1x2",
          value: "\(configuredClassCount)/7",
          label: "Classes",
          tint: DesignTokens.Colors.schedule
        )

        statDivider

        heroStat(
          icon: "person.3.fill",
          value: "\(store.clubs.count)",
          label: "Clubs",
          tint: DesignTokens.Colors.dining
        )

        statDivider

        heroStat(
          icon: "chart.bar.xaxis",
          value: grade.map { "\($0.requirement)" } ?? "—",
          label: "RooPAC goal",
          tint: DesignTokens.Colors.pacTrack
        )
      }
    }
    .padding(18)
    .background(
      DesignTokens.Colors.surface,
      in: RoundedRectangle(
        cornerRadius: 18,
        style: .continuous
      )
    )
    .overlay {
      RoundedRectangle(
        cornerRadius: 18,
        style: .continuous
      )
      .strokeBorder(
        accent.opacity(
          colorScheme == .light ? 0.20 : 0.24
        ),
        lineWidth: 1
      )
    }
  }

  private var statDivider: some View {
    Rectangle()
      .fill(DesignTokens.Colors.border)
      .frame(width: 1, height: 32)
      .padding(.horizontal, 20)
  }

  // MARK: - Editing panels

  private var identityPanel: some View {
    profilePanel(
      title: "About You",
      subtitle: "Keep this lightweight. RooMate only needs what helps personalize the app.",
      icon: "person.fill",
      tint: accent
    ) {
      VStack(spacing: 0) {
        profileInputRow(
          title: "Name",
          subtitle: "Used in your greeting and profile.",
          icon: "textformat"
        ) {
          TextField("Your name", text: $store.profileName)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12.5))
            .frame(width: 190)
        }

        Divider()
          .overlay(DesignTokens.Colors.border)

        profileInputRow(
          title: "Today greeting",
          subtitle: trimmedName.isEmpty
            ? "Set your name first to personalize Today."
            : "Show greetings like “Good afternoon, \(store.profileFirstName ?? trimmedName)”.",
          icon: "sun.max.fill"
        ) {
          Toggle("", isOn: $store.profileGreetingEnabled)
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(accent)
            .disabled(trimmedName.isEmpty)
        }
      }
    }
  }

  private var classYearPanel: some View {
    profilePanel(
      title: "Class Year",
      subtitle: "Set this once, and RooMate updates your grade each school year.",
      icon: "graduationcap.fill",
      tint: DesignTokens.Colors.schedule
    ) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          ForEach(graduationYears, id: \.self) { year in
            classYearButton(year)
          }
        }

        HStack(alignment: .top, spacing: 9) {
          Image(
            systemName: store.profileGraduationYear == nil
              ? "info.circle"
              : "checkmark.circle.fill"
          )
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(
            store.profileGraduationYear == nil
              ? DesignTokens.Colors.secondaryText
              : DesignTokens.Colors.success
          )
          .padding(.top, 1)

          Text(gradeExplanation)
            .font(.system(size: 10.5))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          DesignTokens.Colors.hover.opacity(0.24),
          in: RoundedRectangle(
            cornerRadius: 9,
            style: .continuous
          )
        )
      }
    }
  }

  private var avatarPanel: some View {
    profilePanel(
      title: "Avatar & Color",
      subtitle: "A small visual identity used throughout RooMate.",
      icon: "face.smiling",
      tint: accent
    ) {
      VStack(alignment: .leading, spacing: 14) {
        LazyVGrid(
          columns: [
            GridItem(
              .adaptive(minimum: 46, maximum: 52),
              spacing: 8
            )
          ],
          alignment: .leading,
          spacing: 8
        ) {
          ForEach(ProfileAvatarChoice.allCases) { choice in
            avatarChoiceButton(choice)
          }
        }

        Divider()
          .overlay(DesignTokens.Colors.border)

        HStack(spacing: 10) {
          Text("COLOR")
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(DesignTokens.Colors.secondaryText)

          Spacer()

          ForEach(ProfileAccentChoice.allCases) { choice in
            accentChoiceButton(choice)
          }

          ColorPicker(
            "Custom profile color",
            selection: Binding(
              get: { store.profileAccentColor },
              set: { newColor in
                store.profileCustomAccent = CodableColor(newColor)
              }
            )
          )
          .labelsHidden()
          .help("Choose any profile color")
        }

        if store.profileCustomAccent != nil {
          HStack(spacing: 7) {
            Image(systemName: "paintpalette.fill")
              .foregroundStyle(accent)
            Text("Custom profile color selected")
              .font(.system(size: 10.5, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
            Spacer()
            Button("Use preset") {
              store.profileCustomAccent = nil
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(accent)
          }
        }
      }
    }
  }

  private var connectedPanel: some View {
    profilePanel(
      title: "Used Around RooMate",
      subtitle: "Your profile quietly keeps a few other parts of the app consistent.",
      icon: "arrow.triangle.branch",
      tint: DesignTokens.Colors.events
    ) {
      VStack(spacing: 0) {
        connectionRow(
          icon: "sun.max.fill",
          title: "Today",
          detail: "Uses your name and avatar to personalize Today.",
          tint: DesignTokens.Colors.today
        )

        Divider()
          .overlay(DesignTokens.Colors.border)

        connectionRow(
          icon: "chart.bar.xaxis",
          title: "PacTrack",
          detail: "Uses your current grade to choose the correct annual RooPAC requirement.",
          tint: DesignTokens.Colors.pacTrack
        )

        Divider()
          .overlay(DesignTokens.Colors.border)

        connectionRow(
          icon: "calendar.badge.clock",
          title: "Grade rollover",
          detail: "Your grade updates automatically as your graduation year moves through school.",
          tint: DesignTokens.Colors.schedule
        )
      }
    }
  }

  private var privacyFooter: some View {
    HStack(alignment: .center, spacing: 11) {
      Image(systemName: "lock.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(DesignTokens.Colors.athletics)
        .frame(width: 28, height: 28)
        .background(
          DesignTokens.Colors.athletics.opacity(0.09),
          in: RoundedRectangle(
            cornerRadius: 8,
            style: .continuous
          )
        )

      VStack(alignment: .leading, spacing: 2) {
        Text("No account needed")
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text(
          "Your RooMate profile is stored locally with the rest of your app preferences on this Mac."
        )
        .font(.system(size: 10.5))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
      }

      Spacer()
    }
    .padding(.horizontal, 14)
    .frame(minHeight: 54)
    .background(
      DesignTokens.Colors.surface.opacity(0.66),
      in: RoundedRectangle(
        cornerRadius: 14,
        style: .continuous
      )
    )
    .overlay {
      RoundedRectangle(
        cornerRadius: 14,
        style: .continuous
      )
      .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
    }
  }

  // MARK: - Components

  private func profilePanel<Content: View>(
    title: String,
    subtitle: String,
    icon: String,
    tint: Color,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center, spacing: 10) {
        Image(systemName: icon)
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(tint)
          .frame(width: 31, height: 31)
          .background(
            tint.opacity(0.09),
            in: RoundedRectangle(
              cornerRadius: 9,
              style: .continuous
            )
          )

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)

          Text(subtitle)
            .font(.system(size: 10.5))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(
      DesignTokens.Colors.surface,
      in: RoundedRectangle(
        cornerRadius: 15,
        style: .continuous
      )
    )
    .overlay {
      RoundedRectangle(
        cornerRadius: 15,
        style: .continuous
      )
      .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
    }
  }

  private func profileInputRow<Control: View>(
    title: String,
    subtitle: String,
    icon: String,
    @ViewBuilder control: () -> Control
  ) -> some View {
    HStack(spacing: 11) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(accent)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 12.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text(subtitle)
          .font(.system(size: 10.2))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .lineLimit(2)
      }

      Spacer(minLength: 12)
      control()
    }
    .padding(.vertical, 11)
  }

  private func classYearButton(_ year: Int) -> some View {
    let derivedGrade = RooPACGrade.current(
      forGraduationYear: year
    )
    let selected = store.profileGraduationYear == year

    return Button {
      withAnimation(DesignTokens.Animation.snappy) {
        store.profileGraduationYear = year
      }
    } label: {
      VStack(spacing: 4) {
        Text(String(year))
          .font(
            .system(
              size: 16,
              weight: .semibold,
              design: .rounded
            )
          )
          .foregroundStyle(
            selected
              ? DesignTokens.Colors.schedule
              : DesignTokens.Colors.primaryText
          )

        Text(derivedGrade?.shortTitle ?? "—")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(
            selected
              ? DesignTokens.Colors.schedule
              : DesignTokens.Colors.subtleText
          )
      }
      .frame(maxWidth: .infinity)
      .frame(height: 56)
      .contentShape(Rectangle())
      .background(
        selected
          ? DesignTokens.Colors.schedule.opacity(0.10)
          : DesignTokens.Colors.hover.opacity(0.22),
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
          selected
            ? DesignTokens.Colors.schedule.opacity(0.46)
            : DesignTokens.Colors.border,
          lineWidth: 1
        )
      }
    }
    .buttonStyle(.plain)
    .help("Class of \(year)")
  }

  private func avatarChoiceButton(
    _ choice: ProfileAvatarChoice
  ) -> some View {
    let selected = store.profileAvatar == choice

    return Button {
      withAnimation(DesignTokens.Animation.snappy) {
        store.profileAvatar = choice
      }
    } label: {
      ZStack {
        RoundedRectangle(
          cornerRadius: 10,
          style: .continuous
        )
        .fill(
          selected
            ? accent.opacity(0.12)
            : DesignTokens.Colors.hover.opacity(0.24)
        )

        if let symbol = choice.systemImage {
          Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(
              selected
                ? accent
                : DesignTokens.Colors.secondaryText
            )
        } else {
          Text(store.profileInitials)
            .font(
              .system(
                size: 12,
                weight: .bold,
                design: .rounded
              )
            )
            .foregroundStyle(
              selected
                ? accent
                : DesignTokens.Colors.secondaryText
            )
        }
      }
      .frame(width: 46, height: 42)
      .contentShape(Rectangle())
      .overlay {
        RoundedRectangle(
          cornerRadius: 10,
          style: .continuous
        )
        .strokeBorder(
          selected
            ? accent.opacity(0.48)
            : DesignTokens.Colors.border,
          lineWidth: 1
        )
      }
    }
    .buttonStyle(.plain)
    .help(choice.title)
  }

  private func accentChoiceButton(
    _ choice: ProfileAccentChoice
  ) -> some View {
    let selected = store.profileCustomAccent == nil && store.profileAccent == choice

    return Button {
      withAnimation(DesignTokens.Animation.snappy) {
        store.profileAccent = choice
        store.profileCustomAccent = nil
      }
    } label: {
      ZStack {
        Circle()
          .fill(choice.color)
          .frame(width: 24, height: 24)

        if selected {
          Image(systemName: "checkmark")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(.white)
        }
      }
      .frame(width: 30, height: 30)
      .contentShape(Rectangle())
      .overlay {
        Circle()
          .strokeBorder(
            selected
              ? choice.color.opacity(0.72)
              : Color.clear,
            lineWidth: 2
          )
          .padding(1)
      }
    }
    .buttonStyle(.plain)
    .help(choice.title)
  }

  private func connectionRow(
    icon: String,
    title: String,
    detail: String,
    tint: Color
  ) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 22)
        .padding(.top, 1)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text(detail)
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
    .padding(.vertical, 10)
  }

  private func profileBadge(
    icon: String,
    title: String,
    tint: Color
  ) -> some View {
    HStack(spacing: 5) {
      Image(systemName: icon)
        .font(.system(size: 8.5, weight: .semibold))

      Text(title)
        .font(.system(size: 9.5, weight: .semibold))
        .lineLimit(1)
    }
    .foregroundStyle(tint)
    .padding(.horizontal, 8)
    .frame(height: 24)
    .background(
      tint.opacity(0.08),
      in: Capsule()
    )
    .overlay {
      Capsule()
        .strokeBorder(tint.opacity(0.17), lineWidth: 1)
    }
  }

  private func heroStat(
    icon: String,
    value: String,
    label: String,
    tint: Color
  ) -> some View {
    HStack(spacing: 9) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 25, height: 25)
        .background(
          tint.opacity(0.08),
          in: RoundedRectangle(
            cornerRadius: 7,
            style: .continuous
          )
        )

      VStack(alignment: .leading, spacing: 1) {
        Text(value)
          .font(
            .system(
              size: 14,
              weight: .semibold,
              design: .rounded
            )
          )
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text(label)
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Copy

  private var gradeExplanation: String {
    guard let year = store.profileGraduationYear,
      let grade
    else {
      return
        "Choose your graduation year once. Until then, PacTrack keeps using its existing saved grade."
    }

    return
      "Class of \(year) makes you \(grade.title) right now. PacTrack uses the \(grade.requirement)-RooPAC annual requirement for that grade."
  }

  private var profileSubtitle: String {
    switch (grade, store.profileGraduationYear) {
    case (.some(let grade), .some(let year)):
      return "\(grade.title)  •  Class of \(year)"
    case (.none, .some(let year)):
      return "Class of \(year)"
    default:
      return "Add your name and class year to finish setup"
    }
  }
}

#Preview {
  ProfileView(store: UserScheduleStore())
    .frame(width: 1150, height: 820)
    .background(DesignTokens.Colors.background)
}
