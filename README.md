# Remote32

Project to replace my air conditioning remote by making a Matter, HomeKit compatible one. I've gotten the needed individual parts working just in time for the AC to be winterized and not used until next year. 

For Starting out and reference I used Swift Matter examples and Espressif’s RMT peripheral documentation.  
[Swift Matter Examples](https://github.com/swiftlang/swift-matter-examples)  
[ESP32 RMT peripheral](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/peripherals/rmt.html)

Environment variables will need to be set for each new Terminal instance. For me at the ESP directory

```
export TOOLCHAINS=org.swift.9cc1947527bacea
. ./esp-idf/export.sh
. ./esp-matter/export.sh
```

When in Remote32 directory:  
Set the board type for project  
`idf.py set-target esp32c6`  
Just building  
`idf.py build`  
When connected to the ESP32  
`idf.py build flash monitor`


-------


Still in progress so a lot of unhandled cases and or made for the expected cases of my set up. Feedback is welcome




Notes on what I happen to be using with my setup:
- ESP IDF (5.2.1)  
- swift --version is 6.2-dev (org.swift.9cc1947527bacea)  
- Adafruit ESP32-C6 Feather  
- ESP32-C6-DevKitM-1  
- NTE30131 LED (940nm wavelength was the goal)  
- 38 kHz signal IR receiver  
- NPN transistor 2n2222a and small ceramic capacitor with the IR LED

