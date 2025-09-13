# ESP32-C3 Motor Controller Setup Guide

## Hardware Components Needed

### Required Components:
1. **ESP32-C3 XIAO board** - Main controller
2. **Motor Driver Module** - Choose one:
   - **L298N** (recommended for beginners) - Dual H-bridge, handles up to 2A
   - **L9110** - Compact dual H-bridge, good for small motors
   - **TB6612FNG** - More efficient, better for battery projects
3. **DC Motor** - 6V-12V DC motor (adjust voltage to your needs)
4. **Power Supply** - Separate power source for motor (battery pack or wall adapter)
5. **Jumper Wires** - For connections
6. **Breadboard** (optional) - For prototyping

### Optional Components:
- **Status LED** - Visual feedback
- **Resistors** - For LED current limiting
- **Capacitors** - For motor noise filtering

## Wiring Diagrams

### L298N Motor Driver (Recommended)
```
ESP32-C3 XIAO    L298N Motor Driver
─────────────────────────────────────
GPIO2 (Pin 2)  → IN1 (Direction 1)
GPIO3 (Pin 3)  → IN2 (Direction 2)  
GPIO4 (Pin 4)  → ENA (Speed/PWM)
GPIO5 (Pin 5)  → LED (Status indicator)
GND           → GND
3.3V          → VCC (if needed for logic)

L298N Motor Driver    Motor & Power
─────────────────────────────────────
OUT1          → Motor Terminal 1
OUT2          → Motor Terminal 2
VCC           → Motor Power Supply (+)
GND           → Motor Power Supply (-)
```

### L9110 Motor Driver (Compact)
```
ESP32-C3 XIAO    L9110 Motor Driver
─────────────────────────────────────
GPIO2 (Pin 2)  → A-IA (Motor A Input 1)
GPIO3 (Pin 3)  → A-IB (Motor A Input 2)
GPIO4 (Pin 4)  → VCC (Power)
GPIO5 (Pin 5)  → LED (Status indicator)
GND           → GND

L9110 Motor Driver    Motor & Power
─────────────────────────────────────
A-OA           → Motor Terminal 1
A-OB           → Motor Terminal 2
VCC            → Motor Power Supply (+)
GND            → Motor Power Supply (-)
```

## Software Setup

### 1. Arduino IDE Setup
1. Install **Arduino IDE** (latest version)
2. Add ESP32 board support:
   - Go to File → Preferences
   - Add this URL to "Additional Board Manager URLs":
     ```
     https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
     ```
3. Install ESP32 board package:
   - Go to Tools → Board → Boards Manager
   - Search for "ESP32" and install "ESP32 by Espressif Systems"

### 2. Install Required Libraries
In Arduino IDE, go to Tools → Manage Libraries and install:
- **ArduinoJson** (by Benoit Blanchon) - Version 6.x or 7.x
- **WebServer** (usually included with ESP32 package)

### 3. Board Configuration
1. Select board: **Tools → Board → ESP32 Arduino → XIAO_ESP32C3**
2. Select port: **Tools → Port → [Your ESP32 port]**
3. Set upload speed: **Tools → Upload Speed → 921600**

### 4. Upload Code
1. Open the `esp32_motor_controller.ino` file
2. Click **Upload** (or Ctrl+U)
3. Open **Serial Monitor** (Tools → Serial Monitor) at 115200 baud

## Testing & Operation

### 1. WiFi Connection
1. After upload, the ESP32 creates a WiFi hotspot named **"ESP32-Motor"**
2. Password: **"12345678"**
3. Connect your Mac/iPhone to this network
4. ESP32 IP address: **192.168.4.1**

### 2. Test via Web Browser
1. Open browser and go to: `http://192.168.4.1`
2. You should see the motor controller web interface
3. Test manual controls (Start/Stop, Speed, Direction)

### 3. Test via Swift App
1. Open your Swift alarm app
2. Go to Network Settings (WiFi icon)
3. Set ESP32 IP: `192.168.4.1`
4. Set Port: `80`
5. Test connection
6. Create an alarm - motor should start/stop based on alarm state

## Motor Driver Selection Guide

### L298N (Recommended for Learning)
- **Pros**: Easy to use, dual motor support, built-in voltage regulator
- **Cons**: Higher power consumption, gets hot
- **Best for**: Learning, prototyping, motors up to 2A
- **Price**: $3-5

### L9110 (Compact & Efficient)
- **Pros**: Small size, low power consumption, good efficiency
- **Cons**: Single motor only, lower current capacity
- **Best for**: Small projects, battery-powered applications
- **Price**: $2-3

### TB6612FNG (Professional)
- **Pros**: Very efficient, low heat, high current capacity
- **Cons**: More expensive, SMD package (harder to prototype)
- **Best for**: Final projects, high-performance applications
- **Price**: $5-8

## Power Supply Requirements

### ESP32-C3 Power
- **Voltage**: 3.3V (regulated from USB or external supply)
- **Current**: ~100-200mA during operation
- **Source**: USB cable or 3.3V-5V external supply

### Motor Power Supply
- **Voltage**: Match your motor (typically 6V, 9V, or 12V)
- **Current**: Must exceed motor's stall current (usually 2-5x rated current)
- **Example**: 12V 2A wall adapter for a 12V 1A motor

## Troubleshooting

### Common Issues:

1. **Motor doesn't move**
   - Check power supply connections
   - Verify motor driver wiring
   - Test with manual web interface first

2. **WiFi connection fails**
   - Check if ESP32 hotspot appears in WiFi list
   - Try different password or reset ESP32
   - Check Serial Monitor for error messages

3. **Swift app can't connect**
   - Verify IP address (192.168.4.1)
   - Check port number (80)
   - Test with browser first

4. **Motor runs but very slow/weak**
   - Check power supply voltage and current capacity
   - Verify PWM speed setting
   - Check for loose connections

### Debug Commands:
- Check Serial Monitor for status messages
- Use web interface at `http://192.168.4.1` for manual testing
- Test individual endpoints with curl:
  ```bash
  curl -X GET http://192.168.4.1/status
  curl -X POST http://192.168.4.1/motor/start
  ```

## Safety Notes

⚠️ **Important Safety Considerations:**
- Always use separate power supplies for ESP32 and motor
- Never connect motor power directly to ESP32 pins
- Use appropriate current ratings for your motor
- Add fuses or current limiting if using high-power motors
- Keep motor driver cool (add heatsink if needed)
- Double-check all connections before powering on

## Next Steps

1. **Upload the code** to your ESP32-C3
2. **Wire the motor driver** according to the diagram
3. **Test with web interface** first
4. **Connect your Swift app** and test alarm functionality
5. **Customize the code** for your specific motor and application needs

The ESP32 will now receive HTTP commands from your Swift alarm app and control the motor accordingly!
