//
//  ContentView.swift
//  pillow
//
//  Created by Thomas Li on 9/13/25.
//

import SwiftUI
import Foundation
import Network
import UserNotifications

// MARK: - Alarm Model
struct Alarm: Identifiable, Codable {
    var id = UUID()
    var time: Date
    var label: String
    var isEnabled: Bool
    var repeatDays: Set<Weekday>
    
    init(time: Date, label: String = "Alarm", isEnabled: Bool = true, repeatDays: Set<Weekday> = []) {
        self.time = time
        self.label = label
        self.isEnabled = isEnabled
        self.repeatDays = repeatDays
    }
    
    init(id: UUID, time: Date, label: String = "Alarm", isEnabled: Bool = true, repeatDays: Set<Weekday> = []) {
        self.id = id
        self.time = time
        self.label = label
        self.isEnabled = isEnabled
        self.repeatDays = repeatDays
    }
}

enum Weekday: String, CaseIterable, Codable {
    case sunday = "Sun"
    case monday = "Mon"
    case tuesday = "Tue"
    case wednesday = "Wed"
    case thursday = "Thu"
    case friday = "Fri"
    case saturday = "Sat"
}

// MARK: - Network Manager
class NetworkManager: ObservableObject {
    @Published var isConnected = false
    @Published var esp32IP = "192.168.4.1" // ESP32-C3 Access Point IP
    @Published var esp32Port = "80"
    @Published var lastResponse = ""
    @Published var connectionStatus = "Disconnected"
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    // Persistent URLSession for ESP32 connection
    private let urlSession: URLSession
    private var baseURL: URL?
    
    init() {
        // Configure URLSession for persistent connections
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 30.0
        config.httpMaximumConnectionsPerHost = 1
        config.httpShouldUsePipelining = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        self.urlSession = URLSession(configuration: config)
        
        startNetworkMonitoring()
        updateBaseURL()
    }
    
    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionStatus = path.status == .satisfied ? "Connected" : "Disconnected"
                
                // Update base URL when connection status changes
                if path.status == .satisfied {
                    self?.updateBaseURL()
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    private func updateBaseURL() {
        baseURL = URL(string: "http://\(esp32IP):\(esp32Port)")
        print("🔗 Updated base URL: \(baseURL?.absoluteString ?? "Invalid URL")")
    }
    
    // Update ESP32 settings and refresh connection
    func updateESP32Settings(ip: String, port: String) {
        esp32IP = ip
        esp32Port = port
        updateBaseURL()
        print("🔧 ESP32 settings updated: \(ip):\(port)")
    }
    
    func sendHTTPRequest(endpoint: String, method: String = "GET", body: Data? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        guard isConnected else {
            completion(.failure(NetworkError.noConnection))
            return
        }
        
        guard let baseURL = baseURL,
              let url = URL(string: endpoint, relativeTo: baseURL) else {
            completion(.failure(NetworkError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.httpBody = body
        
        print("📡 Sending \(method) request to: \(url.absoluteString)")
        
        urlSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.lastResponse = "Error: \(error.localizedDescription)"
                    print("❌ Request failed: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    let statusCode = httpResponse.statusCode
                    let responseText = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No response body"
                    self?.lastResponse = "Status: \(statusCode)\nResponse: \(responseText)"
                    
                    print("📨 Response (\(statusCode)): \(responseText)")
                    
                    if statusCode >= 200 && statusCode < 300 {
                        completion(.success(responseText))
                    } else {
                        completion(.failure(NetworkError.httpError(statusCode)))
                    }
                } else {
                    self?.lastResponse = "Invalid response"
                    print("❌ Invalid response received")
                    completion(.failure(NetworkError.invalidResponse))
                }
            }
        }.resume()
    }
    
    func testConnection(completion: @escaping (Bool) -> Void) {
        sendHTTPRequest(endpoint: "/status") { result in
            switch result {
            case .success:
                completion(true)
            case .failure:
                completion(false)
            }
        }
    }
    
    // MARK: - ESP32 Command Methods
    
    func sendMotorCommand(action: String, completion: @escaping (Result<String, Error>) -> Void) {
        let endpoint = "/motor/\(action)"
        sendHTTPRequest(endpoint: endpoint, method: "POST", completion: completion)
    }
    
    func setMotorSpeed(_ speed: Int, completion: @escaping (Result<String, Error>) -> Void) {
        let speedData = ["speed": speed]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: speedData)
            sendHTTPRequest(endpoint: "/motor/speed", method: "POST", body: jsonData, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }
    
    func setMotorDirection(_ direction: Bool, completion: @escaping (Result<String, Error>) -> Void) {
        let directionData = ["direction": direction]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: directionData)
            sendHTTPRequest(endpoint: "/motor/direction", method: "POST", body: jsonData, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }
    
    func getESP32Status(completion: @escaping (Result<String, Error>) -> Void) {
        sendHTTPRequest(endpoint: "/status", method: "GET", completion: completion)
    }
    
    // Clean up resources
    deinit {
        urlSession.invalidateAndCancel()
    }
}

enum NetworkError: Error, LocalizedError {
    case noConnection
    case invalidURL
    case invalidResponse
    case httpError(Int)
    
    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No network connection"
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}

// MARK: - Alarm Manager
class AlarmManager: ObservableObject {
    @Published var alarms: [Alarm] = []
    private let networkManager: NetworkManager
    
    // Alarm trigger logic with notifications for testing
    private var alarmTimer: Timer?
    
    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
        loadAlarms()
        requestNotificationPermission()
        startAlarmTimer()
    }
    
    func addAlarm(_ alarm: Alarm) {
        alarms.append(alarm)
        saveAlarms()
        sendAlarmToESP32(alarm, action: "add")
    }
    
    func updateAlarm(_ alarm: Alarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
            saveAlarms()
            sendAlarmToESP32(alarm, action: "update")
        }
    }
    
    func deleteAlarm(_ alarm: Alarm) {
        alarms.removeAll { $0.id == alarm.id }
        saveAlarms()
        sendAlarmToESP32(alarm, action: "delete")
    }
    
    func toggleAlarm(_ alarm: Alarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index].isEnabled.toggle()
            saveAlarms()
            sendAlarmToESP32(alarms[index], action: "toggle")
        }
    }
    
    private func sendAlarmToESP32(_ alarm: Alarm, action: String) {
        // Send simple status message to ESP32 based on action
        let message: String
        switch action {
        case "add", "update", "toggle":
            message = alarm.isEnabled ? "LED_ON" : "LED_OFF"
        case "delete":
            message = "LED_OFF"
        default:
            message = "GET_STATUS"
        }
        
        let endpoint = "/?message=\(message)"
        
        networkManager.sendHTTPRequest(
            endpoint: endpoint,
            method: "GET"
        ) { result in
            switch result {
            case .success(let response):
                // ESP32 received message successfully
                print("📡 ESP32 Response (\(action)): \(response)")
            case .failure(let error):
                // ESP32 communication failed
                print("❌ ESP32 Error (\(action)): \(error.localizedDescription)")
            }
        }
    }
    
    private func saveAlarms() {
        if let encoded = try? JSONEncoder().encode(alarms) {
            UserDefaults.standard.set(encoded, forKey: "SavedAlarms")
        }
    }
    
    private func loadAlarms() {
        if let data = UserDefaults.standard.data(forKey: "SavedAlarms"),
           let decoded = try? JSONDecoder().decode([Alarm].self, from: data) {
            alarms = decoded
        }
    }
    
    // MARK: - Alarm Trigger Logic with Notifications
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("✅ Notification permission granted - ready to send notifications")
                } else if let error = error {
                    print("❌ Notification permission error: \(error)")
                } else {
                    print("❌ Notification permission denied by user")
                }
            }
        }
    }
    
    private func startAlarmTimer() {
        // Create a timer that checks every 10 seconds for testing (change to 60.0 for production)
        alarmTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkForAlarmsToTrigger()
        }
    }
    
    private func checkForAlarmsToTrigger() {
        let now = Date()
        let calendar = Calendar.current
        let currentTime = calendar.dateComponents([.hour, .minute], from: now)
        let currentWeekday = calendar.component(.weekday, from: now)
        
        // Debug: Print current time and alarms
        print("🕐 Checking alarms at: \(DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .short))")
        print("📋 Total alarms: \(alarms.count), Enabled: \(alarms.filter { $0.isEnabled }.count)")
        
        for alarm in alarms {
            if alarm.isEnabled {
                let shouldTrigger = shouldTriggerAlarm(alarm, currentTime: currentTime, currentWeekday: currentWeekday)
                print("🔍 Alarm '\(alarm.label)' at \(DateFormatter.localizedString(from: alarm.time, dateStyle: .none, timeStyle: .short)) - Should trigger: \(shouldTrigger)")
                
                if shouldTrigger {
                    print("🚨 TRIGGERING ALARM: \(alarm.label)")
                    triggerAlarm(alarm)
                }
            }
        }
    }
    
    private func shouldTriggerAlarm(_ alarm: Alarm, currentTime: DateComponents, currentWeekday: Int) -> Bool {
        let alarmTime = Calendar.current.dateComponents([.hour, .minute], from: alarm.time)
        
        // Check if time matches
        guard currentTime.hour == alarmTime.hour && currentTime.minute == alarmTime.minute else {
            return false
        }
        
        // Check repeat days
        if alarm.repeatDays.isEmpty {
            // One-time alarm - check if it's today
            return true
        } else {
            // Repeating alarm - check if today is in repeat days
            let todayWeekday = Weekday.allCases[currentWeekday - 1] // Calendar.weekday is 1-based
            return alarm.repeatDays.contains(todayWeekday)
        }
    }
    
    private func triggerAlarm(_ alarm: Alarm) {
        // Send notification to iPhone
        sendNotification(for: alarm)
        
        // Send to ESP32 (optional - for testing)
        sendAlarmTriggerToESP32(alarm)
    }
    
    private func sendNotification(for alarm: Alarm) {
        print("📱 Attempting to send notification for alarm: \(alarm.label)")
        
        let content = UNMutableNotificationContent()
        content.title = "🔔 Alarm: \(alarm.label)"
        content.body = "Time: \(DateFormatter.localizedString(from: alarm.time, dateStyle: .none, timeStyle: .short))"
        content.sound = .default
        content.badge = 1
        
        // Create a unique identifier for this alarm
        let identifier = "alarm_\(alarm.id.uuidString)"
        
        // Create the request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        
        // Add the request
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Notification error: \(error.localizedDescription)")
            } else {
                print("✅ Notification sent successfully for alarm: \(alarm.label)")
            }
        }
    }
    
    private func sendAlarmTriggerToESP32(_ alarm: Alarm) {
        // Send simple "LED_ON" message to ESP32
        let message = "LED_ON"
        let endpoint = "/?message=\(message)"
        
        networkManager.sendHTTPRequest(
            endpoint: endpoint,
            method: "GET"
        ) { result in
            switch result {
            case .success(let response):
                // Alarm trigger sent to ESP32 successfully
                print("🔔 ESP32 LED turned ON: \(response)")
            case .failure(let error):
                // Failed to send alarm trigger to ESP32
                print("❌ ESP32 LED trigger error: \(error.localizedDescription)")
            }
        }
    }
    
    deinit {
        alarmTimer?.invalidate()
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var networkManager = NetworkManager()
    @StateObject private var alarmManager: AlarmManager
    @State private var showingAddAlarm = false
    @State private var showingNetworkSettings = false
    
    init() {
        let networkManager = NetworkManager()
        _networkManager = StateObject(wrappedValue: networkManager)
        _alarmManager = StateObject(wrappedValue: AlarmManager(networkManager: networkManager))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    HStack {
                        Text("Alarms")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Spacer()
                        HStack(spacing: 12) {
                            // Network Status
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(networkManager.isConnected ? .green : .red)
                                    .frame(width: 8, height: 8)
                                Text(networkManager.connectionStatus)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            // Network Settings Button
                            Button(action: { showingNetworkSettings = true }) {
                                Image(systemName: "wifi")
                                    .font(.title3)
                                    .foregroundColor(networkManager.isConnected ? .green : .orange)
                            }
                            
                            // Test Notification Button
                            Button(action: { 
                                print("🔔 Test notification button tapped!")
                                testNotification() 
                            }) {
                                Image(systemName: "bell")
                                    .font(.title3)
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Add Alarm Button
                            Button(action: { showingAddAlarm = true }) {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
                    // ESP32 Connection Info
                    if networkManager.isConnected {
                        HStack {
                            Text("ESP32: \(networkManager.esp32IP):\(networkManager.esp32Port)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Alarms List
                if alarmManager.alarms.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "alarm")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No Alarms")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)
                        Text("Tap + to add an alarm")
                            .font(.body)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(alarmManager.alarms) { alarm in
                            AlarmRowView(alarm: alarm, alarmManager: alarmManager)
                        }
                        .onDelete(perform: deleteAlarms)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingAddAlarm) {
            AddAlarmView(alarmManager: alarmManager)
        }
        .sheet(isPresented: $showingNetworkSettings) {
            NetworkSettingsView(networkManager: networkManager)
        }
    }
    
    private func deleteAlarms(offsets: IndexSet) {
        for index in offsets {
            alarmManager.deleteAlarm(alarmManager.alarms[index])
        }
    }
    
    private func testNotification() {
        print("🧪 Testing notification...")
        
        // First check notification settings
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("📱 Notification settings:")
            print("   - Authorization status: \(settings.authorizationStatus.rawValue)")
            print("   - Alert setting: \(settings.alertSetting.rawValue)")
            print("   - Sound setting: \(settings.soundSetting.rawValue)")
            print("   - Badge setting: \(settings.badgeSetting.rawValue)")
            
            DispatchQueue.main.async {
                if settings.authorizationStatus == .authorized {
                    self.sendTestNotification()
                } else if settings.authorizationStatus == .notDetermined {
                    print("⚠️ Notification permission not determined - requesting permission...")
                    self.requestNotificationPermissionAndTest()
                } else {
                    print("❌ Notifications not authorized - status: \(settings.authorizationStatus.rawValue)")
                }
            }
        }
    }
    
    private func sendTestNotification() {
        print("📤 Sending test notification...")
        
        let content = UNMutableNotificationContent()
        content.title = "🧪 Test Notification"
        content.body = "This is a test notification from your alarm app!"
        content.sound = .default
        content.badge = 1
        
        let identifier = "test_notification_\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Test notification error: \(error.localizedDescription)")
                } else {
                    print("✅ Test notification sent successfully!")
                }
            }
        }
    }
    
    private func requestNotificationPermissionAndTest() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("✅ Notification permission granted - sending test notification")
                    self.sendTestNotification()
                } else if let error = error {
                    print("❌ Notification permission error: \(error)")
                } else {
                    print("❌ Notification permission denied by user")
                }
            }
        }
    }
}

// MARK: - Alarm Row View
struct AlarmRowView: View {
    let alarm: Alarm
    let alarmManager: AlarmManager
    @State private var showingEditAlarm = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeString)
                    .font(.system(size: 32, weight: .light, design: .default))
                    .foregroundColor(alarm.isEnabled ? .primary : .secondary)
                
                HStack {
                    Text(alarm.label)
                        .font(.body)
                        .foregroundColor(alarm.isEnabled ? .primary : .secondary)
                    
                    if !alarm.repeatDays.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(repeatDaysString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { alarm.isEnabled },
                set: { _ in alarmManager.toggleAlarm(alarm) }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .orange))
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            showingEditAlarm = true
        }
        .sheet(isPresented: $showingEditAlarm) {
            EditAlarmView(alarm: alarm, alarmManager: alarmManager)
        }
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: alarm.time)
    }
    
    private var repeatDaysString: String {
        if alarm.repeatDays.count == 7 {
            return "Every day"
        } else if alarm.repeatDays.count == 5 && !alarm.repeatDays.contains(.saturday) && !alarm.repeatDays.contains(.sunday) {
            return "Weekdays"
        } else if alarm.repeatDays.count == 2 && alarm.repeatDays.contains(.saturday) && alarm.repeatDays.contains(.sunday) {
            return "Weekends"
        } else {
            return alarm.repeatDays.sorted { $0.rawValue < $1.rawValue }.map { $0.rawValue }.joined(separator: ", ")
        }
    }
}

// MARK: - Add Alarm View
struct AddAlarmView: View {
    @Environment(\.dismiss) var dismiss
    let alarmManager: AlarmManager
    
    @State private var selectedTime = Date()
    @State private var alarmLabel = "Alarm"
    @State private var selectedDays: Set<Weekday> = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Time Picker
                DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(WheelDatePickerStyle())
                    .labelsHidden()
                
                // Label Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Label")
                        .font(.headline)
                    TextField("Alarm", text: $alarmLabel)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                // Repeat Days
                VStack(alignment: .leading, spacing: 12) {
                    Text("Repeat")
                        .font(.headline)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            Button(action: {
                                if selectedDays.contains(day) {
                                    selectedDays.remove(day)
                                } else {
                                    selectedDays.insert(day)
                                }
                            }) {
                                Text(day.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedDays.contains(day) ? .white : .primary)
                                    .frame(width: 40, height: 40)
                                    .background(selectedDays.contains(day) ? Color.orange : Color.gray.opacity(0.2))
                                    .clipShape(Circle())
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Add Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let newAlarm = Alarm(
                            time: selectedTime,
                            label: alarmLabel,
                            isEnabled: true,
                            repeatDays: selectedDays
                        )
                        alarmManager.addAlarm(newAlarm)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Edit Alarm View
struct EditAlarmView: View {
    @Environment(\.dismiss) var dismiss
    let alarm: Alarm
    let alarmManager: AlarmManager
    
    @State private var selectedTime: Date
    @State private var alarmLabel: String
    @State private var selectedDays: Set<Weekday>
    @State private var isEnabled: Bool
    
    init(alarm: Alarm, alarmManager: AlarmManager) {
        self.alarm = alarm
        self.alarmManager = alarmManager
        self._selectedTime = State(initialValue: alarm.time)
        self._alarmLabel = State(initialValue: alarm.label)
        self._selectedDays = State(initialValue: alarm.repeatDays)
        self._isEnabled = State(initialValue: alarm.isEnabled)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Time Picker
                DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(WheelDatePickerStyle())
                    .labelsHidden()
                
                // Label Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Label")
                        .font(.headline)
                    TextField("Alarm", text: $alarmLabel)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                // Repeat Days
                VStack(alignment: .leading, spacing: 12) {
                    Text("Repeat")
                        .font(.headline)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            Button(action: {
                                if selectedDays.contains(day) {
                                    selectedDays.remove(day)
                                } else {
                                    selectedDays.insert(day)
                                }
                            }) {
                                Text(day.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedDays.contains(day) ? .white : .primary)
                                    .frame(width: 40, height: 40)
                                    .background(selectedDays.contains(day) ? Color.orange : Color.gray.opacity(0.2))
                                    .clipShape(Circle())
                            }
                        }
                    }
                }
                
                // Enable/Disable Toggle
                HStack {
                    Text("Enabled")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: $isEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: .orange))
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let updatedAlarm = Alarm(
                            id: alarm.id,
                            time: selectedTime,
                            label: alarmLabel,
                            isEnabled: isEnabled,
                            repeatDays: selectedDays
                        )
                        alarmManager.updateAlarm(updatedAlarm)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Network Settings View
struct NetworkSettingsView: View {
    @Environment(\.dismiss) var dismiss
    let networkManager: NetworkManager
    @State private var tempIP = ""
    @State private var tempPort = ""
    @State private var isTestingConnection = false
    @State private var testResult = ""
    
    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
        self._tempIP = State(initialValue: networkManager.esp32IP)
        self._tempPort = State(initialValue: networkManager.esp32Port)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Connection Status
                VStack(spacing: 8) {
                    HStack {
                        Circle()
                            .fill(networkManager.isConnected ? .green : .red)
                            .frame(width: 12, height: 12)
                        Text("Network Status: \(networkManager.connectionStatus)")
                            .font(.headline)
                        Spacer()
                    }
                    
                    if !networkManager.lastResponse.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last Response:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(networkManager.lastResponse)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
                
                // ESP32 Settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("ESP32-C3 Settings")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("IP Address")
                            .font(.subheadline)
                        TextField("192.168.4.1", text: $tempIP)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Port")
                            .font(.subheadline)
                        TextField("80", text: $tempPort)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
                // Test Connection
                VStack(spacing: 12) {
                    Button(action: testConnection) {
                        HStack {
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "wifi")
                            }
                            Text(isTestingConnection ? "Testing..." : "Test Connection")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(isTestingConnection)
                    
                    if !testResult.isEmpty {
                        Text(testResult)
                            .font(.caption)
                            .foregroundColor(testResult.contains("Success") ? .green : .red)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                // HTTP Test Buttons
                VStack(spacing: 8) {
                    Text("ESP32 Message Tests")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        Button("GET /status") {
                            sendTestRequest(endpoint: "/status", method: "GET")
                        }
                        .buttonStyle(.bordered)
                        
                        Button("LED_ON") {
                            sendTestRequest(endpoint: "/?message=LED_ON", method: "GET")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack(spacing: 12) {
                        Button("LED_OFF") {
                            sendTestRequest(endpoint: "/?message=LED_OFF", method: "GET")
                        }
                        .buttonStyle(.bordered)
                        
                        Button("PING") {
                            sendTestRequest(endpoint: "/?message=PING", method: "GET")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack(spacing: 12) {
                        Button("HELLO") {
                            sendTestRequest(endpoint: "/?message=HELLO", method: "GET")
                        }
                        .buttonStyle(.bordered)
                        
                        Button("BLINK_5") {
                            sendTestRequest(endpoint: "/?message=BLINK_5", method: "GET")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // Motor Control Tests
                VStack(spacing: 8) {
                    Text("Motor Control Tests")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        Button("Start Motor") {
                            networkManager.sendMotorCommand(action: "start") { result in
                                switch result {
                                case .success(let response):
                                    testResult = "✅ Motor started: \(response)"
                                case .failure(let error):
                                    testResult = "❌ Motor start failed: \(error.localizedDescription)"
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Stop Motor") {
                            networkManager.sendMotorCommand(action: "stop") { result in
                                switch result {
                                case .success(let response):
                                    testResult = "✅ Motor stopped: \(response)"
                                case .failure(let error):
                                    testResult = "❌ Motor stop failed: \(error.localizedDescription)"
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack(spacing: 12) {
                        Button("Speed 50%") {
                            networkManager.setMotorSpeed(128) { result in
                                switch result {
                                case .success(let response):
                                    testResult = "✅ Speed set: \(response)"
                                case .failure(let error):
                                    testResult = "❌ Speed set failed: \(error.localizedDescription)"
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Speed 100%") {
                            networkManager.setMotorSpeed(255) { result in
                                switch result {
                                case .success(let response):
                                    testResult = "✅ Speed set: \(response)"
                                case .failure(let error):
                                    testResult = "❌ Speed set failed: \(error.localizedDescription)"
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Spacer()
        }
        .padding()
            .navigationTitle("Network Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        networkManager.updateESP32Settings(ip: tempIP, port: tempPort)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func testConnection() {
        isTestingConnection = true
        testResult = ""
        
        networkManager.testConnection { success in
            isTestingConnection = false
            testResult = success ? "✅ Connection successful!" : "❌ Connection failed"
        }
    }
    
    private func sendTestRequest(endpoint: String, method: String, body: String? = nil) {
        let bodyData = body?.data(using: .utf8)
        networkManager.sendHTTPRequest(endpoint: endpoint, method: method, body: bodyData) { result in
            switch result {
            case .success(let response):
                testResult = "✅ \(method) \(endpoint): \(response)"
            case .failure(let error):
                testResult = "❌ \(method) \(endpoint): \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    ContentView()
}
