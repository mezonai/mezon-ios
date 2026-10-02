#import "MezonNSAudioDevice.h"
#import "MezonNS.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioUnit/AudioUnit.h>
#import <mach/mach_time.h>
#include <algorithm>
#include <atomic>

static constexpr double kAudioSampleRate = 16000;
static constexpr UInt32 kMaxCallbackFrames = 2048;
static constexpr int kModelFrameSamples = 160;

@interface MezonNSAudioDevice () {
@public
    AudioUnit _audioUnit;
    id<RTCAudioDeviceDelegate> _delegate;
    BOOL _initialized;
    BOOL _playoutInitialized;
    BOOL _recordingInitialized;
    std::atomic<bool> _playing;
    std::atomic<bool> _recording;
    BOOL _unitRunning;
    std::atomic<uint64_t> _capturedFrames;
    std::atomic<int32_t> _lastCaptureStatus;
    std::atomic<int32_t> _inputPeak;
    BOOL _hardwareInterrupted;
    std::atomic<bool> _noiseEnabled;
    std::atomic<bool> _resetPending;
    std::atomic<void *> _model;
    std::atomic<uint64_t> _requestGeneration;
    dispatch_queue_t _modelQueue;
    double _ticksToMicroseconds;
    std::atomic<uint32_t> _slowFrameStreak;
    std::atomic<bool> _reportedFirstProcessedFrame;
    int16_t _inputFrame[kModelFrameSamples];
    int16_t _outputFrame[kModelFrameSamples];
    int _inputCount;
    int _outputIndex;
}
@end

static void disableNoiseAfterFailure(MezonNSAudioDevice *device, NSString *reason) {
    if (!device->_noiseEnabled.exchange(false)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[MezonNS][iOS] noise disabled: %@; microphone uses unfiltered audio", reason);
        if (device.onProcessingError) device.onProcessingError();
    });
}

@implementation MezonNSAudioDevice

- (instancetype)init {
    self = [super init];
    if (self) {
        _modelQueue = dispatch_queue_create("mezon.ns.model", DISPATCH_QUEUE_SERIAL);
        _noiseEnabled.store(false);
        _playing.store(false);
        _recording.store(false);
        _capturedFrames.store(0);
        _lastCaptureStatus.store(noErr);
        _inputPeak.store(0);
        _resetPending.store(false);
        _model.store(nullptr);
        _requestGeneration.store(0);
        _outputIndex = kModelFrameSamples;
        mach_timebase_info_data_t timebase = {};
        mach_timebase_info(&timebase);
        _ticksToMicroseconds = (double)timebase.numer / (double)timebase.denom / 1000.0;
        _slowFrameStreak.store(0);
        _reportedFirstProcessedFrame.store(false);
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self terminateDevice];
    void *model = _model.exchange(nullptr);
    if (model) CFRelease(model);
}

- (BOOL)noiseSuppressionEnabled { return _noiseEnabled.load(); }
- (uint64_t)capturedFrameCount { return _capturedFrames.load(); }
- (NSDictionary<NSString *, NSNumber *> *)captureDiagnostics {
    return @{@"device_recording": @(_recording.load()),
             @"device_playing": @(_playing.load()),
             @"captured_frames": @(_capturedFrames.load()),
             @"capture_status": @(_lastCaptureStatus.load()),
             @"input_peak": @(_inputPeak.load())};
}

- (void)setNoiseSuppressionEnabled:(BOOL)enabled completion:(void (^)(BOOL))completion {
    const uint64_t request = _requestGeneration.fetch_add(1) + 1;
    if (!enabled) {
        _noiseEnabled.store(false);
        _resetPending.store(true);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(YES); });
        return;
    }
    if (_model.load() != nullptr) {
        _resetPending.store(true);
        _slowFrameStreak.store(0);
        _reportedFirstProcessedFrame.store(false);
        _noiseEnabled.store(true);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(YES); });
        return;
    }
    dispatch_async(_modelQueue, ^{
        if (self->_model.load() == nullptr) {
            NSString *path = [[NSBundle mainBundle] pathForResource:@"mezon_ns_asym_babble" ofType:@"onnx"];
            MezonNS *engine = path ? [[MezonNS alloc] initWithModelPath:path attenuationLimitDb:15.0f numThreads:1] : nil;
            if (engine) {
                [engine setNoiseGate:YES];
                [engine setSuppressionIntensity:1.6f];
                [engine setModelInputTargetDbfs:-20.0f];
                int16_t probe[kModelFrameSamples] = {};
                int16_t processed[kModelFrameSamples] = {};
                if ([engine processFrameInt16:probe outFrame:processed]) {
                    [engine reset];
                    self->_model.store((__bridge_retained void *)engine);
                }
            }
        }
        const BOOL success = self->_model.load() != nullptr;
        if (success && self->_requestGeneration.load() == request) {
            self->_resetPending.store(true);
            self->_slowFrameStreak.store(0);
            self->_reportedFirstProcessedFrame.store(false);
            self->_noiseEnabled.store(true);
        }
        if (!success) NSLog(@"[MezonNS][iOS] failed to load bundled noise model");
        dispatch_async(dispatch_get_main_queue(), ^{ completion(success); });
    });
}

- (double)deviceInputSampleRate { return kAudioSampleRate; }
- (double)deviceOutputSampleRate { return kAudioSampleRate; }
- (NSTimeInterval)inputIOBufferDuration { return [AVAudioSession sharedInstance].IOBufferDuration; }
- (NSTimeInterval)outputIOBufferDuration { return [AVAudioSession sharedInstance].IOBufferDuration; }
- (NSInteger)inputNumberOfChannels { return 1; }
- (NSInteger)outputNumberOfChannels { return 1; }
- (NSTimeInterval)inputLatency { return [AVAudioSession sharedInstance].inputLatency; }
- (NSTimeInterval)outputLatency { return [AVAudioSession sharedInstance].outputLatency; }
- (BOOL)isInitialized { return _initialized; }
- (BOOL)isPlayoutInitialized { return _playoutInitialized; }
- (BOOL)isRecordingInitialized { return _recordingInitialized; }
- (BOOL)isPlaying { return _playing; }
- (BOOL)isRecording { return _recording; }

static AudioStreamBasicDescription pcmFormat(void) {
    AudioStreamBasicDescription format = {};
    format.mSampleRate = kAudioSampleRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = sizeof(int16_t);
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = sizeof(int16_t);
    format.mChannelsPerFrame = 1;
    format.mBitsPerChannel = 16;
    return format;
}

static OSStatus inputCallback(void *context, AudioUnitRenderActionFlags *flags,
                              const AudioTimeStamp *timeStamp, UInt32 bus, UInt32 frames,
                              AudioBufferList *ignoredData) {
    MezonNSAudioDevice *device = (__bridge MezonNSAudioDevice *)context;
    if (!device->_recording.load() || !device->_delegate) return noErr;
    if (frames > kMaxCallbackFrames) {
        device->_lastCaptureStatus.store(kAudio_ParamError);
        return kAudio_ParamError;
    }
    int16_t samples[kMaxCallbackFrames];
    AudioBufferList data = {};
    data.mNumberBuffers = 1;
    data.mBuffers[0].mNumberChannels = 1;
    data.mBuffers[0].mDataByteSize = frames * sizeof(int16_t);
    data.mBuffers[0].mData = samples;
    OSStatus status = AudioUnitRender(device->_audioUnit, flags, timeStamp, 1, frames, &data);
    if (status != noErr) {
        device->_lastCaptureStatus.store(status);
        return status;
    }
    int32_t peak = 0;
    for (UInt32 i = 0; i < frames; i++) {
        const int32_t sample = samples[i];
        peak = std::max(peak, sample < 0 ? -sample : sample);
    }
    device->_inputPeak.store(peak);

    if (device->_noiseEnabled.load() && device->_model.load() != nullptr) {
        MezonNS *engine = (__bridge MezonNS *)device->_model.load();
        if (device->_resetPending.exchange(false)) {
            [engine reset];
            device->_inputCount = 0;
            device->_outputIndex = kModelFrameSamples;
        }
        // Keep the output filtered when a CoreAudio callback is not aligned to 160 samples.
        for (UInt32 i = 0; i < frames; i++) {
            const int16_t input = samples[i];
            const BOOL outputUnavailable = device->_outputIndex >= kModelFrameSamples;
            samples[i] = !outputUnavailable
                ? device->_outputFrame[device->_outputIndex++] : 0;
            device->_inputFrame[device->_inputCount++] = input;
            if (device->_inputCount == kModelFrameSamples) {
                const uint64_t inferenceStart = mach_absolute_time();
                const BOOL processed = [engine processFrameInt16:device->_inputFrame outFrame:device->_outputFrame];
                const uint64_t inferenceUs = (uint64_t)((mach_absolute_time() - inferenceStart) * device->_ticksToMicroseconds);
                if (inferenceUs > 8'000) {
                    if (device->_slowFrameStreak.fetch_add(1, std::memory_order_relaxed) + 1 >= 3) {
                        disableNoiseAfterFailure(device, @"inference exceeded the 10 ms frame budget repeatedly");
                    }
                } else {
                    device->_slowFrameStreak.store(0, std::memory_order_relaxed);
                }
                if (processed && !device->_reportedFirstProcessedFrame.exchange(true)) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (device.onFirstProcessedFrame) device.onFirstProcessedFrame();
                    });
                }
                if (processed) {
                    device->_outputIndex = 0;
                } else {
                    memcpy(device->_outputFrame, device->_inputFrame, sizeof(device->_outputFrame));
                    device->_outputIndex = 0;
                    disableNoiseAfterFailure(device, @"inference failed");
                }
                device->_inputCount = 0;
            }
        }
    }
    status = device->_delegate.deliverRecordedData(flags, timeStamp, bus, frames, &data, nullptr, nil);
    device->_lastCaptureStatus.store(status);
    if (status == noErr) device->_capturedFrames.fetch_add(frames);
    return status;
}

static OSStatus outputCallback(void *context, AudioUnitRenderActionFlags *flags,
                               const AudioTimeStamp *timeStamp, UInt32 bus, UInt32 frames,
                               AudioBufferList *data) {
    MezonNSAudioDevice *device = (__bridge MezonNSAudioDevice *)context;
    if (!device->_playing.load() || !device->_delegate) {
        for (UInt32 index = 0; index < data->mNumberBuffers; index++) {
            if (data->mBuffers[index].mData) {
                memset(data->mBuffers[index].mData, 0, data->mBuffers[index].mDataByteSize);
            }
        }
        return noErr;
    }
    return device->_delegate.getPlayoutData(flags, timeStamp, bus, frames, data);
}

- (BOOL)createAudioUnit {
    AudioComponentDescription description = {};
    description.componentType = kAudioUnitType_Output;
    description.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    description.componentManufacturer = kAudioUnitManufacturer_Apple;
    AudioComponent component = AudioComponentFindNext(nullptr, &description);
    if (!component || AudioComponentInstanceNew(component, &_audioUnit) != noErr) return NO;
    UInt32 enabled = 1;
    AudioStreamBasicDescription format = pcmFormat();
    AURenderCallbackStruct input = {inputCallback, (__bridge void *)self};
    AURenderCallbackStruct output = {outputCallback, (__bridge void *)self};
    UInt32 maxFrames = kMaxCallbackFrames;
    BOOL ok =
        AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enabled, sizeof(enabled)) == noErr &&
        AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enabled, sizeof(enabled)) == noErr &&
        AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, sizeof(format)) == noErr &&
        AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format)) == noErr &&
        AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, sizeof(maxFrames)) == noErr &&
        AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &input, sizeof(input)) == noErr &&
        AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &output, sizeof(output)) == noErr &&
        AudioUnitInitialize(_audioUnit) == noErr;
    if (!ok) {
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = nullptr;
        NSLog(@"[MezonNS][iOS] failed to initialize WebRTC audio device");
        return NO;
    }
    return YES;
}

- (BOOL)initializeWithDelegate:(id<RTCAudioDeviceDelegate>)delegate {
    if (_initialized) return YES;
    if (![self createAudioUnit]) return NO;
    _delegate = delegate;
    _initialized = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionInterrupted:)
                                                 name:AVAudioSessionInterruptionNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChanged:)
                                                 name:AVAudioSessionRouteChangeNotification object:nil];
    return YES;
}

- (BOOL)terminateDevice {
    if (!_initialized) return YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionRouteChangeNotification object:nil];
    if (_audioUnit) AudioOutputUnitStop(_audioUnit);
    _unitRunning = NO;
    _playing = NO;
    _recording = NO;
    _hardwareInterrupted = NO;
    _playoutInitialized = NO;
    _recordingInitialized = NO;
    _initialized = NO;
    if (_audioUnit) {
        AudioUnitUninitialize(_audioUnit);
        AudioComponentInstanceDispose(_audioUnit);
    }
    _audioUnit = nullptr;
    _delegate = nil;
    return YES;
}

- (BOOL)initializePlayout { _playoutInitialized = _initialized; return _playoutInitialized; }
- (BOOL)initializeRecording { _recordingInitialized = _initialized; return _recordingInitialized; }
- (BOOL)startPlayout {
    if (!_initialized) return NO;
    if (!_unitRunning && !_hardwareInterrupted) {
        if (!_audioUnit && ![self createAudioUnit]) return NO;
        OSStatus status = AudioOutputUnitStart(_audioUnit);
        if (status != noErr) {
            NSLog(@"[MezonNS][iOS] startPlayout failed: %d", (int)status);
            return NO;
        }
        _unitRunning = YES;
    }
    _playing = YES;
    return YES;
}
- (BOOL)startRecording {
    if (!_initialized) return NO;
    if (!_unitRunning && !_hardwareInterrupted) {
        if (!_audioUnit && ![self createAudioUnit]) return NO;
        OSStatus status = AudioOutputUnitStart(_audioUnit);
        if (status != noErr) {
            NSLog(@"[MezonNS][iOS] startRecording failed: %d", (int)status);
            return NO;
        }
        _unitRunning = YES;
    }
    _recording = YES;
    return YES;
}
- (BOOL)stopPlayout {
    _playing = NO;
    if (!_recording && _audioUnit) {
        AudioOutputUnitStop(_audioUnit);
        _unitRunning = NO;
    }
    return YES;
}
- (BOOL)stopRecording {
    _recording = NO;
    _resetPending.store(true);
    if (!_playing && _audioUnit) {
        AudioOutputUnitStop(_audioUnit);
        _unitRunning = NO;
    }
    return YES;
}

- (void)prepareForAudioSessionRestart {
    id<RTCAudioDeviceDelegate> delegate = _delegate;
    if (!delegate) return;
    // Do not hold RTCAudioSession's configuration lock while waiting for ADM.
    [delegate dispatchSync:^{
        if (!self->_initialized || self->_delegate != delegate) return;
        self->_hardwareInterrupted = YES;
        if (self->_audioUnit) AudioOutputUnitStop(self->_audioUnit);
        self->_unitRunning = NO;
        [delegate notifyAudioInputInterrupted];
        [delegate notifyAudioOutputInterrupted];
        self->_resetPending.store(true);
    }];
}

- (void)recoverAudio {
    id<RTCAudioDeviceDelegate> delegate = _delegate;
    if (!delegate) return;
    [delegate dispatchAsync:^{
        if (!self->_initialized || self->_delegate != delegate) return;
        // A successful session restore also covers suspension without an
        // interruption-ended notification. RTCAudioSession's audio-enabled
        // switch does not restart a custom RTCAudioDevice.
        self->_hardwareInterrupted = NO;
        [self rebuildAudioUnit];
    }];
}

// Runs on the ADM thread. Keep WebRTC's requested playout/recording state even
// if a hardware restart fails, so the next recovery can retry both directions.
- (void)rebuildAudioUnit {
    if (_audioUnit) {
        AudioOutputUnitStop(_audioUnit);
        AudioUnitUninitialize(_audioUnit);
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = nullptr;
    }
    _unitRunning = NO;
    [_delegate notifyAudioInputInterrupted];
    [_delegate notifyAudioOutputInterrupted];
    _resetPending.store(true);
    if (![self createAudioUnit]) return;
    // Update WebRTC's buffers before the new unit starts invoking callbacks.
    [_delegate notifyAudioInputParametersChange];
    [_delegate notifyAudioOutputParametersChange];
    if (_playing || _recording) {
        OSStatus status = AudioOutputUnitStart(_audioUnit);
        _unitRunning = status == noErr;
        NSLog(@"[SFU audio] device_recovery status=%d recording=%d playing=%d",
              (int)status, (int)_recording.load(), (int)_playing.load());
    }
}

- (void)audioSessionInterrupted:(NSNotification *)notification {
    id<RTCAudioDeviceDelegate> delegate = _delegate;
    if (!delegate) return;
    NSNumber *type = notification.userInfo[AVAudioSessionInterruptionTypeKey];
    [delegate dispatchAsync:^{
        if (!self->_initialized || self->_delegate != delegate) return;
        if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan) {
            self->_hardwareInterrupted = YES;
            if (self->_audioUnit) AudioOutputUnitStop(self->_audioUnit);
            self->_unitRunning = NO;
            [delegate notifyAudioInputInterrupted];
            [delegate notifyAudioOutputInterrupted];
            self->_resetPending.store(true);
        }
        // The session owner activates AVAudioSession before calling recoverAudio.
    }];
}

- (void)audioRouteChanged:(NSNotification *)notification {
    id<RTCAudioDeviceDelegate> delegate = _delegate;
    if (!delegate) return;
    [delegate dispatchAsync:^{
        if (!self->_initialized || self->_delegate != delegate || self->_hardwareInterrupted) return;
        if (!self->_audioUnit) {
            [self rebuildAudioUnit];
            return;
        }
        // Ordinary route notifications only restart the existing unit. Creating
        // a new VoiceProcessingIO can itself trigger another route notification.
        AudioOutputUnitStop(self->_audioUnit);
        self->_unitRunning = NO;
        [delegate notifyAudioInputInterrupted];
        [delegate notifyAudioOutputInterrupted];
        self->_resetPending.store(true);
        [delegate notifyAudioInputParametersChange];
        [delegate notifyAudioOutputParametersChange];
        if (self->_playing || self->_recording) {
            OSStatus status = AudioOutputUnitStart(self->_audioUnit);
            self->_unitRunning = status == noErr;
            if (status != noErr) NSLog(@"[SFU audio] route_restart status=%d", (int)status);
        }
    }];
}
@end
