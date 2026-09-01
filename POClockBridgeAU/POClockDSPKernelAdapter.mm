#import "POClockDSPKernelAdapter.h"
#import "../Core/POClockEngine.hpp"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <vector>

using poclock::Config;
using poclock::Engine;

@interface POClockDSPKernelAdapter () {
    Engine _engine;
    // Resized only while render resources are being allocated, never in render.
    std::vector<float> _interleavedChannelScratch;

    std::atomic<double> _sampleRate;
    std::atomic<uint32_t> _maximumFrames;
    std::atomic<uint64_t> _configGeneration;
    uint64_t _appliedConfigGeneration;
    std::atomic<bool> _phaseResetRequested;
    int64_t _expectedNextSample;

    std::atomic<float> _thresholdHighAtomic;
    std::atomic<float> _thresholdLowAtomic;
    std::atomic<bool> _autoThresholdAtomic;
    std::atomic<float> _inputPPQNAtomic;
    std::atomic<bool> _autoInputPPQNAtomic;
    std::atomic<int> _inputChannelAtomic;
    std::atomic<int> _outputModeAtomic;
    std::atomic<int> _tapNoteAtomic;
    std::atomic<bool> _sendTransportAtomic;
    std::atomic<float> _initialBPMAtomic;
    std::atomic<float> _smoothingAtomic;
    std::atomic<float> _phaseCorrectionAtomic;
    std::atomic<float> _dropoutPeriodsAtomic;

    std::atomic<float> _detectedBPMAtomic;
    std::atomic<float> _jitterMsAtomic;
    std::atomic<float> _phaseErrorMsAtomic;
    std::atomic<float> _effectiveInputPPQNAtomic;
    std::atomic<float> _effectiveThresholdAtomic;
    std::atomic<float> _peakAtomic;
    std::atomic<bool> _lockedAtomic;
    std::atomic<bool> _runningAtomic;
    std::atomic<uint64_t> _pulseCountAtomic;

    AUMIDIOutputEventBlock _Nullable _midiOutput;
}
@end

@implementation POClockDSPKernelAdapter

- (instancetype)init {
    self = [super init];
    if (self) {
        _sampleRate.store(48000.0);
        _maximumFrames.store(4096);
        _configGeneration.store(1);
        _appliedConfigGeneration = 0;
        _phaseResetRequested.store(false);
        _expectedNextSample = -1;

        _thresholdHighAtomic.store(0.30f);
        _thresholdLowAtomic.store(0.12f);
        _autoThresholdAtomic.store(true);
        _inputPPQNAtomic.store(2.0f);
        _autoInputPPQNAtomic.store(false);
        _inputChannelAtomic.store(0);
        _outputModeAtomic.store(2);
        _tapNoteAtomic.store(60);
        _sendTransportAtomic.store(true);
        _initialBPMAtomic.store(120.0f);
        _smoothingAtomic.store(0.18f);
        _phaseCorrectionAtomic.store(0.30f);
        _dropoutPeriodsAtomic.store(3.0f);

        _detectedBPMAtomic.store(0.0f);
        _jitterMsAtomic.store(0.0f);
        _phaseErrorMsAtomic.store(0.0f);
        _effectiveInputPPQNAtomic.store(2.0f);
        _effectiveThresholdAtomic.store(0.035f);
        _peakAtomic.store(0.0f);
        _lockedAtomic.store(false);
        _runningAtomic.store(false);
        _pulseCountAtomic.store(0);

        _interleavedChannelScratch.resize(4096);
    }
    return self;
}

- (void)markConfigChanged {
    _configGeneration.fetch_add(1, std::memory_order_release);
}

- (void)prepareWithSampleRate:(double)sampleRate
                maximumFrames:(AUAudioFrameCount)maximumFrames {
    const uint32_t safeFrames = std::max<uint32_t>(static_cast<uint32_t>(maximumFrames), 64U);
    _sampleRate.store(sampleRate, std::memory_order_relaxed);
    _maximumFrames.store(safeFrames, std::memory_order_relaxed);
    _interleavedChannelScratch.resize(safeFrames);

    Config config = _engine.config();
    config.sampleRate = sampleRate;
    config.thresholdHigh = _thresholdHighAtomic.load(std::memory_order_relaxed);
    config.thresholdLow = _thresholdLowAtomic.load(std::memory_order_relaxed);
    config.autoThreshold = _autoThresholdAtomic.load(std::memory_order_relaxed);
    config.inputPPQN = _inputPPQNAtomic.load(std::memory_order_relaxed);
    config.autoInputPPQN = _autoInputPPQNAtomic.load(std::memory_order_relaxed);
    config.tapNote = static_cast<uint8_t>(std::clamp(
        _tapNoteAtomic.load(std::memory_order_relaxed), 0, 127));
    config.sendTransport = _sendTransportAtomic.load(std::memory_order_relaxed);
    config.initialBPM = _initialBPMAtomic.load(std::memory_order_relaxed);
    config.periodSmoothing = _smoothingAtomic.load(std::memory_order_relaxed);
    config.phaseCorrection = _phaseCorrectionAtomic.load(std::memory_order_relaxed);
    config.dropoutPeriods = _dropoutPeriodsAtomic.load(std::memory_order_relaxed);
    const int outputMode = _outputModeAtomic.load(std::memory_order_relaxed);
    config.sendTapNote = (outputMode == 0 || outputMode == 2);
    config.sendMIDIClock = (outputMode == 1 || outputMode == 2);
    _engine.setConfig(config);
    _engine.reset();
    _expectedNextSample = -1;
    _phaseResetRequested.store(false, std::memory_order_relaxed);
    _appliedConfigGeneration = _configGeneration.load(std::memory_order_acquire);
}

- (void)reset {
    _engine.reset();
    _expectedNextSample = -1;
}

- (void)requestPhaseReset {
    _phaseResetRequested.store(true, std::memory_order_release);
}

- (void)setMIDIOutputEventBlock:(AUMIDIOutputEventBlock)block {
    _midiOutput = [block copy];
}

- (float)thresholdHigh { return _thresholdHighAtomic.load(); }
- (void)setThresholdHigh:(float)value {
    _thresholdHighAtomic.store(value); [self markConfigChanged];
}
- (float)thresholdLow { return _thresholdLowAtomic.load(); }
- (void)setThresholdLow:(float)value {
    _thresholdLowAtomic.store(value); [self markConfigChanged];
}
- (BOOL)autoThreshold { return _autoThresholdAtomic.load(); }
- (void)setAutoThreshold:(BOOL)value {
    _autoThresholdAtomic.store(value); [self markConfigChanged];
}
- (float)inputPPQN { return _inputPPQNAtomic.load(); }
- (void)setInputPPQN:(float)value {
    _inputPPQNAtomic.store(value); [self markConfigChanged];
}
- (BOOL)autoInputPPQN { return _autoInputPPQNAtomic.load(); }
- (void)setAutoInputPPQN:(BOOL)value {
    _autoInputPPQNAtomic.store(value); [self markConfigChanged];
}
- (NSInteger)inputChannel { return _inputChannelAtomic.load(); }
- (void)setInputChannel:(NSInteger)value {
    _inputChannelAtomic.store(static_cast<int>(value)); [self markConfigChanged];
}
- (NSInteger)outputMode { return _outputModeAtomic.load(); }
- (void)setOutputMode:(NSInteger)value {
    _outputModeAtomic.store(static_cast<int>(value)); [self markConfigChanged];
}
- (NSInteger)tapNote { return _tapNoteAtomic.load(); }
- (void)setTapNote:(NSInteger)value {
    _tapNoteAtomic.store(static_cast<int>(value)); [self markConfigChanged];
}
- (BOOL)sendTransport { return _sendTransportAtomic.load(); }
- (void)setSendTransport:(BOOL)value {
    _sendTransportAtomic.store(value); [self markConfigChanged];
}
- (float)initialBPM { return _initialBPMAtomic.load(); }
- (void)setInitialBPM:(float)value {
    _initialBPMAtomic.store(value); [self markConfigChanged];
}
- (float)smoothing { return _smoothingAtomic.load(); }
- (void)setSmoothing:(float)value {
    _smoothingAtomic.store(value); [self markConfigChanged];
}
- (float)phaseCorrection { return _phaseCorrectionAtomic.load(); }
- (void)setPhaseCorrection:(float)value {
    _phaseCorrectionAtomic.store(value); [self markConfigChanged];
}
- (float)dropoutPeriods { return _dropoutPeriodsAtomic.load(); }
- (void)setDropoutPeriods:(float)value {
    _dropoutPeriodsAtomic.store(value); [self markConfigChanged];
}

- (float)detectedBPM { return _detectedBPMAtomic.load(); }
- (float)jitterMs { return _jitterMsAtomic.load(); }
- (float)phaseErrorMs { return _phaseErrorMsAtomic.load(); }
- (float)effectiveInputPPQN { return _effectiveInputPPQNAtomic.load(); }
- (float)effectiveThreshold { return _effectiveThresholdAtomic.load(); }
- (float)peak { return _peakAtomic.load(); }
- (BOOL)isLocked { return _lockedAtomic.load(); }
- (BOOL)isRunning { return _runningAtomic.load(); }
- (uint64_t)pulseCount { return _pulseCountAtomic.load(); }

- (AUInternalRenderBlock)internalRenderBlock {
    Engine *engine = &_engine;
    std::vector<float> *scratch = &_interleavedChannelScratch;
    uint64_t *appliedGeneration = &_appliedConfigGeneration;
    int64_t *expectedNextSample = &_expectedNextSample;

    auto *sampleRate = &_sampleRate;
    auto *maximumFrames = &_maximumFrames;
    auto *configGeneration = &_configGeneration;
    auto *phaseResetRequested = &_phaseResetRequested;
    auto *thresholdHigh = &_thresholdHighAtomic;
    auto *thresholdLow = &_thresholdLowAtomic;
    auto *autoThreshold = &_autoThresholdAtomic;
    auto *inputPPQN = &_inputPPQNAtomic;
    auto *autoInputPPQN = &_autoInputPPQNAtomic;
    auto *inputChannel = &_inputChannelAtomic;
    auto *outputMode = &_outputModeAtomic;
    auto *tapNote = &_tapNoteAtomic;
    auto *sendTransport = &_sendTransportAtomic;
    auto *initialBPM = &_initialBPMAtomic;
    auto *smoothing = &_smoothingAtomic;
    auto *phaseCorrection = &_phaseCorrectionAtomic;
    auto *dropoutPeriods = &_dropoutPeriodsAtomic;

    auto *detectedBPM = &_detectedBPMAtomic;
    auto *jitterMs = &_jitterMsAtomic;
    auto *phaseErrorMs = &_phaseErrorMsAtomic;
    auto *effectiveInputPPQN = &_effectiveInputPPQNAtomic;
    auto *effectiveThreshold = &_effectiveThresholdAtomic;
    auto *peak = &_peakAtomic;
    auto *locked = &_lockedAtomic;
    auto *running = &_runningAtomic;
    auto *pulseCount = &_pulseCountAtomic;

    // Copied when resources are allocated. Hosts install this before rendering.
    AUMIDIOutputEventBlock midiOutput = _midiOutput;

    return ^AUAudioUnitStatus(AudioUnitRenderActionFlags *actionFlags,
                              const AudioTimeStamp *timestamp,
                              AUAudioFrameCount frameCount,
                              NSInteger outputBusNumber,
                              AudioBufferList *outputData,
                              const AURenderEvent *realtimeEventListHead,
                              AURenderPullInputBlock pullInputBlock) {
        (void)outputBusNumber;
        (void)realtimeEventListHead;
        if (pullInputBlock == nil || outputData == nullptr) {
            return kAudioUnitErr_NoConnection;
        }
        if (frameCount > maximumFrames->load(std::memory_order_relaxed)) {
            return kAudioUnitErr_TooManyFramesToProcess;
        }

        const AUAudioUnitStatus pullStatus =
            pullInputBlock(actionFlags, timestamp, frameCount, 0, outputData);
        if (pullStatus != noErr) return pullStatus;

        const uint64_t generation = configGeneration->load(std::memory_order_acquire);
        if (generation != *appliedGeneration) {
            Config config = engine->config();
            config.sampleRate = sampleRate->load(std::memory_order_relaxed);
            config.thresholdHigh = thresholdHigh->load(std::memory_order_relaxed);
            config.thresholdLow = thresholdLow->load(std::memory_order_relaxed);
            config.autoThreshold = autoThreshold->load(std::memory_order_relaxed);
            config.inputPPQN = std::max(1.0f, inputPPQN->load(std::memory_order_relaxed));
            config.autoInputPPQN = autoInputPPQN->load(std::memory_order_relaxed);
            config.tapNote = static_cast<uint8_t>(std::clamp(
                tapNote->load(std::memory_order_relaxed), 0, 127));
            config.sendTransport = sendTransport->load(std::memory_order_relaxed);
            config.initialBPM = initialBPM->load(std::memory_order_relaxed);
            config.periodSmoothing = smoothing->load(std::memory_order_relaxed);
            config.phaseCorrection = phaseCorrection->load(std::memory_order_relaxed);
            config.dropoutPeriods = dropoutPeriods->load(std::memory_order_relaxed);
            const int mode = outputMode->load(std::memory_order_relaxed);
            config.sendTapNote = (mode == 0 || mode == 2);
            config.sendMIDIClock = (mode == 1 || mode == 2);
            engine->setConfig(config);
            *appliedGeneration = generation;
        }

        if (phaseResetRequested->exchange(false, std::memory_order_acq_rel)) {
            engine->reset();
            *expectedNextSample = -1;
        }

        int64_t absoluteSample = (*expectedNextSample >= 0) ? *expectedNextSample : 0;
        if (timestamp != nullptr &&
            (timestamp->mFlags & kAudioTimeStampSampleTimeValid) != 0 &&
            std::isfinite(timestamp->mSampleTime)) {
            absoluteSample = static_cast<int64_t>(std::llround(timestamp->mSampleTime));
            if (*expectedNextSample >= 0 && absoluteSample != *expectedNextSample) {
                // Route/sample-time discontinuity: avoid a burst of overdue clocks.
                engine->reset();
            }
        }
        *expectedNextSample = absoluteSample + static_cast<int64_t>(frameCount);

        const int requestedChannel = std::max(
            0, inputChannel->load(std::memory_order_relaxed));
        const float *clockInput = nullptr;

        if (outputData->mNumberBuffers > 1) {
            const UInt32 index = std::min<UInt32>(
                static_cast<UInt32>(requestedChannel), outputData->mNumberBuffers - 1);
            const AudioBuffer& buffer = outputData->mBuffers[index];
            if (buffer.mData != nullptr &&
                buffer.mDataByteSize >= frameCount * sizeof(float)) {
                clockInput = static_cast<const float *>(buffer.mData);
            }
        } else if (outputData->mNumberBuffers == 1) {
            const AudioBuffer& buffer = outputData->mBuffers[0];
            const UInt32 channels = std::max<UInt32>(1, buffer.mNumberChannels);
            if (buffer.mData != nullptr &&
                buffer.mDataByteSize >= frameCount * channels * sizeof(float)) {
                const float *interleaved = static_cast<const float *>(buffer.mData);
                const UInt32 channel = std::min<UInt32>(
                    static_cast<UInt32>(requestedChannel), channels - 1);
                if (channels == 1) {
                    clockInput = interleaved;
                } else {
                    float *destination = scratch->data();
                    for (AUAudioFrameCount frame = 0; frame < frameCount; ++frame) {
                        destination[frame] = interleaved[frame * channels + channel];
                    }
                    clockInput = destination;
                }
            }
        }

        engine->processBlock(clockInput, frameCount, absoluteSample);

        if (midiOutput != nil) {
            for (std::size_t index = 0; index < engine->eventCount(); ++index) {
                const auto& event = engine->events()[index];
                const AUEventSampleTime eventTime = static_cast<AUEventSampleTime>(
                    absoluteSample + event.frameOffset);
                (void)midiOutput(eventTime, 0, event.size, event.data);
            }
        }

        const auto status = engine->status();
        detectedBPM->store(static_cast<float>(status.bpm), std::memory_order_relaxed);
        jitterMs->store(static_cast<float>(status.jitterMs), std::memory_order_relaxed);
        phaseErrorMs->store(static_cast<float>(status.phaseErrorMs), std::memory_order_relaxed);
        effectiveInputPPQN->store(
            static_cast<float>(status.effectiveInputPPQN), std::memory_order_relaxed);
        effectiveThreshold->store(status.effectiveThreshold, std::memory_order_relaxed);
        peak->store(status.peak, std::memory_order_relaxed);
        locked->store(status.locked, std::memory_order_relaxed);
        running->store(status.running, std::memory_order_relaxed);
        pulseCount->store(status.pulseCount, std::memory_order_relaxed);

        return noErr;
    };
}

@end
