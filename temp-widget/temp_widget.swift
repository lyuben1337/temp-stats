import WidgetKit
import SwiftUI
import Intents
import Foundation

// MARK: - Логирование

var logMessages: [String] = []

func logMessage(_ message: String) {
    let logEntry = "\(Date()): \(message)"
    logMessages.append(logEntry)
}

// MARK: - Функции получения температуры с логированием

func getCPUtemp() -> Int {
    logMessage("Вызов getCPUtemp")
    return runSMCTempCommand(argument: "-g")
}

func getGPUtemp() -> Int {
    logMessage("Вызов getGPUtemp")
    return runSMCTempCommand(argument: "-c")
}

private func getSmcTempPath() -> String? {
    let fileManager = FileManager.default
    if let resourcePath = Bundle.main.resourcePath {
        let smcTempPath = (resourcePath as NSString).appendingPathComponent("smctemp")
        logMessage("Путь к smctemp: \(smcTempPath)")
        if fileManager.fileExists(atPath: smcTempPath) {
            return smcTempPath
        }
    }
    return nil
}

private func runSMCTempCommand(argument: String) -> Int {
    logMessage("Запуск smctemp с аргументом: \(argument)")

    guard let smctempPath = getSmcTempPath() else {
        logMessage("Ошибка: не удалось найти smctemp в ресурсах приложения.")
        return 0
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: smctempPath)
    process.arguments = [argument]
    process.environment = ProcessInfo.processInfo.environment

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
        try process.run()
        logMessage("smctemp успешно запущен по пути: \(smctempPath)")
    } catch {
        logMessage("Ошибка запуска smctemp: \(error.localizedDescription)")
        return 0
    }

    process.waitUntilExit()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

    if let output = String(data: outputData, encoding: .utf8) {
        logMessage("Вывод smctemp (stdout): \(output)")
    }

    if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
        logMessage("Ошибка smctemp (stderr): \(errorOutput)")
    }

    let trimmedOutput = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if let temperature = Double(trimmedOutput) {
        logMessage("Успех: получена температура \(temperature)°")
        return Int(round(temperature))
    } else {
        logMessage("Ошибка: неожиданный вывод '\(trimmedOutput)'")
        return 0
    }
}

// MARK: - Функция определения цвета для температуры

func colorForTemperature(_ temp: Int) -> Color {
    if temp < 90 {
        return Color.white
    } else if temp < 100 {
        return Color.yellow
    } else {
        return Color.red
    }
}

// MARK: - Timeline Provider

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: ConfigurationAppIntent(), cpuTemp: 0, gpuTemp: 0)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: configuration, cpuTemp: 0, gpuTemp: 0)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let currentDate = Date()

        let cpuTemp = getCPUtemp()
        let gpuTemp = getGPUtemp()

        let entry = SimpleEntry(date: currentDate, configuration: configuration, cpuTemp: cpuTemp, gpuTemp: gpuTemp)

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: currentDate) ?? currentDate.addingTimeInterval(60)

        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

// MARK: - Timeline Entry

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let cpuTemp: Int
    let gpuTemp: Int
}

// MARK: - Виджет

struct temp_widgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        GeometryReader { geometry in
            HStack {
                VStack(spacing: 4) {
                    Text("CPU: \(entry.cpuTemp)°")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(colorForTemperature(entry.cpuTemp))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("GPU: \(entry.gpuTemp)°")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(colorForTemperature(entry.gpuTemp))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(logMessages.reversed(), id: \ .self) { log in
                            Text(log)
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                                .lineLimit(2)
                                .minimumScaleFactor(0.5)
                        }
                    }
                    .padding(4)
                }
            }
            .padding()
        }
    }
}

struct temp_widget: Widget {
    let kind: String = "temp_widget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: ConfigurationAppIntent.self,
                               provider: Provider()) { entry in
            temp_widgetEntryView(entry: entry)
        }
        .configurationDisplayName("Temperature Statistics Widget")
        .description("Displays CPU and GPU temperatures with logs.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Превью

struct temp_widget_Previews: PreviewProvider {
    static var previews: some View {
        temp_widgetEntryView(entry: SimpleEntry(date: Date(),
                                                configuration: ConfigurationAppIntent(),
                                                cpuTemp: 85,
                                                gpuTemp: 105))
        .previewContext(WidgetPreviewContext(family: .systemLarge))
    }
}
