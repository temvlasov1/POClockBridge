#include "POClockEngine.hpp"

#include <algorithm>
#include <cmath>

namespace poclock {

namespace {
constexpr uint8_t kMIDIClock = 0xF8;
constexpr uint8_t kMIDIStart = 0xFA;
constexpr uint8_t kMIDIStop = 0xFC;
constexpr double kTwoPi = 6.28318530717958647692;

template <typename T>
T clamped(T value, T minimum, T maximum) noexcept {
    return std::max(minimum, std::min(value, maximum));
}
} // namespace

Engine::Engine() { setConfig(Config{}); }

Engine::Engine(const Config& config) { setConfig(config); }

void Engine::setConfig(const Config& incoming) noexcept {
    Config next = incoming;
    next.sampleRate = std::max(8000.0, next.sampleRate);
    next.inputPPQN = clamped(next.inputPPQN, 1.0, 96.0);
    next.thresholdHigh = clamped(next.thresholdHigh, 0.001f, 1.0f);
    next.thresholdLow = clamped(next.thresholdLow, 0.0f, next.thresholdHigh * 0.95f);
    next.autoThresholdFloor = clamped(next.autoThresholdFloor, 0.002f, 0.80f);
    next.refractoryMs = clamped(next.refractoryMs, 0.25, 50.0);
    next.dcBlockHz = clamped(next.dcBlockHz, 1.0, 40.0);
    next.minBPM = clamped(next.minBPM, 10.0, 300.0);
    next.maxBPM = clamped(next.maxBPM, next.minBPM + 1.0, 600.0);
    next.initialBPM = clamped(next.initialBPM, next.minBPM, next.maxBPM);
    next.periodSmoothing = clamped(next.periodSmoothing, 0.01, 1.0);
    next.phaseCorrection = clamped(next.phaseCorrection, 0.0, 1.0);
    next.dropoutPeriods = clamped(next.dropoutPeriods, 2.1, 8.0);
    next.tapChannel &= 0x0F;
    next.tapNote &= 0x7F;

    const bool timingChanged = configured_ &&
        (std::abs(config_.sampleRate - next.sampleRate) > 0.5 ||
         std::abs(config_.inputPPQN - next.inputPPQN) > 0.001 ||
         config_.autoInputPPQN != next.autoInputPPQN);

    config_ = next;
    configured_ = true;
    dcBlockCoefficient_ = std::exp(-kTwoPi * config_.dcBlockHz / config_.sampleRate);

    if (timingChanged) {
        reset();
    } else if (!haveMeasuredPeriod_) {
        effectiveInputPPQN_ = config_.inputPPQN;
        estimatedInputPeriod_ = inputPeriodForBPM(config_.initialBPM,
                                                   effectiveInputPPQN_);
    }
}

void Engine::clearTimingState(bool clearCounters) noexcept {
    havePulse_ = false;
    haveMeasuredPeriod_ = false;
    running_ = false;
    locked_ = false;
    lastPulseSample_ = 0;
    intervalHistory_.fill(0.0);
    intervalCount_ = 0;
    intervalWriteIndex_ = 0;
    effectiveInputPPQN_ = config_.inputPPQN;
    estimatedInputPeriod_ = inputPeriodForBPM(config_.initialBPM,
                                               effectiveInputPPQN_);
    nextMidiSample_ = 0.0;
    lastMidiSample_ = -1.0;
    midiTickIndex_ = 0;
    jitterEmaSamples_ = 0.0;
    phaseErrorSamples_ = 0.0;
    if (clearCounters) pulseCount_ = 0;
}

void Engine::reset() noexcept {
    eventCount_ = 0;
    gateHigh_ = false;
    lastEdgeSample_ = -1;
    peak_ = 0.0f;
    noiseFloor_ = 0.002f;
    effectiveThreshold_ = config_.autoThreshold
        ? config_.autoThresholdFloor
        : config_.thresholdHigh;
    dcInputPrevious_ = 0.0f;
    dcOutputPrevious_ = 0.0f;
    clearTimingState(true);
}

double Engine::inputPeriodForBPM(double bpm, double ppqn) const noexcept {
    return config_.sampleRate * 60.0 / (bpm * ppqn);
}

double Engine::midiPeriod() const noexcept {
    return estimatedInputPeriod_ * effectiveInputPPQN_ / 24.0;
}

bool Engine::schedulerEnabled() const noexcept {
    return config_.sendMIDIClock || config_.sendTapNote;
}

bool Engine::validMeasuredPeriod(double samples) const noexcept {
    // Auto PPQN cannot define a unique period range. Use all supported PPQN
    // values, then resolve the musically ambiguous PPQN against Initial BPM.
    const double rangePPQN = config_.autoInputPPQN ? 48.0 : effectiveInputPPQN_;
    const double fastest = inputPeriodForBPM(config_.maxBPM, rangePPQN);
    const double slowPPQN = config_.autoInputPPQN ? 1.0 : effectiveInputPPQN_;
    const double slowest = inputPeriodForBPM(config_.minBPM, slowPPQN);
    return samples >= fastest * 0.80 && samples <= slowest * 1.20;
}

double Engine::chooseAutomaticPPQN(double measuredPeriod) const noexcept {
    constexpr std::array<double, 6> choices{{1.0, 2.0, 4.0, 12.0, 24.0, 48.0}};
    double best = 2.0;
    double bestScore = 1.0e30;
    for (double ppqn : choices) {
        const double bpm = config_.sampleRate * 60.0 / (measuredPeriod * ppqn);
        if (bpm < config_.minBPM || bpm > config_.maxBPM) continue;
        const double tempoScore = std::abs(std::log(bpm / config_.initialBPM));
        const double poPreference = (ppqn == 2.0) ? -0.025 : 0.0;
        const double score = tempoScore + poPreference;
        if (score < bestScore) {
            bestScore = score;
            best = ppqn;
        }
    }
    return best;
}

void Engine::pushInterval(double samples) noexcept {
    intervalHistory_[intervalWriteIndex_] = samples;
    intervalWriteIndex_ = (intervalWriteIndex_ + 1) % intervalHistory_.size();
    intervalCount_ = std::min(intervalCount_ + 1, intervalHistory_.size());
}

double Engine::medianInterval() const noexcept {
    if (intervalCount_ == 0) return estimatedInputPeriod_;
    std::array<double, kIntervalHistorySize> sorted{};
    for (std::size_t i = 0; i < intervalCount_; ++i) sorted[i] = intervalHistory_[i];
    std::sort(sorted.begin(), sorted.begin() + static_cast<std::ptrdiff_t>(intervalCount_));
    const std::size_t middle = intervalCount_ / 2;
    if ((intervalCount_ & 1U) != 0U) return sorted[middle];
    return 0.5 * (sorted[middle - 1] + sorted[middle]);
}

bool Engine::acceptInterval(double measured, double& normalized) noexcept {
    if (!validMeasuredPeriod(measured)) return false;
    normalized = measured;

    if (haveMeasuredPeriod_ && estimatedInputPeriod_ > 1.0) {
        const double ratio = measured / estimatedInputPeriod_;

        // Collapse missed pulses back to one input period. The tolerance is
        // deliberately narrow so a genuine tempo change is not quantized away.
        const int multiple = clamped(static_cast<int>(std::llround(ratio)), 2, 8);
        if (ratio > 1.55 && std::abs(ratio - static_cast<double>(multiple)) < 0.22) {
            normalized = measured / static_cast<double>(multiple);
        } else if (ratio < 0.58 || ratio > 1.55) {
            // A lone early transient or implausible late edge must not move the
            // accepted-pulse timestamp. The following genuine edge is then
            // measured against the last good pulse.
            return false;
        }
    }

    if (intervalCount_ >= 3) {
        const double reference = medianInterval();
        const double ratio = normalized / reference;
        if (ratio < 0.62 || ratio > 1.45) return false;
    }
    return true;
}

void Engine::emit1(uint32_t offset, uint8_t byte) noexcept {
    if (eventCount_ >= events_.size()) return;
    MidiEvent& event = events_[eventCount_++];
    event.frameOffset = offset;
    event.size = 1;
    event.data[0] = byte;
    event.data[1] = 0;
    event.data[2] = 0;
}

void Engine::emit3(uint32_t offset, uint8_t a, uint8_t b, uint8_t c) noexcept {
    if (eventCount_ >= events_.size()) return;
    MidiEvent& event = events_[eventCount_++];
    event.frameOffset = offset;
    event.size = 3;
    event.data[0] = a;
    event.data[1] = b;
    event.data[2] = c;
}

void Engine::emitTap(uint32_t offset) noexcept {
    if (!config_.sendTapNote) return;
    const uint8_t status = static_cast<uint8_t>(0x90 | config_.tapChannel);
    emit3(offset, status, config_.tapNote, 100);
    emit3(offset, status, config_.tapNote, 0);
}

void Engine::startAt(int64_t sample, uint32_t offset) noexcept {
    running_ = true;
    locked_ = true;
    midiTickIndex_ = 0;
    if (config_.sendTransport) emit1(offset, kMIDIStart);
    if (config_.sendMIDIClock) emit1(offset, kMIDIClock);
    emitTap(offset);
    lastMidiSample_ = static_cast<double>(sample);
    nextMidiSample_ = static_cast<double>(sample) + midiPeriod();
}

void Engine::stopAt(uint32_t offset) noexcept {
    if (!running_) return;
    if (config_.sendTransport) emit1(offset, kMIDIStop);

    // Keep detector gate state: if the cable is stuck high, re-arming must wait
    // for a real low level rather than manufacturing a new rising edge.
    clearTimingState(false);
}

void Engine::onPulse(int64_t sample, uint32_t offset) noexcept {
    if (!havePulse_) {
        havePulse_ = true;
        lastPulseSample_ = sample;
        ++pulseCount_;
        return;
    }

    const double measured = static_cast<double>(sample - lastPulseSample_);
    double normalized = measured;
    if (!acceptInterval(measured, normalized)) return;

    lastPulseSample_ = sample;
    ++pulseCount_;

    if (!haveMeasuredPeriod_) {
        if (config_.autoInputPPQN) {
            effectiveInputPPQN_ = chooseAutomaticPPQN(normalized);
        }
        estimatedInputPeriod_ = normalized;
        haveMeasuredPeriod_ = true;
        pushInterval(normalized);
    } else {
        pushInterval(normalized);
        const double robustPeriod = medianInterval();
        const double error = robustPeriod - estimatedInputPeriod_;
        estimatedInputPeriod_ += config_.periodSmoothing * error;
        const double instantaneousError = std::abs(normalized - robustPeriod);
        jitterEmaSamples_ += 0.15 * (instantaneousError - jitterEmaSamples_);
    }

    // The deliberate default is "two-pulse start": there is no guessed clock
    // burst. The second valid physical edge establishes both tempo and phase.
    if (!running_) {
        startAt(sample, offset);
        return;
    }

    if (!schedulerEnabled()) return;
    const double tickPeriod = midiPeriod();
    if (tickPeriod <= 1.0 || nextMidiSample_ <= 0.0) {
        nextMidiSample_ = static_cast<double>(sample) + tickPeriod;
        return;
    }

    const double ticksFromNext =
        std::round((static_cast<double>(sample) - nextMidiSample_) / tickPeriod);
    const double predictedBoundary = nextMidiSample_ + ticksFromNext * tickPeriod;
    phaseErrorSamples_ = static_cast<double>(sample) - predictedBoundary;
    nextMidiSample_ += config_.phaseCorrection * phaseErrorSamples_;
}

void Engine::scheduleAtCurrentSample(int64_t sample, uint32_t offset) noexcept {
    if (!running_ || !schedulerEnabled() || nextMidiSample_ <= 0.0) return;
    const double tickPeriod = midiPeriod();
    if (tickPeriod <= 1.0) return;

    int guard = 0;
    while (static_cast<double>(sample) + 0.5 >= nextMidiSample_ && guard++ < 16) {
        ++midiTickIndex_;
        if (config_.sendMIDIClock &&
            (lastMidiSample_ < 0.0 || nextMidiSample_ - lastMidiSample_ > tickPeriod * 0.35)) {
            emit1(offset, kMIDIClock);
        }
        if ((midiTickIndex_ % 24U) == 0U) emitTap(offset);
        lastMidiSample_ = nextMidiSample_;
        nextMidiSample_ += tickPeriod;
    }
}

void Engine::detectPulse(int64_t sample,
                         uint32_t frameOffset,
                         float inputValue) noexcept {
    float value = inputValue;
    if (config_.dcBlockEnabled) {
        const float output = value - dcInputPrevious_ +
            static_cast<float>(dcBlockCoefficient_) * dcOutputPrevious_;
        dcInputPrevious_ = value;
        dcOutputPrevious_ = output;
        value = output;
    }

    const float amplitude = std::abs(value);
    peak_ = std::max(peak_ * 0.9995f, amplitude);

    if (!gateHigh_ && amplitude < effectiveThreshold_) {
        // Slow background estimator; pulse tops and the high-gate interval are
        // excluded, so PO sync energy does not raise its own threshold.
        noiseFloor_ += 0.0005f * (amplitude - noiseFloor_);
    }

    if (config_.autoThreshold) {
        effectiveThreshold_ = clamped(
            std::max(config_.autoThresholdFloor, noiseFloor_ * 6.0f),
            config_.autoThresholdFloor,
            0.95f);
    } else {
        effectiveThreshold_ = config_.thresholdHigh;
    }
    const float releaseThreshold = config_.autoThreshold
        ? effectiveThreshold_ * 0.40f
        : config_.thresholdLow;

    if (!gateHigh_) {
        if (amplitude >= effectiveThreshold_) {
            const int64_t refractorySamples = static_cast<int64_t>(
                std::max(1.0, config_.sampleRate * config_.refractoryMs / 1000.0));
            if (lastEdgeSample_ < 0 || sample - lastEdgeSample_ >= refractorySamples) {
                gateHigh_ = true;
                lastEdgeSample_ = sample;
                onPulse(sample, frameOffset);
            }
        }
    } else if (amplitude <= releaseThreshold) {
        gateHigh_ = false;
    }
}

void Engine::processBlock(const float* input,
                          uint32_t frameCount,
                          int64_t blockStartSample) noexcept {
    eventCount_ = 0;
    peak_ *= 0.98f;

    for (uint32_t frame = 0; frame < frameCount; ++frame) {
        const int64_t sample = blockStartSample + static_cast<int64_t>(frame);
        if (input != nullptr) detectPulse(sample, frame, input[frame]);

        if (running_ && havePulse_ && estimatedInputPeriod_ > 0.0) {
            const double timeout = estimatedInputPeriod_ * config_.dropoutPeriods;
            if (static_cast<double>(sample - lastPulseSample_) > timeout) {
                stopAt(frame);
            }
        }
        scheduleAtCurrentSample(sample, frame);
    }
}

Status Engine::status() const noexcept {
    Status result;
    result.running = running_;
    result.locked = locked_;
    result.bpm = haveMeasuredPeriod_ && estimatedInputPeriod_ > 0.0
        ? config_.sampleRate * 60.0 /
            (estimatedInputPeriod_ * effectiveInputPPQN_)
        : 0.0;
    result.jitterMs = jitterEmaSamples_ * 1000.0 / config_.sampleRate;
    result.phaseErrorMs = phaseErrorSamples_ * 1000.0 / config_.sampleRate;
    result.effectiveInputPPQN = effectiveInputPPQN_;
    result.peak = peak_;
    result.effectiveThreshold = effectiveThreshold_;
    result.pulseCount = pulseCount_;
    return result;
}

} // namespace poclock
