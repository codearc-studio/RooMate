import Foundation

struct MenuService {
  private let indexURLString = "https://menus.campus-dining.com/eliorna/d1596"
  private let menuHostString = "https://menus.tenkites.com/eliorna/d1596"
  private let browserUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

  private func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
      print("[Dining] \(message())")
    #endif
  }

  func loadIndex() async throws -> [MenuDateEntry] {
    guard let indexURL = URL(string: indexURLString) else {
      throw MenuServiceError.invalidURL
    }
    debugLog("Loading menu index: \(indexURL.absoluteString)")
    let html = try await fetchHTML(from: indexURL)

    let menuGuid = extractMenuGuid(from: html)
    debugLog("Resolved menu GUID: \(menuGuid)")

    let dateEntries = extractDateEntries(from: html, fallbackMenuGuid: menuGuid)
    debugLog("Discovered \(dateEntries.count) usable menu dates.")

    guard !dateEntries.isEmpty else {
      debugLog("No usable menu dates were found.")
      throw MenuServiceError.noDatesFound
    }
    return dateEntries
  }

  func loadSnapshot(for entry: MenuDateEntry) async throws -> MenuDaySnapshot {
    let targetURL = try menuURL(for: entry)
    debugLog("Loading menu for \(entry.dateString).")
    debugLog("Request URL: \(targetURL.absoluteString)")

    let html = try await fetchHTML(from: targetURL)

    debugLog("Extracting menu payload.")
    let jsonString = try extractMenuJSON(from: html)

    debugLog("Parsing menu payload.")
    let items = try parseFlatItems(from: jsonString)
    debugLog("Parsed \(items.count) raw menu nodes.")

    let snapshot = buildSnapshot(from: items, date: entry.date)
    guard !snapshot.mealPeriods.isEmpty,
      snapshot.stations.contains(where: { !$0.recipes.isEmpty })
    else {
      throw MenuServiceError.incompletePayload
    }
    debugLog(
      "Built snapshot with \(snapshot.mealPeriods.count) meal periods and \(snapshot.stations.count) stations."
    )
    return snapshot
  }

  private func menuURL(for entry: MenuDateEntry) throws -> URL {
    guard let menuHost = URL(string: menuHostString),
      var components = URLComponents(url: menuHost, resolvingAgainstBaseURL: false)
    else {
      throw MenuServiceError.invalidURL
    }
    components.queryItems = [
      URLQueryItem(name: "cl", value: "true"),
      URLQueryItem(name: "mguid", value: entry.menuGuid),
      URLQueryItem(name: "mldate", value: entry.dateString),
      URLQueryItem(name: "mlguid", value: entry.layoutGuid),
      URLQueryItem(name: "internalrequest", value: "true"),
    ]
    guard let url = components.url else {
      throw MenuServiceError.invalidURL
    }
    return url
  }

  private func fetchHTML(from url: URL) async throws -> String {
    var request = URLRequest(url: url)
    request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
    request.setValue(
      "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      forHTTPHeaderField: "Accept")
    request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
    request.setValue(url.absoluteString, forHTTPHeaderField: "Referer")

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        debugLog("Menu request did not return an HTTP response.")
        throw MenuServiceError.invalidResponse
      }

      debugLog("Menu server status: \(httpResponse.statusCode)")
      guard (200...299).contains(httpResponse.statusCode) else {
        throw MenuServiceError.invalidResponse
      }

      guard let string = String(data: data, encoding: .utf8) else {
        debugLog("Menu response was not valid UTF-8.")
        throw MenuServiceError.invalidEncoding
      }
      return string
    } catch {
      debugLog("Network error: \(error.localizedDescription)")
      throw error
    }
  }

  private func extractMenuGuid(from html: String) -> String {
    let pattern = #"mguid=([0-9A-Fa-f-]{36})"#
    if let matched = firstMatch(in: html, pattern: pattern) {
      return matched
    }
    debugLog("Menu GUID was not present in the page source; using the known dining menu GUID.")
    return "5c41a7a5-eb33-4100-a619-85725c33ee73"
  }

  private func extractDateEntries(from html: String, fallbackMenuGuid: String) -> [MenuDateEntry] {
    let datePattern = #"\d{4}-\d{2}-\d{2}"#
    guard let regex = try? NSRegularExpression(pattern: datePattern) else { return [] }
    let nsString = html as NSString
    let matches = regex.matches(
      in: html,
      range: NSRange(location: 0, length: nsString.length)
    )

    let calendar = diningCalendar()
    let startOfToday = calendar.startOfDay(for: Date())

    // A date can appear many times in Ten Kites' HTML (week headings,
    // hidden controls, scripts, etc.). The old scraper used the first
    // occurrence and often attached the wrong layout GUID to that date.
    // Collect each date first, then search *all* of its occurrences for
    // the strongest date/GUID pairing.
    let dateStrings = Array(
      Set(matches.map { nsString.substring(with: $0.range) })
    ).sorted()

    var entries: [MenuDateEntry] = []

    for dateString in dateStrings {
      guard let date = parseDiningDate(dateString) else { continue }
      guard calendar.startOfDay(for: date) >= startOfToday else { continue }

      guard
        let layoutGuid = layoutGuid(
          for: dateString,
          in: html,
          excluding: fallbackMenuGuid
        )
      else {
        // Showing fewer dates is safer than pairing a date with a
        // random/fallback layout and displaying somebody else's meal.
        debugLog("Skipping \(dateString): no trustworthy layout GUID.")
        continue
      }

      entries.append(
        MenuDateEntry(
          date: date,
          dateString: dateString,
          layoutGuid: layoutGuid,
          menuGuid: fallbackMenuGuid
        )
      )
    }

    return entries.sorted { $0.date < $1.date }
  }

  private func layoutGuid(
    for dateString: String,
    in html: String,
    excluding menuGuid: String
  ) -> String? {
    let escapedDate = NSRegularExpression.escapedPattern(for: dateString)
    let uuidCapture =
      #"([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})"#

    // Prefer explicit Elior/Ten Kites layout relationships when they are
    // present. The renderer has used several names for this value.
    let strongPatterns = [
      #"mldate(?:=|[\\\"']?\s*:\s*[\\\"'])"# + escapedDate
        + #".{0,900}?(?:mlguid|layoutGuid|layoutGUID|layoutId)(?:=|[\\\"']?\s*:\s*[\\\"'])"#
        + uuidCapture,
      #"(?:mlguid|layoutGuid|layoutGUID|layoutId)(?:=|[\\\"']?\s*:\s*[\\\"'])"# + uuidCapture
        + #".{0,900}?mldate(?:=|[\\\"']?\s*:\s*[\\\"'])"# + escapedDate,
      #"data-(?:ml)?date=[\\\"']"# + escapedDate + #"[\\\"'].{0,900}?data-(?:ml)?guid=[\\\"']"#
        + uuidCapture,
      #"data-(?:ml)?guid=[\\\"']"# + uuidCapture + #"[\\\"'].{0,900}?data-(?:ml)?date=[\\\"']"#
        + escapedDate,
      escapedDate
        + #".{0,900}?(?:mlguid|layout-guid|layoutguid|layout-id|layoutid)[^0-9A-Fa-f]{0,120}"#
        + uuidCapture,
    ]

    for pattern in strongPatterns {
      if let candidate = firstMatch(
        in: html,
        pattern: pattern,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
      ),
        candidate.lowercased() != menuGuid.lowercased()
      {
        return candidate
      }
    }

    let nsString = html as NSString
    guard let exactDateRegex = try? NSRegularExpression(pattern: escapedDate),
      let anyDateRegex = try? NSRegularExpression(pattern: #"\d{4}-\d{2}-\d{2}"#),
      let uuidRegex = try? NSRegularExpression(
        pattern: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#,
        options: [.caseInsensitive]
      )
    else {
      return nil
    }

    let exactMatches = exactDateRegex.matches(
      in: html,
      range: NSRange(location: 0, length: nsString.length)
    )

    // The campus-dining renderer can emit:
    //
    //     menu GUID -> YYYY-MM-DD -> layout GUID
    //
    // without labeling the final GUID as "mlguid". Search forward from
    // EVERY occurrence of the date, but stop at the next date token so a
    // date can never steal the following day's layout.
    var bestForwardCandidate: (guid: String, distance: Int)?

    for dateMatch in exactMatches {
      let afterDate = NSMaxRange(dateMatch.range)
      guard afterDate < nsString.length else { continue }

      let absoluteMaxEnd = min(nsString.length, afterDate + 3000)
      var searchEnd = absoluteMaxEnd

      let remainingRange = NSRange(
        location: afterDate,
        length: absoluteMaxEnd - afterDate
      )

      if let nextDate = anyDateRegex.firstMatch(in: html, range: remainingRange),
        nextDate.range.location > afterDate
      {
        searchEnd = min(searchEnd, nextDate.range.location)
      }

      guard searchEnd > afterDate else { continue }

      let forwardRange = NSRange(
        location: afterDate,
        length: searchEnd - afterDate
      )

      for uuidMatch in uuidRegex.matches(in: html, range: forwardRange) {
        let candidate = nsString.substring(with: uuidMatch.range)
        guard candidate.lowercased() != menuGuid.lowercased() else { continue }

        let distance = uuidMatch.range.location - afterDate
        if let best = bestForwardCandidate {
          if distance < best.distance {
            bestForwardCandidate = (candidate, distance)
          }
        } else {
          bestForwardCandidate = (candidate, distance)
        }
      }
    }

    if let candidate = bestForwardCandidate?.guid {
      return candidate
    }

    // Last-resort compatibility for deployments that emit the layout GUID
    // immediately before the date. Keep this tight and never use a static
    // fallback layout GUID.
    var bestBackwardCandidate: (guid: String, distance: Int)?

    for dateMatch in exactMatches {
      let windowStart = max(0, dateMatch.range.location - 1200)
      let windowRange = NSRange(
        location: windowStart,
        length: dateMatch.range.location - windowStart
      )

      for uuidMatch in uuidRegex.matches(in: html, range: windowRange) {
        let candidate = nsString.substring(with: uuidMatch.range)
        guard candidate.lowercased() != menuGuid.lowercased() else { continue }

        let distance = dateMatch.range.location - NSMaxRange(uuidMatch.range)
        if let best = bestBackwardCandidate {
          if distance < best.distance {
            bestBackwardCandidate = (candidate, distance)
          }
        } else {
          bestBackwardCandidate = (candidate, distance)
        }
      }
    }

    return bestBackwardCandidate?.guid
  }

  private func diningCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    return calendar
  }

  private func parseDiningDate(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = diningCalendar()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = diningCalendar().timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
  }

  private func extractMenuJSON(from html: String) throws -> String {
    // Pattern 1: Classic HTML data attribute string wrapper container
    let dataAttrPattern = #"data-menu-json=(?:\"|')(.+?)(?:\"|')"#
    if let matched = firstMatch(in: html, pattern: dataAttrPattern) {
      return htmlDecode(matched).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Pattern 2: Javascript assignments found directly on empty layout configurations or future dates
    let jsObjectPatterns = [
      #"menuData\s*=\s*([^;]+)"#,
      #"var\s+menuData\s*=\s*([^;]+)"#,
      #"_menuJson\s*=\s*(?:\"|')(.+?)(?:\"|')"#,
    ]

    for pattern in jsObjectPatterns {
      if let regex = try? NSRegularExpression(
        pattern: pattern, options: [.dotMatchesLineSeparators])
      {
        let range = NSRange(location: 0, length: (html as NSString).length)
        if let match = regex.firstMatch(in: html, options: [], range: range) {
          for i in 1..<match.numberOfRanges {
            let r = match.range(at: i)
            if r.location != NSNotFound {
              let captured = (html as NSString).substring(with: r)
              return htmlDecode(captured).trimmingCharacters(in: .whitespacesAndNewlines)
            }
          }
        }
      }
    }

    debugLog("No supported menu payload structure was found.")
    throw MenuServiceError.missingPayload
  }

  private func parseFlatItems(from jsonString: String) throws -> [[String: Any]] {
    let cleanInput =
      jsonString
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: #"\""#, with: "\"")

    guard let data = cleanInput.data(using: .utf8) else {
      throw MenuServiceError.invalidPayload
    }

    if let array = try? JSONSerialization.jsonObject(with: data, options: []) as? [Any] {
      return array.compactMap { $0 as? [String: Any] }
    }

    if let dictionary = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
    {
      if let itemsArray = dictionary["items"] as? [Any] {
        return itemsArray.compactMap { $0 as? [String: Any] }
      }
      return [dictionary]
    }

    throw MenuServiceError.invalidPayload
  }

  private func buildSnapshot(from rawItems: [[String: Any]], date: Date) -> MenuDaySnapshot {
    var mealPeriods: [MenuMealPeriod] = []
    var explicitMealPeriodIDs = Set<String>()

    var stationByID: [String: MenuStation] = [:]
    var stationOrder: [String] = []
    var recipesByStationID: [String: [MenuRecipe]] = [:]

    // Step 1: Track explicit Meal Periods (L1 markers)
    for item in rawItems {
      guard let itemType = stringValue(item["itemType"]), itemType == "sectionL1" else { continue }
      guard
        let guid = stringValue(item["sectionGuid"]) ?? stringValue(item["guid"])
          ?? stringValue(item["id"]),
        let name = stringValue(item["sectionName"]) ?? stringValue(item["name"])
      else { continue }

      if !explicitMealPeriodIDs.contains(guid) {
        explicitMealPeriodIDs.insert(guid)
        mealPeriods.append(MenuMealPeriod(id: guid, name: name))
      }
    }

    let absoluteFallbackID = "All-Day"
    let absoluteFallbackName = "Menu"

    // Step 2: Extract explicit stations (L2 markers)
    for item in rawItems {
      guard let itemType = stringValue(item["itemType"]), itemType == "sectionL2" else { continue }
      guard
        let guid = stringValue(item["sectionGuid"]) ?? stringValue(item["guid"])
          ?? stringValue(item["id"]),
        let name = stringValue(item["sectionName"]) ?? stringValue(item["name"])
      else { continue }

      var parentGuid = stringValue(item["parentGuid"]) ?? ""
      if parentGuid.isEmpty || parentGuid == "0" || !explicitMealPeriodIDs.contains(parentGuid) {
        parentGuid = mealPeriods.first?.id ?? absoluteFallbackID
      }

      let station = MenuStation(id: guid, name: name, mealPeriodID: parentGuid, recipes: [])
      if stationByID[guid] == nil {
        stationByID[guid] = station
        stationOrder.append(guid)
      }
    }

    // Step 3: Parse recipe listings to catch structural layout flips
    for item in rawItems {
      guard let itemType = stringValue(item["itemType"]), itemType == "recipe" else { continue }
      guard let name = stringValue(item["recipeName"]) ?? stringValue(item["name"]) else {
        continue
      }

      let stationID = stringValue(item["sectionGuid"]) ?? stringValue(item["parentGuid"]) ?? ""
      let recipeID =
        stringValue(item["recipeGuid"]) ?? stringValue(item["guid"]) ?? "\(stationID)-\(name)"
      let labels = extractLabels(from: item)

      // Handle inverted layout schemas (where structural layout transforms stations into L1 categories)
      if explicitMealPeriodIDs.contains(stationID) && stationByID[stationID] == nil {
        if let matchedL1Name = mealPeriods.first(where: { $0.id == stationID })?.name {
          let syntheticStation = MenuStation(
            id: stationID, name: matchedL1Name, mealPeriodID: stationID, recipes: [])
          stationByID[stationID] = syntheticStation
          if !stationOrder.contains(stationID) {
            stationOrder.append(stationID)
          }
        }
      }

      var targetStationID = stationID
      if stationByID[targetStationID] == nil {
        targetStationID = stationOrder.first ?? absoluteFallbackID
        if stationByID[targetStationID] == nil {
          let fallbackStation = MenuStation(
            id: absoluteFallbackID, name: "Main Kitchen",
            mealPeriodID: mealPeriods.first?.id ?? absoluteFallbackID, recipes: [])
          stationByID[absoluteFallbackID] = fallbackStation
          stationOrder.append(absoluteFallbackID)
        }
      }

      guard let resolvedStation = stationByID[targetStationID] else {
        debugLog("Skipping recipe \(name): unable to resolve a station.")
        continue
      }
      let recipe = MenuRecipe(
        id: recipeID,
        name: name,
        mealPeriodID: resolvedStation.mealPeriodID,
        stationID: targetStationID,
        stationName: resolvedStation.name,
        labels: labels
      )
      recipesByStationID[targetStationID, default: []].append(recipe)
    }

    let finalStations = stationOrder.compactMap { stationID -> MenuStation? in
      guard let baseStation = stationByID[stationID] else { return nil }
      let associatedRecipes = recipesByStationID[stationID] ?? []
      guard !associatedRecipes.isEmpty else { return nil }
      return MenuStation(
        id: baseStation.id, name: baseStation.name, mealPeriodID: baseStation.mealPeriodID,
        recipes: associatedRecipes)
    }

    if mealPeriods.isEmpty || finalStations.isEmpty {
      mealPeriods = [MenuMealPeriod(id: absoluteFallbackID, name: absoluteFallbackName)]
      let unifiedStations = stationOrder.compactMap { stationID -> MenuStation? in
        guard let base = stationByID[stationID] else { return nil }
        let items = recipesByStationID[stationID] ?? []
        if items.isEmpty { return nil }
        return MenuStation(
          id: base.id, name: base.name, mealPeriodID: absoluteFallbackID,
          recipes: items.map {
            MenuRecipe(
              id: $0.id, name: $0.name, mealPeriodID: absoluteFallbackID, stationID: $0.stationID,
              stationName: $0.stationName, labels: $0.labels)
          })
      }
      return MenuDaySnapshot(date: date, mealPeriods: mealPeriods, stations: unifiedStations)
    }

    let activeMealPeriodIDs = Set(finalStations.map { $0.mealPeriodID })
    let cleanMealPeriods = mealPeriods.filter { activeMealPeriodIDs.contains($0.id) }

    return MenuDaySnapshot(
      date: date,
      mealPeriods: cleanMealPeriods.isEmpty ? mealPeriods : cleanMealPeriods,
      stations: finalStations
    )
  }

  private func htmlDecode(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#34;", with: "\"")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&apos;", with: "'")
  }

  private func stringValue(_ value: Any?) -> String? {
    switch value {
    case let string as String: return string
    case let number as NSNumber: return number.stringValue
    default: return nil
    }
  }

  private func extractLabels(from item: [String: Any]) -> [String] {
    let likelyKeys = [
      "lbls", "labels", "label", "dietaryLabels", "dietary",
      "allergens", "allergenLabels", "icons", "badges", "attributes",
    ]

    var values: [String] = []
    for key in likelyKeys {
      values.append(contentsOf: stringArrayValue(item[key]) ?? [])
    }

    // Ten Kites has changed label field names before. Preserve any
    // string-bearing field whose key clearly describes dietary/allergen
    // metadata instead of silently discarding it.
    for (key, value) in item {
      let normalizedKey = key.lowercased()
      guard
        normalizedKey.contains("label")
          || normalizedKey.contains("allergen")
          || normalizedKey.contains("diet")
          || normalizedKey.contains("suitable")
          || normalizedKey.contains("contain")
      else {
        continue
      }
      values.append(contentsOf: stringArrayValue(value) ?? [])
    }

    var seen = Set<String>()
    return values.compactMap { raw in
      let cleaned = htmlDecode(raw)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleaned.isEmpty else { return nil }
      let key = cleaned.lowercased()
      guard seen.insert(key).inserted else { return nil }
      return cleaned
    }
  }

  private func stringArrayValue(_ value: Any?) -> [String]? {
    guard let value else { return nil }

    if let string = value as? String {
      let decoded = htmlDecode(string)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !decoded.isEmpty else { return [] }

      // Some deployments serialize lbls as a JSON string rather than
      // an actual JSON array.
      if let data = decoded.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data)
      {
        return stringArrayValue(json)
      }

      return
        decoded
        .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" })
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    if let array = value as? [Any] {
      return array.flatMap { stringArrayValue($0) ?? [] }
    }

    if let dict = value as? [String: Any] {
      let preferredKeys = [
        "label", "text", "name", "title", "value", "description",
        "alt", "displayName",
      ]

      for key in preferredKeys {
        if let result = stringArrayValue(dict[key]), !result.isEmpty {
          return result
        }
      }

      return dict.values.flatMap { stringArrayValue($0) ?? [] }
    }

    if let number = value as? NSNumber {
      return [number.stringValue]
    }

    return nil
  }

  private func firstMatch(
    in text: String,
    pattern: String,
    options: NSRegularExpression.Options = []
  ) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
      return nil
    }
    let range = NSRange(location: 0, length: (text as NSString).length)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
      match.numberOfRanges > 1
    else { return nil }
    return (text as NSString).substring(with: match.range(at: 1))
  }

  private func firstUUID(in text: String, excluding excluded: String? = nil) -> String? {
    let pattern = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let range = NSRange(location: 0, length: (text as NSString).length)
    let matches = regex.matches(in: text, options: [], range: range)
    for match in matches {
      let value = (text as NSString).substring(with: match.range)
      if value.lowercased() != excluded?.lowercased() {
        return value
      }
    }
    return nil
  }
}

enum MenuServiceError: LocalizedError {
  case invalidURL
  case invalidResponse
  case invalidEncoding
  case missingPayload
  case invalidPayload
  case incompletePayload
  case noDatesFound

  var errorDescription: String? {
    switch self {
    case .invalidURL: "The dining menu URL could not be created."
    case .invalidResponse: "The dining menu server returned an unexpected response."
    case .invalidEncoding: "The dining menu page could not be decoded."
    case .missingPayload: "The dining menu payload was not found."
    case .invalidPayload: "The dining menu payload could not be parsed."
    case .incompletePayload: "The dining menu response was incomplete."
    case .noDatesFound: "No dining dates were found on the menu page."
    }
  }
}
