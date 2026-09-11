import Foundation

enum TemperatureUnit: String {
    case celsius
    case fahrenheit

    func convert(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius: return celsius
        case .fahrenheit: return celsius * 9.0 / 5.0 + 32.0
        }
    }

    var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }
}
