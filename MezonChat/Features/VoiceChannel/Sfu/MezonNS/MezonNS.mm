#import "MezonNS.h"
#include "mezon_ns.h"
#include <exception>
#import <CommonCrypto/CommonDigest.h>
#include <atomic>

static NSString *const kModelURL = @"https://cdn.komu.vn/ns/mezon_ns_asym.onnx";
static NSString *const kModelFile = @"mezon_ns_asym.onnx";
static std::atomic<bool> modelRefreshing(false);

static NSString *modelSHA256(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (unsigned char byte : digest) [hex appendFormat:@"%02x", byte];
    return hex;
}

static NSDictionary *cachedModelMetadata(NSURL *directory) {
    NSURL *metadataURL = [directory URLByAppendingPathComponent:@"mezon_ns_asym.plist"];
    NSData *metadataData = [NSData dataWithContentsOfURL:metadataURL];
    if (!metadataData) return nil;
    id metadata = [NSPropertyListSerialization propertyListWithData:metadataData options:0 format:nil error:nil];
    if (![metadata isKindOfClass:NSDictionary.class]) return nil;
    if (![metadata[@"sha256"] isKindOfClass:NSString.class]) return nil;
    NSData *model = [NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:kModelFile]];
    if (!model || ![metadata[@"sha256"] isEqualToString:modelSHA256(model)]) return nil;
    return metadata;
}

// This runs on a model worker. Audio callbacks never wait for disk or the CDN.
static BOOL downloadModel(NSURL *directory, NSDictionary *cached) {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 12;
    configuration.timeoutIntervalForResource = 12;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kModelURL]
                                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                     timeoutInterval:12];
    if ([cached[@"etag"] isKindOfClass:NSString.class]) [request setValue:cached[@"etag"] forHTTPHeaderField:@"If-None-Match"];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSData *data = nil;
    __block NSHTTPURLResponse *response = nil;
    __block NSError *failure = nil;
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *body, NSURLResponse *reply, NSError *error) {
        data = body;
        if ([reply isKindOfClass:NSHTTPURLResponse.class]) response = (NSHTTPURLResponse *)reply;
        failure = error;
        dispatch_semaphore_signal(done);
    }];
    [task resume];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 13 * NSEC_PER_SEC)) != 0) {
        [task cancel];
        [session invalidateAndCancel];
        return NO;
    }
    [session finishTasksAndInvalidate];
    if (failure || !response) return NO;
    if (response.statusCode == 304) return cached != nil;
    if (response.statusCode < 200 || response.statusCode >= 300 || data.length == 0) return NO;
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
    NSURL *temporary = [directory URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".part"]];
    if (![data writeToURL:temporary options:NSDataWritingAtomic error:nil]) return NO;
    MezonNS *probe = [[MezonNS alloc] initWithModelPath:temporary.path attenuationLimitDb:15.0f numThreads:1];
    int16_t input[160] = {};
    int16_t output[160] = {};
    BOOL valid = probe && [probe processFrameInt16:input outFrame:output];
    [probe close];
    [files removeItemAtURL:temporary error:nil];
    if (!valid) return NO;
    NSMutableDictionary *metadata = [@{@"sha256": modelSHA256(data)} mutableCopy];
    NSString *etag = [response valueForHTTPHeaderField:@"ETag"];
    if (etag.length > 0) metadata[@"etag"] = etag;
    NSData *metadataData = [NSPropertyListSerialization dataWithPropertyList:metadata format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    return [data writeToURL:[directory URLByAppendingPathComponent:kModelFile] options:NSDataWritingAtomic error:nil]
        && [metadataData writeToURL:[directory URLByAppendingPathComponent:@"mezon_ns_asym.plist"] options:NSDataWritingAtomic error:nil];
}

@implementation MezonNS {
    MezonNSEngine* _engine;
}

+ (nullable instancetype)modelFromCDN {
    @autoreleasepool {
        NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        if (!base) return nil;
        NSURL *directory = [base URLByAppendingPathComponent:@"mezon/ns" isDirectory:YES];
        NSDictionary *cached = cachedModelMetadata(directory);
        NSString *path = [directory URLByAppendingPathComponent:kModelFile].path;
        MezonNS *engine = cached ? [[self alloc] initWithModelPath:path attenuationLimitDb:15.0f numThreads:1] : nil;
        if (engine) {
            if (!modelRefreshing.exchange(true)) {
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    @autoreleasepool {
                        downloadModel(directory, cached);
                        modelRefreshing.store(false);
                    }
                });
            }
            return engine;
        }
        if (!downloadModel(directory, nil)) return nil;
        return [[self alloc] initWithModelPath:path attenuationLimitDb:15.0f numThreads:1];
    }
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
