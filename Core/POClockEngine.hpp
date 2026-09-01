#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace poclock {

struct Config {
    double sampleRate = 48000.0;
    double inputPPQN = 2.0;
    bool autoInputPPQN = false;

    bool autoThreshold = true;
    float thresholdHigh = 0.30f;
    float thresholdLow = 0.12f;
    float autoThresholdFloor = 0.035f;
    double refractoryMs = 8.0;
    bool dcBlockEnabled = true;
    double dcBlockHz = 8.0;

    double minBPM = 30.0;
    double maxBPM = 300.0;
    double initialBPM = 120.0;
    double periodSmoothing = 0.18;  // 0..1; higher follows real changes faster.
    double phaseCorrection = 0.30;  // 0..1; higher pulls the clock grid harder.
    double dropoutPeriods = 3.0;

    bool sendMIDIClock = true;
    bool sendTransport = true;
    bool sendTapNote = true;
    uint8_t tapNote = 60;
    uint8_t tapChannel = 0;
};

struct MidiEvent {
    uint32_t frameOffset = 0;
    uint8_t size = 0;
    uint8_t data[3] = {0, 0, 0};
};

struct Status {
    bool running = false;
    bool locked = false;
    double bpm = 0.0;
    double jitterMs = 0.0;
    double phaseErrorMs = 0.0;
    double effectiveInputPPQN = 2.0;
    float peak = 0.0f;
    float effectiveThreshold = 0.0f;
    uint64_t pulseCount = 0;
};

// Realtime contract: after construction/configuration, processBlock performs no
// allocation, locking, logging, I/O, or language-runtime calls.
class Engine {
public:
    static constexpr std::size_t kMaxEventsPerBlock = 512;

    Engine();
    explicit Engine(const Config& config);

    // Call at a render-block boundary. Changing sample rate or PPQN re-arms lock.
    void setConfig(const Config& config) noexcept;
    const Config& config() const noexcept { return config_; }
    void reset() noexcept;

    // input may be null; audio is never modified. blockStartSample must be a
    // monotonic sample timeline for the current render allocation.
    void processBlock(const float* input,
                      uint32_t frameCount,
                      int64_t blockStartSample) noexcept;

    const MidiEvent* events() const noexcept { return events_.data(); }
    std::size_t eventCount() const noexcept { return eventCount_; }
    Status status() const noexcept;

private:
    static constexpr std::size_t kIntervalHistorySize = 7;

    void detectPulse(int64_t sample, uint32_t frameOffset, float value) noexcept;
    void onPulse(int64_t sample, uint32_t frameOffset) noexcept;
    void scheduleAtCurrentSample(int64_t sample, uint32_t frameOffset) noexcept;
    void emit1(uint32_t offset, uint8_t byte) noexcept;
    void emit3(uint32_t offset, uint8_t a, uint8_t b, uint8_t c) noexcept;
    void emitTap(uint32_t offset) noexcept;
    void startAt(int64_t sample, uint32_t offset) noexcept;
    void stopAt(uint32_t offset) noexcept;
    void clearTimingState(bool clearCounters) noexcept;

    bool acceptInterval(double measured, double& normalized) noexcept;
    void pushInterval(double samples) noexcept;
    double medianInterval() const noexcept;
    double chooseAutomaticPPQN(double measuredPeriod) const noexcept;
    double inputPeriodForBPM(double bpm, double ppqn) const noexcept;
    double midiPeriod() const noexcept;
    bool validMeasuredPeriod(double samples) const noexcept;
    bool schedulerEnabled() const noexcept;

    Config config_{};
    bool configured_ = false;
    std::array<MidiEvent, kMaxEventsPerBlock> events_{};
    std::size_t eventCount_ = 0;

    bool gateHigh_ = false;
    bool havePulse_ = false;
    bool haveMeasuredPeriod_ = false;
    bool running_ = false;
    bool locked_ = false;
    int64_t lastPulseSample_ = 0;
    int64_t lastEdgeSample_ = -1;
    uint64_t pulseCount_ = 0;

    std::array<double, kIntervalHistorySize> intervalHistory_{};
    std::size_t intervalCount_ = 0;
    std::size_t intervalWriteIndex_ = 0;

    double effectiveInputPPQN_ = 2.0;
    double estimatedInputPeriod_ = 0.0;
    double nextMidiSample_ = 0.0;
    double lastMidiSample_ = -1.0;
    uint64_t midiTickIndex_ = 0;
    double jitterEmaSamples_ = 0.0;
    double phaseErrorSamples_ = 0.0;

    float peak_ = 0.0f;
    float noiseFloor_ = 0.002f;
    float effectiveThreshold_ = 0.30f;
    float dcInputPrevious_ = 0.0f;
    float dcOutputPrevious_ = 0.0f;
    double dcBlockCoefficient_ = 0.999;
};

} // namespace poclock
