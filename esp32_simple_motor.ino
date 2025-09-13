/*
 * ESP32-C3 Simple Motor Controller
 * Simplified version for basic motor control
 * 
 * Hardware Setup:
 * - ESP32-C3 XIAO board
 * - Any motor driver (L298N, L9110, etc.)
 * - DC Motor with separate power supply
 * 
 * Pin Connections (adjust for your driver):
 * - GPIO2 -> Motor Direction/Speed control
 * - GPIO3 -> Motor Direction control (if needed)
 * - GPIO4 -> Status LED
 * 
 * WiFi: Creates hotspot "ESP32-Motor" with password "12345678"
 */

#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>

// WiFi Configuration
const char* ssid = "ESP32-Motor";
const char* password = "12345678";

// Motor Control Pins
#define MOTOR_PIN1 2    // Primary motor control
#define MOTOR_PIN2 3    // Secondary motor control (if needed)
#define STATUS_LED 4    // Status LED

// Motor State
bool motorRunning = false;
int motorSpeed = 128; // 0-255

WebServer server(80);

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("ESP32-C3 Simple Motor Controller");
  
  // Setup pins
  pinMode(MOTOR_PIN1, OUTPUT);
  pinMode(MOTOR_PIN2, OUTPUT);
  pinMode(STATUS_LED, OUTPUT);
  
  // Stop motor initially
  stopMotor();
  
  // Setup WiFi
  WiFi.softAP(ssid, password);
  IPAddress local_IP(192, 168, 4, 1);
  IPAddress gateway(192, 168, 4, 1);
  IPAddress subnet(255, 255, 255, 0);
  WiFi.softAPConfig(local_IP, gateway, subnet);
  
  // Setup web server
  setupWebServer();
  
  server.begin();
  Serial.println("Server started at: " + WiFi.softAPIP().toString());
}

void loop() {
  server.handleClient();
  delay(2);
}

void setupWebServer() {
  // Status endpoint
  server.on("/status", HTTP_GET, []() {
    String response = "{\"status\":\"online\",\"motor_running\":" + 
                     String(motorRunning ? "true" : "false") + 
                     ",\"motor_speed\":" + String(motorSpeed) + "}";
    server.send(200, "application/json", response);
  });
  
  // Alarm endpoint - receives commands from Swift app
  server.on("/alarm", HTTP_POST, []() {
    if (server.hasArg("plain")) {
      String body = server.arg("plain");
      Serial.println("Received: " + body);
      
      DynamicJsonDocument doc(1024);
      DeserializationError error = deserializeJson(doc, body);
      
      if (!error) {
        String action = doc["action"].as<String>();
        bool enabled = doc["enabled"].as<bool>();
        
        if (action == "add" || action == "update" || action == "toggle") {
          if (enabled) {
            startMotor();
            Serial.println("Alarm enabled - Motor started");
          } else {
            stopMotor();
            Serial.println("Alarm disabled - Motor stopped");
          }
        } else if (action == "delete") {
          stopMotor();
          Serial.println("Alarm deleted - Motor stopped");
        }
      }
      
      server.send(200, "application/json", "{\"status\":\"success\"}");
    } else {
      server.send(400, "application/json", "{\"error\":\"No data\"}");
    }
  });
  
  // Simple motor control
  server.on("/motor/start", HTTP_POST, []() {
    startMotor();
    server.send(200, "application/json", "{\"status\":\"Motor started\"}");
  });
  
  server.on("/motor/stop", HTTP_POST, []() {
    stopMotor();
    server.send(200, "application/json", "{\"status\":\"Motor stopped\"}");
  });
  
  // Root page
  server.on("/", HTTP_GET, []() {
    String html = "<html><body>";
    html += "<h1>ESP32-C3 Motor Controller</h1>";
    html += "<p>Motor Status: " + String(motorRunning ? "RUNNING" : "STOPPED") + "</p>";
    html += "<p>Speed: " + String(motorSpeed) + "</p>";
    html += "<button onclick=\"fetch('/motor/start', {method:'POST'})\">START MOTOR</button> ";
    html += "<button onclick=\"fetch('/motor/stop', {method:'POST'})\">STOP MOTOR</button>";
    html += "</body></html>";
    server.send(200, "text/html", html);
  });
}

void startMotor() {
  motorRunning = true;
  
  // For L298N driver:
  digitalWrite(MOTOR_PIN1, HIGH);
  digitalWrite(MOTOR_PIN2, LOW);
  
  // For L9110 driver (uncomment if using):
  // analogWrite(MOTOR_PIN1, motorSpeed);
  // digitalWrite(MOTOR_PIN2, LOW);
  
  digitalWrite(STATUS_LED, HIGH);
  Serial.println("Motor started");
}

void stopMotor() {
  motorRunning = false;
  
  // Stop motor
  digitalWrite(MOTOR_PIN1, LOW);
  digitalWrite(MOTOR_PIN2, LOW);
  
  digitalWrite(STATUS_LED, LOW);
  Serial.println("Motor stopped");
}
