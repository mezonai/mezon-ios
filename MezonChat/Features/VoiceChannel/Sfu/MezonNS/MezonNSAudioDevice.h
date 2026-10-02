#import <Foundation/Foundation.h>
#import <WebRTC/RTCAudioDevice.h>

NS_ASSUME_NONNULL_BEGIN

@interface MezonNSAudioDevice : NSObject <RTCAudioDevice>
@property (nonatomic, readonly) BOOL noiseSuppressionEnabled;
@property (nonatomic, readonly) uint64_t capturedFrameCount;
@property (nonatomic, readonly) NSDictionary<NSString *, NSNumber *> *captureDiagnostics;
@property (nonatomic, copy, nullable) void (^onProcessingError)(void);
@property (nonatomic, copy, nullable) void (^onFirstProcessedFrame)(void);
- (void)setNoiseSuppressionEnabled:(BOOL)enabled completion:(void (^)(BOOL success))completion;
// Stop hardware before deactivating AVAudioSession; preserves WebRTC intent.
- (void)prepareForAudioSessionRestart;
// Call only after the owner has successfully restored AVAudioSession.
- (void)recoverAudio;
@end

NS_ASSUME_NONNULL_END
