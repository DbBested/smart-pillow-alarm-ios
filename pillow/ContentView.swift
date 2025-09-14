//
//  ContentView.swift
//  pillow
//
//

import SwiftUI
import Foundation
import Network
import UserNotifications

// MARK: - Alarm Model
struct Alarm: Identifiable, Codable, Hashable {
    var id = UUID()
    var time: Date
    var label: String
    var isEnabled: Bool
    var repeatDays: Set<Weekday>
    var intensity: Int // NEW

    init(time: Date, label: String = "Alarm", isEnabled: Bool = true, repeatDays: Set<Weekday> = [], intensity: Int = 50) {
        self.time = time
        self.label = label
        self.isEnabled = isEnabled
        self.repeatDays = repeatDays
        self.intensity = intensity;
    }
    
    init(id: UUID, time: Date, label: String = "Alarm", isEnabled: Bool = true, repeatDays: Set<Weekday> = [], intensity: Int = 50) {
        self.id = id
        self.time = time
        self.label = label
        self.isEnabled = isEnabled
        self.repeatDays = repeatDays
        self.intensity = intensity;

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

enum AlarmNotification {
    static let categoryIdentifier = "ALARM_CATEGORY"
    static let stopActionIdentifier = "STOP_ALARM"
}

// MARK: - Alarm Manager
class AlarmManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    
    @Published var alarms: [Alarm] = []
    private let networkManager: NetworkManager
    
    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
        super.init() // Call NSObject initializer
        
        // This is the new, more robust setup
        configureNotifications { [weak self] in
            self?.loadAlarms()
            self?.scheduleAllEnabledAlarms()
        }
        UNUserNotificationCenter.current().delegate = self
    }
    
    private func configureNotifications(completion: @escaping () -> Void) {
        // Define the "Stop" action
        let stopAction = UNNotificationAction(
            identifier: AlarmNotification.stopActionIdentifier,
            title: "Stop",
            options: [.destructive, .foreground]
        )
        
        // Define the category that includes the action
        let category = UNNotificationCategory(
            identifier: AlarmNotification.categoryIdentifier,
            actions: [stopAction],
            intentIdentifiers: [],
            options: []
        )
        
        let center = UNUserNotificationCenter.current()
        
        // Request authorization
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("✅ Notification permission granted")
                    // Now that we have permission, set the categories
                    center.setNotificationCategories([category])
                    print("✅ Notification category with 'Stop' action registered.")
                    completion()
                } else if let error = error {
                    print("❌ Notification permission error: \(error)")
                    completion() // Still call completion to load alarms
                } else {
                    print("❌ Notification permission denied")
                    completion()
                }
            }
        }
    }
    
    private func scheduleAllEnabledAlarms() {
        for alarm in alarms {
            if alarm.isEnabled {
                scheduleNotification(for: alarm)
            }
        }
    }
    
    func addAlarm(_ alarm: Alarm) {
        alarms.append(alarm)
        saveAlarms()
        if alarm.isEnabled {
            scheduleNotification(for: alarm)
        }
    }
    
    func updateAlarm(_ alarm: Alarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            // First, remove old notifications for this alarm
            removeScheduledNotifications(for: alarms[index])
            
            // Then, update the alarm and schedule new notifications if enabled
            alarms[index] = alarm
            saveAlarms()
            if alarm.isEnabled {
                scheduleNotification(for: alarm)
            }
        }
    }
    
    func deleteAlarm(_ alarm: Alarm) {
        alarms.removeAll { $0.id == alarm.id }
        removeScheduledNotifications(for: alarm)
        saveAlarms()
    }
    
    // NEW public function to handle the toggle state change
    func setAlarmEnabled(_ isEnabled: Bool, for alarm: Alarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            // Update the alarm's state
            alarms[index].isEnabled = isEnabled
            
            if isEnabled {
                // If it was just enabled, schedule a notification
                scheduleNotification(for: alarms[index])
            } else {
                // If it was just disabled, remove notifications and send the "off" signal
                removeScheduledNotifications(for: alarms[index])
                sendAlarmOffToESP32(alarms[index])
            }
            // Always save the updated state
            saveAlarms()
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
    private func scheduleNotification(for alarm: Alarm) {
        // Clear any existing notifications for this alarm
        removeScheduledNotifications(for: alarm)
        
        let content = UNMutableNotificationContent()
        content.title = "🔔 Alarm: \(alarm.label)"
        content.body = "Time: \(DateFormatter.localizedString(from: alarm.time, dateStyle: .none, timeStyle: .short))"
        content.sound = .default
        content.badge = 1
        
        // This line is crucial to link the notification to the category with the 'Stop' button.
        content.categoryIdentifier = AlarmNotification.categoryIdentifier
        print("🔔 Notification content category identifier set to: \(content.categoryIdentifier)")

        let calendar = Calendar.current
        
        if alarm.repeatDays.isEmpty {
            // One-time alarm
            let now = Date()
            
            // Get the hour and minute from the alarm time
            let alarmTimeComponents = calendar.dateComponents([.hour, .minute], from: alarm.time)
            
            // Combine with today's date
            var triggerDateComponents = calendar.dateComponents([.year, .month, .day], from: now)
            triggerDateComponents.hour = alarmTimeComponents.hour
            triggerDateComponents.minute = alarmTimeComponents.minute
            
            var triggerDate = calendar.date(from: triggerDateComponents)!
            
            // If the alarm time has already passed today, schedule it for tomorrow
            if triggerDate < now {
                triggerDate = calendar.date(byAdding: .day, value: 1, to: triggerDate)!
                print("⏰ Scheduling one-time alarm for tomorrow.")
            } else {
                print("⏰ Scheduling one-time alarm for today.")
            }
            
            // Use the full date components for the trigger
            let finalDateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: finalDateComponents, repeats: false)
            let identifier = "alarm_\(alarm.id.uuidString)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("❌ Notification error: \(error.localizedDescription)")
                } else {
                    print("✅ One-time notification scheduled for: \(trigger.nextTriggerDate()?.description ?? "N/A")")
                }
            }
        } else {
            // Repeating alarm
            for day in alarm.repeatDays {
                var dateComponents = calendar.dateComponents([.hour, .minute, .second], from: alarm.time)
                // Set weekday component (1-based, Sunday = 1)
                dateComponents.weekday = Weekday.allCases.firstIndex(of: day)! + 1
                
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let identifier = "alarm_\(alarm.id.uuidString)_\(day.rawValue)"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ Repeating notification error for \(day.rawValue): \(error.localizedDescription)")
                    } else {
                        print("✅ Repeating notification for \(day.rawValue) scheduled for: \(trigger.nextTriggerDate()?.description ?? "N/A")")
                    }
                }
            }
        }
    }
    
    private func removeScheduledNotifications(for alarm: Alarm) {
        var identifiersToRemove = [String]()
        if alarm.repeatDays.isEmpty {
            // One-time alarm
            identifiersToRemove.append("alarm_\(alarm.id.uuidString)")
        } else {
            // Repeating alarm
            for day in alarm.repeatDays {
                identifiersToRemove.append("alarm_\(alarm.id.uuidString)_\(day.rawValue)")
            }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
        print("🗑️ Removed pending notifications for \(alarm.label) with identifiers: \(identifiersToRemove)")
    }
    
    private func sendAlarmTriggerToESP32(_ alarm: Alarm) {
        // Build message in format: "<intensity> TRIGGER <label>"
        let message = "\(alarm.intensity) TRIGGER \(alarm.label)"

        // Encode message safely for URL
        guard let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("❌ Failed to encode message: \(message)")
            return
        }

        let endpoint = "/?message=\(encodedMessage)"

        networkManager.sendHTTPRequest(
            endpoint: endpoint,
            method: "GET"
        ) { result in
            switch result {
            case .success(let response):
                print("🔔 ESP32 Trigger Sent: \(response)")
            case .failure(let error):
                print("❌ ESP32 Trigger Error: \(error.localizedDescription)")
            }
        }
    }
    private func sendAlarmOffToESP32(_ alarm: Alarm) {
        // Build message in format: "<intensity> OFF <label>"
        let message = "\(alarm.intensity) OFF \(alarm.label)"

        // Encode message safely for URL
        guard let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("❌ Failed to encode message: \(message)")
            return
        }

        let endpoint = "/?message=\(encodedMessage)"

        networkManager.sendHTTPRequest(
            endpoint: endpoint,
            method: "GET"
        ) { result in
            switch result {
            case .success(let response):
                print("🛑 ESP32 OFF Sent: \(response)")
            case .failure(let error):
                print("❌ ESP32 OFF Error: \(error.localizedDescription)")
            }
        }
    }

    deinit {
        // Since we are now using system notifications, we no longer need to invalidate the timer here.
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    // This method is called when a notification is delivered to the app while it's in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        // --- START NEW LOGIC ---
        // Check if the notification is for an alarm and trigger the ESP32
        let notificationIdentifier = notification.request.identifier
        print("🔔 Notification presented in foreground: \(notificationIdentifier)")
        
        // Try to parse the UUID from the notification identifier
        let components = notificationIdentifier.components(separatedBy: "_")
        if components.count >= 2, components[0] == "alarm", let uuid = UUID(uuidString: components[1]) {
            // Find the corresponding alarm in our list
            if let alarmToTrigger = alarms.first(where: { $0.id == uuid }) {
                print("Found alarm to trigger: \(alarmToTrigger.label)")
                
                // Send the "start" command to the ESP32
                sendAlarmTriggerToESP32(alarmToTrigger)
            }
        }
        // --- END NEW LOGIC ---

        // Display the notification banner/sound/badge even if the app is in the foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // This method is called when the user interacts with a notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        // Check if the action is our "Stop" button
        if response.actionIdentifier == AlarmNotification.stopActionIdentifier {
            let notificationIdentifier = response.notification.request.identifier
            print("🛑 Stop button tapped for notification: \(notificationIdentifier)")
            
            // Try to parse the UUID from the notification identifier
            let components = notificationIdentifier.components(separatedBy: "_")
            if components.count >= 2, components[0] == "alarm", let uuid = UUID(uuidString: components[1]) {
                // Find the corresponding alarm in our list
                if let alarmToStop = alarms.first(where: { $0.id == uuid }) {
                    print("Found alarm to stop: \(alarmToStop.label)")
                    
                    // Stop the alarm on the ESP32
                    sendAlarmOffToESP32(alarmToStop)
                    
                    // Disable the alarm in the app
                    if let index = alarms.firstIndex(where: { $0.id == uuid }) {
                        alarms[index].isEnabled = false
                        saveAlarms()
                    }
                }
            } else {
                print("❌ Could not parse alarm UUID from notification identifier.")
            }
        }
        
        // You must call the completion handler when you're done
        completionHandler()
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
                        // The ForEach loop now binds directly to each alarm in the array
                        // to allow for direct modification.
                        ForEach($alarmManager.alarms) { $alarm in
                            AlarmRowView(alarm: $alarm, alarmManager: alarmManager)
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
        content.categoryIdentifier = AlarmNotification.categoryIdentifier // Ensure the category is set for the test notification as well
        
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
    // The alarm is now a Binding, allowing direct modification from this view.
    @Binding var alarm: Alarm
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
                    Text("Intensity: \(alarm.intensity)").font(.caption) // NEW

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
            
            Toggle("", isOn: $alarm.isEnabled)
                .toggleStyle(SwitchToggleStyle(tint: .orange))
                // This modifier listens for changes to the toggle's state
                .onChange(of: alarm.isEnabled) { isNowEnabled in
                    // Call the public method on the manager to handle the state change
                    alarmManager.setAlarmEnabled(isNowEnabled, for: alarm)
                }
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
    @State private var intensityy = 5   // NEW

    
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
                Section(header: Text("Vibration Intensity")) {
                    Slider(value: Binding(
                        get: { Double(intensityy) },
                        set: { intensityy = Int($0) }
                    ), in: 1...10, step: 1)
                    Text("Intensity: \(intensityy)")
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
                            repeatDays: selectedDays,
                            intensity:
                                intensityy
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
    @State private var intensity: Int

    
    init(alarm: Alarm, alarmManager: AlarmManager) {
        self.alarm = alarm
        self.alarmManager = alarmManager
        self._selectedTime = State(initialValue: alarm.time)
        self._alarmLabel = State(initialValue: alarm.label)
        self._selectedDays = State(initialValue: alarm.repeatDays)
        self._intensity = State(initialValue: alarm.intensity)
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
                Section(header: Text("Vibration Intensity")) {
                                Slider(value: Binding(
                                    get: { Double(intensity) },
                                    set: { intensity = Int($0) }
                                ), in: 1...10, step: 1)
                                Text("Intensity: \(intensity)")
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
                            repeatDays: selectedDays,
                            intensity: intensity
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
    
    // New state variables for the alarm controls
    @State private var alarmIntensity: Double = 5.0

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
                
                // Alarm Control Section
                VStack(spacing: 8) {
                    Text("Manual Alarm Control")
                        .font(.headline)
                    
                    // Intensity Slider
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Intensity")
                            Spacer()
                            Text("\(Int(alarmIntensity))%")
                        }
                        Slider(value: $alarmIntensity, in: 0...10, step: 1)
                            .tint(.orange)
                    }
                    
                    HStack(spacing: 12) {
                        // Turn Alarm ON Button
                        Button("Turn Alarm ON") {
                            sendAlarmCommand(action: "trigger", intensity:Int(alarmIntensity))

                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        
                        // Turn Alarm OFF Button
                        Button("Turn Alarm OFF") {
                            sendAlarmCommand(action: "OFF", intensity: 0)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
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
    
    private func sendAlarmCommand(action: String, intensity: Int) {
        // Build message in format: "<intensity> <action> <label>"
        let message = "\(intensity) \(action) Alarm"

        // Encode message safely for URL
        guard let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            testResult = "❌ Failed to encode message."
            return
        }

        let endpoint = "/?message=\(encodedMessage)"
        
        networkManager.sendHTTPRequest(endpoint: endpoint, method: "GET") { result in
            switch result {
            case .success(let response):
                testResult = "✅ Command sent: \(response)"
            case .failure(let error):
                testResult = "❌ Command failed: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    ContentView()
}
    
