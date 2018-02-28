
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

Servo shutter1;
Servo shutter2;

MCP4725 dac; // create dac object

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
// global variables
volatile int servo1_state = LOW;
volatile int servo2_state = LOW;
int lastInjectButtonState = LOW;
int injectButtonState;
int tempSensor1_val = 0;
int humiSensor1_val = 0;
int tempSensor2_val = 0;
int humiSensor2_val = 0;
int tempSensor3_val = 0;
int humiSensor3_val = 0;
int dacAddr = 0x62;
int dacSetpoint;
boolean dacRecvInProgress = false;
byte transmitStatus;

void setup() {
  Serial.begin(9600);
  // declare pinMode of digital pins
  pinMode(injectTrigger, OUTPUT);
  pinMode(contactLED, OUTPUT);
  pinMode(servo1PWM, OUTPUT);
  pinMode(servo2PWM, OUTPUT);
  pinMode(injectPushbutton, INPUT);
  pinMode(contactSensor, INPUT);
  // attach pins to the servo object
  shutter1.attach(servo1PWM);
  shutter2.attach(servo2PWM);
  // default injector pin to HIGH
  digitalWrite(injectTrigger, HIGH);
  // check whether i2c device is attached
  // NB this will silently hang if I2C pins are
  // being pulled LOW from elsewhere in the circuit
  Wire.begin();
  Wire.beginTransmission(dacAddr);
  transmitStatus = Wire.endTransmission();
  if (transmitStatus == 0) {
    // set up dac
    Serial.println("Connected to I2C device");
    dac.begin(dacAddr);
    dac.setFastMode(); // set i2c communication to 400 kHz
    // important to read dac value in setup: Arduino resets
    // every time a new serial connection to Matlab starts
    dacSetpoint = dac.readCurrentDacVal();
  }
  else {
    Serial.print("Did not connect to I2C device. Status ");
    Serial.println(transmitStatus);
  }
}

void loop() {
  if (Serial.available() > 0) {
    byte input = Serial.read();
    // behavior depends on value of input
    // perform dac tasks only if I2C connected at setup
    if (dacRecvInProgress) {
      if (transmitStatus == 0) {
        // receive remaining 8 bits for dac and set
        dacSetpoint += input;
        // report what's going on
        Serial.println("Last 8 dac bits");
        String setpointPrefix = "dacSetpoint: ";
        String setpointReport = setpointPrefix + dacSetpoint;
        Serial.println(setpointReport);
        // only try to set voltage if it's in range
        if (dacSetpoint >= 0 && dacSetpoint <= 4095) {
          dac.setVoltageFast(dacSetpoint);
        }
        dacRecvInProgress = false;
      }
      else {
        Serial.println("Invalid command. No I2C connection.");
      }
    }
    // check for flag bit for start of dac transmission
    else if (input & 0b10000000)  {
      if (transmitStatus == 0) {
      dacRecvInProgress = true;
      // set high bits of dacSetpoint
      dacSetpoint = (input & 0b00001111) * 256;
      Serial.println("First 4 dac bits");
      }
      else {
        Serial.println("Invalid command. No I2C connection.");
      }
    }
    // d = check dc setpoint
    else if (input == 'd') {
      if (transmitStatus == 0) {
      Serial.println(dacSetpoint);
      }
      else {
        Serial.println("Invalid command. No I2C connection.");
      }
    }
    // s = single injection
    else if (input == 's') {
      digitalWrite(injectTrigger, LOW);
      digitalWrite(injectTrigger, HIGH);
      Serial.println("Inject");
      blinkLED();
    }
    // 1 = 0.1 sec burst, 200Hz
    else if (input == '1') {
      blinkLED();
      for (int i = 0; i < 20; i++) {
        digitalWrite(injectTrigger, LOW);
        digitalWrite(injectTrigger, HIGH);
        delay(5);
        Serial.println(i);
      }
    }
    // 5 = 5 sec burst, 50Hz
    else if (input == '5') {
      blinkLED();
      for (int i = 0; i < 250; i ++) {
        digitalWrite(injectTrigger, LOW);
        digitalWrite(injectTrigger, HIGH);
        delay(20);
        Serial.println(i);
      }
    }
    // c = close shutter
    else if (input == 'c') {
      //servo1_state = HIGH;
      //servo2_state = HIGH;
      shutter1.write(30);
      shutter2.write(30);
      Serial.println("closing shutters");
    }
    // o = open shutter
    else if (input == 'o') {
      // servo1_state = LOW;
      // servo2_state = LOW;
      shutter1.write(150);
      shutter2.write(150);
      Serial.println("opening shutters");
    }
    // r = read analog inputs
    else if (input == 'r') {
      tempSensor1_val = analogRead(tempSensor1);
      humiSensor1_val = analogRead(humiSensor1);
      tempSensor2_val = analogRead(tempSensor2);
      humiSensor2_val = analogRead(humiSensor2);
      tempSensor3_val = analogRead(tempSensor3);
      humiSensor3_val = analogRead(humiSensor3);

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
  contactCheck();
  checkInjectButton();
}

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

// depending on the readout of the voltage divider,
// turn on/off the LED indicator
void contactCheck() {
  (digitalRead(contactSensor)) ?
  digitalWrite(contactLED, HIGH)  : digitalWrite(contactLED, LOW);
}

int lastDebounceTime;
int debounceDelay = 40;
int counter = 0;

void blinkLED() {
  for (int numloops = 1; numloops < 5; numloops++) {
    // turn the pin on:
    digitalWrite(contactLED, HIGH);
    delay(50);
    // turn the pin off:
    digitalWrite(contactLED, LOW);
    delay(50);
  }
}

void checkInjectButton() {
  int reading = digitalRead(injectPushbutton);
  // If the switch changed, due to noise or pressing:
  if (reading != lastInjectButtonState) {
    // reset the debouncing timer
    lastDebounceTime = millis();
  }

  if ((millis() - lastDebounceTime) > debounceDelay) {
    // whatever the reading is at, it's been there for longer
    // than the debounce delay, so take it as the actual current state:

    // if the button state has changed:
    if (reading != injectButtonState) {
      injectButtonState = reading;

      // only toggle the LED if the new button state is HIGH
      if (injectButtonState == HIGH) {
        digitalWrite(injectTrigger, LOW);
        digitalWrite(injectTrigger, HIGH);
        Serial.println("Injected");
        blinkLED();
      }
    }
  }

  // save the reading.  Next time through the loop,
  // it'll be the lastButtonState:
  lastInjectButtonState = reading;
}
