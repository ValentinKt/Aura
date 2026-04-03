import CoreLocation
import Foundation
import os

private struct WeatherResponse: Codable {
    struct Current: Codable {
        let weather_code: Int
        let is_day: Int
        let wind_speed_10m: Double
    }

    let current: Current
}

@MainActor
final class WeatherEngine: NSObject, CLLocationManagerDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.valentinkt.Aura", category: "Weather")
    private let locationManager = CLLocationManager()
    private let moodEngine: MoodEngine
    private let settingsEngine: SettingsEngine
    private var refreshTask: Task<Void, Never>?
    private var retryCount = 0
    private let maxRetries = 3

    /// The current state of weather synchronization.
    private(set) var state: WeatherState = .idle

    /// Last successfully fetched weather condition.
    private(set) var lastCondition: WeatherCondition?

    init(moodEngine: MoodEngine, settingsEngine: SettingsEngine) {
        self.moodEngine = moodEngine
        self.settingsEngine = settingsEngine
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers // Energy efficient
        locationManager.distanceFilter = 5000 // Only update if moved 5km
    }

    func start() {
        guard settingsEngine.loadSettings().weatherSyncEnabled else { return }

        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            logger.error("Location access denied or restricted")
            state = .failure(.unauthorized)
            return
        case .authorizedAlways:
            locationManager.requestLocation()
        @unknown default:
            break
        }

        scheduleRefresh()
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        state = .idle
        retryCount = 0
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        let waitSeconds = nextRefreshDelay()
        refreshTask = Task(priority: .background) { [weak self] in
            await AuraBackgroundActor.sleep(for: .seconds(waitSeconds))
            await AuraBackgroundActor.waitUntilRenderingActive()
            guard let self, !Task.isCancelled else { return }

            let isEnabled = await MainActor.run {
                self.settingsEngine.loadSettings().weatherSyncEnabled
            }

            guard isEnabled else { return }
            await MainActor.run {
                self.locationManager.requestLocation()
            }
        }
    }

    private func nextRefreshDelay() -> UInt64 {
        retryCount > 0 ? UInt64(pow(2.0, Double(retryCount)) * 30) : 1800
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            logger.error("Location unavailable")
            state = .failure(.locationUnavailable)
            return
        }

        Task {
            await fetchWeather(for: location.coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let weatherError: WeatherError
        if let clError = error as? CLError {
            switch clError.code {
            case .denied: weatherError = .unauthorized
            case .locationUnknown: weatherError = .locationUnavailable
            default: weatherError = .networkError(error.localizedDescription)
            }
        } else {
            weatherError = .networkError(error.localizedDescription)
        }

        state = .failure(weatherError)
        logger.error("Location manager failed: \(weatherError.localizedDescription, privacy: .public)")
        handleRetry()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    // MARK: - Weather Fetching

    private func fetchWeather(for coordinate: CLLocationCoordinate2D) async {
        state = .loading

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&current=weather_code,is_day,wind_speed_10m&timezone=auto"
        guard let url = URL(string: urlString) else {
            logger.error("Invalid URL: \(urlString, privacy: .public)")
            state = .failure(.invalidURL)
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                logger.error("Unknown HTTP error or invalid response")
                state = .failure(.unknown)
                return
            }

            if let (condition, extraLayers) = decodeCondition(from: data) {
                lastCondition = condition
                state = .success(condition)
                retryCount = 0
                scheduleRefresh()

                if let mood = moodEngine.moods.first(where: { $0.id == mapMoodID(for: condition) }) {
                    await applyWeatherAdjustedMood(mood, extras: extraLayers)
                }
            } else {
                logger.error("Failed to decode weather condition")
                state = .failure(.unknown)
                handleRetry()
            }
        } catch {
            state = .failure(.networkError(error.localizedDescription))
            logger.error("Failed to fetch weather: \(error.localizedDescription, privacy: .public)")
            handleRetry()
        }
    }

    private func handleRetry() {
        if retryCount < maxRetries {
            retryCount += 1
            scheduleRefresh() // Shorter wait for retry
        } else {
            retryCount = 0 // Give up after max retries
        }
    }

    private func applyWeatherAdjustedMood(_ mood: Mood, extras: [String: Float]) async {
        var adjustedMood = mood
        // Deep copy the layer mix to avoid modifying the original mood preset
        var adjustedMix = mood.layerMix

        for (layer, offset) in extras {
            let current = adjustedMix[layer] ?? 0
            adjustedMix[layer] = min(1.0, max(0.0, current + offset))
        }

        adjustedMood.layerMix = adjustedMix
        await moodEngine.applyMood(adjustedMood)
    }

    private func decodeCondition(from data: Data) -> (WeatherCondition, [String: Float])? {
        do {
            let response = try JSONDecoder().decode(WeatherResponse.self, from: data)
            let current = response.current
            let weatherCode = current.weather_code
            let windSpeed = current.wind_speed_10m
            let isDay = current.is_day == 1

            var extras: [String: Float] = [:]

            // Wind speed takes precedence for "windy" condition
            if windSpeed > 30 {
                extras["wind"] = 0.3
                return (.windy, extras)
            }

            // Mapping based on WMO Weather interpretation codes (WW)
            // https://open-meteo.com/en/docs
            switch weatherCode {
            case 0: // Clear sky
                return (isDay ? .clearDay : .clearNight, extras)

            case 1, 2, 3: // Mainly clear, partly cloudy, and overcast
                return (.cloudy, extras)

            case 45, 48: // Fog and depositing rime fog
                return (.cloudy, extras)

            case 51, 53, 55: // Drizzle: Light, moderate, and dense intensity
                extras["rain"] = 0.2
                return (.rain, extras)

            case 61, 63, 65: // Rain: Slight, moderate and heavy intensity
                extras["rain"] = 0.4
                return (.rain, extras)

            case 71, 73, 75: // Snow fall: Slight, moderate, and heavy intensity
                extras["wind"] = 0.2
                return (.snow, extras)

            case 80, 81, 82: // Rain showers: Slight, moderate, and violent
                extras["rain"] = 0.5
                return (.rain, extras)

            case 95, 96, 99: // Thunderstorm: Slight, moderate, and heavy
                extras["thunder"] = 0.4
                extras["rain"] = 0.2
                return (.thunderstorm, extras)

            default:
                return (.cloudy, extras)
            }
        } catch {
            logger.error("Decoding error: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func mapMoodID(for condition: WeatherCondition) -> String {
        switch condition {
        case .clearDay: return "focus"
        case .clearNight: return "sleep"
        case .cloudy: return "calm"
        case .rain: return "deepwork"
        case .thunderstorm: return "meditation"
        case .snow: return "calm"
        case .windy: return "energy"
        }
    }
}
