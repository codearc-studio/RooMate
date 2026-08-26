#if os(macOS)
  import SwiftUI
  import AppKit
  import QuartzCore

  extension Notification.Name {
    fileprivate static let rooMateFloatingTimerResize =
      Notification.Name("RooMateFloatingTimerResize")

    fileprivate static let rooMateFloatingTimerRecoverInteraction =
      Notification.Name("RooMateFloatingTimerRecoverInteraction")
  }
  import Combine
  import UserNotifications

  private struct MenuBarBlockInfo {
    let title: String
    let subtitle: String
    let color: Color
    let start: Date
    let end: Date
    let isPrimaryTimelineBlock: Bool
  }

  @MainActor
  private func menuBarBlocks(store: UserScheduleStore, reference: Date) -> [MenuBarBlockInfo] {
    let calendar = Calendar.current
    guard let weekday = store.scheduleWeekday(for: reference) else { return [] }
    let startOfDay = calendar.startOfDay(for: reference)

    var blocks = store.bellBlocks(for: reference).compactMap { block -> MenuBarBlockInfo? in
      guard block.isPrimaryTimelineBlock else { return nil }
      var startComponents = calendar.dateComponents([.year, .month, .day], from: startOfDay)
      startComponents.hour = block.start.hour
      startComponents.minute = block.start.minute
      startComponents.second = 0

      var endComponents = calendar.dateComponents([.year, .month, .day], from: startOfDay)
      endComponents.hour = block.end.hour
      endComponents.minute = block.end.minute
      endComponents.second = 0

      guard let start = calendar.date(from: startComponents),
        let end = calendar.date(from: endComponents)
      else { return nil }

      let presentation = store.schedulePresentation(for: block, on: weekday)
      return MenuBarBlockInfo(
        title: presentation.title,
        subtitle: presentation.subtitle,
        color: presentation.color,
        start: start,
        end: end,
        isPrimaryTimelineBlock: true
      )
    }

    // Additional My Clubs meetings are timeline extras. They belong in the
    // menu bar/floating timer even when they happen after school. If one
    // overlaps a normal class, the normal class remains the current block.
    let calendarWeekday = calendar.component(.weekday, from: reference)
    for club in store.clubs {
      let clubName = club.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !clubName.isEmpty else { continue }

      for meeting in club.otherMeetings where meeting.weekday == calendarWeekday {
        let startTime = calendar.dateComponents([.hour, .minute], from: meeting.startTime)
        let endTime = calendar.dateComponents([.hour, .minute], from: meeting.endTime)

        guard let startHour = startTime.hour,
          let startMinute = startTime.minute,
          let endHour = endTime.hour,
          let endMinute = endTime.minute,
          let start = calendar.date(
            bySettingHour: startHour, minute: startMinute, second: 0, of: startOfDay),
          let end = calendar.date(
            bySettingHour: endHour, minute: endMinute, second: 0, of: startOfDay),
          end > start
        else {
          continue
        }

        let room = club.room.trimmingCharacters(in: .whitespacesAndNewlines)
        blocks.append(
          MenuBarBlockInfo(
            title: clubName,
            subtitle: room.isEmpty ? "Club meeting" : "Club meeting • \(room)",
            color: club.displayColor,
            start: start,
            end: end,
            isPrimaryTimelineBlock: false
          )
        )
      }
    }

    return blocks.sorted {
      if $0.start != $1.start { return $0.start < $1.start }
      if $0.isPrimaryTimelineBlock != $1.isPrimaryTimelineBlock {
        return $0.isPrimaryTimelineBlock
      }
      return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }

  private func currentMenuBarBlock(
    in blocks: [MenuBarBlockInfo],
    at reference: Date
  ) -> MenuBarBlockInfo? {
    blocks.first {
      $0.isPrimaryTimelineBlock && reference >= $0.start && reference < $0.end
    }
      ?? blocks.first {
        reference >= $0.start && reference < $0.end
      }
  }

  @MainActor
  final class RooMateMenuBarAppDelegate: NSObject, NSApplicationDelegate {
    private let statusController = RooMateStatusItemController()
    private let floatingTimerController = RooMateFloatingTimerController()
    private let notificationDelegate = RooMateNotificationDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
      UNUserNotificationCenter.current().delegate = notificationDelegate
      statusController.start()
      floatingTimerController.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
      _ sender: NSApplication
    ) -> Bool {
      // RooMate is designed to keep its menu bar companion and floating
      // timer alive after the main window is closed. ⌘Q still quits fully.
      false
    }

    func applicationShouldHandleReopen(
      _ sender: NSApplication,
      hasVisibleWindows flag: Bool
    ) -> Bool {
      if !flag,
        let mainWindow = sender.windows.first(where: {
          $0.level == .normal
            && $0.canBecomeKey
            && $0.styleMask.contains(.titled)
        })
      {
        mainWindow.makeKeyAndOrderFront(nil)
      }
      return true
    }
  }

  private final class RooMateNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
      _ center: UNUserNotificationCenter,
      willPresent notification: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
      completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
      _ center: UNUserNotificationCenter,
      didReceive response: UNNotificationResponse,
      withCompletionHandler completionHandler: @escaping () -> Void
    ) {
      let isAnnouncement =
        response.notification.request.identifier.hasPrefix("roomate.announcements.")
        || response.notification.request.content.userInfo["RooMateAnnouncementID"] != nil

      guard isAnnouncement else {
        completionHandler()
        return
      }

      UserDefaults.standard.set(true, forKey: "RooMateOpenAnnouncementsOnLaunch")
      completionHandler()

      Task { @MainActor in
        NSApp.activate(ignoringOtherApps: true)

        // Give SwiftUI's main scene a moment to finish restoring when the app
        // was launched from a notification click, then open the announcement center.
        try? await Task.sleep(nanoseconds: 180_000_000)
        NotificationCenter.default.post(name: .rooMateShowAnnouncements, object: nil)
      }
    }
  }

  @MainActor
  private final class RooMateStatusItemController: NSObject {
    private enum DefaultsKey {
      static let enabled = "RooMateMenuBarEnabled"
      static let iconOnly = "RooMateMenuBarIconOnly"
    }

    private let store = UserScheduleStore.shared
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var timer: Timer?

    private var menuBarEnabled: Bool {
      let defaults = UserDefaults.standard
      // Existing installs predate this preference, so absence means enabled.
      guard defaults.object(forKey: DefaultsKey.enabled) != nil else {
        return true
      }
      return defaults.bool(forKey: DefaultsKey.enabled)
    }

    func start() {
      guard timer == nil else { return }

      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleRooMateReset(_:)),
        name: .rooMateDidReset,
        object: nil
      )

      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleScheduleOrAppearanceChange(_:)),
        name: .rooMateScheduleDidChange,
        object: nil
      )

      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleScheduleOrAppearanceChange(_:)),
        name: .rooMateAppearanceDidChange,
        object: nil
      )

      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleMenuBarPreferenceChange(_:)),
        name: UserDefaults.didChangeNotification,
        object: UserDefaults.standard
      )

      popover.behavior = .transient
      popover.animates = true
      popover.contentSize = NSSize(width: 352, height: 548)
      popover.contentViewController = NSHostingController(
        rootView: RooMateMenuBarView()
      )

      syncStatusItemWithPreferences()

      let timer = Timer(
        timeInterval: 30,
        target: self,
        selector: #selector(statusTimerFired(_:)),
        userInfo: nil,
        repeats: true
      )
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    }

    @objc
    private func statusTimerFired(_ timer: Timer) {
      updateStatusItem()
    }

    @objc
    private func handleRooMateReset(_ notification: Notification) {
      syncStatusItemWithPreferences()
    }

    @objc
    private func handleScheduleOrAppearanceChange(_ notification: Notification) {
      syncStatusItemWithPreferences()
    }

    @objc
    private func handleMenuBarPreferenceChange(
      _ notification: Notification
    ) {
      syncStatusItemWithPreferences()
    }

    @objc
    private func togglePopover(_ sender: Any?) {
      guard let button = statusItem?.button else { return }

      if popover.isShown {
        popover.performClose(sender)
      } else {
        TelemetryTracker.trackMenuBarOpened()
        popover.show(
          relativeTo: button.bounds,
          of: button,
          preferredEdge: .minY
        )
        popover.contentViewController?.view.window?.makeKey()
      }
    }

    private func syncStatusItemWithPreferences() {
      guard menuBarEnabled else {
        popover.performClose(nil)
        if let statusItem {
          NSStatusBar.system.removeStatusItem(statusItem)
          self.statusItem = nil
        }
        return
      }

      makeStatusItemIfNeeded()
      updateStatusItem()
    }

    private func makeStatusItemIfNeeded() {
      guard statusItem == nil else { return }

      let item = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
      )
      statusItem = item

      guard let button = item.button else { return }

      if let image = NSImage(named: "RooMenuBar") {
        image.isTemplate = true
        image.size = NSSize(width: 15, height: 15)
        button.image = image
        button.imagePosition = .imageLeading
      }

      button.font = .systemFont(ofSize: 12, weight: .medium)
      button.toolTip = "RooMate"
      button.target = self
      button.action = #selector(togglePopover(_:))
      button.sendAction(on: [.leftMouseUp])
    }

    private func updateStatusItem() {
      guard menuBarEnabled else { return }
      makeStatusItemIfNeeded()

      guard let item = statusItem,
        let button = item.button
      else {
        return
      }

      let iconOnly = UserDefaults.standard.bool(
        forKey: DefaultsKey.iconOnly
      )

      if iconOnly {
        item.length = NSStatusItem.squareLength
        button.imagePosition = .imageOnly
        button.title = ""
        button.setAccessibilityLabel("RooMate")
        return
      }

      item.length = NSStatusItem.variableLength
      button.imagePosition = .imageLeading

      let now = Date()
      let blocks = menuBarBlocks(
        store: store,
        reference: now
      )

      if let current = currentMenuBarBlock(in: blocks, at: now) {
        let minutes = max(
          1,
          Int(current.end.timeIntervalSince(now)) / 60
        )
        let total = max(
          1,
          current.end.timeIntervalSince(current.start)
        )
        let elapsed = max(
          0,
          now.timeIntervalSince(current.start)
        )
        let percent = Int(
          (min(
            1,
            max(0, elapsed / total)
          ) * 100).rounded()
        )

        button.title =
          " \(compact(current.title)) · \(percent)% · \(minutes)m"
      } else if let next = blocks.first(
        where: { now < $0.start }
      ) {
        button.title = " Next · \(compact(next.title))"
      } else {
        button.title = ""
      }

      button.setAccessibilityLabel("RooMate")
    }

    private func compact(_ title: String) -> String {
      let limit = 16
      guard title.count > limit else { return title }
      return String(title.prefix(limit - 1)) + "…"
    }

    deinit {
      timer?.invalidate()
      NotificationCenter.default.removeObserver(self)
    }
  }

  @MainActor
  private final class RooMateFloatingTimerHostingView:
    NSHostingView<RooMateFloatingTimerView>
  {

    override func mouseDown(with event: NSEvent) {
      let point = convert(event.locationInWindow, from: nil)
      let actionZone = NSRect(
        x: max(0, bounds.maxX - 78),
        y: max(0, bounds.maxY - 42),
        width: 78,
        height: 42
      )

      if actionZone.contains(point) {
        super.mouseDown(with: event)
        return
      }

      window?.performDrag(with: event)
    }
  }

  @MainActor
  private final class RooMateFloatingTimerController: NSObject {
    private enum DefaultsKey {
      static let enabled = "RooMateFloatingTimerEnabled"
      static let clickThrough = "RooMateFloatingTimerClickThrough"
      static let compact = "RooMateFloatingTimerCompact"
    }

    private var panel: NSPanel?
    private var defaultsObserver: NSObjectProtocol?
    private var resetObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var scheduleObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?
    private var contentReloadTask: Task<Void, Never>?
    private var passiveLocalMonitor: Any?
    private var passiveGlobalMonitor: Any?

    func start() {
      guard defaultsObserver == nil else { return }

      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handlePassiveRecoveryRequest),
        name: .rooMateFloatingTimerRecoverInteraction,
        object: nil
      )

      defaultsObserver = NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification,
        object: UserDefaults.standard,
        queue: .main
      ) { [weak self] _ in
        guard let self else { return }

        Task { @MainActor [self] in
          self.syncWithPreferences()
        }
      }

      resetObserver = NotificationCenter.default.addObserver(
        forName: .rooMateDidReset,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        guard let self else { return }

        Task { @MainActor [self] in
          self.reloadTimerContent()
        }
      }

      scheduleObserver = NotificationCenter.default.addObserver(
        forName: .rooMateScheduleDidChange,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        Task { @MainActor [self] in
          self.scheduleContentReload()
        }
      }

      appearanceObserver = NotificationCenter.default.addObserver(
        forName: .rooMateAppearanceDidChange,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        Task { @MainActor [self] in
          self.scheduleContentReload()
        }
      }

      resizeObserver = NotificationCenter.default.addObserver(
        forName: .rooMateFloatingTimerResize,
        object: nil,
        queue: .main
      ) { [weak self] note in
        guard let self,
          let width = note.userInfo?["width"] as? CGFloat,
          let height = note.userInfo?["height"] as? CGFloat
        else {
          return
        }

        Task { @MainActor [self] in
          self.handleFloatingTimerResize(
            width: width,
            height: height
          )
        }
      }

      syncWithPreferences()
    }

    deinit {
      NotificationCenter.default.removeObserver(self)

      if let defaultsObserver {
        NotificationCenter.default.removeObserver(defaultsObserver)
      }

      if let resetObserver {
        NotificationCenter.default.removeObserver(resetObserver)
      }

      if let resizeObserver {
        NotificationCenter.default.removeObserver(resizeObserver)
      }

      if let scheduleObserver {
        NotificationCenter.default.removeObserver(scheduleObserver)
      }

      if let appearanceObserver {
        NotificationCenter.default.removeObserver(appearanceObserver)
      }

      contentReloadTask?.cancel()

      if let passiveLocalMonitor {
        NSEvent.removeMonitor(passiveLocalMonitor)
      }

      if let passiveGlobalMonitor {
        NSEvent.removeMonitor(passiveGlobalMonitor)
      }
    }

    @objc
    private func handlePassiveRecoveryRequest() {
      UserDefaults.standard.set(
        false,
        forKey: DefaultsKey.clickThrough
      )

      syncWithPreferences()
    }

    private func scheduleContentReload() {
      contentReloadTask?.cancel()
      contentReloadTask = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 180_000_000)
        guard let self, !Task.isCancelled else { return }
        self.reloadTimerContent()
      }
    }

    private func reloadTimerContent() {
      guard let panel else { return }

      let hostingView = RooMateFloatingTimerHostingView(
        rootView: RooMateFloatingTimerView()
      )
      hostingView.frame = panel.contentView?.bounds ?? .zero
      hostingView.autoresizingMask = [.width, .height]
      panel.contentView = hostingView
    }

    private func syncWithPreferences() {
      let defaults = UserDefaults.standard
      let enabled = defaults.bool(forKey: DefaultsKey.enabled)
      let clickThrough = defaults.bool(forKey: DefaultsKey.clickThrough)

      guard enabled else {
        panel?.orderOut(nil)
        removePassiveInteractionMonitors()
        return
      }

      let panel = makePanelIfNeeded()
      let preferredSize = floatingTimerSize(defaults: defaults)

      let currentSize =
        panel.contentView?.bounds.size
        ?? panel.frame.size

      if abs(currentSize.width - preferredSize.width) > 0.5
        || abs(currentSize.height - preferredSize.height) > 0.5
      {
        let oldTopRight = NSPoint(
          x: panel.frame.maxX,
          y: panel.frame.maxY
        )

        panel.setContentSize(preferredSize)
        panel.setFrameOrigin(
          NSPoint(
            x: oldTopRight.x - preferredSize.width,
            y: oldTopRight.y - preferredSize.height
          )
        )
      }

      panel.ignoresMouseEvents = clickThrough
      panel.isMovableByWindowBackground = !clickThrough
      updatePassiveInteractionMonitors(
        timerFrame: panel.frame,
        clickThrough: clickThrough
      )

      if !panel.isVisible {
        positionPanelIfNeeded(panel)
        panel.orderFrontRegardless()
        TelemetryTracker.trackFloatingTimerShown(
          compact: defaults.bool(forKey: DefaultsKey.compact)
        )
      }
    }

    private func handleFloatingTimerResize(
      width: CGFloat,
      height: CGFloat
    ) {
      guard let panel else {
        return
      }

      let targetSize = NSSize(
        width: width,
        height: height
      )
      let currentSize =
        panel.contentView?.bounds.size
        ?? panel.frame.size

      guard
        abs(currentSize.width - targetSize.width) > 0.5
          || abs(currentSize.height - targetSize.height) > 0.5
      else {
        return
      }

      // Keep the top-right corner anchored so resizing feels intentional
      // instead of making the timer "jump" around the desktop.
      let topRight = NSPoint(
        x: panel.frame.maxX,
        y: panel.frame.maxY
      )

      let targetFrame = NSRect(
        x: topRight.x - targetSize.width,
        y: topRight.y - targetSize.height,
        width: targetSize.width,
        height: targetSize.height
      )

      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.20
        context.timingFunction = CAMediaTimingFunction(
          name: .easeInEaseOut
        )
        panel.animator().setFrame(
          targetFrame,
          display: true
        )
      }

      updatePassiveInteractionMonitors(
        timerFrame: targetFrame,
        clickThrough: UserDefaults.standard.bool(
          forKey: DefaultsKey.clickThrough
        )
      )
    }

    private func removePassiveInteractionMonitors() {
      if let passiveLocalMonitor {
        NSEvent.removeMonitor(passiveLocalMonitor)
        self.passiveLocalMonitor = nil
      }

      if let passiveGlobalMonitor {
        NSEvent.removeMonitor(passiveGlobalMonitor)
        self.passiveGlobalMonitor = nil
      }
    }

    private func updatePassiveInteractionMonitors(
      timerFrame: NSRect,
      clickThrough: Bool
    ) {
      removePassiveInteractionMonitors()

      guard clickThrough else {
        return
      }

      let clickThroughKey = DefaultsKey.clickThrough

      passiveLocalMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.leftMouseDown, .rightMouseDown]
      ) { event in
        let isRightClick = event.type == .rightMouseDown
        let isDoubleClick =
          event.type == .leftMouseDown
          && event.clickCount >= 2

        guard isRightClick || isDoubleClick else {
          return event
        }

        guard timerFrame.contains(NSEvent.mouseLocation) else {
          return event
        }

        Task { @MainActor in
          UserDefaults.standard.set(
            false,
            forKey: clickThroughKey
          )

          NotificationCenter.default.post(
            name: .rooMateFloatingTimerRecoverInteraction,
            object: nil
          )
        }

        return nil
      }

      passiveGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
        matching: [.leftMouseDown, .rightMouseDown]
      ) { event in
        let isRightClick = event.type == .rightMouseDown
        let isDoubleClick =
          event.type == .leftMouseDown
          && event.clickCount >= 2

        guard isRightClick || isDoubleClick else {
          return
        }

        guard timerFrame.contains(NSEvent.mouseLocation) else {
          return
        }

        Task { @MainActor in
          UserDefaults.standard.set(
            false,
            forKey: clickThroughKey
          )

          NotificationCenter.default.post(
            name: .rooMateFloatingTimerRecoverInteraction,
            object: nil
          )
        }
      }
    }

    private func makePanelIfNeeded() -> NSPanel {
      if let panel {
        return panel
      }

      let size = floatingTimerSize(
        defaults: UserDefaults.standard
      )
      let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )

      panel.level = .floating
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      panel.hidesOnDeactivate = false
      panel.isReleasedWhenClosed = false
      panel.animationBehavior = .utilityWindow
      panel.collectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
      ]
      panel.isMovable = true
      panel.isMovableByWindowBackground = true

      let hostingView = RooMateFloatingTimerHostingView(
        rootView: RooMateFloatingTimerView()
      )
      hostingView.frame = NSRect(
        origin: .zero,
        size: size
      )
      hostingView.autoresizingMask = [.width, .height]
      hostingView.wantsLayer = true
      hostingView.layer?.backgroundColor = NSColor.clear.cgColor
      hostingView.layer?.masksToBounds = false
      panel.contentView = hostingView

      self.panel = panel
      return panel
    }

    private func floatingTimerSize(
      defaults: UserDefaults
    ) -> NSSize {
      defaults.bool(forKey: DefaultsKey.compact)
        ? NSSize(width: 244, height: 98)
        : NSSize(width: 304, height: 140)
    }

    private func positionPanelIfNeeded(_ panel: NSPanel) {
      guard panel.frame.origin == .zero else { return }

      let screen =
        NSScreen.main
        ?? NSScreen.screens.first

      guard let visibleFrame = screen?.visibleFrame else { return }

      let frame = panel.frame
      let x = visibleFrame.maxX - frame.width - 24
      let y = visibleFrame.maxY - frame.height - 22

      panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
  }

  private struct RooMateFloatingTimerView: View {
    @ObservedObject private var store = UserScheduleStore.shared

    @AppStorage("RooMateFloatingTimerEnabled")
    private var isEnabled = false

    @AppStorage("RooMateFloatingTimerClickThrough")
    private var clickThrough = false

    @AppStorage("RooMateFloatingTimerCompact")
    private var compactMode = false

    @AppStorage("RooMateFloatingTimerShowNextUp")
    private var showNextUp = true

    @State private var now = Date()
    @State private var isHovering = false
    @State private var lastReportedSize = CGSize.zero

    private let timer = Timer.publish(
      every: 1,
      on: .main,
      in: .common
    )
    .autoconnect()

    private var blocks: [MenuBarBlockInfo] {
      menuBarBlocks(store: store, reference: now)
    }

    private var current: MenuBarBlockInfo? {
      currentMenuBarBlock(in: blocks, at: now)
    }

    private var next: MenuBarBlockInfo? {
      blocks.first { now < $0.start }
    }

    private var progress: Double {
      guard let current else { return 0 }

      let duration = max(
        1,
        current.end.timeIntervalSince(current.start)
      )
      let elapsed = max(
        0,
        now.timeIntervalSince(current.start)
      )

      return min(1, max(0, elapsed / duration))
    }

    private var accent: Color {
      current?.color
        ?? next?.color
        ?? DesignTokens.Colors.schedule
    }

    private var timerWidth: CGFloat {
      compactMode ? 244 : 304
    }

    private var timerHeight: CGFloat {
      if compactMode {
        return 98
      }

      if current != nil {
        return showNextUp && next != nil
          ? 140
          : 108
      }

      if next != nil {
        return 112
      }

      return 100
    }

    private var emptyState: (title: String, detail: String, symbol: String) {
      if let specialDay = store.remoteSpecialScheduleDay(on: now), specialDay.isSchoolClosed {
        return (
          specialDay.displayTitle, "No classes are scheduled", "calendar.badge.exclamationmark"
        )
      }
      let weekday = Calendar.current.component(.weekday, from: now)
      if weekday == 1 || weekday == 7 {
        return ("No school today", "Enjoy the weekend", "calendar")
      }
      if blocks.isEmpty {
        return ("No schedule available", "Check your schedule setup", "calendar.badge.questionmark")
      }
      return ("School day done", "Nothing else on your schedule", "checkmark.circle.fill")
    }

    private func reportPreferredSizeIfNeeded() {
      let size = CGSize(
        width: timerWidth,
        height: timerHeight
      )

      guard
        abs(lastReportedSize.width - size.width) > 0.5
          || abs(lastReportedSize.height - size.height) > 0.5
      else {
        return
      }

      lastReportedSize = size

      NotificationCenter.default.post(
        name: .rooMateFloatingTimerResize,
        object: nil,
        userInfo: [
          "width": size.width,
          "height": size.height,
        ]
      )
    }

    var body: some View {
      VStack(alignment: .leading, spacing: compactMode ? 7 : 9) {
        timerHeader

        if compactMode {
          compactTimerBody
        } else {
          boldTimerBody
        }
      }
      .padding(compactMode ? 11 : 12)
      .frame(
        width: timerWidth,
        height: timerHeight,
        alignment: .topLeading
      )
      .background {
        RoundedRectangle(
          cornerRadius: compactMode ? 18 : 21,
          style: .continuous
        )
        .fill(accent.opacity(0.055))
      }
      .rooGlass(
        cornerRadius: compactMode ? 18 : 21
      )
      .overlay {
        RoundedRectangle(
          cornerRadius: compactMode ? 18 : 21,
          style: .continuous
        )
        .strokeBorder(
          accent.opacity(0.30),
          lineWidth: 1
        )
      }
      .opacity(clickThrough ? 0.58 : 1)
      .contentShape(Rectangle())
      .onHover { hovering in
        isHovering = hovering
      }
      .onAppear {
        reportPreferredSizeIfNeeded()
      }
      .onReceive(timer) { date in
        now = date
        reportPreferredSizeIfNeeded()
      }
      .onChange(of: compactMode) {
        reportPreferredSizeIfNeeded()
      }
      .onChange(of: showNextUp) {
        reportPreferredSizeIfNeeded()
      }
      .animation(
        DesignTokens.Animation.quick,
        value: clickThrough
      )
      .animation(
        DesignTokens.Animation.quick,
        value: isHovering
      )
      .animation(
        DesignTokens.Animation.snappy,
        value: compactMode
      )
      .accessibilityElement(children: .combine)
      .accessibilityLabel(accessibilityText)
      .preferredColorScheme(store.theme.colorScheme)
    }

    private var timerHeader: some View {
      HStack(spacing: 7) {
        Text("ROOMATE")
          .font(.system(size: 8.5, weight: .black))
          .tracking(1.05)
          .foregroundStyle(
            DesignTokens.Colors.secondaryText
          )

        if clickThrough {
          Circle()
            .fill(accent)
            .frame(width: 5, height: 5)

          Text("CLICK-THROUGH ON")
            .font(.system(size: 7, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(accent)
        }

        Spacer(minLength: 0)

        if isHovering && !clickThrough {
          HStack(spacing: 5) {
            Button {
              clickThrough = true
            } label: {
              Image(systemName: "cursorarrow.rays")
                .font(
                  .system(
                    size: 8.5,
                    weight: .bold
                  )
                )
                .foregroundStyle(accent)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
                .background(
                  accent.opacity(0.11),
                  in: Circle()
                )
            }
            .buttonStyle(.plain)
            .help("Let clicks pass through the timer")

            Button {
              isEnabled = false
            } label: {
              Image(systemName: "xmark")
                .font(
                  .system(
                    size: 8.5,
                    weight: .bold
                  )
                )
                .foregroundStyle(
                  DesignTokens.Colors.secondaryText
                )
                .frame(width: 22, height: 22)
                .contentShape(Circle())
                .background(
                  DesignTokens.Colors.hover.opacity(0.72),
                  in: Circle()
                )
            }
            .buttonStyle(.plain)
            .help("Hide Floating Timer")
          }
          .transition(
            .opacity.combined(
              with: .scale(scale: 0.94)
            )
          )
        }
      }
      .frame(height: 22)
    }

    @ViewBuilder
    private var boldTimerBody: some View {
      if let current {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
              Text("RIGHT NOW")
                .font(.system(size: 8, weight: .black))
                .tracking(0.9)
                .foregroundStyle(accent)

              Text(current.title)
                .font(
                  .system(
                    size: 16,
                    weight: .bold
                  )
                )
                .foregroundStyle(
                  DesignTokens.Colors.primaryText
                )
                .lineLimit(1)

              if !current.subtitle.isEmpty {
                Text(current.subtitle)
                  .font(
                    .system(
                      size: 9,
                      weight: .medium
                    )
                  )
                  .foregroundStyle(
                    DesignTokens.Colors.secondaryText
                  )
                  .lineLimit(1)
              }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: -1) {
              Text(
                remainingText(
                  until: current.end
                )
              )
              .font(
                .system(
                  size: 24,
                  weight: .black,
                  design: .rounded
                )
              )
              .foregroundStyle(accent)
              .lineLimit(1)
              .minimumScaleFactor(0.72)
              .layoutPriority(2)
              .contentTransition(.numericText())

              Text("LEFT")
                .font(.system(size: 7, weight: .black))
                .tracking(0.9)
                .foregroundStyle(
                  DesignTokens.Colors.subtleText
                )
            }
          }

          progressBar

          if showNextUp, let next {
            nextRow(next)
          }
        }
      } else if let next {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
              Text("UP NEXT")
                .font(.system(size: 8, weight: .black))
                .tracking(0.9)
                .foregroundStyle(accent)

              Text(next.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(
                  DesignTokens.Colors.primaryText
                )
                .lineLimit(1)

              if !next.subtitle.isEmpty {
                Text(next.subtitle)
                  .font(.system(size: 9, weight: .medium))
                  .foregroundStyle(
                    DesignTokens.Colors.secondaryText
                  )
                  .lineLimit(1)
              }
            }

            Spacer()

            Text(
              remainingText(
                until: next.start
              )
            )
            .font(
              .system(
                size: 22,
                weight: .black,
                design: .rounded
              )
            )
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .layoutPriority(2)
            .contentTransition(.numericText())
          }

          Text("Starts \(clockText(next.start))")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(
              DesignTokens.Colors.secondaryText
            )
        }
      } else {
        completedBody
      }
    }

    @ViewBuilder
    private var compactTimerBody: some View {
      if let current {
        VStack(alignment: .leading, spacing: 7) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
              Text("NOW")
                .font(.system(size: 7.5, weight: .black))
                .tracking(0.85)
                .foregroundStyle(accent)

              Text(current.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(
                  DesignTokens.Colors.primaryText
                )
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(
              remainingText(
                until: current.end
              )
            )
            .font(
              .system(
                size: 18,
                weight: .black,
                design: .rounded
              )
            )
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .layoutPriority(2)
            .contentTransition(.numericText())
          }

          progressBar
        }
      } else if let next {
        HStack(alignment: .center, spacing: 8) {
          VStack(alignment: .leading, spacing: 1) {
            Text("NEXT")
              .font(.system(size: 7.5, weight: .black))
              .tracking(0.85)
              .foregroundStyle(accent)

            Text(next.title)
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(
                DesignTokens.Colors.primaryText
              )
              .lineLimit(1)
          }

          Spacer(minLength: 6)

          Text(
            remainingText(
              until: next.start
            )
          )
          .font(
            .system(
              size: 18,
              weight: .black,
              design: .rounded
            )
          )
          .foregroundStyle(accent)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .layoutPriority(2)
          .contentTransition(.numericText())
        }
      } else {
        HStack(spacing: 9) {
          Image(systemName: emptyState.symbol)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(accent)

          Text(emptyState.title.uppercased())
            .font(.system(size: 11, weight: .black))
            .tracking(0.55)
            .foregroundStyle(
              DesignTokens.Colors.primaryText
            )

          Spacer()
        }
      }
    }

    private var completedBody: some View {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text("TODAY")
            .font(.system(size: 8, weight: .black))
            .tracking(0.9)
            .foregroundStyle(accent)

          Text(emptyState.title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(
              DesignTokens.Colors.primaryText
            )

          Text(emptyState.detail)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(
              DesignTokens.Colors.secondaryText
            )
        }

        Spacer()

        Image(systemName: emptyState.symbol)
          .font(.system(size: 25, weight: .bold))
          .foregroundStyle(accent)
      }
    }

    private var progressBar: some View {
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(
              DesignTokens.Colors.selection.opacity(0.86)
            )

          Capsule()
            .fill(accent)
            .frame(
              width: max(
                progress > 0 ? 8 : 0,
                proxy.size.width * progress
              )
            )
        }
      }
      .frame(height: compactMode ? 4 : 5)
      .animation(
        .linear(duration: 0.25),
        value: progress
      )
    }

    private func nextRow(
      _ block: MenuBarBlockInfo
    ) -> some View {
      HStack(spacing: 7) {
        Text("NEXT")
          .font(.system(size: 7, weight: .black))
          .tracking(0.85)
          .foregroundStyle(
            DesignTokens.Colors.subtleText
          )

        Circle()
          .fill(block.color)
          .frame(width: 6, height: 6)

        Text(block.title)
          .font(.system(size: 9.5, weight: .bold))
          .foregroundStyle(
            DesignTokens.Colors.primaryText
          )
          .lineLimit(1)

        Spacer(minLength: 4)

        Text(clockText(block.start))
          .font(
            .system(
              size: 8.5,
              weight: .bold,
              design: .rounded
            )
          )
          .foregroundStyle(
            DesignTokens.Colors.secondaryText
          )
      }
      .padding(.horizontal, 8)
      .frame(height: 24)
      .background(
        DesignTokens.Colors.hover.opacity(0.25),
        in: RoundedRectangle(
          cornerRadius: 8,
          style: .continuous
        )
      )
    }

    private var accessibilityText: String {
      if let current {
        let nextText =
          next.map {
            ", next is \($0.title)"
          } ?? ""

        return "\(current.title), \(remainingText(until: current.end)) remaining\(nextText)"
      }

      if let next {
        return "Next is \(next.title) in \(remainingText(until: next.start))"
      }

      return "\(emptyState.title). \(emptyState.detail)"
    }

    private func clockText(_ date: Date) -> String {
      date.formatted(
        date: .omitted,
        time: .shortened
      )
    }

    private func remainingText(
      until date: Date
    ) -> String {
      let seconds = max(
        0,
        Int(date.timeIntervalSince(now))
      )

      if seconds >= 3600 {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        return minutes == 0
          ? "\(hours)h"
          : "\(hours)h \(minutes)m"
      }

      let minutes = seconds / 60
      let remainder = seconds % 60

      if minutes > 0 {
        return "\(minutes)m \(remainder)s"
      }

      return "\(remainder)s"
    }
  }

  struct RooMateMenuBarLabel: View {
    @ObservedObject private var store = UserScheduleStore.shared
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
      HStack(spacing: 5) {
        Image("RooMenuBar")
          .resizable()
          .renderingMode(.template)
          .scaledToFit()
          .frame(width: 14, height: 14)
          .accessibilityHidden(true)

        Text(labelText)
      }
      .onReceive(timer) { now = $0 }
    }

    private var labelText: String {
      if let specialDay = store.remoteSpecialScheduleDay(on: now),
        specialDay.isSchoolClosed
      {
        return specialDay.displayTitle
      }

      let blocks = menuBarBlocks(store: store, reference: now)
      if let current = currentMenuBarBlock(in: blocks, at: now) {
        let minutes = max(1, Int(current.end.timeIntervalSince(now)) / 60)
        let total = max(1, current.end.timeIntervalSince(current.start))
        let elapsed = max(0, now.timeIntervalSince(current.start))
        let percent = Int((min(1, max(0, elapsed / total)) * 100).rounded())
        return "\(current.title) · \(percent)% · \(minutes)m"
      }
      if let next = blocks.first(where: { now < $0.start }) {
        return "Next · \(next.title)"
      }
      return "RooMate"
    }
  }

  struct RooMateMenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var store = UserScheduleStore.shared
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var blocks: [MenuBarBlockInfo] {
      menuBarBlocks(store: store, reference: now)
    }

    private var current: MenuBarBlockInfo? {
      currentMenuBarBlock(in: blocks, at: now)
    }

    private var next: MenuBarBlockInfo? {
      blocks.first { now < $0.start }
    }

    private var currentProgress: Double {
      guard let current else { return 0 }
      let total = max(1, current.end.timeIntervalSince(current.start))
      let elapsed = max(0, now.timeIntervalSince(current.start))
      return min(1, max(0, elapsed / total))
    }

    private var daySchedule: [MenuBarBlockInfo] {
      blocks
    }

    private var remainingCount: Int {
      blocks.filter { $0.end > now }.count
    }

    private var specialDay: RemoteSpecialScheduleDay? {
      store.remoteSpecialScheduleDay(on: now)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 14) {
        header

        if let current {
          currentProgressSection(current)
        } else if let next {
          freeTimeSection(next)
        } else {
          completedSection
        }

        Divider()

        quickActionsSection

        if !daySchedule.isEmpty {
          Divider()

          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("TODAY")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

              Spacer()

              Text(
                remainingCount == 0
                  ? "\(daySchedule.count) blocks"
                  : "\(remainingCount) left"
              )
              .font(.system(size: 9, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.subtleText)
            }

            ScrollView(.vertical, showsIndicators: true) {
              LazyVStack(spacing: 5) {
                ForEach(
                  Array(daySchedule.enumerated()),
                  id: \.offset
                ) { _, block in
                  scheduleRow(block)
                }
              }
              .padding(.trailing, 2)
            }
            .frame(maxHeight: 160)
          }
        }

        HStack(spacing: 8) {
          Button {
            openRooMate()
          } label: {
            Text("Open RooMate")
              .font(.system(size: 11, weight: .semibold))
              .frame(maxWidth: .infinity)
              .frame(height: 34)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .background(
            Color.secondary.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
          )

          Button {
            NSApp.terminate(nil)
          } label: {
            Label("Quit", systemImage: "power")
              .font(.system(size: 10.5, weight: .semibold))
              .padding(.horizontal, 10)
              .frame(height: 34)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .background(
            Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
          )
          .help("Quit RooMate completely")
        }
      }
      .padding(16)
      .frame(width: 320)
      .onReceive(timer) { now = $0 }
      .preferredColorScheme(store.theme.colorScheme)
    }

    private var quickActionsSection: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text("ACTIONS")
          .font(.system(size: 9, weight: .bold))
          .tracking(0.8)
          .foregroundStyle(.secondary)

        HStack(spacing: 7) {
          menuQuickActionButton(
            title: "Schedule",
            systemImage: "calendar",
            color: DesignTokens.Colors.schedule,
            action: "schedule"
          )

          menuQuickActionButton(
            title: "Focus",
            systemImage: "rectangle.center.inset.filled",
            color: DesignTokens.Colors.today,
            action: "focus"
          )

          menuQuickActionButton(
            title: "Dining",
            systemImage: "fork.knife",
            color: DesignTokens.Colors.dining,
            action: "dining"
          )

          menuQuickActionButton(
            title: "Search",
            systemImage: "magnifyingglass",
            color: DesignTokens.Colors.links,
            action: "search"
          )
        }
      }
    }

    private func menuQuickActionButton(
      title: String,
      systemImage: String,
      color: Color,
      action: String
    ) -> some View {
      Button {
        openRooMate(action: action)
      } label: {
        VStack(spacing: 5) {
          ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(color.opacity(0.12))

            Image(systemName: systemImage)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(color)
          }
          .frame(width: 30, height: 30)

          Text(title)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background(
        Color.secondary.opacity(0.07),
        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
      )
    }

    private func openRooMate(action: String? = nil) {
      // Recreate the SwiftUI WindowGroup if the user closed the last main
      // window. Post navigation only after requesting the window so the
      // action is not lost while no ContentView is listening.
      openWindow(id: RooMateWindowID.main)
      NSApp.activate(ignoringOtherApps: true)

      DispatchQueue.main.async {
        let mainWindow = NSApp.windows.first { window in
          window.level == .normal
            && window.canBecomeKey
            && window.styleMask.contains(.titled)
        }
        mainWindow?.makeKeyAndOrderFront(nil)

        if let action {
          NotificationCenter.default.post(
            name: Notification.Name("RooMateQuickAction"),
            object: nil,
            userInfo: ["action": action]
          )
        }
      }
    }

    private var header: some View {
      HStack(spacing: 10) {
        Image("RooMenuBar")
          .resizable()
          .renderingMode(.template)
          .scaledToFit()
          .frame(width: 18, height: 18)

        VStack(alignment: .leading, spacing: 1) {
          Text("RooMate")
            .font(.system(size: 13, weight: .semibold))

          Text(dateText(now))
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
        }

        Spacer()
      }
    }

    private func currentProgressSection(_ current: MenuBarBlockInfo) -> some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text("RIGHT NOW")
              .font(.system(size: 9, weight: .bold))
              .tracking(0.8)
              .foregroundStyle(current.color)

            Text(current.title)
              .font(.system(size: 17, weight: .semibold))
              .lineLimit(1)

            if !current.subtitle.isEmpty {
              Text(current.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }

          Spacer()

          VStack(alignment: .trailing, spacing: 1) {
            Text("\(Int((currentProgress * 100).rounded()))%")
              .font(.system(size: 17, weight: .semibold, design: .rounded))
              .foregroundStyle(current.color)

            Text(shortDuration(current.end.timeIntervalSince(now)))
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(.secondary)
          }
        }

        ProgressView(value: currentProgress)
          .tint(current.color)

        HStack {
          Text("Ends \(timeText(current.end))")
          Spacer()
          Text("\(Int((currentProgress * 100).rounded()))% complete")
        }
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(.secondary)

        if let next {
          HStack(spacing: 7) {
            Circle()
              .fill(next.color)
              .frame(width: 7, height: 7)

            Text("Next")
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(.secondary)

            Text(next.title)
              .font(.system(size: 10, weight: .semibold))
              .lineLimit(1)

            Spacer()

            Text(timeText(next.start))
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(.secondary)
          }
        }
      }
    }

    private func freeTimeSection(_ next: MenuBarBlockInfo) -> some View {
      VStack(alignment: .leading, spacing: 7) {
        Text("FREE RIGHT NOW")
          .font(.system(size: 9, weight: .bold))
          .tracking(0.8)
          .foregroundStyle(.secondary)

        HStack(alignment: .firstTextBaseline) {
          Text("Next: \(next.title)")
            .font(.system(size: 16, weight: .semibold))
            .lineLimit(1)

          Spacer()

          Text(shortDuration(next.start.timeIntervalSince(now)))
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(next.color)
        }

        Text("Starts at \(timeText(next.start))")
          .font(.system(size: 9.5))
          .foregroundStyle(.secondary)
      }
    }

    private var completedSection: some View {
      VStack(alignment: .leading, spacing: 4) {
        if let specialDay, specialDay.isSchoolClosed {
          Text("NO SCHOOL TODAY")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.secondary)

          Text(specialDay.displayTitle)
            .font(.system(size: 16, weight: .semibold))

          if !specialDay.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(specialDay.note)
              .font(.system(size: 9.5))
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        } else if Calendar.current.isDateInWeekend(now) {
          Text("NO SCHOOL TODAY")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.secondary)

          Text("Enjoy the weekend")
            .font(.system(size: 16, weight: .semibold))
        } else if daySchedule.isEmpty {
          Text("SCHEDULE NOT SET UP")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.secondary)

          Text("Check your schedule setup")
            .font(.system(size: 16, weight: .semibold))
        } else {
          Text("DONE FOR TODAY")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.secondary)

          Text("School day complete")
            .font(.system(size: 16, weight: .semibold))
        }
      }
    }

    private func scheduleRow(_ block: MenuBarBlockInfo) -> some View {
      let isCurrent = now >= block.start && now < block.end
      let isPast = now >= block.end

      return HStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(
            isPast
              ? block.color.opacity(0.42)
              : block.color
          )
          .frame(width: 3, height: 25)

        VStack(alignment: .leading, spacing: 1) {
          Text(block.title)
            .font(
              .system(
                size: 10.5,
                weight: isCurrent ? .semibold : .medium
              )
            )
            .foregroundStyle(
              isPast
                ? .secondary
                : .primary
            )
            .lineLimit(1)

          if !block.subtitle.isEmpty {
            Text(block.subtitle)
              .font(.system(size: 8.5))
              .foregroundStyle(
                isPast
                  ? DesignTokens.Colors.subtleText
                  : .secondary
              )
              .lineLimit(1)
          }
        }

        Spacer()

        Text(
          isCurrent
            ? "Now"
            : (isPast
              ? "Done"
              : timeText(block.start))
        )
        .font(
          .system(
            size: 9,
            weight: isCurrent ? .semibold : .medium
          )
        )
        .foregroundStyle(
          isCurrent
            ? block.color
            : (isPast
              ? DesignTokens.Colors.subtleText
              : .secondary)
        )
      }
      .padding(.horizontal, 7)
      .frame(height: 34)
      .background(
        isCurrent ? block.color.opacity(0.08) : Color.clear,
        in: RoundedRectangle(
          cornerRadius: 7,
          style: .continuous
        )
      )
    }

    private func shortDuration(_ interval: TimeInterval) -> String {
      let minutes = max(0, Int(interval) / 60)
      if minutes >= 60 {
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
      }
      return "\(max(1, minutes))m"
    }

    private func timeText(_ date: Date) -> String {
      let formatter = DateFormatter()
      formatter.dateFormat = "h:mm a"
      return formatter.string(from: date)
    }

    private func dateText(_ date: Date) -> String {
      let formatter = DateFormatter()
      formatter.dateFormat = "EEEE, MMM d"
      return formatter.string(from: date)
    }
  }
#endif
