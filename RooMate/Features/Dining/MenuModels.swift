import Foundation

struct MenuDateEntry: Identifiable, Hashable, Codable {
  let date: Date
  let dateString: String
  let layoutGuid: String
  let menuGuid: String

  var id: String { "\(dateString)-\(layoutGuid)" }

  var isToday: Bool {
    Calendar.current.isDateInToday(date)
  }

  var displayTitle: String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateFormat = "EEE, MMM d"
    return formatter.string(from: date)
  }
}

struct MenuMealPeriod: Identifiable, Hashable, Codable {
  let id: String
  let name: String
}

struct MenuStation: Identifiable, Hashable, Codable {
  let id: String
  let name: String
  let mealPeriodID: String
  let recipes: [MenuRecipe]
}

struct MenuRecipe: Identifiable, Hashable, Codable {
  let id: String
  let name: String
  let mealPeriodID: String
  let stationID: String
  let stationName: String
  let labels: [String]

  var lifestyleTags: Set<MenuLifestyleTag> {
    MenuLabelMatcher.lifestyleTags(in: labels)
  }

  var coreAllergens: Set<MenuCoreAllergen> {
    MenuLabelMatcher.coreAllergens(in: labels)
  }

  var displayBadges: [MenuBadge] {
    let lifestyleBadges =
      lifestyleTags
      .sorted { $0.sortOrder < $1.sortOrder }
      .map { MenuBadge(title: $0.displayName, symbol: $0.symbol, kind: .lifestyle) }

    let allergenBadges =
      coreAllergens
      .sorted { $0.sortOrder < $1.sortOrder }
      .map { MenuBadge(title: $0.displayName, symbol: $0.symbol, kind: .allergen) }

    return lifestyleBadges + allergenBadges
  }
}

struct MenuDaySnapshot: Hashable, Codable {
  let date: Date
  let mealPeriods: [MenuMealPeriod]
  let stations: [MenuStation]

  func stations(for mealPeriodID: String) -> [MenuStation] {
    stations.filter { $0.mealPeriodID == mealPeriodID }
  }

  func visibleStations(for mealPeriodID: String, filters: MenuFilterState) -> [MenuStation] {
    stations(for: mealPeriodID).compactMap { station in
      let visibleRecipes = station.recipes.filter { filters.matches($0) }
      guard !visibleRecipes.isEmpty else { return nil }
      return MenuStation(
        id: station.id,
        name: station.name,
        mealPeriodID: station.mealPeriodID,
        recipes: visibleRecipes
      )
    }
  }
}

enum MenuLifestyleTag: String, CaseIterable, Identifiable, Hashable {
  case vegetarian
  case vegan
  case beWell

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .vegetarian: "Vegetarian"
    case .vegan: "Vegan"
    case .beWell: "BeWell"
    }
  }

  var symbol: String {
    switch self {
    case .vegetarian: "leaf"
    case .vegan: "leaf.fill"
    case .beWell: "heart.fill"
    }
  }

  var sortOrder: Int {
    switch self {
    case .vegetarian: 0
    case .vegan: 1
    case .beWell: 2
    }
  }

  var matchTokens: [String] {
    switch self {
    case .vegetarian: ["vegetarian", "vegetarians"]
    case .vegan: ["vegan", "vegans"]
    case .beWell: ["bewell", "be well"]
    }
  }
}

enum MenuCoreAllergen: String, CaseIterable, Identifiable, Hashable {
  case eggs
  case milk
  case soy
  case wheat
  case treeNuts
  case peanuts
  case fish
  case shellfish
  case sesameSeeds
  case gluten

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .eggs: "Eggs"
    case .milk: "Milk"
    case .soy: "Soy"
    case .wheat: "Wheat"
    case .treeNuts: "Tree Nuts"
    case .peanuts: "Peanuts"
    case .fish: "Fish"
    case .shellfish: "Shellfish"
    case .sesameSeeds: "Sesame Seeds"
    case .gluten: "Gluten"
    }
  }

  // Provide a more specific SF Symbol per allergen so UI shows distinct icons
  var symbol: String {
    switch self {
    case .eggs: return "oval.portrait.fill"
    case .milk: return "cup.and.saucer.fill"
    case .soy: return "leaf"
    case .wheat: return "leaf"
    case .treeNuts: return "leaf.circle"
    case .peanuts: return "circle.grid.3x3"
    case .fish: return "fish.fill"
    case .shellfish: return "tortoise.fill"
    case .sesameSeeds: return "circle.grid.3x3.fill"
    case .gluten: return "g.circle"
    }
  }

  var sortOrder: Int {
    switch self {
    case .eggs: 0
    case .milk: 1
    case .soy: 2
    case .wheat: 3
    case .treeNuts: 4
    case .peanuts: 5
    case .fish: 6
    case .shellfish: 7
    case .sesameSeeds: 8
    case .gluten: 9
    }
  }

  var matchTokens: [String] {
    switch self {
    case .eggs: ["eggs"]
    case .milk: ["milk", "dairy"]
    case .soy: ["soy"]
    case .wheat: ["wheat"]
    case .treeNuts: ["treenuts", "tree nuts", "treenut"]
    case .peanuts: ["peanuts", "peanut"]
    case .fish: ["fish"]
    case .shellfish: ["shellfish"]
    case .sesameSeeds: ["sesameseeds", "sesame seeds", "sesame seed", "sesame"]
    case .gluten: ["gluten"]
    }
  }
}

struct MenuBadge: Hashable {
  enum Kind: Hashable {
    case lifestyle
    case allergen
  }

  let title: String
  let symbol: String
  let kind: Kind
}

enum MenuFilterItem: Hashable {
  case lifestyle(MenuLifestyleTag)
  case allergen(MenuCoreAllergen)

  var id: String {
    switch self {
    case .lifestyle(let tag): "lifestyle-\(tag.rawValue)"
    case .allergen(let allergen): "allergen-\(allergen.rawValue)"
    }
  }

  var title: String {
    switch self {
    case .lifestyle(let tag): tag.displayName
    case .allergen(let allergen): allergen.displayName
    }
  }

  var symbol: String {
    switch self {
    case .lifestyle(let tag): tag.symbol
    case .allergen(let allergen): allergen.symbol
    }
  }
}

struct MenuFilterState: Hashable {
  var lifestyleTags: Set<MenuLifestyleTag> = []
  var excludedAllergens: Set<MenuCoreAllergen> = []

  func contains(_ item: MenuFilterItem) -> Bool {
    switch item {
    case .lifestyle(let tag):
      return lifestyleTags.contains(tag)
    case .allergen(let allergen):
      return excludedAllergens.contains(allergen)
    }
  }

  mutating func toggle(_ item: MenuFilterItem) {
    switch item {
    case .lifestyle(let tag):
      if lifestyleTags.contains(tag) {
        lifestyleTags.remove(tag)
      } else {
        lifestyleTags.insert(tag)
      }
    case .allergen(let allergen):
      if excludedAllergens.contains(allergen) {
        excludedAllergens.remove(allergen)
      } else {
        excludedAllergens.insert(allergen)
      }
    }
  }

  func matches(_ recipe: MenuRecipe) -> Bool {
    let recipeLifestyle = recipe.lifestyleTags
    let recipeAllergens = recipe.coreAllergens

    if !lifestyleTags.isEmpty, lifestyleTags.isDisjoint(with: recipeLifestyle) {
      return false
    }

    if !excludedAllergens.isDisjoint(with: recipeAllergens) {
      return false
    }

    return true
  }

  var isFiltering: Bool {
    !lifestyleTags.isEmpty || !excludedAllergens.isEmpty
  }
}

enum MenuLabelMatcher {
  static func lifestyleTags(in labels: [String]) -> Set<MenuLifestyleTag> {
    let normalizedLabels = Set(labels.map(normalize))
    return Set(
      MenuLifestyleTag.allCases.filter { tag in
        normalizedLabels.contains { label in
          tag.matchTokens.contains { token in
            label.contains(normalize(token))
          }
        }
      })
  }

  static func coreAllergens(in labels: [String]) -> Set<MenuCoreAllergen> {
    let normalizedLabels = Set(labels.map(normalize))
    return Set(
      MenuCoreAllergen.allCases.filter { allergen in
        normalizedLabels.contains { label in
          allergen.matchTokens.contains { token in
            label.contains(normalize(token))
          }
        }
      })
  }

  nonisolated private static func normalize(_ value: String) -> String {
    value
      .lowercased()
      .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
  }
}
