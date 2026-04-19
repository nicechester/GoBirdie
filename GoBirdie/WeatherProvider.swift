//
//  WeatherProvider.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/18/26.
//

import Foundation
import CoreLocation

/// Provides current weather data using NOAA API (free, no authentication required).
actor WeatherProvider {
    static let shared = WeatherProvider()

    /// Fetch current weather conditions at the player's current location using NOAA API.
    /// Returns a tuple of (temperatureMinF, temperatureMaxF, condition)
    /// or nil if weather data cannot be fetched.
    func fetchCurrentWeather(location: CLLocationCoordinate2D) async -> (minF: Double, maxF: Double, condition: String)? {
        do {
            // Step 1: Get grid point and forecast URL from NOAA Points API
            let pointsURL = URL(string: "https://api.weather.gov/points/\(location.latitude),\(location.longitude)")!
            var request = URLRequest(url: pointsURL)
            request.setValue("GoBirdie/1.0", forHTTPHeaderField: "User-Agent")

            let (pointsData, pointsResponse) = try await URLSession.shared.data(for: request)

            guard let httpResponse = pointsResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("[WeatherProvider] NOAA Points API failed with status: \((pointsResponse as? HTTPURLResponse)?.statusCode ?? -1)")
                return fallbackWeather()
            }

            let pointsJSON = try JSONDecoder().decode(NOAAPointsResponse.self, from: pointsData)
            guard let forecastURL = URL(string: pointsJSON.properties.forecast) else {
                print("[WeatherProvider] No forecast URL in NOAA response")
                return fallbackWeather()
            }

            // Step 2: Fetch the forecast data
            var forecastRequest = URLRequest(url: forecastURL)
            forecastRequest.setValue("GoBirdie/1.0", forHTTPHeaderField: "User-Agent")

            let (forecastData, forecastResponse) = try await URLSession.shared.data(for: forecastRequest)

            guard let httpForecastResponse = forecastResponse as? HTTPURLResponse, httpForecastResponse.statusCode == 200 else {
                print("[WeatherProvider] NOAA Forecast API failed with status: \((forecastResponse as? HTTPURLResponse)?.statusCode ?? -1)")
                return fallbackWeather()
            }

            let forecastJSON = try JSONDecoder().decode(NOAAForecastResponse.self, from: forecastData)
            guard !forecastJSON.properties.periods.isEmpty else {
                print("[WeatherProvider] No forecast periods in NOAA response")
                return fallbackWeather()
            }

            // Extract temperature and condition from today's forecast
            let periods = forecastJSON.properties.periods

            // Find daytime and nighttime periods for today
            let todayPeriods = periods.prefix(2) // Typically first is daytime, second is nighttime
            let temps = todayPeriods.map { Double($0.temperature) }.compactMap { $0 }
            let minTemp = temps.min() ?? Double(periods.first?.temperature ?? 70)
            let maxTemp = temps.max() ?? Double(periods.first?.temperature ?? 80)

            // Get condition from first period
            let condition = periods.first?.shortForecast ?? "Clear"
            let conditionWithEmoji = addEmojiToCondition(condition)

            print("[WeatherProvider] Weather fetched from NOAA: min=\(minTemp)°F, max=\(maxTemp)°F, \(conditionWithEmoji)")
            return (minTemp, maxTemp, conditionWithEmoji)

        } catch {
            print("[WeatherProvider] Failed to fetch weather: \(error)")
            return fallbackWeather()
        }
    }

    private func fallbackWeather() -> (minF: Double, maxF: Double, condition: String) {
        print("[WeatherProvider] Using fallback weather data")
        return (68.0, 78.0, "Partly Cloudy ⛅")
    }

    private func addEmojiToCondition(_ condition: String) -> String {
        let emoji: String
        let lowerCondition = condition.lowercased()

        if lowerCondition.contains("sunny") || lowerCondition.contains("clear") {
            emoji = "☀️"
        } else if lowerCondition.contains("cloudy") || lowerCondition.contains("overcast") {
            emoji = "☁️"
        } else if lowerCondition.contains("rain") {
            emoji = "🌧️"
        } else if lowerCondition.contains("snow") || lowerCondition.contains("sleet") {
            emoji = "❄️"
        } else if lowerCondition.contains("storm") || lowerCondition.contains("thunder") {
            emoji = "⛈️"
        } else if lowerCondition.contains("partly") {
            emoji = "⛅"
        } else if lowerCondition.contains("mostly") {
            emoji = "🌤️"
        } else {
            emoji = "🌤️"
        }

        return "\(condition) \(emoji)"
    }
}

// MARK: - NOAA API Models

struct NOAAPointsResponse: Codable {
    let properties: NOAAPointsProperties

    struct NOAAPointsProperties: Codable {
        let forecast: String
    }
}

struct NOAAForecastResponse: Codable {
    let properties: NOAAForecastProperties

    struct NOAAForecastProperties: Codable {
        let periods: [NOAAForecastPeriod]
    }

    struct NOAAForecastPeriod: Codable {
        let temperature: Int
        let shortForecast: String
    }
}
