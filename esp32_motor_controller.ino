/*
 * ESP32-C3 Motor Controller
 * Receives HTTP commands from Swift app and controls motor via driver
 * 
 * Hardware Setup:
 * - ESP32-C3 XIAO board
 * - Motor driver (L298N, L9110, or TB6612FNG)
 * - DC Motor with separate power supply
 * - Optional: Status LED
 * 
 * Pin Connections (example for L298N):
 * - GPIO2 -> IN1 (Motor A direction)
 * - GPIO3 -> IN2 (Motor A direction) 
 * - GPIO4 -> ENA (Motor A speed/PWM)
 * - GPIO5 -> LED (status indicator)
 * 
 * WiFi: Creates hotspot "ESP32-Motor" with password "12345678"
 * IP: 192.168.4.1 (default ESP32 SoftAP IP)
 */

#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>

// WiFi Configuration
const char* ssid = "ESP32-Motor";
const char* password = "12345678";

// Motor Control Pins (adjust for your driver)
#define MOTOR_IN1 2    // Direction pin 1
#define MOTOR_IN2 3    // Direction pin 2
#define MOTOR_ENA 4    // Speed/PWM pin
#define STATUS_LED 5   // Status LED

// Motor Control Variables
int motorSpeed = 0;        // 0-255 PWM value
bool motorDirection = true; // true = forward, false = reverse
bool motorEnabled = false;  // Motor on/off state

// Web Server
WebServer server(80);

// Alarm Data Structure
struct AlarmData {
  String id;
  String time;
  String label;
  bool enabled;
  String repeatDays;
  String action;
};

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("ESP32-C3 Motor Controller Starting...");
  
  // Initialize GPIO pins
  setupPins();
  
  // Setup WiFi hotspot
  setupWiFi();
  
  // Setup web server routes
  setupWebServer();
  
  // Start server
  server.begin();
  Serial.println("HTTP server started");
  Serial.println("Connect to WiFi: " + String(ssid));
  Serial.println("Password: " + String(password));
  Serial.println("IP address: " + WiFi.softAPIP().toString());
  
  // Initial status
  updateStatusLED();
}

void loop() {
  server.handleClient();
  delay(2);
}

void setupPins() {
  // Configure motor control pins
  pinMode(MOTOR_IN1, OUTPUT);
  pinMode(MOTOR_IN2, OUTPUT);
  pinMode(MOTOR_ENA, OUTPUT);
  pinMode(STATUS_LED, OUTPUT);
  
  // Initialize motor to stopped state
  digitalWrite(MOTOR_IN1, LOW);
  digitalWrite(MOTOR_IN2, LOW);
  analogWrite(MOTOR_ENA, 0);
  
  Serial.println("GPIO pins configured");
}

void setupWiFi() {
  // Create WiFi hotspot
  WiFi.softAP(ssid, password);
  
  // Configure IP settings
  IPAddress local_IP(192, 168, 4, 1);
  IPAddress gateway(192, 168, 4, 1);
  IPAddress subnet(255, 255, 255, 0);
  
  WiFi.softAPConfig(local_IP, gateway, subnet);
  
  Serial.println("WiFi hotspot created");
}

void setupWebServer() {
  // Status endpoint
  server.on("/status", HTTP_GET, []() {
    String response = "{\"status\":\"online\",\"motor_enabled\":" + 
                     String(motorEnabled ? "true" : "false") + 
                     ",\"motor_speed\":" + String(motorSpeed) + 
                     ",\"motor_direction\":" + String(motorDirection ? "true" : "false") + "}";
    server.send(200, "application/json", response);
    Serial.println("Status requested: " + response);
  });
  
  // Alarm endpoint - receives commands from Swift app
  server.on("/alarm", HTTP_POST, []() {
    if (server.hasArg("plain")) {
      String body = server.arg("plain");
      Serial.println("Received alarm data: " + body);
      
      // Parse JSON
      DynamicJsonDocument doc(1024);
      DeserializationError error = deserializeJson(doc, body);
      
      if (error) {
        Serial.println("JSON parsing failed: " + String(error.c_str()));
        server.send(400, "application/json", "{\"error\":\"Invalid JSON\"}");
        return;
      }
      
      // Extract alarm data
      AlarmData alarm;
      alarm.id = doc["id"].as<String>();
      alarm.time = doc["time"].as<String>();
      alarm.label = doc["label"].as<String>();
      alarm.enabled = doc["enabled"].as<bool>();
      alarm.repeatDays = doc["repeatDays"].as<String>();
      alarm.action = doc["action"].as<String>();
      
      // Process alarm command
      processAlarmCommand(alarm);
      
      // Send response
      String response = "{\"status\":\"success\",\"action\":\"" + alarm.action + 
                       "\",\"alarm_id\":\"" + alarm.id + "\"}";
      server.send(200, "application/json", response);
      Serial.println("Alarm processed: " + response);
    } else {
      server.send(400, "application/json", "{\"error\":\"No data received\"}");
    }
  });
  
  // Motor control endpoints
  server.on("/motor/start", HTTP_POST, []() {
    startMotor();
    server.send(200, "application/json", "{\"status\":\"Motor started\"}");
  });
  
  server.on("/motor/stop", HTTP_POST, []() {
    stopMotor();
    server.send(200, "application/json", "{\"status\":\"Motor stopped\"}");
  });
  
  server.on("/motor/speed", HTTP_POST, []() {
    if (server.hasArg("plain")) {
      String body = server.arg("plain");
      DynamicJsonDocument doc(256);
      deserializeJson(doc, body);
      
      int speed = doc["speed"].as<int>();
      setMotorSpeed(speed);
      
      String response = "{\"status\":\"Speed set to " + String(speed) + "\"}";
      server.send(200, "application/json", response);
    } else {
      server.send(400, "application/json", "{\"error\":\"No speed data\"}");
    }
  });
  
  server.on("/motor/direction", HTTP_POST, []() {
    if (server.hasArg("plain")) {
      String body = server.arg("plain");
      DynamicJsonDocument doc(256);
      deserializeJson(doc, body);
      
      bool direction = doc["direction"].as<bool>();
      setMotorDirection(direction);
      
      String response = "{\"status\":\"Direction set to " + String(direction ? "forward" : "reverse") + "\"}";
      server.send(200, "application/json", response);
    } else {
      server.send(400, "application/json", "{\"error\":\"No direction data\"}");
    }
  });
  
  // Root endpoint
  server.on("/", HTTP_GET, []() {
    String html = "<html><body>";
    html += "<h1>ESP32-C3 Motor Controller</h1>";
    html += "<p>Status: Online</p>";
    html += "<p>Motor Enabled: " + String(motorEnabled ? "Yes" : "No") + "</p>";
    html += "<p>Motor Speed: " + String(motorSpeed) + "</p>";
    html += "<p>Motor Direction: " + String(motorDirection ? "Forward" : "Reverse") + "</p>";
    html += "<h2>Manual Control</h2>";
    html += "<button onclick=\"fetch('/motor/start', {method:'POST'})\">Start Motor</button> ";
    html += "<button onclick=\"fetch('/motor/stop', {method:'POST'})\">Stop Motor</button><br><br>";
    html += "<button onclick=\"fetch('/motor/speed', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({speed:128})})\">Set Speed 50%</button> ";
    html += "<button onclick=\"fetch('/motor/speed', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({speed:255})})\">Set Speed 100%</button><br><br>";
    html += "<button onclick=\"fetch('/motor/direction', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({direction:true})})\">Forward</button> ";
    html += "<button onclick=\"fetch('/motor/direction', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({direction:false})})\">Reverse</button>";
    html += "</body></html>";
    server.send(200, "text/html", html);
  });
}

void processAlarmCommand(AlarmData alarm) {
  Serial.println("Processing alarm: " + alarm.label + " (" + alarm.action + ")");
  
  if (alarm.action == "add" || alarm.action == "update") {
    if (alarm.enabled) {
      // Alarm is enabled - could trigger motor action
      // For example: start motor when alarm is added/enabled
      startMotor();
      setMotorSpeed(200); // Medium speed
      Serial.println("Alarm enabled - Motor started");
    } else {
      // Alarm is disabled - stop motor
      stopMotor();
      Serial.println("Alarm disabled - Motor stopped");
    }
  } else if (alarm.action == "delete") {
    // Alarm deleted - stop motor
    stopMotor();
    Serial.println("Alarm deleted - Motor stopped");
  } else if (alarm.action == "toggle") {
    if (alarm.enabled) {
      startMotor();
      setMotorSpeed(150);
      Serial.println("Alarm toggled ON - Motor started");
    } else {
      stopMotor();
      Serial.println("Alarm toggled OFF - Motor stopped");
    }
  } else if (alarm.action == "trigger") {
    // Alarm triggered - start motor with high speed
    startMotor();
    setMotorSpeed(255); // Full speed for alarm trigger
    Serial.println("🔔 ALARM TRIGGERED: " + alarm.label + " - Motor started at full speed!");
    
    // Optional: Run motor for a few seconds then stop
    delay(3000); // Run for 3 seconds
    stopMotor();
    Serial.println("Alarm motor sequence completed");
  }
  
  updateStatusLED();
}

void startMotor() {
  motorEnabled = true;
  digitalWrite(MOTOR_IN1, motorDirection ? HIGH : LOW);
  digitalWrite(MOTOR_IN2, motorDirection ? LOW : HIGH);
  analogWrite(MOTOR_ENA, motorSpeed);
  Serial.println("Motor started - Speed: " + String(motorSpeed) + ", Direction: " + String(motorDirection ? "Forward" : "Reverse"));
}

void stopMotor() {
  motorEnabled = false;
  digitalWrite(MOTOR_IN1, LOW);
  digitalWrite(MOTOR_IN2, LOW);
  analogWrite(MOTOR_ENA, 0);
  Serial.println("Motor stopped");
}

void setMotorSpeed(int speed) {
  motorSpeed = constrain(speed, 0, 255);
  if (motorEnabled) {
    analogWrite(MOTOR_ENA, motorSpeed);
  }
  Serial.println("Motor speed set to: " + String(motorSpeed));
}

void setMotorDirection(bool direction) {
  motorDirection = direction;
  if (motorEnabled) {
    digitalWrite(MOTOR_IN1, motorDirection ? HIGH : LOW);
    digitalWrite(MOTOR_IN2, motorDirection ? LOW : HIGH);
  }
  Serial.println("Motor direction set to: " + String(motorDirection ? "Forward" : "Reverse"));
}

void updateStatusLED() {
  // Blink LED based on motor state
  if (motorEnabled) {
    digitalWrite(STATUS_LED, HIGH);
    delay(100);
    digitalWrite(STATUS_LED, LOW);
  } else {
    digitalWrite(STATUS_LED, LOW);
  }
}
