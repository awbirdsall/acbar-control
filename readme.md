# acbar-control

Control ACBAR electrodynamic balance (EDB), using MATLAB & Arduino.

## Dependencies

`control_acbar.m` has been run with MATLAB 2016a, including the Image Acquisition Toolbox.

`injector/injector.ino` has been used with an Arduino Uno with custom circuit board and I2C connection to MCP4725 DAC. The code has a dependency on shtarbanov's MCP4725 library (https://github.com/shtarbanov/MCP4725), which is more fully featured than the library provided by Adafruit.

## Contributors

Originally developed by Andrew Huisman, Htoo Wai Htet, and the Huisman Lab at Union College. Further development by Adam Birdsall and the Keutsch Lab at Harvard University.
