#ifndef MEZON_NS_H
#define MEZON_NS_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32) || defined(__CYGWIN__)
  #ifdef MEZON_NS_BUILD_SHARED
    #define MEZON_NS_API __declspec(dllexport)
  #else
    #define MEZON_NS_API __declspec(dllimport)
  #endif
#else
  #define MEZON_NS_API __attribute__((visibility("default")))
#endif

typedef struct MezonNSEngine MezonNSEngine;

typedef struct {
    int sample_rate;             /* Sample rate in Hz (default: 16000) */
    int frame_size;              /* Frame size in samples (default: 160 = 10ms at 16kHz) */
    float attenuation_limit_db;  /* Maximum attenuation limit in dB (0.0 = unlimited) */
    int num_threads;             /* Number of CPU threads for inference (default: 1) */
    float suppression_intensity; /* Psychoacoustic mask power shaping gamma [1.0 - 2.5] (default: 1.6f) */
    int enable_noise_gate;       /* Enable adaptive noise floor tracking & VAD gating (1=on, 0=off, default: 1) */
} MezonNSConfig;

/**
 * Initialize MezonNSConfig with sensible default parameters.
 */
MEZON_NS_API void mezon_ns_config_init(MezonNSConfig* config);

/**
 * Create a real-time noise suppression engine from an ONNX model file.
 * Returns NULL on failure.
 */
MEZON_NS_API MezonNSEngine* mezon_ns_create(const char* model_path, const MezonNSConfig* config);

/**
 * Create engine from in-memory ONNX model buffer (useful for embedded binary assets).
 */
MEZON_NS_API MezonNSEngine* mezon_ns_create_from_memory(
    const void* model_data,
    size_t model_size,
    const MezonNSConfig* config
);

/**
 * Create engine using default built-in embedded model weights (zero file I/O).
 * Returns NULL if library was compiled without embedded model weights.
 */
MEZON_NS_API MezonNSEngine* mezon_ns_create_embedded(const MezonNSConfig* config);

/**
 * Returns 1 if the library was compiled with built-in embedded model weights, 0 otherwise.
 */
MEZON_NS_API int mezon_ns_has_embedded_model(void);

/**
 * Process a single 10ms frame of 32-bit floating point audio (-1.0 to 1.0).
 * in_frame and out_frame must have length equal to config->frame_size (160 samples).
 * In-place processing (in_frame == out_frame) is supported.
 * Returns 0 on success, non-zero on error.
 */
MEZON_NS_API int mezon_ns_process_frame_float(
    MezonNSEngine* engine,
    const float* in_frame,
    float* out_frame
);

/**
 * Process a single 10ms frame of 16-bit signed PCM audio (-32768 to 32767).
 * In-place processing (in_frame == out_frame) is supported.
 * Returns 0 on success, non-zero on error.
 */
MEZON_NS_API int mezon_ns_process_frame_int16(
    MezonNSEngine* engine,
    const int16_t* in_frame,
    int16_t* out_frame
);

/**
 * Reset internal ring buffers and GRU recurrent hidden states.
 */
MEZON_NS_API void mezon_ns_reset(MezonNSEngine* engine);

/**
 * Free all engine resources and memory.
 */
MEZON_NS_API void mezon_ns_destroy(MezonNSEngine* engine);

/**
 * Dynamically enable or disable adaptive VAD noise gating at runtime.
 */
MEZON_NS_API void mezon_ns_set_noise_gate(MezonNSEngine* engine, int enable);

/**
 * Dynamically set psychoacoustic suppression intensity gamma [1.0 - 2.5] at runtime.
 */
MEZON_NS_API void mezon_ns_set_suppression_intensity(MezonNSEngine* engine, float gamma);

/**
 * Raise quiet frames only in the model input; reconstructed audio retains the
 * original microphone level. A non-negative value disables adaptation.
 */
MEZON_NS_API void mezon_ns_set_model_input_target_dbfs(MezonNSEngine* engine, float target_dbfs);

#ifdef __cplusplus
}
#endif

#endif /* MEZON_NS_H */
