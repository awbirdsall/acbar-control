
// injector.ino: code for Arduino with injector shield attached
// Written for PCB shield with design "Arduino Shield v3.1"
// This code has six functions:
//     1. Inject using pushbutton and serial command
//     2. Shutter the servos using the pushbuttons and serial command
//     3. Read the temperature and humidity using the sensors
//     4. Detect if injector made proper contact
//     5. Interrupt routine for the laser shutter
//     6. Communicate with I2C DAC chip to set DC trap voltage

// Code originally written as InjectorShield_v2
// Authors of InjectorShield_v2: Htoo Wai Htet and Andy Huisman, Union College
// Adapated by Keutsch Lab, Harvard University (Adam Birdsall)

#include <Servo.h>
#include <Wire.h>
// more fully-featured DAC library than Adafruit's
#include <MCP4725.h>

// servo and dac objects
Servo shutter1;
Servo shutter2;
MCP4725 dac;

// analog pins
const int tempSensor1 = 0;
const int humiSensor1 = 3;
const int tempSensor2 = 1;
const int humiSensor2 = 4;
const int tempSensor3 = 2;
const int humiSensor3 = 5;

// digital pins
const int injectTrigger = 11;
const int contactLED = 12;
const int servo1PWM = 5;
const int servo2PWM = 6;
const int injectPushbutton = 13;
const int contactSensor = 10;

// global state variables
volatile int servo1_state = LOW;
volatile int servo2_state = LOW;
int rawInjectButtonState = LOW;
int debouncedInjectButtonState;
int dacSetpoint;
boolean dacRecvInProgress = false;
// hardcode address, could be 0x60 thru 0x67
int dacAddr = 0x60;

void setup() {
  Serial.begin(9600);
  pinMode(injectTrigger, OUTPUT);
  pinMode(contactLED, OUTPUT);
  pinMode(servo1PWM, OUTPUT);
  pinMode(servo2PWM, OUTPUT);
  pinMode(injectPushbutton, INPUT);
  pinMode(contactSensor, INPUT);
  shutter1.attach(servo1PWM);
  shutter2.attach(servo2PWM);
  digitalWrite(injectTrigger, HIGH);
  setupDac(dacAddr);
}

void loop() {
  if (Serial.available() > 0) {
    readSerialInputByte();
  }
  checkCartridgeContact();
  checkInjectButton();
}

// SUPPORTING FUNCTIONS

// ISR for door open
void shutterClose() {
  servo1_state = HIGH;
  servo2_state = HIGH;
}

// ISR for door close
void shutterOpen() {
  servo1_state = LOW;
  servo2_state = LOW;
}

// depending on voltage divider readout,
// turn LED indicator on/off
void checkCartridgeContact() {
  (digitalRead(contactSensor)) ?
  digitalWrite(contactLED, HIGH)  : digitalWrite(contactLED, LOW);
}

void blinkLED() {
  for (int numloops = 1; numloops < 5; numloops++) {
    digitalWrite(contactLED, HIGH);
    delay(50);
    digitalWrite(contactLED, LOW);
    delay(50);
  }
}

void checkInjectButton() {
  int lastDebounceTime;
  int debounceDelay = 40;
  int reading = digitalRead(injectPushbutton);
  // reset debounce timer when raw button state changed
  if (reading != rawInjectButtonState) {
    lastDebounceTime = millis();
  }
  // filter out bounce
  if ((millis() - lastDebounceTime) > debounceDelay) {
    if (reading != debouncedInjectButtonState) {
      debouncedInjectButtonState = reading;
      if (debouncedInjectButtonState == HIGH) {
        // trigger injection
        digitalWrite(injectTrigger, LOW);
        digitalWrite(injectTrigger, HIGH);
        Serial.println("Injected");
        blinkLED();
      }
    }
  }
  // update rawInjectButtonState every loop
  rawInjectButtonState = reading;
}

byte checkDac(int dacAddr) {
  // empty transmission to check whether dac is there.
  // endTransmission() should return 0 if okay.
  Wire.beginTransmission(dacAddr);
  byte dacTransmitStatus = Wire.endTransmission();
  return dacTransmitStatus;
}

void setupDac(int addr) {
  // first, check whether i2c device is attached
  // NB this will silently hang if I2C pins are
  // being pulled LOW from elsewhere in the circuit
  Wire.begin();
  byte dacTransmitStatus = checkDac(addr);
  if (dacTransmitStatus == 0) {
    Serial.println("Connected to I2C device");
    dac.begin(addr);
    dac.setFastMode(); // set i2c communication to 400 kHz
    // important to read dac value in setup: Arduino resets
    // every time a new serial connection to Matlab starts
    dacSetpoint = dac.readCurrentDacVal();
  }
  else {
    Serial.print("Did not connect to I2C device. Status ");
    Serial.println(dacTransmitStatus);
  }
}

void readSerialInputByte() {
  // behavior depends on value of input:
  // 0b1xxx#### : start transmitting 12-bit value to DAC,
  //              #### are four highest bits, first '1'
  //              is flag, xxx are ignored
  // (any 8 bits) : transmit 8 lowest bits to DAC, if
  //                previous byte was first DAC byte
  // 'd' : print ACII string of 12-bit DAC setpoint
  // 'e' : report DAC EEPROM value (used on DAC startup)
  // 'f' : write current DAC setpoint to DAC EEPROM
  // 's' : single droplet injection
  // '1' : 20 droplet burst (0.1 sec, 200Hz)
  // '5' : 250 droplet burst (5 sec, 50Hz)
  // 'c' : close shutter
  // 'o' : open shutter
  // 'r' : read analog inputs (3x temp/humidity channels)
  //
  // perform dac tasks only if I2C connected at setup,
  // otherwise send string describing problem
  //
  // silently ignore any other received byte

  byte input = Serial.read();

  if (dacRecvInProgress) {
    if (checkDac(dacAddr) == 0) {
      // receive remaining 8 bits for dac and set
      dacSetpoint += input;
      // report what's going on
      String setpointPrefix = "Last 8 dac bits. dacSetpoint: ";
      String setpointReport = setpointPrefix + dacSetpoint;
      Serial.println(setpointReport);
      // only try to set voltage if it's in range
      if (dacSetpoint >= 0 && dacSetpoint <= 4095) {
        dac.setVoltageFast(dacSetpoint);
      }
      dacRecvInProgress = false;
    }
    else {
      // something weird went wrong to get here. abort
      // change to dac setpoint and reset variable to 0.
      dacSetpoint = 0;
      dacRecvInProgress = false;
      Serial.println("Invalid command. No I2C connection.");
    }
  }
  else if (input & 0b10000000)  {
    if (checkDac(dacAddr) == 0) {
      dacRecvInProgress = true;
      // set high bits of dacSetpoint
      dacSetpoint = (input & 0b00001111) * 256;
      Serial.println("First 4 dac bits");
    }
    else {
      Serial.println("Invalid command. No I2C connection.");
    }
  }
  else if (input == 'd') {
    if (checkDac(dacAddr) == 0) {
      // make sure Arduino variable is up-to-date
      dacSetpoint = dac.readCurrentDacVal();
      Serial.println(dacSetpoint);
    }
    else {
      Serial.println("Invalid command. No I2C connection.");
    }
  }
  else if (input == 'e') {
    if (checkDac(dacAddr) == 0) {
      int eepromVal = dac.readValFromEEPROM();
      Serial.println(eepromVal);
    }
    else {
      Serial.println("Invalid command. No I2C connection.");
    }
  }
  else if (input == 'f') {
    if (checkDac(dacAddr) == 0) {
      dacSetpoint = dac.readCurrentDacVal();
      // EEPROM write time 25-50 ms
      // EEPROM endurance 1 million cycles
      dac.setVoltageAndSave(dacSetpoint);
      Serial.println(dacSetpoint);
    }
    else {
      Serial.println("Invalid command. No I2C connection.");
    }
  }
  else if (input == 's') {
    digitalWrite(injectTrigger, LOW);
    digitalWrite(injectTrigger, HIGH);
    Serial.println("Inject");
    blinkLED();
  }
  else if (input == '1') {
    blinkLED();
    for (int i = 0; i < 20; i++) {
      digitalWrite(injectTrigger, LOW);
      digitalWrite(injectTrigger, HIGH);
      delay(5);
      Serial.println(i);
    }
  }
  else if (input == '5') {
    blinkLED();
    for (int i = 0; i < 250; i ++) {
      digitalWrite(injectTrigger, LOW);
      digitalWrite(injectTrigger, HIGH);
      delay(20);
      Serial.println(i);
    }
  }
  else if (input == 'c') {
    //servo1_state = HIGH;
    //servo2_state = HIGH;
    shutter1.write(30);
    shutter2.write(30);
    Serial.println("closing shutters");
  }
  else if (input == 'o') {
    // servo1_state = LOW;
    // servo2_state = LOW;
    shutter1.write(150);
    shutter2.write(150);
    Serial.println("opening shutters");
  }
  else if (input == 'r') {
    int tempSensor1_val = analogRead(tempSensor1);
    int humiSensor1_val = analogRead(humiSensor1);
    int tempSensor2_val = analogRead(tempSensor2);
    int humiSensor2_val = analogRead(humiSensor2);
    int tempSensor3_val = analogRead(tempSensor3);
    int humiSensor3_val = analogRead(humiSensor3);

    Serial.print(tempSensor1_val);
    Serial.print(" ");
    Serial.print(humiSensor1_val);
    Serial.print(" ");
    Serial.print(tempSensor2_val);
    Serial.print(" ");
    Serial.print(humiSensor2_val);
    Serial.print(" ");
    Serial.print(tempSensor3_val);
    Serial.print(" ");
    Serial.println(humiSensor3_val);
  }
}
