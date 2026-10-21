#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <functional>
#include <string>
#include <vector>

namespace feeder {
struct Config {
  double bowlCapacity = 150, dailyLimit = 200, tolerance = 3,
         fineThreshold = 10;
  double stableSpread = 3, idleDelta = 5, interferenceDrop = 2,
         minPulseGain = 1;
  double emptyDistance = 20, hopperHeight = 25, refillJump = 5;
  uint32_t safeInterval = 180, maxDuration = 30000, stableTimeout = 3000;
  uint32_t coarseOpen = 500, coarseSettle = 400, fineOpen = 200,
           fineSettle = 600;
  uint32_t antiStep = 150, sampleStale = 1000;
  unsigned maxPulses = 15, maxRecoveries = 3, dailyFeeds = 6;
  bool valid() const {
    return std::isfinite(bowlCapacity) && bowlCapacity >= 5 &&
           bowlCapacity <= 10000 && std::isfinite(dailyLimit) &&
           dailyLimit >= 5 && dailyLimit <= 10000 && tolerance > 0 &&
           tolerance <= 10 && fineThreshold > 0 &&
           fineThreshold <= bowlCapacity && stableSpread > 0 &&
           stableSpread <= 10 && idleDelta > 0 && idleDelta <= 100 &&
           interferenceDrop > 0 && interferenceDrop <= 10 && minPulseGain > 0 &&
           minPulseGain <= 5 && emptyDistance > 0 &&
           emptyDistance <= hopperHeight && hopperHeight <= 400 &&
           refillJump > 0 && refillJump <= hopperHeight &&
           safeInterval <= 86400 && maxDuration >= 1000 &&
           maxDuration <= 120000 && stableTimeout >= 250 &&
           stableTimeout <= 10000 && coarseOpen >= 50 && coarseOpen <= 2000 &&
           coarseSettle >= 50 && coarseSettle <= 5000 && fineOpen >= 50 &&
           fineOpen <= 2000 && fineSettle >= 50 && fineSettle <= 5000 &&
           antiStep >= 50 && antiStep <= 500 && sampleStale >= 250 &&
           sampleStale <= 5000 && maxPulses > 0 && maxPulses <= 100 &&
           maxRecoveries > 0 && maxRecoveries <= 5 && dailyFeeds > 0 &&
           dailyFeeds <= 100;
  }
};
struct Reading {
  double weight = 0, distance = 12;
  bool scale = false, ultrasonic = false, stable = false;
  bool presenceAvailable = false, bowlPresent = false, lidOpen = false;
  uint32_t weightAt = 0, distanceAt = 0;
};
struct Command {
  std::string id, source = "app", action = "FEED", retryOf;
  double target = 30;
  bool overrideInterval = false, confirmBowl = false;
  uint64_t expiresAt = 0;
};
struct Result {
  Command command;
  std::string status, error = "NONE", rootId;
  double target = 0, rootTarget = 0, actual = 0, cumulative = 0, bowl = 0,
         tolerance = 3;
  bool measurementValid = true;
  uint64_t startedAt = 0, completedAt = 0;
  unsigned revision = 0;
  std::string eventId() const {
    return command.id + ":" + std::to_string(revision);
  }
};
enum class Phase { Idle, Validating, Open, Settling, Recovering, Paused };

// No Arduino, networking or sleeping here. The same controller runs in MCU and
// host tests.
class Controller {
public:
  Config config;
  Reading reading;
  Phase phase = Phase::Idle;
  Result active;
  std::vector<Result> recent;
  double charged = 0;
  unsigned feedCount = 0;
  int day = -1;
  uint64_t lastFeedAt = 0;
  bool lockdown = false, refillVerified = false;
  int feedAngle = 0, antiAngle = 90;
  std::function<void(const Result &)> onResult;
  std::function<void(const std::string &, double, double, const std::string &)>
      onBowl;
  std::function<bool()> persist = [] { return true; };

  bool busy() const { return phase != Phase::Idle; }
  const Result *find(const std::string &id) const {
    for (const auto &r : recent)
      if (r.command.id == id)
        return &r;
    return nullptr;
  }
  bool updateConfig(const Config &next) {
    if (busy() || !next.valid())
      return false;
    Config old = config;
    config = next;
    if (!persist()) {
      config = old;
      return false;
    }
    return true;
  }
  bool setSafety(bool locked, bool markRefill, bool confirmRefill) {
    const bool oldLock = lockdown, oldVerified = refillVerified;
    lockdown = locked;
    if (markRefill || reading.lidOpen)
      refillVerified = false;
    if (confirmRefill && !markRefill && !reading.lidOpen)
      refillVerified = true;
    if (!persist()) {
      // Persistence failure must never undo an emergency stop or approve new
      // food.
      lockdown = oldLock || locked;
      refillVerified = (markRefill || reading.lidOpen) ? false : oldVerified;
      return false;
    }
    return true;
  }
  bool request(const Command &command, uint32_t now, uint64_t epoch,
               int currentDay) {
    if (const Result *old = find(command.id)) {
      if (onResult)
        onResult(*old);
      return false;
    }
    if (command.id.empty() || command.id.size() > 64 ||
        !std::isfinite(command.target) || command.target < 5 ||
        command.target > 300 ||
        (command.action != "FEED" && command.action != "RETRY"))
      return reject(command, "INVALID_COMMAND", epoch);
    const bool resume = phase == Phase::Paused && command.action == "RETRY" &&
                        command.retryOf == active.command.id;
    if (busy() && !resume)
      return reject(command, "DEVICE_BUSY", epoch);
    Result parent;
    if (command.action == "RETRY") {
      const Result *found = find(command.retryOf);
      if (!found)
        return reject(command, "RETRY_NOT_FOUND", epoch);
      parent = *found;
      const bool retryable = parent.status == "JAM_ERROR" ||
                             parent.status == "PARTIAL" ||
                             parent.status == "TIMEOUT" || resume;
      if (!retryable)
        return reject(command, "RETRY_NOT_ALLOWED", epoch);
      for (const auto &r : recent)
        if (r.command.retryOf == parent.command.id && r.status != "REJECTED")
          return reject(command, "RETRY_ALREADY_USED", epoch);
      if (!parent.measurementValid) {
        if (!resume || !command.confirmBowl || !reading.stable ||
            !reading.presenceAvailable || !reading.bowlPresent ||
            std::fabs(reading.weight - parent.bowl) > config.tolerance)
          return reject(command, "RECONCILIATION_REQUIRED", epoch);
      }
    }
    if (command.expiresAt && (!epoch || epoch > command.expiresAt))
      return reject(command, "COMMAND_EXPIRED", epoch);
    if (lockdown)
      return reject(command, "SAFETY_LOCKOUT", epoch);
    if (!refillVerified || reading.lidOpen)
      return reject(command, "UNVERIFIED_FOOD", epoch);
    if (!epoch || currentDay < 0)
      return reject(command, "TIME_INVALID", epoch);
    if (day >= 0 && currentDay < day)
      return reject(command, "TIME_INVALID", epoch);
    if (day != currentDay) {
      day = currentDay;
      charged = 0;
      feedCount = 0;
    }
    if (!command.overrideInterval && lastFeedAt &&
        epoch < lastFeedAt + config.safeInterval)
      return reject(command, "SAFE_INTERVAL_ACTIVE", epoch,
                    "BLOCKED_DUPLICATE");
    const double target = command.action == "RETRY"
                              ? parent.rootTarget - parent.cumulative
                              : command.target;
    if (target <= config.tolerance)
      return reject(command, "NOTHING_TO_RETRY", epoch);
    const double releasable =
        resume ? std::max(0.0, parent.target - parent.actual) : 0;
    if (feedCount >= config.dailyFeeds ||
        charged - releasable + target > config.dailyLimit)
      return reject(command, "DAILY_LIMIT_EXCEEDED", epoch);
    if (resume) {
      charged -= releasable;
      feedAngle = 0;
    }
    active = Result{};
    active.command = command;
    active.target = target;
    active.tolerance = config.tolerance;
    active.rootId = command.action == "RETRY" ? parent.rootId : command.id;
    active.rootTarget = command.action == "RETRY" ? parent.rootTarget : target;
    priorDelivered = command.action == "RETRY" ? parent.cumulative : 0;
    active.cumulative = priorDelivered;
    active.startedAt = epoch;
    phase = Phase::Validating;
    phaseAt = now;
    startedMs = now;
    pulses = recoveries = antiSteps = 0;
    reserved = false;
    recoveryCheck = false;
    emit("ACCEPTED", "NONE", epoch);
    if (!persist())
      finish("REJECTED", "PERSISTENCE_ERROR", epoch, true);
    return busy();
  }
  void query(const Command &command, uint64_t epoch) {
    if (const Result *old = find(command.id)) {
      if (onResult)
        onResult(*old);
    } else if (command.expiresAt && epoch > command.expiresAt) {
      reject(command, "COMMAND_EXPIRED", epoch, "COMMAND_EXPIRED");
    }
    // An unknown, unexpired ID remains pending. Query never admits a feeding
    // session.
  }
  bool cancel(const std::string &id, uint64_t epoch) {
    if (phase != Phase::Paused || active.command.id != id)
      return false;
    finish("INTERRUPTED", "CANCELLED_BY_OWNER", epoch, false);
    return true;
  }
  void tick(uint32_t now, uint64_t epoch) {
    if (phase == Phase::Idle) {
      monitorIdle(now);
      return;
    }
    if (phase == Phase::Paused) {
      if (lockdown || !refillVerified || reading.lidOpen)
        finish("INTERRUPTED", lockdown ? "SAFETY_LOCKOUT" : "UNVERIFIED_FOOD",
               epoch, false);
      return;
    }
    const bool freshWeight = reading.scale && std::isfinite(reading.weight) &&
                             now - reading.weightAt <= config.sampleStale;
    const bool freshDistance = reading.ultrasonic &&
                               std::isfinite(reading.distance) &&
                               now - reading.distanceAt <= config.sampleStale;
    if (lockdown || !refillVerified || reading.lidOpen) {
      finish(reserved ? "INTERRUPTED" : "REJECTED",
             lockdown ? "SAFETY_LOCKOUT" : "UNVERIFIED_FOOD", epoch, !reserved);
      return;
    }
    if (!reading.presenceAvailable || !reading.bowlPresent) {
      if (reserved && reading.presenceAvailable) {
        feedAngle = 0;
        antiAngle = 90;
        phase = Phase::Paused;
        active.measurementValid = false;
        emit("PAUSED", "BOWL_MISSING", epoch);
        persist();
      } else
        finish("REJECTED",
               reading.presenceAvailable ? "BOWL_MISSING"
                                         : "BOWL_PRESENCE_UNAVAILABLE",
               epoch, true);
      return;
    }
    if (!freshWeight) {
      finish("SENSOR_ERROR", "HX711_OFFLINE", epoch, !reserved);
      return;
    }
    if (!freshDistance) {
      finish("SENSOR_ERROR", "ULTRASONIC_TIMEOUT", epoch, !reserved);
      return;
    }
    if (reading.distance >= config.emptyDistance) {
      finish("FOOD_EMPTY", "HOPPER_EMPTY", epoch, !reserved);
      return;
    }
    if (phase == Phase::Validating) {
      if (!reading.stable) {
        if (now - phaseAt >= config.stableTimeout)
          finish("REJECTED", "SCALE_UNSTABLE", epoch, true);
        return;
      }
      if (reading.weight < -config.tolerance) {
        finish("SENSOR_ERROR", "SCALE_INVALID", epoch, true);
        return;
      }
      if (reading.weight + active.target > config.bowlCapacity) {
        finish("REJECTED", "BOWL_CAPACITY_EXCEEDED", epoch, true);
        return;
      }
      initialWeight = beforePulse = reading.weight;
      active.bowl = reading.weight;
      charged += active.target;
      feedCount++;
      reserved = true;
      if (!persist()) {
        feedAngle = 0;
        finish("REJECTED", "PERSISTENCE_ERROR", epoch, false);
        return;
      }
      emit("DISPENSING", "NONE", epoch);
      open(now);
      return;
    }
    if (now - startedMs >= config.maxDuration) {
      finish(active.measurementValid ? "TIMEOUT" : "INTERRUPTED",
             "MAX_DURATION_REACHED", epoch, false);
      return;
    }
    if (reading.weight < active.bowl - config.interferenceDrop) {
      finish("INTERRUPTED", "WEIGHT_UNTRUSTED", epoch, false);
      return;
    }
    if (phase == Phase::Open) {
      if (now - phaseAt >= openMs) {
        feedAngle = 0;
        phase = Phase::Settling;
        phaseAt = now;
      }
      return;
    }
    if (phase == Phase::Recovering) {
      if (now - phaseAt >= config.antiStep) {
        phaseAt = now;
        antiSteps++;
        antiAngle = antiSteps % 2 ? 135 : 45;
        if (antiSteps >= 6) {
          antiAngle = 90;
          feedAngle = 0;
          // Read the bowl again after anti-jam motion before declaring
          // delivered grams.
          recoveryCheck = true;
          phase = Phase::Settling;
          phaseAt = now;
        }
      }
      return;
    }
    if (!reading.stable) {
      if (now - phaseAt >= settleMs + config.stableTimeout)
        finish("INTERRUPTED", "SCALE_UNSTABLE", epoch, false);
      return;
    }
    if (now - phaseAt < settleMs)
      return;
    active.bowl = reading.weight;
    active.actual = std::max(0.0, reading.weight - initialWeight);
    active.cumulative = priorDelivered + active.actual;
    if (active.actual > active.target + config.tolerance) {
      finish("INTERRUPTED", "OVER_PORTION", epoch, true);
      return;
    }
    if (active.actual >= active.target - config.tolerance) {
      finish("SUCCESS", "NONE", epoch, true);
      return;
    }
    if (recoveryCheck) {
      recoveryCheck = false;
      if (reading.weight - beforePulse < config.minPulseGain &&
          recoveries >= config.maxRecoveries) {
        finish("JAM_ERROR", "JAM_RECOVERY_FAILED", epoch, true);
        return;
      }
      if (pulses >= config.maxPulses) {
        finish("PARTIAL", "MAX_PULSES_REACHED", epoch, true);
        return;
      }
      if (!persist()) {
        finish("INTERRUPTED", "PERSISTENCE_ERROR", epoch, false);
        return;
      }
      open(now);
      return;
    }
    if (pulses >= config.maxPulses) {
      finish("PARTIAL", "MAX_PULSES_REACHED", epoch, true);
      return;
    }
    if (reading.weight - beforePulse < config.minPulseGain) {
      recoveries++;
      phase = Phase::Recovering;
      phaseAt = now;
      antiSteps = 0;
      feedAngle = 120;
      antiAngle = 45;
      return;
    }
    recoveries = 0;
    if (pulses >= config.maxPulses) {
      finish("PARTIAL", "MAX_PULSES_REACHED", epoch, true);
      return;
    }
    if (!persist()) {
      finish("INTERRUPTED", "PERSISTENCE_ERROR", epoch, false);
      return;
    }
    open(now);
  }

private:
  uint32_t phaseAt = 0, startedMs = 0, idleAt = 0, openMs = 0, settleMs = 0;
  unsigned pulses = 0, recoveries = 0, antiSteps = 0;
  double initialWeight = 0, beforePulse = 0, priorDelivered = 0, idleWeight = 0,
         idleDistance = 0;
  bool reserved = false, recoveryCheck = false, idleInitialized = false,
       distanceInitialized = false;
  void remember(const Result &result) {
    for (auto &r : recent)
      if (r.command.id == result.command.id) {
        r = result;
        return;
      }
    if (recent.size() >= 64) {
      auto rejected =
          std::find_if(recent.begin(), recent.end(), [](const Result &r) {
            return !r.startedAt;
          });
      recent.erase(rejected != recent.end() ? rejected : recent.begin());
    }
    recent.push_back(result);
  }
  bool reject(const Command &c, const std::string &error, uint64_t epoch,
              const std::string &status = "REJECTED") {
    Result r;
    r.command = c;
    r.status = status;
    r.error = error;
    r.target = r.rootTarget = c.target;
    r.rootId = c.id;
    r.completedAt = epoch;
    r.revision = 1;
    remember(r);
    if (onResult)
      onResult(r);
    return false;
  }
  void emit(const std::string &status, const std::string &error,
            uint64_t epoch) {
    active.status = status;
    active.error = error;
    active.revision++;
    if (phase == Phase::Idle)
      active.completedAt = epoch;
    remember(active);
    if (onResult)
      onResult(active);
  }
  void finish(const std::string &status, const std::string &error,
              uint64_t epoch, bool reliable) {
    feedAngle = 0;
    antiAngle = 90;
    active.measurementValid = reliable;
    // Empty at the preflight check is known zero. Never infer a mid-pulse
    // quantity.
    if (reserved && reliable)
      charged = std::max(0.0, charged - active.target + active.actual);
    if (reserved)
      lastFeedAt = epoch;
    phase = Phase::Idle;
    idleInitialized = false;
    emit(status, error, epoch);
    persist();
  }
  void open(uint32_t now) {
    const bool fine = active.target - active.actual <= config.fineThreshold;
    openMs = fine ? config.fineOpen : config.coarseOpen;
    settleMs = fine ? config.fineSettle : config.coarseSettle;
    beforePulse = reading.weight;
    feedAngle = fine ? 60 : 90;
    phase = Phase::Open;
    phaseAt = now;
    pulses++;
  }
  void monitorIdle(uint32_t now) {
    if (reading.ultrasonic && std::isfinite(reading.distance) &&
        now - reading.distanceAt <= config.sampleStale) {
      if (distanceInitialized &&
          idleDistance - reading.distance >= config.refillJump) {
        refillVerified = false;
        persist();
        if (onBowl)
          onBowl("REFILL_SUSPECTED", 0, reading.weight, "UNVERIFIED");
      }
      idleDistance = reading.distance;
      distanceInitialized = true;
    }
    if (reading.lidOpen && refillVerified) {
      refillVerified = false;
      persist();
    }
    if (now - idleAt < 1500 || !reading.scale || !reading.stable ||
        !reading.presenceAvailable || !reading.bowlPresent ||
        !std::isfinite(reading.weight) ||
        now - reading.weightAt > config.sampleStale)
      return;
    idleAt = now;
    if (!idleInitialized) {
      idleWeight = reading.weight;
      idleInitialized = true;
      return;
    }
    const double delta = reading.weight - idleWeight;
    if (std::fabs(delta) > config.idleDelta) {
      if (onBowl)
        onBowl(delta > 0 ? "WEIGHT_INCREASED" : "WEIGHT_DECREASED", delta,
               reading.weight, "UNKNOWN_CAUSE");
      idleWeight = reading.weight;
    }
  }
};
} // namespace feeder
