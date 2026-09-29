#import "MezonNS.h"
#include "mezon_ns.h"
#include <exception>

@implementation MezonNS {
    MezonNSEngine* _engine;
}

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                       attenuationLimitDb:(float)attenuationLimitDb
                               numThreads:(int)numThreads {
    self = [super init];
    if (self) {
        MezonNSConfig config;
        mezon_ns_config_init(&config);
        config.attenuation_limit_db = attenuationLimitDb;
        config.num_threads = numThreads > 0 ? numThreads : 1;

        _engine = mezon_ns_create([modelPath UTF8String], &config);
        if (!_engine) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    [self close];
}

- (void)close {
    if (_engine) {
        mezon_ns_destroy(_engine);
        _engine = nullptr;
    }
}

- (BOOL)processFrameInt16:(const int16_t *)inFrame outFrame:(int16_t *)outFrame {
    if (!_engine || !inFrame || !outFrame) {
        return NO;
    }
    try {
        return mezon_ns_process_frame_int16(_engine, inFrame, outFrame) == 0;
    } catch (const std::exception&) {
        return NO;
    }
}

- (void)setNoiseGate:(BOOL)enable {
    if (_engine) {
        mezon_ns_set_noise_gate(_engine, enable ? 1 : 0);
    }
}

- (void)setSuppressionIntensity:(float)gamma {
    if (_engine) {
        mezon_ns_set_suppression_intensity(_engine, gamma);
    }
}

- (void)setModelInputTargetDbfs:(float)targetDbfs {
    if (_engine) {
        mezon_ns_set_model_input_target_dbfs(_engine, targetDbfs);
    }
}

- (void)reset {
    if (_engine) {
        mezon_ns_reset(_engine);
    }
}

@end
