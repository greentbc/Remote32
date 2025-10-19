# Remote32


Used [Swift Matter Examples] (https://github.com/swiftlang/swift-matter-examples) as a starting point of refrence. 
Using ESP32 RMT peripheral:
https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/peripherals/rmt.html

swift --version //to check
export TOOLCHAINS=org.swift.9cc1947527bacea

. ./esp-idf/export.sh
. ./esp-matter/export.sh
idf.py set-target esp32c6

idf.py build flash monitor
