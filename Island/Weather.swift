import SwiftUI
import Combine
import Charts
import UniformTypeIdentifiers

@MainActor final class IslandWeather: ObservableObject {
    static let shared = IslandWeather()
    struct Place: Codable { var name: String; var latitude: Double; var longitude: Double; var country: String? }
    struct Search: Codable { var results: [Place]? }
    struct Forecast: Codable {
        struct Current: Codable { var temperature_2m: Double; var relative_humidity_2m: Double; var apparent_temperature: Double; var weather_code: Int; var wind_speed_10m: Double;var surface_pressure:Double? }
        struct Hourly:Codable { var time:[String];var temperature_2m:[Double];var precipitation_probability:[Double]? }
        struct Daily: Codable { var time: [String]; var temperature_2m_max: [Double]; var temperature_2m_min: [Double];var sunrise:[String]?;var sunset:[String]?;var uv_index_max:[Double]? }
        var current: Current; var daily: Daily;var hourly:Hourly?;var timezone:String?
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
            request.queryItems = ["latitude": String(found.latitude), "longitude": String(found.longitude), "current": "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,surface_pressure", "daily": "temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max", "hourly":"temperature_2m,precipitation_probability", "temperature_unit": "celsius", "timezone": "auto"].map { URLQueryItem(name: $0.key, value: $0.value) }
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
    struct Hour:Identifiable { let date:Date;let temperature:Double;let rain:Double?;var id:Date { date } }
    var hours:[Hour] {
        guard let hourly=forecast?.hourly else { return [] }
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="yyyy-MM-dd'T'HH:mm";formatter.timeZone=TimeZone(identifier:forecast?.timezone ?? "") ?? .current
        return hourly.time.enumerated().compactMap { index,value in
            guard index < hourly.temperature_2m.count,let date=formatter.date(from:value),date >= Date().addingTimeInterval(-3600) else { return nil }
            return Hour(date:date,temperature:hourly.temperature_2m[index],rain:hourly.precipitation_probability.flatMap { index < $0.count ? $0[index] : nil })
        }.prefix(24).map { $0 }
    }
    static func condition(_ code: Int) -> String {
        switch code { case 0: return "Clear"; case 1...3: return "Partly cloudy"; case 45,48: return "Fog"; case 51...67: return "Rain"; case 71...77,85,86: return "Snow"; case 80...82: return "Showers"; case 95...99: return "Thunderstorms"; default: return "Weather" }
    }
}
struct IslandWeatherView: View {
    @ObservedObject var weather = IslandWeather.shared
    @AppStorage("island.weather.city") var city = ""
    @AppStorage("island.weather.fahrenheit") var fahrenheit = false
    @AppStorage("island.weather.photo") var photo=""
    @State var photoError:String?
    var photoURL:URL? { guard !photo.isEmpty,!photo.contains("/"),!photo.contains("..") else { return nil };return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Island/Weather").appendingPathComponent(photo) }
    func choosePhoto() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.image];guard panel.runModal() == .OK,let source=panel.url else { return }
        let scoped=source.startAccessingSecurityScopedResource();defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            guard let size=try source.resourceValues(forKeys:[.fileSizeKey]).fileSize,size < 30_000_000,NSImage(contentsOf:source) != nil else { throw CocoaError(.fileReadTooLarge) }
            let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Island/Weather",isDirectory:true);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let old=photoURL;let name=UUID().uuidString+"."+source.pathExtension;try FileManager.default.copyItem(at:source,to:folder.appendingPathComponent(name));photo=name;photoError=nil
            if let old { try? FileManager.default.removeItem(at:old) }
        } catch { photoError="Choose a readable image under 30 MB." }
    }
    func temperature(_ celsius:Double)->Int { Int((fahrenheit ? celsius*9/5+32 : celsius).rounded()) }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { TextField("City", text: $city).textFieldStyle(.roundedBorder); Toggle("°F", isOn: $fahrenheit).toggleStyle(.checkbox); Button(weather.loading ? "Loading…" : "Get forecast") { Task { await weather.search(city: city, fahrenheit: fahrenheit) } }.disabled(weather.loading) }
            if let current = weather.forecast?.current {
                HStack(spacing: 20) {
                    Text("\(temperature(current.temperature_2m))°").font(.system(size: 35,weight: .medium,design: .rounded))
                    VStack(alignment: .leading) { Text(weather.place?.name ?? city).font(.headline); Text(IslandWeather.condition(current.weather_code)).foregroundStyle(.secondary) }
                    Spacer()
                    VStack(alignment: .trailing) { Text("Feels \(temperature(current.apparent_temperature))°"); Text("Humidity \(Int(current.relative_humidity_2m))% · Wind \(Int(current.wind_speed_10m)) km/h").font(.caption).foregroundStyle(.secondary) }
                }.padding(12).background {
                    if let url=photoURL,let image=NSImage(contentsOf:url) { Image(nsImage:image).resizable().scaledToFill().overlay(.black.opacity(0.45)) }
                    else { LinearGradient(colors:[Color.blue.opacity(0.4),Color.cyan.opacity(0.08)],startPoint:.topLeading,endPoint:.bottomTrailing) }
                }.clipShape(RoundedRectangle(cornerRadius:16))
                if let daily=weather.forecast?.daily {
                    HStack(spacing:14) {
                        if let uv=daily.uv_index_max?.first,uv.isFinite { Label(String(format:"UV %.0f",uv),systemImage:"sun.max") }
                        if let pressure=current.surface_pressure,pressure.isFinite { Text(String(format:"%.0f hPa",pressure)) }
                        if let sunrise=daily.sunrise?.first { Label(String(sunrise.suffix(5)),systemImage:"sunrise") }
                        if let sunset=daily.sunset?.first { Label(String(sunset.suffix(5)),systemImage:"sunset") }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                if !weather.hours.isEmpty {
                    Text("Next 24 hours").font(.caption).foregroundStyle(.secondary)
                    Chart(weather.hours) { hour in LineMark(x:.value("Time",hour.date),y:.value("Temperature",Double(temperature(hour.temperature)))).interpolationMethod(.monotone).foregroundStyle(.cyan);AreaMark(x:.value("Time",hour.date),y:.value("Temperature",Double(temperature(hour.temperature)))).foregroundStyle(.cyan.opacity(0.07)) }.frame(height:85).chartXAxis { AxisMarks(values:.stride(by:.hour,count:6)) { _ in AxisValueLabel(format:.dateTime.hour()) } }
                    HStack { ForEach(Array(weather.hours.prefix(6))) { hour in VStack { Text(hour.date,style:.time);Text("\(temperature(hour.temperature))°");if let rain=hour.rain { Text("\(Int(rain))%").foregroundStyle(.cyan) } }.font(.caption2).frame(maxWidth:.infinity) } }
                }
                if let daily = weather.forecast?.daily {
                    HStack { ForEach(Array(daily.time.prefix(7).enumerated()), id: \.offset) { index, day in
                        if index < daily.temperature_2m_max.count && index < daily.temperature_2m_min.count { VStack { Text(String(day.suffix(5))); Text("\(temperature(daily.temperature_2m_max[index]))° / \(temperature(daily.temperature_2m_min[index]))°") }.font(.caption).frame(maxWidth: .infinity) }
                    } }
                }
            }
            HStack { Button("Choose background…") { choosePhoto() };if !photo.isEmpty { Button("Use Island sky") { if let url=photoURL { try? FileManager.default.removeItem(at:url) };photo="" } };if let updated=weather.updated { Text("Updated "+updated.formatted(date:.omitted,time:.shortened)).font(.caption2).foregroundStyle(.secondary) } }
            if let error=photoError { Text(error).foregroundStyle(.orange) }
            if let error = weather.error { Text(error).foregroundStyle(.orange) }
            Link("Weather data: Open-Meteo · City searches are sent to Open-Meteo", destination: URL(string:"https://open-meteo.com/")!).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
