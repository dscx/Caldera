import Foundation

/// Persists which sensor keys the user has chosen to pin to the menu bar.
final class PreferencesStore: ObservableObject {
    private static let visibleKeysDefaultsKey = "TempBar.visibleSensorKeys"
    private static let hasChosenDefaultDefaultsKey = "TempBar.hasChosenDefault"
    private static let temperatureUnitDefaultsKey = "TempBar.temperatureUnit"
    private static let displayModeDefaultsKey = "TempBar.displayMode"
    private static let pollIntervalDefaultsKey = "TempBar.pollIntervalSeconds"
    private static let defaultAlertThresholdDefaultsKey = "TempBar.defaultAlertThresholdCelsius"
    private static let customAlertThresholdsDefaultsKey = "TempBar.customAlertThresholdsCelsius"
    private static let collapsedSectionsDefaultsKey = "TempBar.collapsedSections"

    static let pollIntervalRange: ClosedRange<Double> = 1...30
    static let defaultAlertThresholdCelsius: Double = 85
    static let alertThresholdRange: ClosedRange<Double> = 40...110

    @Published var visibleKeys: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(visibleKeys), forKey: Self.visibleKeysDefaultsKey)
        }
    }

    @Published var temperatureUnit: TemperatureUnit {
        didSet {
            UserDefaults.standard.set(temperatureUnit.rawValue, forKey: Self.temperatureUnitDefaultsKey)
        }
    }

    @Published var displayMode: DisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: Self.displayModeDefaultsKey)
        }
    }

    @Published var pollIntervalSeconds: Double {
        didSet {
            UserDefaults.standard.set(pollIntervalSeconds, forKey: Self.pollIntervalDefaultsKey)
        }
    }

    /// Canonical Celsius threshold used for any sensor that doesn't have its
    /// own custom threshold below.
    @Published var defaultAlertThreshold: Double {
        didSet {
            UserDefaults.standard.set(defaultAlertThreshold, forKey: Self.defaultAlertThresholdDefaultsKey)
        }
    }

    /// Per-sensor overrides (SMC key -> Celsius threshold), for sensors the
    /// user has explicitly customized. Anything not in here uses `defaultAlertThreshold`.
    @Published var customAlertThresholds: [String: Double] {
        didSet {
            UserDefaults.standard.set(customAlertThresholds, forKey: Self.customAlertThresholdsDefaultsKey)
        }
    }

    /// Section/subgroup labels (e.g. "Temperatures", "CPU", "TD") the user
    /// has collapsed in the popover list.
    @Published var collapsedSections: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(collapsedSections), forKey: Self.collapsedSectionsDefaultsKey)
        }
    }

    init() {
        let saved = UserDefaults.standard.array(forKey: Self.visibleKeysDefaultsKey) as? [String]
        visibleKeys = Set(saved ?? [])

        let savedUnit = UserDefaults.standard.string(forKey: Self.temperatureUnitDefaultsKey)
            .flatMap(TemperatureUnit.init(rawValue:))
        temperatureUnit = savedUnit ?? .celsius

        let savedMode = UserDefaults.standard.string(forKey: Self.displayModeDefaultsKey)
            .flatMap(DisplayMode.init(rawValue:))
        displayMode = savedMode ?? .separate

        let savedInterval = UserDefaults.standard.object(forKey: Self.pollIntervalDefaultsKey) as? Double
        pollIntervalSeconds = savedInterval ?? 2.0

        let savedDefaultThreshold = UserDefaults.standard.object(forKey: Self.defaultAlertThresholdDefaultsKey) as? Double
        defaultAlertThreshold = savedDefaultThreshold ?? Self.defaultAlertThresholdCelsius

        customAlertThresholds = UserDefaults.standard.dictionary(forKey: Self.customAlertThresholdsDefaultsKey) as? [String: Double] ?? [:]

        let savedCollapsed = UserDefaults.standard.array(forKey: Self.collapsedSectionsDefaultsKey) as? [String]
        collapsedSections = Set(savedCollapsed ?? [])
    }

    func toggle(_ key: String) {
        if visibleKeys.contains(key) {
            visibleKeys.remove(key)
        } else {
            visibleKeys.insert(key)
        }
    }

    /// On first launch only, pin one sensor automatically so the menu bar
    /// isn't empty before the user has opened the picker. Does nothing on
    /// later launches, even if the user has since deselected everything.
    func selectFirstSensorIfFirstLaunch(_ key: String) {
        guard !UserDefaults.standard.bool(forKey: Self.hasChosenDefaultDefaultsKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hasChosenDefaultDefaultsKey)
        if visibleKeys.isEmpty {
            visibleKeys = [key]
        }
    }

    func alertThreshold(for key: String) -> Double {
        customAlertThresholds[key] ?? defaultAlertThreshold
    }

    func setCustomAlertThreshold(_ value: Double, for key: String) {
        customAlertThresholds[key] = value
    }

    func hasCustomAlertThreshold(for key: String) -> Bool {
        customAlertThresholds[key] != nil
    }

    func resetAlertThreshold(for key: String) {
        customAlertThresholds.removeValue(forKey: key)
    }

    func isCollapsed(_ sectionKey: String) -> Bool {
        collapsedSections.contains(sectionKey)
    }

    func toggleCollapsed(_ sectionKey: String) {
        if collapsedSections.contains(sectionKey) {
            collapsedSections.remove(sectionKey)
        } else {
            collapsedSections.insert(sectionKey)
        }
    }
}
