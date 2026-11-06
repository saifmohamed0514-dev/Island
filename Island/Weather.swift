import SwiftUI
import Combine

@MainActor final class IslandWeather: ObservableObject {
    struct Place: Codable { var name: String; var latitude: Double; var longitude: Double; var country: String? }
    struct Search: Codable { var results: [Place]? }
    struct Forecast: Codable {
        struct Current: Codable { var temperature_2m: Double; var relative_humidity_2m: Double; var apparent_temperature: Double; var weather_code: Int; var wind_speed_10m: Double }
        struct Daily: Codable { var time: [String]; var temperature_2m_max: [Double]; var temperature_2m_min: [Double] }
        var current: Current; var daily: Daily
    }
    @Published var forecast: Forecast?
    @Published var place: Place?
    @Published var error: String?
    @Published var loading = false
    @Published var updated: Date?
    func search(city: String, fahrenheit: Bool) async {
        guard !loading, !city.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        loading = true; error = nil; defer { loading = false }
        do {
            var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            components.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"), URLQueryItem(name: "language", value: "en")]
            let result: Search = try await fetch(components.url!)
            guard let found = result.results?.first else { error = "No matching city found."; return }
            var request = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            request.queryItems = ["latitude": String(found.latitude), "longitude": String(found.longitude), "current": "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m", "daily": "temperature_2m_max,temperature_2m_min", "temperature_unit": fahrenheit ? "fahrenheit" : "celsius", "timezone": "auto"].map { URLQueryItem(name: $0.key, value: $0.value) }
            let data: Forecast = try await fetch(request.url!)
            forecast = data; place = found; updated = Date()
        } catch { self.error = "Weather unavailable. Check your connection and try again." }
    }
    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url); request.timeoutInterval = 15
        let (data,response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
    static func condition(_ code: Int) -> String {
        switch code { case 0: return "Clear"; case 1...3: return "Partly cloudy"; case 45,48: return "Fog"; case 51...67: return "Rain"; case 71...77,85,86: return "Snow"; case 80...82: return "Showers"; case 95...99: return "Thunderstorms"; default: return "Weather" }
    }
}
struct IslandWeatherView: View {
    @StateObject var weather = IslandWeather()
    @AppStorage("island.weather.city") var city = ""
    @AppStorage("island.weather.fahrenheit") var fahrenheit = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { TextField("City", text: $city).textFieldStyle(.roundedBorder); Toggle("°F", isOn: $fahrenheit).toggleStyle(.checkbox); Button(weather.loading ? "Loading…" : "Get forecast") { Task { await weather.search(city: city, fahrenheit: fahrenheit) } }.disabled(weather.loading) }
            if let current = weather.forecast?.current {
                HStack(spacing: 20) {
                    Text("\(Int(current.temperature_2m.rounded()))°").font(.system(size: 35,weight: .medium,design: .rounded))
                    VStack(alignment: .leading) { Text(weather.place?.name ?? city).font(.headline); Text(IslandWeather.condition(current.weather_code)).foregroundStyle(.secondary) }
                    Spacer()
                    VStack(alignment: .trailing) { Text("Feels \(Int(current.apparent_temperature.rounded()))°"); Text("Humidity \(Int(current.relative_humidity_2m))% · Wind \(Int(current.wind_speed_10m)) km/h").font(.caption).foregroundStyle(.secondary) }
                }
                if let daily = weather.forecast?.daily {
                    HStack { ForEach(Array(daily.time.prefix(7).enumerated()), id: \.offset) { index, day in
                        if index < daily.temperature_2m_max.count && index < daily.temperature_2m_min.count { VStack { Text(String(day.suffix(5))); Text("\(Int(daily.temperature_2m_max[index]))° / \(Int(daily.temperature_2m_min[index]))°") }.font(.caption).frame(maxWidth: .infinity) }
                    } }
                }
            }
            if let error = weather.error { Text(error).foregroundStyle(.orange) }
            Link("Weather data: Open-Meteo · City searches are sent to Open-Meteo", destination: URL(string:"https://open-meteo.com/")!).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
