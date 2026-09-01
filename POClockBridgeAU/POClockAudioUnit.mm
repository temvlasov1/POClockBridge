#import "POClockAudioUnit.h"
#import "POClockDSPKernelAdapter.h"

#include <cmath>

namespace {
constexpr AUParameterAddress kParamThresholdHigh = 0;
constexpr AUParameterAddress kParamThresholdLow = 1;
constexpr AUParameterAddress kParamInputPPQN = 2;
constexpr AUParameterAddress kParamInputChannel = 3;
constexpr AUParameterAddress kParamOutputMode = 4;
constexpr AUParameterAddress kParamTapNote = 5;
constexpr AUParameterAddress kParamSendTransport = 6;
constexpr AUParameterAddress kParamAutoThreshold = 7;
constexpr AUParameterAddress kParamInitialBPM = 8;
constexpr AUParameterAddress kParamSmoothing = 9;
constexpr AUParameterAddress kParamPhaseCorrection = 10;
constexpr AUParameterAddress kParamDropoutPeriods = 11;
NSString *const kSavedParametersKey = @"POClockBridge.parameters.v1";

float ppqnForMode(NSInteger mode) {
    constexpr float values[] = {2.0f, 1.0f, 2.0f, 4.0f, 12.0f, 24.0f, 48.0f};
    const NSInteger safeMode = MAX(0, MIN(mode, 6));
    return values[safeMode];
}

NSInteger modeForPPQN(float ppqn, BOOL automatic) {
    if (automatic) return 0;
    constexpr float values[] = {1.0f, 2.0f, 4.0f, 12.0f, 24.0f, 48.0f};
    NSInteger best = 2;
    float bestError = INFINITY;
    for (NSInteger index = 0; index < 6; ++index) {
        const float error = std::abs(ppqn - values[index]);
        if (error < bestError) {
            bestError = error;
            best = index + 1;
        }
    }
    return best;
}
} // namespace

@interface POClockAudioUnit () {
    AUAudioUnitBus *_inputBus;
    AUAudioUnitBus *_outputBus;
    AUAudioUnitBusArray *_inputBusArray;
    AUAudioUnitBusArray *_outputBusArray;
    AUParameterTree *_parameterTreeInternal;
    POClockDSPKernelAdapter *_kernel;
}
@end

@implementation POClockAudioUnit

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                      options:(AudioComponentInstantiationOptions)options
                                        error:(NSError * _Nullable __autoreleasing *)outError {
    self = [super initWithComponentDescription:componentDescription
                                       options:options
                                         error:outError];
    if (!self) return nil;

    _kernel = [[POClockDSPKernelAdapter alloc] init];
    self.maximumFramesToRender = 4096;

    AVAudioFormat *format = [[AVAudioFormat alloc]
        initStandardFormatWithSampleRate:48000.0 channels:2];
    NSError *busError = nil;
    _inputBus = [[AUAudioUnitBus alloc] initWithFormat:format error:&busError];
    if (busError != nil) {
        if (outError != nullptr) *outError = busError;
        return nil;
    }
    _outputBus = [[AUAudioUnitBus alloc] initWithFormat:format error:&busError];
    if (busError != nil) {
        if (outError != nullptr) *outError = busError;
        return nil;
    }

    _inputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                           busType:AUAudioUnitBusTypeInput
                                                            busses:@[_inputBus]];
    _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                            busType:AUAudioUnitBusTypeOutput
                                                             busses:@[_outputBus]];
    [self buildParameterTree];
    return self;
}

- (AUParameter *)parameterWithIdentifier:(NSString *)identifier
                                    name:(NSString *)name
                                 address:(AUParameterAddress)address
                                     min:(AUValue)minimum
                                     max:(AUValue)maximum
                                    unit:(AudioUnitParameterUnit)unit
                            valueStrings:(nullable NSArray<NSString *> *)valueStrings {
    const AudioUnitParameterOptions flags =
        kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable;
    return [AUParameterTree createParameterWithIdentifier:identifier
                                                     name:name
                                                  address:address
                                                      min:minimum
                                                      max:maximum
                                                     unit:unit
                                                 unitName:nil
                                                    flags:flags
                                             valueStrings:valueStrings
                                      dependentParameters:nil];
}

- (void)buildParameterTree {
    AUParameter *threshold = [self parameterWithIdentifier:@"thresholdHigh"
        name:@"Manual Threshold" address:kParamThresholdHigh min:0.02 max:0.95
        unit:kAudioUnitParameterUnit_LinearGain valueStrings:nil];
    AUParameter *hysteresis = [self parameterWithIdentifier:@"thresholdLow"
        name:@"Release Threshold" address:kParamThresholdLow min:0.0 max:0.90
        unit:kAudioUnitParameterUnit_LinearGain valueStrings:nil];
    AUParameter *ppqn = [self parameterWithIdentifier:@"inputPPQN"
        name:@"Input PPQN" address:kParamInputPPQN min:0 max:6
        unit:kAudioUnitParameterUnit_Indexed
        valueStrings:@[@"Auto", @"1", @"2", @"4", @"12", @"24", @"48"]];
    AUParameter *channel = [self parameterWithIdentifier:@"inputChannel"
        name:@"Clock Channel" address:kParamInputChannel min:0 max:1
        unit:kAudioUnitParameterUnit_Indexed valueStrings:@[@"L", @"R"]];
    AUParameter *mode = [self parameterWithIdentifier:@"outputMode"
        name:@"Output" address:kParamOutputMode min:0 max:2
        unit:kAudioUnitParameterUnit_Indexed
        valueStrings:@[@"Tap Note", @"MIDI Clock", @"Both"]];
    AUParameter *tapNote = [self parameterWithIdentifier:@"tapNote"
        name:@"Tap MIDI Note" address:kParamTapNote min:0 max:127
        unit:kAudioUnitParameterUnit_MIDINoteNumber valueStrings:nil];
    AUParameter *transport = [self parameterWithIdentifier:@"transport"
        name:@"MIDI Start/Stop" address:kParamSendTransport min:0 max:1
        unit:kAudioUnitParameterUnit_Boolean valueStrings:nil];
    AUParameter *automaticThreshold = [self parameterWithIdentifier:@"autoThreshold"
        name:@"Automatic Threshold" address:kParamAutoThreshold min:0 max:1
        unit:kAudioUnitParameterUnit_Boolean valueStrings:nil];
    AUParameter *initialBPM = [self parameterWithIdentifier:@"initialBPM"
        name:@"Auto PPQN Reference BPM" address:kParamInitialBPM min:30 max:300
        unit:kAudioUnitParameterUnit_BPM valueStrings:nil];
    AUParameter *smoothing = [self parameterWithIdentifier:@"smoothing"
        name:@"Tempo Smoothing" address:kParamSmoothing min:0.01 max:1.0
        unit:kAudioUnitParameterUnit_Generic valueStrings:nil];
    AUParameter *phase = [self parameterWithIdentifier:@"phaseCorrection"
        name:@"Phase Correction" address:kParamPhaseCorrection min:0 max:1
        unit:kAudioUnitParameterUnit_Generic valueStrings:nil];
    AUParameter *dropout = [self parameterWithIdentifier:@"dropoutPeriods"
        name:@"Dropout Periods" address:kParamDropoutPeriods min:2.1 max:8.0
        unit:kAudioUnitParameterUnit_Generic valueStrings:nil];

    _parameterTreeInternal = [AUParameterTree createTreeWithChildren:@[
        threshold, hysteresis, ppqn, channel, mode, tapNote, transport,
        automaticThreshold, initialBPM, smoothing, phase, dropout
    ]];

    __weak POClockAudioUnit *weakSelf = self;
    _parameterTreeInternal.implementorValueObserver =
        ^(AUParameter *parameter, AUValue value) {
            POClockAudioUnit *strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf setKernelParameter:parameter.address value:value];
            }
        };
    _parameterTreeInternal.implementorValueProvider = ^AUValue(AUParameter *parameter) {
        POClockAudioUnit *strongSelf = weakSelf;
        return strongSelf != nil
            ? [strongSelf kernelParameterValue:parameter.address]
            : 0.0f;
    };

    threshold.value = 0.30f;
    hysteresis.value = 0.12f;
    ppqn.value = 2.0f; // indexed mode 2 == 2 PPQN
    channel.value = 0.0f;
    mode.value = 2.0f;
    tapNote.value = 60.0f;
    transport.value = 1.0f;
    automaticThreshold.value = 1.0f;
    initialBPM.value = 120.0f;
    smoothing.value = 0.18f;
    phase.value = 0.30f;
    dropout.value = 3.0f;
}

- (void)setKernelParameter:(AUParameterAddress)address value:(AUValue)value {
    switch (address) {
        case kParamThresholdHigh: _kernel.thresholdHigh = value; break;
        case kParamThresholdLow: _kernel.thresholdLow = value; break;
        case kParamInputPPQN: {
            const NSInteger mode = static_cast<NSInteger>(llroundf(value));
            _kernel.autoInputPPQN = (mode == 0);
            _kernel.inputPPQN = ppqnForMode(mode);
            break;
        }
        case kParamInputChannel:
            _kernel.inputChannel = static_cast<NSInteger>(llroundf(value)); break;
        case kParamOutputMode:
            _kernel.outputMode = static_cast<NSInteger>(llroundf(value)); break;
        case kParamTapNote:
            _kernel.tapNote = static_cast<NSInteger>(llroundf(value)); break;
        case kParamSendTransport: _kernel.sendTransport = value >= 0.5f; break;
        case kParamAutoThreshold: _kernel.autoThreshold = value >= 0.5f; break;
        case kParamInitialBPM: _kernel.initialBPM = value; break;
        case kParamSmoothing: _kernel.smoothing = value; break;
        case kParamPhaseCorrection: _kernel.phaseCorrection = value; break;
        case kParamDropoutPeriods: _kernel.dropoutPeriods = value; break;
        default: break;
    }
}

- (AUValue)kernelParameterValue:(AUParameterAddress)address {
    switch (address) {
        case kParamThresholdHigh: return _kernel.thresholdHigh;
        case kParamThresholdLow: return _kernel.thresholdLow;
        case kParamInputPPQN:
            return static_cast<AUValue>(modeForPPQN(
                _kernel.inputPPQN, _kernel.autoInputPPQN));
        case kParamInputChannel: return static_cast<AUValue>(_kernel.inputChannel);
        case kParamOutputMode: return static_cast<AUValue>(_kernel.outputMode);
        case kParamTapNote: return static_cast<AUValue>(_kernel.tapNote);
        case kParamSendTransport: return _kernel.sendTransport ? 1.0f : 0.0f;
        case kParamAutoThreshold: return _kernel.autoThreshold ? 1.0f : 0.0f;
        case kParamInitialBPM: return _kernel.initialBPM;
        case kParamSmoothing: return _kernel.smoothing;
        case kParamPhaseCorrection: return _kernel.phaseCorrection;
        case kParamDropoutPeriods: return _kernel.dropoutPeriods;
        default: return 0.0f;
    }
}

- (AUAudioUnitBusArray *)inputBusses { return _inputBusArray; }
- (AUAudioUnitBusArray *)outputBusses { return _outputBusArray; }
- (AUParameterTree *)parameterTree { return _parameterTreeInternal; }
- (NSArray<NSString *> *)MIDIOutputNames { return @[@"Clock + Tap"]; }
- (NSInteger)virtualMIDICableCount { return 1; }
- (BOOL)isMusicDeviceOrEffect { return YES; }
- (BOOL)canProcessInPlace { return YES; }

- (BOOL)shouldChangeToFormat:(AVAudioFormat *)format forBus:(AUAudioUnitBus *)bus {
    (void)bus;
    return format.commonFormat == AVAudioPCMFormatFloat32 &&
        format.sampleRate >= 8000.0 &&
        format.channelCount >= 1 && format.channelCount <= 2;
}

- (BOOL)allocateRenderResourcesAndReturnError:
    (NSError * _Nullable __autoreleasing *)outError {
    AVAudioFormat *inputFormat = _inputBus.format;
    AVAudioFormat *outputFormat = _outputBus.format;
    const BOOL formatsMatch =
        inputFormat.commonFormat == AVAudioPCMFormatFloat32 &&
        outputFormat.commonFormat == AVAudioPCMFormatFloat32 &&
        std::abs(inputFormat.sampleRate - outputFormat.sampleRate) < 0.5 &&
        inputFormat.channelCount == outputFormat.channelCount &&
        inputFormat.channelCount >= 1 && inputFormat.channelCount <= 2;
    if (!formatsMatch) {
        if (outError != nullptr) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                             code:kAudioUnitErr_FormatNotSupported
                                         userInfo:@{
                NSLocalizedDescriptionKey:
                    @"PO Clock Bridge requires matching mono/stereo Float32 input and output."
            }];
        }
        return NO;
    }

    if (![super allocateRenderResourcesAndReturnError:outError]) return NO;
    [_kernel setMIDIOutputEventBlock:self.MIDIOutputEventBlock];
    [_kernel prepareWithSampleRate:outputFormat.sampleRate
                     maximumFrames:self.maximumFramesToRender
                       channelCount:outputFormat.channelCount];
    return YES;
}

- (void)deallocateRenderResources {
    [_kernel reset];
    [_kernel setMIDIOutputEventBlock:nil];
    [super deallocateRenderResources];
}

- (void)reset {
    [super reset];
    [_kernel reset];
}

- (AUInternalRenderBlock)internalRenderBlock {
    return [_kernel internalRenderBlock];
}

- (NSDictionary<NSString *, id> *)fullState {
    NSMutableDictionary<NSString *, id> *state =
        [[super fullState] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *parameters =
        [NSMutableDictionary dictionary];
    for (AUParameter *parameter in _parameterTreeInternal.allParameters) {
        parameters[parameter.identifier] = @(parameter.value);
    }
    state[kSavedParametersKey] = parameters;
    return state;
}

- (void)setFullState:(NSDictionary<NSString *, id> *)fullState {
    [super setFullState:fullState];
    NSDictionary<NSString *, NSNumber *> *parameters = fullState[kSavedParametersKey];
    if (![parameters isKindOfClass:[NSDictionary class]]) return;
    for (AUParameter *parameter in _parameterTreeInternal.allParameters) {
        NSNumber *savedValue = parameters[parameter.identifier];
        if ([savedValue isKindOfClass:[NSNumber class]]) {
            parameter.value = savedValue.floatValue;
        }
    }
}

- (float)detectedBPM { return _kernel.detectedBPM; }
- (float)jitterMs { return _kernel.jitterMs; }
- (float)phaseErrorMs { return _kernel.phaseErrorMs; }
- (float)effectiveInputPPQN { return _kernel.effectiveInputPPQN; }
- (float)effectiveThreshold { return _kernel.effectiveThreshold; }
- (float)inputPeak { return _kernel.peak; }
- (BOOL)isLocked { return _kernel.isLocked; }
- (BOOL)isClockRunning { return _kernel.isRunning; }
- (uint64_t)pulseCount { return _kernel.pulseCount; }
- (void)resetClockPhase { [_kernel requestPhaseReset]; }

@end
