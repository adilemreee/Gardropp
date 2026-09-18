import CoreLocation
import Foundation
import Observation

/// Current conditions for the home screen, from Open-Meteo (no key needed).
/// Weather is a nice-to-have: if location is refused the app simply hides the chip.
@MainActor
@Observable
final class WeatherService: NSObject {

    struct Conditions {
        var temperature: Double
        var low: Double
        var high: Double
        var code: Int

        var symbol: String {
            switch code {
            case 0, 1: "sun.max"
            case 2: "cloud.sun"
            case 3: "cloud"
            case 45, 48: "cloud.fog"
            case 51...67, 80...82: "cloud.rain"
            case 71...77, 85, 86: "cloud.snow"
            case 95...99: "cloud.bolt.rain"
            default: "cloud"
            }
        }

        var summary: String {
            switch code {
            case 0, 1: String(localized: "clear")
            case 2: String(localized: "partly cloudy")
            case 3: String(localized: "overcast")
            case 45, 48: String(localized: "foggy")
            case 51...67, 80...82: String(localized: "rainy")
            case 71...77, 85, 86: String(localized: "snowy")
            case 95...99: String(localized: "stormy")
            default: String(localized: "mild")
            }
        }
    }

    private(set) var conditions: Conditions?
    private(set) var isLoading = false

    private let manager = CLLocationManager()
    private var lastFetch: Date?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refresh() {
        // One fetch per half hour is plenty for a temperature chip.
        if let lastFetch, Date.now.timeIntervalSince(lastFetch) < 1800, conditions != nil { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            isLoading = true
            manager.requestLocation()
        default:
            conditions = nil
        }
    }

    private func load(for coordinate: CLLocationCoordinate2D) async {
        defer { isLoading = false }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_min,temperature_2m_max"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let temperature = current["temperature_2m"] as? Double else { return }
            let daily = json["daily"] as? [String: Any]
            let lows = daily?["temperature_2m_min"] as? [Double]
            let highs = daily?["temperature_2m_max"] as? [Double]
            conditions = Conditions(
                temperature: temperature,
                low: lows?.first ?? temperature,
                high: highs?.first ?? temperature,
                code: current["weather_code"] as? Int ?? 0
            )
            lastFetch = .now
        } catch {
            conditions = nil
        }
    }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in refresh() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in await load(for: coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in isLoading = false }
    }
}

extension WeatherService.Conditions {
    func formatted(celsius: Bool) -> String {
        celsius ? "\(Int(temperature.rounded()))°" : "\(Int((temperature * 9 / 5 + 32).rounded()))°"
    }

    func rangeFormatted(celsius: Bool) -> String {
        let convert: (Double) -> Int = { celsius ? Int($0.rounded()) : Int(($0 * 9 / 5 + 32).rounded()) }
        return "\(convert(low))° – \(convert(high))°"
    }
}
