import Foundation
import SwiftUI

private func bundledURL(_ rawValue: String) -> URL {
  guard let url = URL(string: rawValue) else {
    preconditionFailure("Invalid bundled RooMate URL: \(rawValue)")
  }
  return url
}

struct SchoolLinksView: View {
  @Environment(\.openURL) private var openURL

  // These four destinations are intentionally kept exactly as RooMate already had them.
  private let canvasURL = bundledURL(
    "https://accounts.google.com/o/saml2/initsso?idpid=C03lnpy2u&spid=964156697375&forceauthn=false"
  )
  private let blackbaudURL = bundledURL("https://abingtonfriends.myschoolapp.com")
  private let accessItURL = bundledURL(
    "https://accounts.google.com/o/saml2/initsso?idpid=C03lnpy2u&spid=265886547823&forceauthn=false"
  )
  private let noodleToolsURL = bundledURL(
    "https://apis.google.com/additnow/l?applicationid=471879773528&__ls=ogb&__lu=https%3A%2F%2Fmy.noodletools.com%2Flogon%2Fgapps%2Flanding%2Fabingtonfriends.net"
  )

  @AppStorage("RooMateCustomSchoolLinksJSON") private var customLinksJSON = "[]"
  @AppStorage("RooMateFavoriteSchoolLinkIDs") private var favoriteIDsRaw = ""

  @State private var showLinkEditor = false
  @State private var editingLink: CustomSchoolLink?
  @State private var showManageLinks = false

  private var essentials: [SchoolLinkItem] {
    [
      SchoolLinkItem(
        id: "builtin.canvas",
        title: "Canvas",
        subtitle: "Classes and assignments",
        destination: canvasURL,
        icon: .asset("canvas"),
        tint: .orange,
        isBuiltIn: true
      ),
      SchoolLinkItem(
        id: "builtin.blackbaud",
        title: "Blackbaud",
        subtitle: "School portal",
        destination: blackbaudURL,
        icon: .asset("blackbaud"),
        tint: .blue,
        isBuiltIn: true
      ),
      SchoolLinkItem(
        id: "builtin.accessit",
        title: "Access-It",
        subtitle: "Library catalog",
        destination: accessItURL,
        icon: .asset("accessit"),
        tint: .green,
        isBuiltIn: true
      ),
      SchoolLinkItem(
        id: "builtin.noodletools",
        title: "NoodleTools",
        subtitle: "Research and citations",
        destination: noodleToolsURL,
        icon: .asset("noodletools"),
        tint: .purple,
        isBuiltIn: true
      ),
    ]
  }

  // Keep this list intentionally focused.
  // Removed: Library Services, Google Classroom, Student Support, College Guidance.
  private var schoolTools: [SchoolLinkItem] {
    [
      SchoolLinkItem(
        id: "builtin.afswebsite",
        title: "School Website",
        subtitle: "School website",
        destination: bundledURL("https://www.abingtonfriends.net/"),
        icon: .system("globe.americas.fill"),
        tint: DesignTokens.Colors.primary,
        isBuiltIn: true
      ),
      SchoolLinkItem(
        id: "builtin.schoolcalendar",
        title: "School Calendar",
        subtitle: "Official school calendar",
        destination: bundledURL("https://www.abingtonfriends.net/calendar"),
        icon: .system("calendar"),
        tint: DesignTokens.Colors.events,
        isBuiltIn: true
      ),
      SchoolLinkItem(
        id: "builtin.gmail",
        title: "Gmail",
        subtitle: "School email",
        destination: bundledURL("https://mail.google.com/mail/u/0/"),
        icon: .system("envelope.fill"),
        tint: .red,
        isBuiltIn: true
      ),
      SchoolLinkItem(
        id: "builtin.drive",
        title: "Google Drive",
        subtitle: "Files and shared docs",
        destination: bundledURL("https://drive.google.com/drive/u/0/my-drive"),
        icon: .system("folder.fill"),
        tint: .blue,
        isBuiltIn: true
      ),
      SchoolLinkItem(
        id: "builtin.googlecalendar",
        title: "Google Calendar",
        subtitle: "Your Google calendar",
        destination: bundledURL("https://calendar.google.com/calendar/u/0/r"),
        icon: .system("calendar.badge.clock"),
        tint: .blue,
        isBuiltIn: true
      ),
      SchoolLinkItem(
        id: "builtin.roopacexemption",
        title: "RooPAC Exemption",
        subtitle: "Official exemption request",
        destination: bundledURL(
          "https://docs.google.com/forms/d/e/1FAIpQLSddo4yesbk-KMYhG8jzS2NF7KmBqMxaxSE81ae7ICx-YF-zDg/viewform?usp=sharing&ouid=101974263945767886964"
        ),
        icon: .system("figure.run.circle.fill"),
        tint: DesignTokens.Colors.pacTrack,
        isBuiltIn: true
      ),
    ]
  }

  private var studyTools: [SchoolLinkItem] {
    [
      SchoolLinkItem(
        id: "builtin.khan",
        title: "Khan Academy",
        subtitle: "Learning resources",
        destination: bundledURL("https://www.khanacademy.org/"),
        icon: .system("book.pages.fill"),
        tint: DesignTokens.Colors.athletics,
        isBuiltIn: true
      ),
      SchoolLinkItem(
        id: "builtin.quizlet",
        title: "Quizlet",
        subtitle: "Study sets and practice",
        destination: bundledURL("https://quizlet.com/"),
        icon: .system("rectangle.stack.fill"),
        tint: DesignTokens.Colors.info,
        isBuiltIn: true
      ),
    ]
  }

  private var customLinks: [CustomSchoolLink] {
    get {
      guard let data = customLinksJSON.data(using: .utf8),
        let decoded = try? JSONDecoder().decode([CustomSchoolLink].self, from: data)
      else { return [] }
      return decoded
    }
    nonmutating set {
      guard let data = try? JSONEncoder().encode(newValue),
        let string = String(data: data, encoding: .utf8)
      else { return }
      customLinksJSON = string
    }
  }

  private var customItems: [SchoolLinkItem] {
    customLinks.compactMap { link in
      guard let url = URL(string: link.urlString) else { return nil }
      return SchoolLinkItem(
        id: link.id.uuidString,
        title: link.title,
        subtitle: link.hostDisplay,
        destination: url,
        icon: .system(link.iconSystemName),
        tint: DesignTokens.Colors.links,
        isBuiltIn: false
      )
    }
  }

  private var favoriteIDs: Set<String> {
    Set(
      favoriteIDsRaw
        .split(separator: "\n")
        .map(String.init)
        .filter { !$0.isEmpty }
    )
  }

  private var allItems: [SchoolLinkItem] {
    essentials + schoolTools + studyTools + customItems
  }

  private var favoriteItems: [SchoolLinkItem] {
    allItems.filter { favoriteIDs.contains($0.id) }
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: 24) {
        header

        if !favoriteItems.isEmpty {
          sectionHeader(
            title: "Favorites",
            subtitle: "Your starred links, kept right at the top."
          )

          LazyVGrid(
            columns: [
              GridItem(.flexible(), spacing: 12),
              GridItem(.flexible(), spacing: 12),
            ],
            alignment: .leading,
            spacing: 12
          ) {
            ForEach(favoriteItems) { link in
              LinkManagementCard(
                link: link,
                isFavorite: true,
                compact: true,
                onOpen: { openURL(link.destination) },
                onToggleFavorite: { toggleFavorite(link.id) },
                onEdit: link.isBuiltIn ? nil : { beginEditingCustomLink(id: link.id) },
                onDelete: link.isBuiltIn ? nil : { deleteCustomLink(id: link.id) }
              )
            }
          }
        }

        sectionHeader(
          title: "Essentials",
          subtitle: "The four school tools that were already in RooMate."
        )

        LazyVGrid(
          columns: [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14),
          ],
          spacing: 14
        ) {
          ForEach(essentials) { link in
            LinkManagementCard(
              link: link,
              isFavorite: favoriteIDs.contains(link.id),
              compact: false,
              onOpen: { openURL(link.destination) },
              onToggleFavorite: { toggleFavorite(link.id) },
              onEdit: nil,
              onDelete: nil
            )
          }
        }

        sectionHeader(
          title: "School & Google",
          subtitle: "Useful school and account destinations."
        )

        compactGrid(schoolTools)

        sectionHeader(
          title: "Study",
          subtitle: "A couple of useful study tools."
        )

        compactGrid(studyTools)

        HStack(alignment: .firstTextBaseline) {
          sectionHeader(
            title: "My Links",
            subtitle: customLinks.isEmpty
              ? "Add your own links when you need something RooMate doesn't include."
              : "\(customLinks.count) custom \(customLinks.count == 1 ? "link" : "links")."
          )

          Spacer()

          if !customLinks.isEmpty {
            Button {
              showManageLinks = true
            } label: {
              Label("Edit", systemImage: "slider.horizontal.3")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 11)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
              DesignTokens.Colors.hover.opacity(0.45),
              in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
              RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
            }
          }
        }

        if customItems.isEmpty {
          emptyCustomLinksCard
        } else {
          LazyVGrid(
            columns: [
              GridItem(.flexible(), spacing: 12),
              GridItem(.flexible(), spacing: 12),
            ],
            alignment: .leading,
            spacing: 12
          ) {
            ForEach(customItems) { link in
              LinkManagementCard(
                link: link,
                isFavorite: favoriteIDs.contains(link.id),
                compact: true,
                onOpen: { openURL(link.destination) },
                onToggleFavorite: { toggleFavorite(link.id) },
                onEdit: { beginEditingCustomLink(id: link.id) },
                onDelete: { deleteCustomLink(id: link.id) }
              )
            }
          }
        }

        footer
      }
      .padding(.vertical, 4)
      .frame(maxWidth: 980, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .navigationTitle("Links")
    .sheet(isPresented: $showLinkEditor) {
      CustomSchoolLinkEditor(
        existing: editingLink,
        onSave: saveCustomLink
      )
    }
    .sheet(isPresented: $showManageLinks) {
      ManageSchoolLinksSheet(
        initialLinks: customLinks,
        onSave: { customLinks = $0 },
        onEdit: { link in
          showManageLinks = false
          DispatchQueue.main.async {
            editingLink = link
            showLinkEditor = true
          }
        },
        onDelete: { link in
          deleteCustomLink(id: link.id.uuidString)
        }
      )
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .fill(DesignTokens.Colors.links.opacity(0.14))

        Image(systemName: "link")
          .font(.system(size: 21, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.links)
      }
      .frame(width: 48, height: 48)

      VStack(alignment: .leading, spacing: 3) {
        Text("Links")
          .font(DesignTokens.Typography.pageTitle)
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text("Quick access to the school sites and tools you actually use.")
          .font(DesignTokens.Typography.subheadline)
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }

      Spacer()

      HStack(spacing: 9) {
        if !customLinks.isEmpty {
          Button {
            showManageLinks = true
          } label: {
            Label("Edit Links", systemImage: "pencil")
              .font(.system(size: 11.5, weight: .semibold))
              .padding(.horizontal, 12)
              .frame(height: 36)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .background(
            DesignTokens.Colors.hover.opacity(0.45),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
          }
        }

        Button {
          editingLink = nil
          showLinkEditor = true
        } label: {
          Label("Add Link", systemImage: "plus")
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 13)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DesignTokens.Colors.primaryText)
        .background(
          DesignTokens.Colors.links.opacity(0.18),
          in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(DesignTokens.Colors.links.opacity(0.42), lineWidth: 1)
        }
      }
    }
  }

  @ViewBuilder
  private func compactGrid(_ links: [SchoolLinkItem]) -> some View {
    LazyVGrid(
      columns: [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
      ],
      alignment: .leading,
      spacing: 12
    ) {
      ForEach(links) { link in
        LinkManagementCard(
          link: link,
          isFavorite: favoriteIDs.contains(link.id),
          compact: true,
          onOpen: { openURL(link.destination) },
          onToggleFavorite: { toggleFavorite(link.id) },
          onEdit: nil,
          onDelete: nil
        )
      }
    }
  }

  private var emptyCustomLinksCard: some View {
    Button {
      editingLink = nil
      showLinkEditor = true
    } label: {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(DesignTokens.Colors.links.opacity(0.10))

          Image(systemName: "plus")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.links)
        }
        .frame(width: 40, height: 40)

        VStack(alignment: .leading, spacing: 2) {
          Text("Add your first link")
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)

          Text("Give it a name, URL, and icon.")
            .font(.system(size: 10.5))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(DesignTokens.Colors.subtleText)
      }
      .padding(12)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .background(
        DesignTokens.Colors.surface,
        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  private var footer: some View {
    HStack(spacing: 16) {
      Label(
        "\(allItems.count) total links",
        systemImage: "link"
      )

      Label(
        "\(favoriteItems.count) \(favoriteItems.count == 1 ? "favorite" : "favorites")",
        systemImage: "star.fill"
      )

      if !customLinks.isEmpty {
        Label(
          "\(customLinks.count) custom",
          systemImage: "person.crop.circle.badge.plus"
        )
      }

      Spacer()

      Label("Opens in your default browser", systemImage: "safari")
    }
    .font(.system(size: 10.5, weight: .medium))
    .foregroundStyle(DesignTokens.Colors.subtleText)
    .padding(.top, 4)
    .padding(.bottom, 8)
  }

  private func sectionHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(DesignTokens.Colors.primaryText)

      Text(subtitle)
        .font(.system(size: 11.5))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
    }
  }

  private func toggleFavorite(_ id: String) {
    var ids = favoriteIDs
    if ids.contains(id) {
      ids.remove(id)
    } else {
      ids.insert(id)
    }
    favoriteIDsRaw = ids.sorted().joined(separator: "\n")
  }

  private func beginEditingCustomLink(id: String) {
    guard let uuid = UUID(uuidString: id),
      let link = customLinks.first(where: { $0.id == uuid })
    else { return }

    editingLink = link
    showLinkEditor = true
  }

  private func saveCustomLink(_ link: CustomSchoolLink) {
    var links = customLinks

    if let index = links.firstIndex(where: { $0.id == link.id }) {
      links[index] = link
    } else {
      links.append(link)
    }

    customLinks = links
    editingLink = nil
  }

  private func deleteCustomLink(id: String) {
    guard let uuid = UUID(uuidString: id) else { return }

    var links = customLinks
    links.removeAll { $0.id == uuid }
    customLinks = links

    var ids = favoriteIDs
    ids.remove(id)
    favoriteIDsRaw = ids.sorted().joined(separator: "\n")
  }
}

private struct SchoolLinkItem: Identifiable {
  enum Icon {
    case asset(String)
    case system(String)
  }

  let id: String
  let title: String
  let subtitle: String
  let destination: URL
  let icon: Icon
  let tint: Color
  let isBuiltIn: Bool
}

private struct LinkManagementCard: View {
  let link: SchoolLinkItem
  let isFavorite: Bool
  let compact: Bool
  let onOpen: () -> Void
  let onToggleFavorite: () -> Void
  let onEdit: (() -> Void)?
  let onDelete: (() -> Void)?

  @State private var isHovering = false

  var body: some View {
    HStack(spacing: compact ? 11 : 14) {
      Button(action: onOpen) {
        HStack(spacing: compact ? 11 : 14) {
          iconTile

          VStack(alignment: .leading, spacing: 3) {
            Text(link.title)
              .font(.system(size: compact ? 12.5 : 14.5, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)
              .lineLimit(compact ? 2 : 1)
              .fixedSize(horizontal: false, vertical: true)

            Text(link.subtitle)
              .font(.system(size: compact ? 10.5 : 11.5))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .lineLimit(compact ? 2 : 1)
              .fixedSize(horizontal: false, vertical: true)
          }
          .layoutPriority(1)

          Spacer(minLength: 6)

          Image(systemName: "arrow.up.right")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(isHovering ? link.tint : DesignTokens.Colors.subtleText)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Button(action: onToggleFavorite) {
        Image(systemName: isFavorite ? "star.fill" : "star")
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(isFavorite ? .yellow : DesignTokens.Colors.subtleText)
          .frame(width: 30, height: 30)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")

      Menu {
        Button("Open", systemImage: "arrow.up.right", action: onOpen)

        Button(
          isFavorite ? "Remove from Favorites" : "Add to Favorites",
          systemImage: isFavorite ? "star.slash" : "star",
          action: onToggleFavorite
        )

        if let onEdit {
          Divider()
          Button("Edit Link", systemImage: "pencil", action: onEdit)
        }

        if let onDelete {
          Button("Delete Link", systemImage: "trash", role: .destructive, action: onDelete)
        }

        if link.isBuiltIn {
          Divider()
          Text("Built-in RooMate link")
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(DesignTokens.Colors.subtleText)
          .frame(width: 30, height: 30)
          .contentShape(Rectangle())
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
    }
    .padding(compact ? 11 : 14)
    .frame(maxWidth: .infinity, minHeight: compact ? 70 : 82)
    .background(
      isHovering ? DesignTokens.Colors.surfaceElevated : DesignTokens.Colors.surface,
      in: RoundedRectangle(cornerRadius: compact ? 13 : 15, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: compact ? 13 : 15, style: .continuous)
        .strokeBorder(
          isHovering ? link.tint.opacity(0.35) : DesignTokens.Colors.border,
          lineWidth: 1
        )
    }
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.14)) {
        isHovering = hovering
      }
    }
  }

  private var iconTile: some View {
    ZStack {
      switch link.icon {
      case .asset(let name):
        RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
          .fill(Color.white.opacity(0.94))
          .overlay {
            RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
              .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
          }

        Image(name)
          .resizable()
          .scaledToFit()
          .frame(
            width: compact ? 27 : 35,
            height: compact ? 27 : 35
          )

      case .system(let name):
        RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
          .fill(link.tint.opacity(0.11))

        Image(systemName: name)
          .font(.system(size: compact ? 16 : 22, weight: .semibold))
          .foregroundStyle(link.tint)
      }
    }
    .frame(width: compact ? 40 : 50, height: compact ? 40 : 50)
  }
}

private struct CustomSchoolLink: Codable, Identifiable, Hashable {
  var id: UUID
  var title: String
  var urlString: String
  var iconSystemName: String

  init(
    id: UUID = UUID(),
    title: String,
    urlString: String,
    iconSystemName: String = "link"
  ) {
    self.id = id
    self.title = title
    self.urlString = urlString
    self.iconSystemName = iconSystemName
  }

  var hostDisplay: String {
    guard let url = URL(string: urlString),
      let host = url.host
    else { return "Custom link" }

    return host.replacingOccurrences(of: "www.", with: "")
  }
}

private struct CustomSchoolLinkEditor: View {
  @Environment(\.dismiss) private var dismiss

  let existing: CustomSchoolLink?
  let onSave: (CustomSchoolLink) -> Void

  @State private var title: String
  @State private var urlString: String
  @State private var selectedIcon: String

  private let iconOptions: [(String, String)] = [
    ("link", "Link"),
    ("globe", "Website"),
    ("book.closed.fill", "School"),
    ("folder.fill", "Files"),
    ("envelope.fill", "Email"),
    ("calendar", "Calendar"),
    ("graduationcap.fill", "Study"),
    ("person.2.fill", "People"),
    ("doc.text.fill", "Document"),
    ("star.fill", "Favorite"),
  ]

  init(
    existing: CustomSchoolLink?,
    onSave: @escaping (CustomSchoolLink) -> Void
  ) {
    self.existing = existing
    self.onSave = onSave
    _title = State(initialValue: existing?.title ?? "")
    _urlString = State(initialValue: existing?.urlString ?? "")
    _selectedIcon = State(initialValue: existing?.iconSystemName ?? "link")
  }

  private var normalizedURLString: String {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "" }
    if trimmed.contains("://") { return trimmed }
    return "https://\(trimmed)"
  }

  private var isValid: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && URL(string: normalizedURLString)?.host != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(existing == nil ? "Add Link" : "Edit Link")
            .font(.system(size: 19, weight: .semibold))

          Text(
            existing == nil
              ? "Add a website you want quick access to."
              : "Update this custom link."
          )
          .font(.system(size: 11.5))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer()

        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("NAME")
          .font(.system(size: 9.5, weight: .bold))
          .tracking(0.7)
          .foregroundStyle(DesignTokens.Colors.secondaryText)

        TextField("Example: School Newspaper", text: $title)
          .textFieldStyle(.roundedBorder)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("URL")
          .font(.system(size: 9.5, weight: .bold))
          .tracking(0.7)
          .foregroundStyle(DesignTokens.Colors.secondaryText)

        TextField("https://example.com", text: $urlString)
          .textFieldStyle(.roundedBorder)
      }

      VStack(alignment: .leading, spacing: 9) {
        Text("ICON")
          .font(.system(size: 9.5, weight: .bold))
          .tracking(0.7)
          .foregroundStyle(DesignTokens.Colors.secondaryText)

        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 66), spacing: 8)],
          spacing: 8
        ) {
          ForEach(iconOptions, id: \.0) { option in
            let selected = selectedIcon == option.0

            Button {
              selectedIcon = option.0
            } label: {
              VStack(spacing: 6) {
                Image(systemName: option.0)
                  .font(.system(size: 17, weight: .semibold))

                Text(option.1)
                  .font(.system(size: 9))
                  .lineLimit(1)
              }
              .foregroundStyle(
                selected
                  ? DesignTokens.Colors.links
                  : DesignTokens.Colors.secondaryText
              )
              .frame(maxWidth: .infinity, minHeight: 54)
              .contentShape(Rectangle())
              .background(
                selected
                  ? DesignTokens.Colors.links.opacity(0.12)
                  : DesignTokens.Colors.hover.opacity(0.25),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
              )
              .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .strokeBorder(
                    selected
                      ? DesignTokens.Colors.links.opacity(0.45)
                      : DesignTokens.Colors.border,
                    lineWidth: 1
                  )
              }
            }
            .buttonStyle(.plain)
          }
        }
      }

      Divider()

      HStack {
        Text(
          "Built-in RooMate links stay locked so their destinations can't be accidentally changed."
        )
        .font(.system(size: 10))
        .foregroundStyle(DesignTokens.Colors.subtleText)

        Spacer()

        Button("Cancel") {
          dismiss()
        }

        Button(existing == nil ? "Add Link" : "Save Changes") {
          let link = CustomSchoolLink(
            id: existing?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            urlString: normalizedURLString,
            iconSystemName: selectedIcon
          )
          onSave(link)
          dismiss()
        }
        .disabled(!isValid)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 500)
  }
}

private struct ManageSchoolLinksSheet: View {
  @Environment(\.dismiss) private var dismiss

  let onSave: ([CustomSchoolLink]) -> Void
  let onEdit: (CustomSchoolLink) -> Void
  let onDelete: (CustomSchoolLink) -> Void

  @State private var links: [CustomSchoolLink]

  init(
    initialLinks: [CustomSchoolLink],
    onSave: @escaping ([CustomSchoolLink]) -> Void,
    onEdit: @escaping (CustomSchoolLink) -> Void,
    onDelete: @escaping (CustomSchoolLink) -> Void
  ) {
    self.onSave = onSave
    self.onEdit = onEdit
    self.onDelete = onDelete
    _links = State(initialValue: initialLinks)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Edit My Links")
            .font(.system(size: 19, weight: .semibold))

          Text("Reorder, edit, or remove the links you've added.")
            .font(.system(size: 11.5))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer()

        Button("Done") {
          onSave(links)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }

      if links.isEmpty {
        ContentUnavailableView(
          "No Custom Links",
          systemImage: "link.badge.plus",
          description: Text("Add a custom link from the Links page.")
        )
        .frame(height: 240)
      } else {
        VStack(spacing: 8) {
          ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
            HStack(spacing: 11) {
              Image(systemName: link.iconSystemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.links)
                .frame(width: 34, height: 34)
                .background(
                  DesignTokens.Colors.links.opacity(0.10),
                  in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

              VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                  .font(.system(size: 12.5, weight: .semibold))

                Text(link.hostDisplay)
                  .font(.system(size: 10.5))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
              }

              Spacer()

              HStack(spacing: 4) {
                Button {
                  moveLink(at: index, direction: -1)
                } label: {
                  Image(systemName: "arrow.up")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                .help("Move up")

                Button {
                  moveLink(at: index, direction: 1)
                } label: {
                  Image(systemName: "arrow.down")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(index == links.count - 1)
                .help("Move down")

                Button {
                  onSave(links)
                  onEdit(link)
                  dismiss()
                } label: {
                  Image(systemName: "pencil")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit")

                Button(role: .destructive) {
                  links.removeAll { $0.id == link.id }
                  onDelete(link)
                } label: {
                  Image(systemName: "trash")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete")
              }
              .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
            .padding(10)
            .background(
              DesignTokens.Colors.surface,
              in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
              RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
            }
          }
        }
      }

      Text(
        "The four original school links and RooMate's built-in links are protected from editing."
      )
      .font(.system(size: 10))
      .foregroundStyle(DesignTokens.Colors.subtleText)
    }
    .padding(20)
    .frame(width: 570, height: 520)
  }

  private func moveLink(at index: Int, direction: Int) {
    let newIndex = index + direction
    guard links.indices.contains(index),
      links.indices.contains(newIndex)
    else { return }

    let item = links.remove(at: index)
    links.insert(item, at: newIndex)
  }
}

#Preview {
  SchoolLinksView()
    .padding(24)
    .frame(width: 1050, height: 820)
    .background(DesignTokens.Colors.background)
}
