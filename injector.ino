// This is the code for the Arduino attached with the injector shield
// The PCB design for the shield can be found at "arduino_v2.0.pcb"
// This code has five functions: 
//     1. Inject using pushbutton and serial command
//     2. Shutter the servos using the pushbuttons and serial command
//     3. Read the temperature and humidity using the sensors
//     4. Deteect if injector made proper contact
//     5. Interrupt routine for the laser shutter

// Author: Htoo Wai Htet and Andy Huisman
// Version: 2.0 to conntect to Arduino board v3.1

#include <Servo.h>

Servo shutter1;
Servo shutter2;

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

void setup() {
  Serial.begin(9600);
  // declare pinMode of digital pins
  pinMode(injectTrigger, OUTPUT);
  pinMode(contactLED, OUTPUT);
  pinMode(servo1PWM, OUTPUT);
  pinMode(servo2PWM, OUTPUT);
  pinMode(injectPushbutton, INPUT);
  pinMode(contactSensor, INPUT);
  // attaches the pin to the servo object
  shutter1.attach(servo1PWM);   
  shutter2.attach(servo2PWM);
  // defaults the injector pin to HIGH
  digitalWrite(injectTrigger, HIGH);
}

void loop() {
  // put your main code here, to run repeatedly:
  if (Serial.available()) {
    char input = Serial.read();
    // s = single injection
    if (input == 's') {
      digitalWrite(injectTrigger, LOW);
      digitalWrite(injectTrigger, HIGH);
      Serial.println("Inject");
      blinkLED();
    }
    // 1 = 0.1 sec burst, 200Hz
    if (input == '1') {
      for (int i = 0; i < 20; i++) {
        digitalWrite(injectTrigger, LOW);
        digitalWrite(injectTrigger, HIGH);
        delay(5);
        Serial.println(i); 
      }
    }
    // 5 = 5 sec burst, 50Hz
    if (input == '5') {
      for (int i = 0; i < 250; i ++) {
        digitalWrite(injectTrigger, LOW);
        digitalWrite(injectTrigger, HIGH);
        delay(20);
        Serial.println(i);
      }
    }
    // c = close shutter
    if (input == 'c') {
      //servo1_state = HIGH;
      //servo2_state = HIGH;
      shutter1.write(30);
      shutter2.write(30);
      Serial.println("closing shutters");
    }
    // o = open shutter
    if (input == 'o') {
     // servo1_state = LOW;
     // servo2_state = LOW;
      shutter1.write(150);
      shutter2.write(150);
      Serial.println("opening shutters");
    }  
   // r = read analog inputs
    if (input == 'r') {
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
//  checkServo2Button();
//  checkServo1Button();
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
  (digitalRead(contactSensor))? 
  digitalWrite(contactLED, HIGH)  : digitalWrite(contactLED, LOW);
}

int lastDebounceTime;
int debounceDelay = 40;
int counter = 0;

void blinkLED(){
    for (int numloops = 1; numloops < 5; numloops++) {
    // turn the pin on:
    digitalWrite(contactLED, HIGH);
    delay(50);
    // turn the pin off:
    digitalWrite(contactLED, LOW);
    delay(50);
  } }

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


