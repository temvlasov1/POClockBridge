#include "../Core/POClockEngine.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <functional>
#include <iomanip>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

using poclock::Config;
using poclock::Engine;
using poclock::Status;

namespace {

struct Pulse {
    int64_t sample = 0;
    float amplitude = 0.9f;
};

struct Capture {
    std::vector<int64_t> clocks;
    std::vector<int64_t> starts;
    std::vector<int64_t> stops;
    std::vector<int64_t> taps;
    std::vector<int64_t> tapOffs;
};

[[noreturn]] void fail(const char* expression, const char* file, int line) {
    throw std::runtime_error(std::string(file) + ":" + std::to_string(line) +
                             " CHECK failed: " + expression);
}

#define CHECK(expression) do { if (!(expression)) fail(#expression, __FILE__, __LINE__); } while (false)

Config baseConfig(double sampleRate = 48000.0) {
    Config config;
    config.sampleRate = sampleRate;
    config.inputPPQN = 2.0;
    config.autoInputPPQN = false;
    config.autoThreshold = false;
    config.thresholdHigh = 0.22f;
    config.thresholdLow = 0.08f;
    config.initialBPM = 120.0;
    config.periodSmoothing = 0.22;
    config.phaseCorrection = 0.30;
    config.dropoutPeriods = 3.0;
    return config;
}

std::vector<Pulse> makePulses(double sampleRate,
                              double bpm,
                              double ppqn,
                              double seconds,
                              double jitterMs = 0.0,
                              float polarity = 1.0f,
                              int64_t startSample = 1024) {
    std::vector<Pulse> pulses;
    const double period = sampleRate * 60.0 / (bpm * ppqn);
    const int64_t end = startSample + static_cast<int64_t>(std::llround(seconds * sampleRate));
    std::mt19937 random(0x504F4342U);
    std::uniform_real_distribution<double> jitter(
        -jitterMs * sampleRate / 1000.0,
        jitterMs * sampleRate / 1000.0);

    for (double position = static_cast<double>(startSample);
         position < static_cast<double>(end);
         position += period) {
        pulses.push_back({static_cast<int64_t>(std::llround(position + jitter(random))),
                          0.90f * polarity});
    }
    return pulses;
}

Capture render(Engine& engine,
               std::vector<Pulse> pulses,
               int64_t endSample,
               uint32_t blockSize = 257,
               float noiseAmplitude = 0.0f) {
    std::sort(pulses.begin(), pulses.end(), [](const Pulse& a, const Pulse& b) {
        return a.sample < b.sample;
    });

    Capture capture;
    std::vector<float> block(blockSize, 0.0f);
    std::size_t firstRelevantPulse = 0;
    constexpr int64_t pulseWidth = 12;

    for (int64_t blockStart = 0; blockStart < endSample;
         blockStart += static_cast<int64_t>(blockSize)) {
        const uint32_t frames = static_cast<uint32_t>(std::min<int64_t>(
            blockSize, endSample - blockStart));
        std::fill(block.begin(), block.begin() + frames, 0.0f);

        if (noiseAmplitude > 0.0f) {
            for (uint32_t frame = 0; frame < frames; ++frame) {
                const int64_t absolute = blockStart + static_cast<int64_t>(frame);
                block[frame] = noiseAmplitude * static_cast<float>(
                    std::sin(static_cast<double>(absolute) * 0.037));
            }
        }

        while (firstRelevantPulse < pulses.size() &&
               pulses[firstRelevantPulse].sample + pulseWidth < blockStart) {
            ++firstRelevantPulse;
        }
        for (std::size_t index = firstRelevantPulse; index < pulses.size(); ++index) {
            const Pulse& pulse = pulses[index];
            if (pulse.sample >= blockStart + frames) break;
            for (int64_t width = 0; width < pulseWidth; ++width) {
                const int64_t absolute = pulse.sample + width;
                if (absolute >= blockStart && absolute < blockStart + frames) {
                    block[static_cast<std::size_t>(absolute - blockStart)] += pulse.amplitude;
                }
            }
        }

        engine.processBlock(block.data(), frames, blockStart);
        for (std::size_t eventIndex = 0; eventIndex < engine.eventCount(); ++eventIndex) {
            const auto& event = engine.events()[eventIndex];
            const int64_t absolute = blockStart + event.frameOffset;
            if (event.size == 1 && event.data[0] == 0xF8) capture.clocks.push_back(absolute);
            if (event.size == 1 && event.data[0] == 0xFA) capture.starts.push_back(absolute);
            if (event.size == 1 && event.data[0] == 0xFC) capture.stops.push_back(absolute);
            if (event.size == 3 && (event.data[0] & 0xF0) == 0x90 &&
                event.data[2] > 0) capture.taps.push_back(absolute);
            if (event.size == 3 && (event.data[0] & 0xF0) == 0x80)
                capture.tapOffs.push_back(absolute);
        }
    }
    return capture;
}

void verifyTempo(double bpm,
                 double sampleRate = 48000.0,
                 double jitterMs = 0.0,
                 float polarity = 1.0f,
                 double tolerance = 0.10) {
    Config config = baseConfig(sampleRate);
    Engine engine(config);
    auto pulses = makePulses(sampleRate, bpm, 2.0, 10.0, jitterMs, polarity);
    const int64_t end = pulses.back().sample + static_cast<int64_t>(
        sampleRate * 60.0 / (bpm * 2.0) * 0.8);
    const Capture capture = render(engine, pulses, end);
    const Status status = engine.status();

    CHECK(status.locked);
    CHECK(status.running);
    CHECK(std::abs(status.bpm - bpm) <= tolerance);
    CHECK(capture.starts.size() == 1);
    CHECK(capture.stops.empty());
    CHECK(capture.clocks.size() > 20);
    CHECK(capture.taps.size() >= 3);
}

void testTempos() {
    for (double bpm : {60.0, 90.0, 120.0, 123.0, 180.0}) {
        verifyTempo(bpm);
    }
}

void testTwoPulseStart() {
    Config config = baseConfig();
    Engine engine(config);
    const double period = config.sampleRate * 60.0 / (120.0 * 2.0);
    std::vector<Pulse> first{{1024, 0.9f}};
    Capture firstCapture = render(engine, first, 1024 + static_cast<int64_t>(period * 0.8));
    CHECK(firstCapture.starts.empty());
    CHECK(!engine.status().locked);

    std::vector<Pulse> second{{1024 + static_cast<int64_t>(std::llround(period)), 0.9f}};
    Capture secondCapture = render(
        engine, second, 1024 + static_cast<int64_t>(period * 1.5));
    CHECK(secondCapture.starts.size() == 1);
    CHECK(engine.status().locked);
}

void testJitter() {
    verifyTempo(123.0, 48000.0, 0.5, 1.0f, 0.20);
    verifyTempo(123.0, 48000.0, 2.0, 1.0f, 0.45);
}

void testMissingPulse() {
    Config config = baseConfig();
    Engine engine(config);
    auto pulses = makePulses(config.sampleRate, 120.0, 2.0, 8.0);
    const std::size_t originalCount = pulses.size();
    pulses.erase(pulses.begin() + 10);
    const int64_t end = pulses.back().sample + 8000;
    const Capture capture = render(engine, pulses, end);
    CHECK(capture.starts.size() == 1);
    CHECK(capture.stops.empty());
    CHECK(engine.status().pulseCount == originalCount - 1);
    CHECK(std::abs(engine.status().bpm - 120.0) < 0.10);
}

void testFalseTransient() {
    Config config = baseConfig();
    Engine engine(config);
    auto pulses = makePulses(config.sampleRate, 120.0, 2.0, 8.0);
    const std::size_t originalCount = pulses.size();
    const double period = config.sampleRate * 60.0 / (120.0 * 2.0);
    pulses.push_back({pulses[10].sample + static_cast<int64_t>(period * 0.35), 0.85f});
    const int64_t end = pulses[pulses.size() - 2].sample + 8000;
    const Capture capture = render(engine, pulses, end);
    CHECK(capture.starts.size() == 1);
    CHECK(capture.stops.empty());
    CHECK(engine.status().pulseCount == originalCount);
    CHECK(std::abs(engine.status().bpm - 120.0) < 0.10);
}

void testTempoChange() {
    Config config = baseConfig();
    config.periodSmoothing = 0.30;
    Engine engine(config);
    std::vector<Pulse> pulses;
    double position = 1024.0;
    const double firstPeriod = config.sampleRate * 60.0 / (100.0 * 2.0);
    const double secondPeriod = config.sampleRate * 60.0 / (128.0 * 2.0);
    const double split = position + config.sampleRate * 6.0;
    const double endPosition = split + config.sampleRate * 14.0;
    while (position < split) {
        pulses.push_back({static_cast<int64_t>(std::llround(position)), 0.9f});
        position += firstPeriod;
    }
    while (position < endPosition) {
        pulses.push_back({static_cast<int64_t>(std::llround(position)), 0.9f});
        position += secondPeriod;
    }
    const Capture capture = render(engine, pulses, static_cast<int64_t>(endPosition));
    CHECK(capture.starts.size() == 1);
    CHECK(capture.stops.empty());
    CHECK(std::abs(engine.status().bpm - 128.0) < 0.15);
}

void testDropoutAndRestart() {
    Config config = baseConfig();
    Engine engine(config);
    auto first = makePulses(config.sampleRate, 120.0, 2.0, 4.0);
    const int64_t restartAt = first.back().sample + static_cast<int64_t>(config.sampleRate * 2.0);
    auto second = makePulses(config.sampleRate, 120.0, 2.0, 3.0, 0.0, 1.0f, restartAt);
    std::vector<Pulse> all = first;
    all.insert(all.end(), second.begin(), second.end());
    const int64_t period = static_cast<int64_t>(config.sampleRate * 60.0 / (120.0 * 2.0));
    const Capture capture = render(engine, all, second.back().sample + period);
    CHECK(capture.starts.size() == 2);
    CHECK(capture.stops.size() == 1);
    CHECK(capture.stops.front() < capture.starts.back());
    CHECK(engine.status().locked);
}

void testLongRunDrift() {
    Config config = baseConfig();
    config.phaseCorrection = 0.25;
    Engine engine(config);
    constexpr double bpm = 120.0;
    auto pulses = makePulses(config.sampleRate, bpm, 2.0, 600.0);
    const int64_t end = pulses.back().sample + 8000;
    const Capture capture = render(engine, pulses, end, 1024);
    CHECK(capture.starts.size() == 1);
    CHECK(capture.stops.empty());
    CHECK(std::abs(engine.status().bpm - bpm) < 0.05);
    CHECK(capture.clocks.size() > 28000);

    const double tickPeriod = config.sampleRate * 60.0 / (bpm * 24.0);
    const double expectedLast = static_cast<double>(capture.clocks.front()) +
        static_cast<double>(capture.clocks.size() - 1) * tickPeriod;
    CHECK(std::abs(static_cast<double>(capture.clocks.back()) - expectedLast) <= 1.5);
}

void testFractionalSourceTempoNoDrift() {
    Config config = baseConfig();
    config.phaseCorrection = 0.25;
    Engine engine(config);
    constexpr double bpm = 119.5;
    auto pulses = makePulses(config.sampleRate, bpm, 2.0, 600.0);
    const int64_t end = pulses.back().sample + 8000;
    const Capture capture = render(engine, pulses, end, 1024);
    CHECK(capture.starts.size() == 1);
    CHECK(capture.stops.empty());
    CHECK(std::abs(engine.status().bpm - bpm) < 0.05);

    // The PO's panel may call this tempo "120", but following the measured
    // 119.5 pulse train is what prevents phase drift against its audio.
    const double tickPeriod = config.sampleRate * 60.0 / (bpm * 24.0);
    const double expectedLast = static_cast<double>(capture.clocks.front()) +
        static_cast<double>(capture.clocks.size() - 1) * tickPeriod;
    CHECK(std::abs(static_cast<double>(capture.clocks.back()) - expectedLast) <= 1.5);
}

void testPolarities() {
    verifyTempo(120.0, 48000.0, 0.0, 1.0f, 0.10);
    verifyTempo(120.0, 48000.0, 0.0, -1.0f, 0.10);
}

void testSampleRates() {
    for (double sampleRate : {44100.0, 48000.0, 96000.0}) {
        verifyTempo(123.0, sampleRate, 0.0, 1.0f, 0.10);
    }
}

void testAdaptiveThreshold() {
    Config config = baseConfig();
    config.autoThreshold = true;
    config.autoThresholdFloor = 0.025f;
    Engine engine(config);
    auto pulses = makePulses(config.sampleRate, 120.0, 2.0, 8.0);
    for (Pulse& pulse : pulses) pulse.amplitude = 0.16f;
    const Capture capture = render(engine, pulses, pulses.back().sample + 8000, 257, 0.004f);
    CHECK(capture.starts.size() == 1);
    CHECK(engine.status().locked);
    CHECK(std::abs(engine.status().bpm - 120.0) < 0.10);
    CHECK(engine.status().effectiveThreshold < 0.10f);
}

void testTapOnlyMode() {
    Config config = baseConfig();
    config.sendMIDIClock = false;
    config.sendTapNote = true;
    Engine engine(config);
    auto pulses = makePulses(config.sampleRate, 120.0, 2.0, 5.0);
    const Capture capture = render(engine, pulses, pulses.back().sample + 8000);
    CHECK(capture.clocks.empty());
    CHECK(capture.taps.size() >= 4);
    CHECK(capture.tapOffs.size() == capture.taps.size());
    CHECK(capture.starts.size() == 1);
}

void testAutomaticPPQNHeuristic() {
    Config config = baseConfig();
    config.autoInputPPQN = true;
    config.initialBPM = 120.0;
    Engine engine(config);
    auto pulses = makePulses(config.sampleRate, 120.0, 2.0, 6.0);
    render(engine, pulses, pulses.back().sample + 8000);
    CHECK(engine.status().effectiveInputPPQN == 2.0);
    CHECK(std::abs(engine.status().bpm - 120.0) < 0.10);
}

} // namespace

int main() {
    const std::vector<std::pair<std::string, std::function<void()>>> tests{
        {"stable tempos 60/90/120/123/180", testTempos},
        {"two-pulse predictive-safe start", testTwoPulseStart},
        {"input jitter +/-0.5 and +/-2 ms", testJitter},
        {"one missing pulse", testMissingPulse},
        {"one false extra transient", testFalseTransient},
        {"tempo change 100 -> 128", testTempoChange},
        {"dropout and restart", testDropoutAndRestart},
        {"ten-minute drift", testLongRunDrift},
        {"fractional PO tempo has no ten-minute drift", testFractionalSourceTempoNoDrift},
        {"both polarities", testPolarities},
        {"44.1/48/96 kHz", testSampleRates},
        {"adaptive threshold", testAdaptiveThreshold},
        {"tap-only scheduling", testTapOnlyMode},
        {"automatic PPQN PO heuristic", testAutomaticPPQNHeuristic},
    };

    std::size_t passed = 0;
    for (const auto& test : tests) {
        try {
            test.second();
            ++passed;
            std::cout << "[PASS] " << test.first << '\n';
        } catch (const std::exception& error) {
            std::cerr << "[FAIL] " << test.first << "\n  " << error.what() << '\n';
            return 1;
        }
    }

    std::cout << "All " << passed << " test groups passed.\n";
    return 0;
}
