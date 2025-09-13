"""
ESP32-C3 Motor Controller - MicroPython Version
Alternative to Arduino IDE for those who prefer Python

Hardware Setup:
- ESP32-C3 XIAO board
- Motor driver (L298N, L9110, etc.)
- DC Motor with separate power supply

Pin Connections:
- GPIO2 -> Motor control pin 1
- GPIO3 -> Motor control pin 2
- GPIO4 -> Status LED

WiFi: Creates hotspot "ESP32-Motor" with password "12345678"
"""

import network
import socket
import json
from machine import Pin, PWM
import time

# Motor control pins
MOTOR_PIN1 = Pin(2, Pin.OUT)
MOTOR_PIN2 = Pin(3, Pin.OUT)
STATUS_LED = Pin(4, Pin.OUT)

# Motor state
motor_running = False
motor_speed = 128

# WiFi configuration
SSID = "ESP32-Motor"
PASSWORD = "12345678"

def setup_wifi():
    """Setup WiFi hotspot"""
    ap = network.WLAN(network.AP_IF)
    ap.active(True)
    ap.config(essid=SSID, password=PASSWORD)
    
    # Configure IP
    ap.ifconfig(('192.168.4.1', '255.255.255.0', '192.168.4.1', '8.8.8.8'))
    
    print("WiFi hotspot created:")
    print("SSID:", SSID)
    print("Password:", PASSWORD)
    print("IP:", ap.ifconfig()[0])
    
    return ap

def stop_motor():
    """Stop the motor"""
    global motor_running
    motor_running = False
    MOTOR_PIN1.off()
    MOTOR_PIN2.off()
    STATUS_LED.off()
    print("Motor stopped")

def start_motor():
    """Start the motor"""
    global motor_running
    motor_running = True
    MOTOR_PIN1.on()
    MOTOR_PIN2.off()
    STATUS_LED.on()
    print("Motor started")

def process_alarm_command(data):
    """Process alarm command from Swift app"""
    try:
        alarm_data = json.loads(data)
        action = alarm_data.get('action', '')
        enabled = alarm_data.get('enabled', False)
        
        print(f"Processing alarm: {action}, enabled: {enabled}")
        
        if action in ['add', 'update', 'toggle']:
            if enabled:
                start_motor()
            else:
                stop_motor()
        elif action == 'delete':
            stop_motor()
            
        return '{"status": "success"}'
    except Exception as e:
        print(f"Error processing alarm: {e}")
        return '{"error": "Invalid data"}'

def handle_request(conn, addr):
    """Handle HTTP requests"""
    try:
        request = conn.recv(1024).decode('utf-8')
        print(f"Request from {addr}: {request[:100]}...")
        
        # Parse request
        lines = request.split('\n')
        if lines:
            request_line = lines[0]
            method, path, _ = request_line.split(' ')
            
            # Get request body if POST
            body = ""
            if method == "POST":
                for i, line in enumerate(lines):
                    if line.strip() == "" and i < len(lines) - 1:
                        body = lines[i + 1]
                        break
            
            # Route requests
            if path == "/status":
                response = f'{{"status": "online", "motor_running": {str(motor_running).lower()}, "motor_speed": {motor_speed}}}'
                content_type = "application/json"
                
            elif path == "/alarm" and method == "POST":
                response = process_alarm_command(body)
                content_type = "application/json"
                
            elif path == "/motor/start" and method == "POST":
                start_motor()
                response = '{"status": "Motor started"}'
                content_type = "application/json"
                
            elif path == "/motor/stop" and method == "POST":
                stop_motor()
                response = '{"status": "Motor stopped"}'
                content_type = "application/json"
                
            elif path == "/":
                response = f"""
                <html><body>
                <h1>ESP32-C3 Motor Controller</h1>
                <p>Motor Status: {'RUNNING' if motor_running else 'STOPPED'}</p>
                <p>Speed: {motor_speed}</p>
                <button onclick="fetch('/motor/start', {{method:'POST'}})">START MOTOR</button>
                <button onclick="fetch('/motor/stop', {{method:'POST'}})">STOP MOTOR</button>
                </body></html>
                """
                content_type = "text/html"
                
            else:
                response = '{"error": "Not found"}'
                content_type = "application/json"
            
            # Send response
            http_response = f"""HTTP/1.1 200 OK
Content-Type: {content_type}
Content-Length: {len(response)}
Connection: close

{response}"""
            
            conn.send(http_response.encode('utf-8'))
            
    except Exception as e:
        print(f"Error handling request: {e}")
    finally:
        conn.close()

def main():
    """Main function"""
    print("ESP32-C3 Motor Controller - MicroPython")
    
    # Initialize motor to stopped state
    stop_motor()
    
    # Setup WiFi
    ap = setup_wifi()
    
    # Create socket server
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('0.0.0.0', 80))
    s.listen(5)
    
    print("Server listening on port 80...")
    
    # Main loop
    while True:
        try:
            conn, addr = s.accept()
            handle_request(conn, addr)
        except KeyboardInterrupt:
            print("Shutting down...")
            break
        except Exception as e:
            print(f"Server error: {e}")
            time.sleep(1)
    
    s.close()

if __name__ == "__main__":
    main()
