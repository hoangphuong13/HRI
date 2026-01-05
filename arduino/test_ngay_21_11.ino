/*
 * CODE ROBOT 6 DOF + 1 EXTRA STEPPER (TRỤC THỨ 7) CHO ATMEGA2560
 * Gửi tín hiệu SSE qua Serial để ESP8266 xử lý.
 */

#include <AccelStepper.h>
#include <Servo.h>
#include <Adafruit_NeoPixel.h>

// ==========================================
// 1. CẤU HÌNH PHẦN CỨNG
// ==========================================
float gearRatios[] = {5.0, 113.0, 5.0, 3.0, 2.0, 1.0}; 
const float STEPS_PER_REV_MOTOR = 3200.0; 

// Hệ số bù J5
const float J5_RATIO_J2 = -0.5;
const float J5_RATIO_J3 = 0.5;

const int numAxes = 6;
const int stepPins[] = {3, 5, 7, 9, 11, 13}; 
const int dirPins[]  = {2, 4, 6, 8, 10, 12};
const int commonEnablePin = 29;
const int switchPins[] = {22, 23, 24, 25, 26, 27}; 

// Cấu hình Động cơ phụ
const int extraStepPin = 35;
const int extraDirPin = 33;
AccelStepper extraStepper(AccelStepper::DRIVER, extraStepPin, extraDirPin);

// Biến điều khiển động cơ phụ
int currentExtraStatus = 0;   
int extraMotorDirection = 1;  
unsigned long extraMotorTimer = 0;
const unsigned long INTERVAL_10S = 10000; 

// Servo kẹp & LED
const int servoPin = 53;
const int openAngle = 90;
const int closeAngle = 0;
#define LED_PIN 31
#define NUM_LEDS 8

// ==========================================
// 2. THÔNG SỐ VẬN HÀNH
// ==========================================
long homingSearchSpeed[] = { -1000, 2000, -100, -500, 60, -500 };
long backoffDist[] = {4000, 12000, 1700, 400, 260, 1150};
float maxSpeeds[] = { 1000, 2000, 1000, 1000, 500, 1000 }; 
float accelerations[] = { 1000, 500, 1000, 1000, 200, 500 };

AccelStepper* steppers[numAxes];
Servo gripper;
Adafruit_NeoPixel strip(NUM_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);

String inputString = "";
bool stringComplete = false;

// ==========================================
// [MỚI] HÀM BÁO CÁO BƯỚC (GỬI QUA SERIAL)
// ==========================================
void baoCaoBuoc(int soBuoc, String noiDung = "") {
  String thongBao = "Buoc: " + String(soBuoc);
  if (noiDung != "") {
    thongBao += " - " + noiDung;
  }
  // Gửi với tiền tố "SSE:" để ESP8266 nhận diện
  Serial.println("SSE:" + thongBao); 
}

// ==========================================
// SETUP
// ==========================================
void setup() {
  Serial.begin(115200); // Tốc độ này phải khớp với code ESP8266
  
  gripper.attach(servoPin);
  moKep();
  
  strip.begin(); strip.show(); strip.setBrightness(150);

  pinMode(commonEnablePin, OUTPUT);
  digitalWrite(commonEnablePin, LOW);

  for (int i = 0; i < numAxes; i++) {
    pinMode(switchPins[i], INPUT_PULLUP);
    steppers[i] = new AccelStepper(AccelStepper::DRIVER, stepPins[i], dirPins[i]);
    steppers[i]->setMaxSpeed(maxSpeeds[i]);
    steppers[i]->setAcceleration(accelerations[i]);
  }

  extraStepper.setMaxSpeed(10000);
  extraStepper.setAcceleration(1000);
  
  Serial.println(F("--- DANG KHOI DONG HE THONG ---"));
  performFullHomingSequence(); 
  Serial.println(F("SYSTEM READY"));
}

// ==========================================
// LOOP CHÍNH
// ==========================================
void loop() {
  while (Serial.available()) {
    char inChar = (char)Serial.read();
    if (inChar == '\n') stringComplete = true;
    else inputString += inChar;
  }

  if (stringComplete) {
    processUserCommand(inputString);
    inputString = "";
    stringComplete = false;
  }

  updateExtraMotor();
}

// ==========================================
// HÀM CẬP NHẬT ĐỘNG CƠ PHỤ
// ==========================================
void updateExtraMotor() {
  if (currentExtraStatus == 1) {
    if (millis() - extraMotorTimer >= INTERVAL_10S) {
      extraMotorDirection *= -1;
      extraMotorTimer = millis();
    }
    extraStepper.setSpeed(800 * extraMotorDirection);
    extraStepper.runSpeed();
  } else {
    extraStepper.stop();
  }
}

// ==========================================
// HÀM DI CHUYỂN BLOCKING
// ==========================================
void moveBlocking(float j1, float j2, float j3, float j4, float j6, int servoPos, int extraStatus) {
  currentExtraStatus = extraStatus;
  if (currentExtraStatus == 1 && extraMotorTimer == 0) extraMotorTimer = millis();

  float j5_auto = - ( (j2 * J5_RATIO_J2) + (j3 * J5_RATIO_J3) );
  gripper.write(servoPos);

  float finalAngles[] = { j1, j2, j3, j4, j5_auto, j6 };
  long targetSteps[6];
  for(int i=0; i<6; i++) {
    float stepsPerDegree = (STEPS_PER_REV_MOTOR / 360.0) * gearRatios[i];
    targetSteps[i] = (long)(finalAngles[i] * stepsPerDegree);
  }

  syncMotorsToPosition(targetSteps);

  while(true) {
    bool stillMoving = false;
    for(int i=0; i<6; i++) {
      if(steppers[i]->distanceToGo() != 0) {
        steppers[i]->run();
        stillMoving = true;
      }
    }
    updateExtraMotor();
    if (!stillMoving) break; 
  }
}

// ==========================================
// KỊCH BẢN (RUN SCENARIO)
// ==========================================
void runScenario(int scenarioNum) {
  setLedStripColor(strip.Color(255, 0, 0)); 

  switch (scenarioNum) {
    case 1:
      Serial.println(F("Bat dau Kich ban 1 (23 buoc)..."));
 // --- BẮT ĐẦU CHUỖI HÀNH ĐỘNG ---

    baoCaoBuoc(1, "Về vị trí gốc");
    moveBlocking(0, 0, 0, 0, 0, openAngle, 0);

    baoCaoBuoc(2);
    moveBlocking(77, 0, -15, 0, 0, closeAngle, 0);

    baoCaoBuoc(3);
    moveBlocking(77, -11, -9, 0, 0, closeAngle, 0);

    baoCaoBuoc(4);
    moveBlocking(77, -11, -9, 0, 0, openAngle, 0);

    baoCaoBuoc(5);
    moveBlocking(77, 0, -9, 0, 0, openAngle, 0);

    baoCaoBuoc(6);
    moveBlocking(0, 0, -9, 0, 0, openAngle, 0);

    baoCaoBuoc(7);
    moveBlocking(-10, -30, -20, 0, 0, openAngle, 0);

    baoCaoBuoc(8);
    moveBlocking(-15, -30, -20, 0, -20, openAngle, 0);

    baoCaoBuoc(9);
    moveBlocking(-15, -40, -20, 0, -20, openAngle, 0);

    // --- CỤM THAO TÁC CỐC ---
    baoCaoBuoc(10, "Vào vị trí đặt cốc");
    moveBlocking(-26, -40, -20, 0, -20, openAngle, 0);

    baoCaoBuoc(11, "Đặt xuống");
    moveBlocking(-26, -42, -23, 0, -20, openAngle, 0);

    baoCaoBuoc(12, "Mở kẹp (trạng thái closeAngle theo code)");
    moveBlocking(-26, -42, -23, 0, -20, closeAngle, 0);

    baoCaoBuoc(13, "Nhấc lên");
    moveBlocking(-26, -36, -25, 0, -20, closeAngle, 0);

    // --- CỤM THAO TÁC KẸP ĐẨY (LẮC) ---
    baoCaoBuoc(14, "Ra vị trí kẹp đẩy");
    moveBlocking(-20, -8, -5, 0, -20, closeAngle, 0);

    baoCaoBuoc(15, "Kẹp");
    moveBlocking(-20, -8, -5, 0, -20, openAngle, 0);

    baoCaoBuoc(16);
    moveBlocking(-20, -12, -7, 0, -20, openAngle, 0);

    baoCaoBuoc(17);
    moveBlocking(-20, -9, -4, 0, -20, openAngle, 0);

    baoCaoBuoc(18);
    moveBlocking(-20, -12, -7, 0, -20, openAngle, 0);

    baoCaoBuoc(19);
    moveBlocking(-20, -9, -4, 0, -20, openAngle, 0);

    baoCaoBuoc(20, "Mở kẹp kết thúc đẩy");
    moveBlocking(-20, -12, -7, 0, -20, closeAngle, 0);

    // --- CỤM THAO TÁC THU HỒI ---
    baoCaoBuoc(21, "Về vị trí cũ");
    moveBlocking(-26, -42, -23, 0, -20, closeAngle, 0);

    baoCaoBuoc(22, "Hạ");
    moveBlocking(-26, -42, -23, 0, -20, closeAngle, 0);

    baoCaoBuoc(23, "Kẹp");
    moveBlocking(-26, -42, -23, 0, -20, openAngle, 0);

    baoCaoBuoc(24, "Kẹp (nhấc nhẹ)");
    moveBlocking(-26, -35, -23, 0, -20, openAngle, 0);

    baoCaoBuoc(25, "Kẹp (di chuyển ngang)");
    moveBlocking(0, -35, -23, 0, -20, openAngle, 0);

    baoCaoBuoc(26, "Về Home");
    moveBlocking(0, 0, 0, 0, 0, openAngle, 0);

    // --- CỤM THAO TÁC XẢ/VỨT ---
    baoCaoBuoc(27);
    moveBlocking(-50, -30, 10, 0, 0, openAngle, 0);

    baoCaoBuoc(28);
    moveBlocking(-70, -30, 0, 0, 0, openAngle, 0);

    baoCaoBuoc(29);
    moveBlocking(-70, -30, 0, 0, 0, closeAngle, 0);

    baoCaoBuoc(30);
    moveBlocking(-68, 0, -15, 0, 0, closeAngle, 0);

    baoCaoBuoc(31);
    moveBlocking(-70, 0, -15, 0, 0, openAngle, 0);

    baoCaoBuoc(32);
    moveBlocking(-70, -19, -15, 0, 0, openAngle, 0);
      // Báo hoàn thành cho ESP biết
      Serial.println("SSE:hoàn thành pha chế!"); 
      break;
  }

  setLedStripColor(strip.Color(0, 255, 0)); 
}

// ==========================================
// CÁC HÀM HỆ THỐNG
// ==========================================
void processUserCommand(String cmd) {
  cmd.trim();
  if (cmd.equalsIgnoreCase("H")) { performFullHomingSequence(); Serial.println(F("DONE")); return; }
  
  int scenarioNum = cmd.toInt();
  if (scenarioNum >= 1 && scenarioNum <= 10) {
    runScenario(scenarioNum);
    Serial.println(F("DONE")); 
  }
}

void syncMotorsToPosition(long targetPos[6]) {
  float max_duration = 0.0;
  long steps_diff[6];
  for(int i=0; i<6; i++) {
    steps_diff[i] = targetPos[i] - steppers[i]->currentPosition();
    float duration = (maxSpeeds[i] > 0) ? (float)abs(steps_diff[i]) / maxSpeeds[i] : 0;
    if (duration > max_duration) max_duration = duration;
  }
  for(int i=0; i<6; i++) {
    float new_speed = (max_duration > 0) ? (float)abs(steps_diff[i]) / max_duration : 0;
    if(new_speed < 1.0 && new_speed > 0.0) new_speed = 1.0;
    steppers[i]->setMaxSpeed(new_speed);
    steppers[i]->moveTo(targetPos[i]);
  }
}

void performFullHomingSequence() {
  setLedStripColor(strip.Color(255, 165, 0)); // Màu Cam
  Serial.println(F("-> Phase 1: Homing J1-J5..."));

  findSwitchAndStop(0, 1);
  findSwitchAndStop(2, 3);
  findSwitchAndStop(4, -1);
  delay(200);

  for(int i=0; i<5; i++) {
      steppers[i]->setCurrentPosition(0);
      long dir = (homingSearchSpeed[i] > 0) ? -1 : 1;
      steppers[i]->moveTo(backoffDist[i] * dir);
  }
  
  while(steppers[0]->distanceToGo()!=0 || steppers[1]->distanceToGo()!=0 || 
        steppers[2]->distanceToGo()!=0 || steppers[3]->distanceToGo()!=0 || 
        steppers[4]->distanceToGo()!=0) {
      for(int i=0; i<5; i++) steppers[i]->run();
  }
  for(int i=0; i<5; i++) steppers[i]->setCurrentPosition(0);
  
  Serial.println(F("-> Phase 2: Homing J6..."));
  steppers[5]->setMaxSpeed(maxSpeeds[5]);
  findSwitchAndStop(5, -1); 
  delay(200);

  steppers[5]->setCurrentPosition(0); 
  long dir6 = (homingSearchSpeed[5] > 0) ? -1 : 1;
  long targetJ6 = backoffDist[5] * dir6; 
  steppers[5]->moveTo(targetJ6); 
  
  while(steppers[5]->distanceToGo() != 0) { 
      steppers[5]->run(); 
  }

  steppers[5]->setCurrentPosition(0); 

  for(int i=0; i<6; i++) steppers[i]->setMaxSpeed(maxSpeeds[i]);
  
  moKep();
  ledReady();
  Serial.println(F("-> HOMING COMPLETE."));
}

void findSwitchAndStop(int idx1, int idx2) {
  steppers[idx1]->setSpeed(homingSearchSpeed[idx1]);
  if(idx2 != -1) steppers[idx2]->setSpeed(homingSearchSpeed[idx2]);
  bool d1 = false; bool d2 = (idx2 == -1) ? true : false;
  while (!d1 || !d2) {
    if (!d1) { if (isSwitchPressed(idx1)) { steppers[idx1]->stop(); d1 = true; } else steppers[idx1]->runSpeed(); }
    if (!d2) { if (isSwitchPressed(idx2)) { steppers[idx2]->stop(); d2 = true; } else steppers[idx2]->runSpeed(); }
  }
}

bool isSwitchPressed(int index) {
  int state = digitalRead(switchPins[index]);
  return (index == 2) ? (state == HIGH) : (state == LOW);
}

void moKep() { gripper.write(openAngle); }
void ledReady() { strip.clear(); for(int i=0; i<NUM_LEDS; i++) strip.setPixelColor(i, 0, 255, 0); strip.show(); }
void setLedStripColor(uint32_t c) { for(int i=0; i<8; i++) strip.setPixelColor(i, c); strip.show(); }