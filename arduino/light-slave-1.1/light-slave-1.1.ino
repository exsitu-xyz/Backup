/**
 * Exsitu - Programme d'éclairage des objets
 * 
 * V0.5 2019-11-04 (fadein/hold/fadeout)
 * V0.6 2019-11-05 (background)
 * 
 * Stripes PINOUT fixed by the OctoWS2811 : pins 2, 14, 7, 8, 6, 20, 21, 5
 * So you MUST convert led id to bypass the pin 8 with translatePin(int pin) (The pins 2, 14, 7, 6, 20 are pysicaly connected)
 */

// Load OctoWS2811 library
#include <OctoWS2811.h>

// Use hardware UART SERIAL1 instead USB
#define HWSERIAL Serial1

#define MAXLEDS 1000
#define NUM_LEDS_PER_STRIP 200
#define OCTOWS2811CONFIG WS2811_GRB | WS2811_800kHz

// Define the delay in ms between entire refresh of lights (fadein/fadeout)
// you must calculate for substract time of refresh leds and instructions (7,5ms for 1000 leds)
#define FRAMEDELAY 20

// Define memories
DMAMEM int displayMemory[NUM_LEDS_PER_STRIP*6];
int drawingMemory[NUM_LEDS_PER_STRIP*6];

// Some color for debug
#define RED    0xFF0000
#define GREEN  0x00FF00
#define BLUE   0x0000FF
#define YELLOW 0xFFFF00
#define PINK   0xFF1088
#define ORANGE 0xE05800
#define WHITE  0xFFFFFF

// Set default colors 
int colorBackground = 0;

// String received by serial
String inputString = "";

// A led is controled by timers for fadein, holding and fadeout. This values is used on each frame
struct timers
{
    int fadein_left = 0; // fadein left in ms to process
    int fadein_initial = 0; // fadein in ms for remind what % of fadedin the led is
    int hold2 = 0; // The led is on for this time remaining in ms
    int fadeout_left = 0;
    int fadeout_initial = 0;
    int level = 0; // Level of brightness requested for this led
};
// Reserve memory for each led
struct timers ledTimers[MAXLEDS];

// Define the octows2811
OctoWS2811 leds(NUM_LEDS_PER_STRIP, displayMemory, drawingMemory, OCTOWS2811CONFIG);

/**
 * Start teensy, setup and tests
 */
void setup() {
  // Setup serial
  HWSERIAL.begin(57600);
  // Setup OctoWS2811
  leds.begin();
  leds.show();
  // Run test program
  testLeds();
  // Reset all var (needed ?)
  for (int i=0; i < 999; i++) {
    ledTimers[i].fadein_left = 0;
    ledTimers[i].fadein_initial = 0;
    ledTimers[i].hold2 = 0;
    ledTimers[i].fadeout_left = 0;
    ledTimers[i].fadeout_initial = 0;
    ledTimers[i].level = 0;
  }
  // Set background to 0
  setBackgroundColor(0, 0, 0, 0);
  HWSERIAL.println("Start main program");
}

void loop() {  
  // Parse serial buffers
  serialEvent();

  // Refresh all leds and display them
  frameProcess();

  // Sleep for the next frame
  delay(FRAMEDELAY);
}

/**
 * Return the good color and level
 * {int} level: the level of led 0-255 in active mode
 * {int} percent: the percent to switch on (0-100)
 */
int calculateColor(int level, int percent)
{
  int rApplied = constrain(ceil(((255.0*percent)/100.0)*level/255.0), 0, 255);
  int gApplied = constrain(ceil(((255.0*percent)/100.0)*level/255.0), 0, 255);
  int bApplied = constrain(ceil(((255.0*percent)/100.0)*level/255.0), 0, 255);
  return leds.color(rApplied, gApplied, bApplied);
}

/**
 * Process a frame for display, use the leds
 */
void frameProcess()
{
  // Scan all timers for update each leds
  for (int i=0; i < 999; i++) {
    if (ledTimers[i].fadein_left > 0) {
      // This led have a fadein to process
      HWSERIAL.printf("Fadein on %d left:%d initial:%d\n", i, ledTimers[i].fadein_left, ledTimers[i].fadein_initial);
      // Calculate percent to switch on the led
      float percent = 100 - ((ledTimers[i].fadein_left *100) / ledTimers[i].fadein_initial);
      // Set the led
      leds.setPixel(translateLed(i), calculateColor(ledTimers[i].level, percent));
      // Update timer
      ledTimers[i].fadein_left = ledTimers[i].fadein_left - FRAMEDELAY;
      // Reset timer if reached
      if (ledTimers[i].fadein_left <= 0) {
        ledTimers[i].fadein_left = 0;
        ledTimers[i].fadein_initial = 0;
      }
    } else if (ledTimers[i].hold2 > 0) {
      // This led must be switch on 100%
      //HWSERIAL.printf("hold2 on %d\n", i);
      // Set the led to 100%
      leds.setPixel(translateLed(i), calculateColor(ledTimers[i].level, 100));
      // Update timer
      ledTimers[i].hold2 = ledTimers[i].hold2 - FRAMEDELAY;
      // Reset timer if reached
      if (ledTimers[i].hold2 <= 0) {
        ledTimers[i].hold2 = 0;
      }
    } else if (ledTimers[i].fadeout_left > 0) {
      //HWSERIAL.printf("Fadeout on %d\n", i);
      // Calculate the percent to switch off the led
      float percent = ((ledTimers[i].fadeout_left *100) / ledTimers[i].fadeout_initial);
      // Set the led
      leds.setPixel(translateLed(i), calculateColor(ledTimers[i].level, percent));
      // Update timer
      ledTimers[i].fadeout_left = ledTimers[i].fadeout_left - FRAMEDELAY;
      // Reset timer if reached
      if (ledTimers[i].fadeout_left <= 0) {
        ledTimers[i].fadeout_left = 0;
        ledTimers[i].fadeout_initial = 0;
      }
    } else  {
      // The led have no timer, set to background
      leds.setPixel(translateLed(i), colorBackground);
    }
  }
  // Send command to strips leds
  leds.show();
}

/**
 * Set the timers of a led
 */
void setLedTimer(int ledId, int level, int fadein, int hold2, int fadeout)
{
  HWSERIAL.printf("Assign timers to led %d : level: %d, fadein: %d, hold: %d, fadeout: %d\n", ledId, level, fadein, hold2, fadeout);
  ledTimers[ledId] = {fadein, fadein, hold2, fadeout, fadeout, level};
}

/**
 * Set background color
 */
void setBackgroundColor(int r, int g, int b, int back_lev)
{
  HWSERIAL.printf("Assign backgroud color r:%d, g: %d, b: %d, level:%d\n", r, g, b, back_lev);
  int rApplied = constrain(ceil((r * back_lev)/255.0), 0, 255);
  int gApplied = constrain(ceil((g * back_lev)/255.0), 0, 255);
  int bApplied = constrain(ceil((b * back_lev)/255.0), 0, 255);
  colorBackground = leds.color(rApplied, gApplied, bApplied);
  HWSERIAL.printf("Assigned backgroud color r:%d, g: %d, b: %d\n", rApplied, gApplied, bApplied);
}

/**
 * Refresh the serial buffer and detect new line
 */
void serialEvent() {
  while (HWSERIAL.available()) {
    // récupérer le prochain octet (byte ou char) et l'enlever
    char inChar = (char)HWSERIAL.read();
    // concaténation des octets reçus
    inputString += inChar;
    // caractère de fin pour notre chaine
    if (inChar == '\n') {
      parseSerialMessage(inputString);
      inputString = "";
    }
  }
}


void parseSerialMessage(String commandline)
{
  // Copy string, if serial edit this var

  HWSERIAL.println("New command received by serial:");
  HWSERIAL.println(commandline);

  // Extract function
  int index = commandline.indexOf(' ');
  String fct = commandline.substring(0, index);

  // The command is LED request
  if (fct == "LED") {
    // Extract arg1
    commandline = commandline.substring(index+1);
    index = commandline.indexOf(' ');
    String arg1 = commandline.substring(0,index);

    // Extract arg2
    commandline = commandline.substring(index+1);
    index = commandline.indexOf(' ');
    String arg2 = commandline.substring(0,index);

    // Extract arg3
    commandline = commandline.substring(index+1);
    index = commandline.indexOf(' ');
    String arg3 = commandline.substring(0,index);

    // Extract arg4
    commandline = commandline.substring(index+1);
    index = commandline.indexOf(' ');
    String arg4 = commandline.substring(0,index);

    // Extract arg5
    commandline = commandline.substring(index+1);
    index = commandline.indexOf(' ');
    String arg5 = commandline.substring(0,index);

    // Set timers for this led
    setLedTimer(arg1.toInt(), arg2.toInt(), arg3.toInt(), arg4.toInt(), arg5.toInt());
  }

  // The command is background change request
  if (fct == "BACK") {
    // Extract arg1
    commandline = commandline.substring(index+1);
    index = commandline.indexOf(' ');
    String arg1 = commandline.substring(0,index);

    // Extract arg2
    commandline = commandline.substring(index+1);
    index = commandline.indexOf(' ');
    String arg2 = commandline.substring(0,index);

    // Extract arg3
    commandline = commandline.substring(index+1);
    index = commandline.indexOf(' ');
    String arg3 = commandline.substring(0,index);

    // Extract arg4
    commandline = commandline.substring(index+1);
    index = commandline.indexOf(' ');
    String arg4 = commandline.substring(0,index);
    
    // Set background color
    setBackgroundColor(arg1.toInt(), arg2.toInt(), arg3.toInt(), arg4.toInt());
  }
}
/**
 * Test each led by light on/off, call this on boot-up for tests
 */
void testLeds()
{
  HWSERIAL.println("Check the leds...");
  for (int i=0; i < 11; i++) {

    // Switch off all leds
    for (int j=0; j < 1000; j++) {
      leds.setPixel(translateLed(j), leds.color(0,0,0));
    }

    // Switch on 1 serie
    for (int j=0; j < 100; j++) {
      leds.setPixel(translateLed(i*100+j), leds.color(127,127,127));
    }
    leds.show();
    delay(30);
  }
  // Switch off all leds
  for (int i=0; i < 1000; i++) {
    leds.setPixel(translateLed(i), leds.color(0,0,0));
  }
  leds.show();
  HWSERIAL.println("Check done");
}

/**
 * This is a software bugfix for exsitu
 * 
 * Convert the id of led (0-999) to the id in OctoWS2811 library
 * In this case, the strip n+4 is skipped because not connected
 */
int translateLed(int led) {
  if (led > 599) {
    return led + 200;
  } else {
    return led;
  }
}


