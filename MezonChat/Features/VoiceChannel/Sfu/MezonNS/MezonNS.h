#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Processes 160-sample frames of 16 kHz mono PCM audio. */
NS_SWIFT_NAME(MezonNoiseSuppression)
@interface MezonNS : NSObject

/** Load a bundled ONNX model with the requested maximum attenuation. */
- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                       attenuationLimitDb:(float)attenuationLimitDb
                               numThreads:(int)numThreads;

- (BOOL)processFrameInt16:(const int16_t *)inFrame outFrame:(int16_t *)outFrame;
- (void)setNoiseGate:(BOOL)enable;
- (void)setSuppressionIntensity:(float)gamma;
/** Help the model recognize quiet speech without raising the transmitted PCM level. */
- (void)setModelInputTargetDbfs:(float)targetDbfs;
- (void)reset;
- (void)close;

@end

NS_ASSUME_NONNULL_END
