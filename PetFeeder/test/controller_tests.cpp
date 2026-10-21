#include "feeding_controller.h"
#include <cassert>
#include <iostream>
#include <limits>
using namespace feeder;
struct Rig {
  Controller c;
  uint32_t now = 100;
  uint64_t epoch = 1700000000;
  double yield = 5, late = 0;
  int pulses = 0, jamAfter = -1;
  std::vector<Result> events;
  std::vector<std::string> bowlEvents;
  Rig() {
    c.refillVerified = true;
    c.config.safeInterval = 0;
    c.reading.scale = c.reading.ultrasonic = c.reading.stable = true;
    c.reading.presenceAvailable = c.reading.bowlPresent = true;
    c.onResult = [&](const Result &r) { events.push_back(r); };
    c.onBowl = [&](const std::string &type, double, double,
                   const std::string &cause) {
      bowlEvents.push_back(type + ":" + cause);
    };
    refresh();
  }
  void refresh() { c.reading.weightAt = c.reading.distanceAt = now; }
  bool request(std::string id, double amount = 30,
               bool overrideInterval = false, std::string source = "app") {
    Command a;
    a.id = id;
    a.target = amount;
    a.overrideInterval = overrideInterval;
    a.source = source;
    return c.request(a, now, epoch + now / 1000, 2026300);
  }
  void step(unsigned ms = 10) {
    for (unsigned i = 0; i < ms; i += 10) {
      now += 10;
      refresh();
      const auto phase = c.phase;
      const int angle = c.feedAngle;
      c.tick(now, epoch + now / 1000);
      if (phase == Phase::Open && c.phase == Phase::Settling) {
        pulses++;
        if (jamAfter < 0 || pulses <= jamAfter)
          c.reading.weight +=
              (angle == 60 ? std::min(2.5, yield) : yield) + late;
      }
    }
  }
  void run() {
    for (unsigned i = 0; i < 15000 && c.busy() && c.phase != Phase::Paused; ++i)
      step();
    assert(!c.busy() || c.phase == Phase::Paused);
  }
  const Result &last() const {
    assert(!events.empty());
    return events.back();
  }
};
int main() {
  {
    Rig r;
    assert(r.request("C03"));
    r.step();
    assert(!r.request("C03-button", 30, false, "button"));
    assert(r.last().error == "DEVICE_BUSY");
    r.run();
    auto count = r.c.feedCount;
    assert(!r.request("C03"));
    assert(r.c.feedCount == count);
    std::cout << "C03 PASS\n";
  }
  {
    Rig r;
    r.c.reading.distance = 22;
    r.request("C05", 30, true);
    r.run();
    assert(r.last().status == "FOOD_EMPTY" && r.c.feedCount == 0 &&
           r.c.feedAngle == 0);
    Rig m;
    m.request("mid-empty");
    m.step(1000);
    m.c.reading.distance = 22;
    m.step();
    assert(m.last().status == "FOOD_EMPTY" && m.c.feedAngle == 0);
    std::cout << "C05 PASS\n";
  }
  {
    Rig r;
    r.c.refillVerified = false;
    assert(!r.request("C07", 30, true));
    assert(r.last().error == "UNVERIFIED_FOOD");
    r.c.setSafety(false, false, true);
    r.c.reading.distance = 18;
    r.step(1600);
    r.c.reading.distance = 5;
    r.step();
    assert(!r.c.refillVerified);
    assert(!r.request("C07-refill"));
    std::cout << "C07 PASS\n";
  }
  {
    Rig r;
    r.c.setSafety(true, false, true);
    assert(!r.request("C08", 30, true));
    assert(r.last().error == "SAFETY_LOCKOUT");
    r.c.setSafety(false, false, false);
    assert(r.request("C08-unlocked"));
    std::cout << "C08 PASS\n";
  }
  {
    Rig r;
    r.c.reading.weight = 135;
    r.request("N01");
    r.run();
    assert(r.last().error == "BOWL_CAPACITY_EXCEEDED" && r.pulses == 0);
    std::cout << "N01 PASS\n";
  }
  {
    Rig r;
    r.c.config.dailyFeeds = 2;
    r.request("N02-1");
    r.run();
    r.request("N02-2");
    r.run();
    assert(!r.request("N02-3", 30, true));
    assert(r.last().error == "DAILY_LIMIT_EXCEEDED");
    Rig p;
    p.yield = 1.5;
    p.c.config.maxPulses = 2;
    p.request("partial-limit");
    p.run();
    assert(p.c.charged > 0);
    p.c.config.dailyLimit = 30;
    assert(!p.request("partial-again"));
    std::cout << "N02 PASS\n";
  }
  {
    Rig r;
    r.request("N03-button", 40, false, "button");
    r.step();
    r.request("N03-app");
    assert(r.last().error == "DEVICE_BUSY");
    r.request("N03-schedule", 30, false, "schedule");
    assert(r.last().error == "DEVICE_BUSY" && r.c.feedCount == 1);
    r.run();
    std::cout << "N03 PASS\n";
  }
  {
    Rig r;
    r.jamAfter = 4;
    r.request("N04", 50);
    r.run();
    assert(r.last().status == "JAM_ERROR" && r.last().actual == 20);
    r.jamAfter = -1;
    Command a;
    a.id = "N04-retry";
    a.action = "RETRY";
    a.retryOf = "N04";
    a.target = 50;
    assert(r.c.request(a, r.now, r.epoch + r.now / 1000, 2026300));
    r.run();
    assert(r.last().status == "SUCCESS" && r.last().rootTarget == 50 &&
           r.last().cumulative <= 53 && r.last().target == 30);
    a.id = "N04-duplicate-retry";
    assert(!r.c.request(a, r.now, r.epoch + r.now / 1000, 2026300));
    assert(r.last().error == "RETRY_ALREADY_USED");
    std::cout << "N04 PASS\n";
  }
  {
    Rig r;
    r.yield = 1.5;
    r.request("N05", 60);
    r.run();
    assert(r.last().status == "PARTIAL" &&
           r.last().error == "MAX_PULSES_REACHED" && r.pulses == 15);
    Rig t;
    t.c.config.maxDuration = 1000;
    t.request("timeout");
    t.run();
    assert(t.last().status == "TIMEOUT" && t.c.feedAngle == 0);
    std::cout << "N05 PASS\n";
  }
  {
    Rig r;
    r.yield = 40;
    r.request("N06");
    r.run();
    assert(r.last().status != "SUCCESS" && r.last().error == "OVER_PORTION" &&
           r.c.charged == 40);
    Rig f;
    f.request("fine");
    f.run();
    assert(f.last().status == "SUCCESS" &&
           std::fabs(f.last().actual - 30) <= 3);
    std::cout << "N06 PASS\n";
  }
  {
    Rig r;
    r.request("N07", 40);
    r.step(1000);
    r.c.reading.weight = -5;
    r.step();
    assert(r.last().status == "INTERRUPTED" && !r.last().measurementValid &&
           r.c.charged == 40);
    assert(r.last().error == "WEIGHT_UNTRUSTED");
    std::cout << "N07 PASS\n";
  }
  {
    Rig r;
    r.c.reading.stable = false;
    r.request("N08");
    r.run();
    assert(r.last().error == "SCALE_UNSTABLE" && r.c.feedCount == 0);
    Rig m;
    m.request("mid-unstable");
    m.step(800);
    m.c.reading.stable = false;
    m.run();
    assert(m.last().status == "INTERRUPTED" && !m.last().measurementValid);
    std::cout << "N08 PASS\n";
  }
  {
    Rig r;
    r.c.reading.bowlPresent = false;
    r.request("N09");
    r.run();
    assert(r.last().error == "BOWL_MISSING");
    Rig m;
    m.request("mid-missing");
    m.step(1000);
    m.c.reading.bowlPresent = false;
    m.step();
    assert(m.c.phase == Phase::Paused && m.c.feedAngle == 0);
    m.c.reading.bowlPresent = true;
    m.step(2000);
    assert(m.c.phase == Phase::Paused);
    assert(m.c.cancel("mid-missing", m.epoch));
    assert(!m.c.busy());
    Rig unavailable;
    unavailable.c.reading.presenceAvailable = false;
    unavailable.request("no-presence");
    unavailable.run();
    assert(unavailable.last().error == "BOWL_PRESENCE_UNAVAILABLE");
    std::cout << "N09 PASS\n";
  }
  {
    Rig r;
    r.c.reading.scale = false;
    r.request("N10");
    r.run();
    assert(r.last().status == "SENSOR_ERROR" &&
           r.last().error == "HX711_OFFLINE" && r.pulses == 0);
    std::cout << "N10 PASS\n";
  }
  {
    Rig r;
    r.c.reading.ultrasonic = false;
    r.request("N11");
    r.run();
    assert(r.last().status == "SENSOR_ERROR" &&
           r.last().error == "ULTRASONIC_TIMEOUT");
    std::cout << "N11 PASS\n";
  }
  {
    Rig r;
    r.yield = 0;
    r.request("N12");
    r.run();
    assert(r.last().status == "JAM_ERROR" && r.pulses == 3 &&
           r.c.feedAngle == 0);
    std::cout << "N12 PASS\n";
  }
  {
    Rig r;
    r.step(1600);
    r.c.reading.weight = 45;
    r.step(1600);
    assert(r.bowlEvents.back() == "WEIGHT_INCREASED:UNKNOWN_CAUSE" &&
           r.c.charged == 0 && r.c.feedCount == 0);
    std::cout << "N13 PASS\n";
  }
  {
    Rig r;
    r.c.reading.weight = 45;
    r.step(1600);
    r.c.reading.weight = 15;
    r.step(1600);
    assert(r.bowlEvents.back() == "WEIGHT_DECREASED:UNKNOWN_CAUSE");
    std::cout << "N14 PASS\n";
  }
  {
    Rig r;
    r.c.persist = [] { return false; };
    r.request("storage-failure");
    r.run();
    assert(r.c.feedAngle == 0 && r.last().error == "PERSISTENCE_ERROR");
    Rig n;
    n.request("invalid", std::numeric_limits<double>::quiet_NaN());
    assert(n.last().error == "INVALID_COMMAND");
    std::cout << "Persistence and invalid inputs PASS\n";
  }
  {
    Rig r;
    r.yield = 0;
    r.c.config.maxPulses = 2;
    r.request("hard-pulse-limit");
    r.run();
    assert(r.pulses == 2 && r.last().error == "MAX_PULSES_REACHED");
  }
  {
    Rig r;
    r.request("mid-lock");
    r.step(100);
    r.c.setSafety(true, false, false);
    r.step();
    assert(r.last().error == "SAFETY_LOCKOUT" && r.c.feedAngle == 0 &&
           !r.last().measurementValid);
  }
  {
    Rig r;
    r.request("resume-root", 50);
    r.step(1000);
    r.c.reading.bowlPresent = false;
    r.step();
    auto prior = r.c.active;
    r.c.reading.bowlPresent = true;
    r.c.reading.weight = prior.bowl;
    Command c;
    c.id = "resume-child";
    c.retryOf = "resume-root";
    c.action = "RETRY";
    c.target = 50;
    c.confirmBowl = true;
    assert(r.c.request(c, r.now, r.epoch + r.now / 1000, 2026300));
    r.run();
    assert(r.last().status == "SUCCESS" && r.last().cumulative <= 53);
  }
  {
    Rig r;
    Command c;
    c.id = "query-only";
    c.target = 30;
    c.expiresAt = r.epoch + 60;
    r.c.query(c, r.epoch);
    assert(!r.c.busy() && r.c.feedCount == 0 && r.events.empty());
    r.c.query(c, r.epoch + 61);
    assert(r.last().error == "COMMAND_EXPIRED" && r.pulses == 0);
  }
  {
    Rig r;
    r.request("failed-lock-storage");
    r.step();
    r.c.persist = [] { return false; };
    assert(!r.c.setSafety(true, false, false));
    r.step();
    assert(r.c.lockdown && r.c.feedAngle == 0 &&
           r.last().error == "SAFETY_LOCKOUT");
  }
  std::cout << "All 18 case groups passed\n";
}
