#import <Foundation/Foundation.h>
#import <WebRTC/RTCAudioDevice.h>

NS_ASSUME_NONNULL_BEGIN

@interface MezonNSAudioDevice : NSObject <RTCAudioDevice>
@property (nonatomic, readonly) BOOL noiseSuppressionEnabled;
@property (nonatomic, copy, nullable) void (^onProcessingError)(void);
@property (nonatomic, copy, nullable) void (^onFirstProcessedFrame)(void);
- (void)setNoiseSuppressionEnabled:(BOOL)enabled completion:(void (^)(BOOL success))completion;
@end

NS_ASSUME_NONNULL_END
