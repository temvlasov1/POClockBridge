#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface POClockAudioUnit : AUAudioUnit
@property (nonatomic, readonly) float detectedBPM;
@property (nonatomic, readonly) float jitterMs;
@property (nonatomic, readonly) float phaseErrorMs;
@property (nonatomic, readonly) float effectiveInputPPQN;
@property (nonatomic, readonly) float effectiveThreshold;
@property (nonatomic, readonly) float inputPeak;
@property (nonatomic, readonly, getter=isLocked) BOOL locked;
@property (nonatomic, readonly, getter=isClockRunning) BOOL clockRunning;
@property (nonatomic, readonly) uint64_t pulseCount;
- (void)resetClockPhase;
@end

NS_ASSUME_NONNULL_END
