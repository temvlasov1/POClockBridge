#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface POClockDSPKernelAdapter : NSObject

- (void)prepareWithSampleRate:(double)sampleRate
                maximumFrames:(AUAudioFrameCount)maximumFrames
                  channelCount:(AUAudioChannelCount)channelCount;
- (void)reset;
- (void)requestPhaseReset;
- (void)setMIDIOutputEventBlock:(nullable AUMIDIOutputEventBlock)block;
- (AUInternalRenderBlock)internalRenderBlock;

@property (atomic) float thresholdHigh;
@property (atomic) float thresholdLow;
@property (atomic) BOOL autoThreshold;
@property (atomic) float inputPPQN;
@property (atomic) BOOL autoInputPPQN;
@property (atomic) NSInteger inputChannel; // 0=L, 1=R
@property (atomic) NSInteger outputMode;   // 0=tap, 1=clock, 2=both
@property (atomic) NSInteger tapNote;
@property (atomic) BOOL sendTransport;
@property (atomic) float initialBPM;
@property (atomic) float smoothing;
@property (atomic) float phaseCorrection;
@property (atomic) float dropoutPeriods;

@property (atomic, readonly) float detectedBPM;
@property (atomic, readonly) float jitterMs;
@property (atomic, readonly) float phaseErrorMs;
@property (atomic, readonly) float effectiveInputPPQN;
@property (atomic, readonly) float effectiveThreshold;
@property (atomic, readonly) float peak;
@property (atomic, readonly, getter=isLocked) BOOL locked;
@property (atomic, readonly, getter=isRunning) BOOL running;
@property (atomic, readonly) uint64_t pulseCount;

@end

NS_ASSUME_NONNULL_END
