#include "mezon_ns.h"
#include "mezon_ns_engine.hpp"

#if __has_include("mezon_ns_model_data.h") || defined(MEZON_NS_HAS_EMBEDDED_MODEL)
#include "mezon_ns_model_data.h"
#define MEZON_NS_EMBEDDED_AVAILABLE 1
#else
#define MEZON_NS_EMBEDDED_AVAILABLE 0
#endif

struct MezonNSEngine {
    mezon::NoiseSuppressionEngine engine;
};

void mezon_ns_config_init(MezonNSConfig* config) {
    if (!config) return;
    config->sample_rate = 16000;
    config->frame_size = 160;
    config->attenuation_limit_db = 0.0f;
    config->num_threads = 1;
    config->suppression_intensity = 1.0f;
    config->enable_noise_gate = 0;
}

MezonNSEngine* mezon_ns_create(const char* model_path, const MezonNSConfig* config) {
    if (!model_path) return nullptr;

    auto* handle = new (std::nothrow) MezonNSEngine();
    if (!handle) return nullptr;

    if (!handle->engine.init(model_path, config)) {
        delete handle;
        return nullptr;
    }

    return handle;
}

MezonNSEngine* mezon_ns_create_from_memory(
    const void* model_data,
    size_t model_size,
    const MezonNSConfig* config
) {
    if (!model_data || model_size == 0) return nullptr;

    auto* handle = new (std::nothrow) MezonNSEngine();
    if (!handle) return nullptr;

    if (!handle->engine.init_from_memory(model_data, model_size, config)) {
        delete handle;
        return nullptr;
    }

    return handle;
}

int mezon_ns_has_embedded_model(void) {
#if MEZON_NS_EMBEDDED_AVAILABLE
    return 1;
#else
    return 0;
#endif
}

MezonNSEngine* mezon_ns_create_embedded(const MezonNSConfig* config) {
#if MEZON_NS_EMBEDDED_AVAILABLE
    return mezon_ns_create_from_memory(mezon_ns_model_bytes, mezon_ns_model_size, config);
#else
    (void)config;
    return nullptr;
#endif
}

int mezon_ns_process_frame_float(
    MezonNSEngine* engine,
    const float* in_frame,
    float* out_frame
) {
    if (!engine || !in_frame || !out_frame) return -1;
    return engine->engine.process_frame_float(in_frame, out_frame);
}

int mezon_ns_process_frame_int16(
    MezonNSEngine* engine,
    const int16_t* in_frame,
    int16_t* out_frame
) {
    if (!engine || !in_frame || !out_frame) return -1;
    return engine->engine.process_frame_int16(in_frame, out_frame);
}

void mezon_ns_reset(MezonNSEngine* engine) {
    if (!engine) return;
    engine->engine.reset();
}

void mezon_ns_destroy(MezonNSEngine* engine) {
    if (!engine) return;
    delete engine;
}

void mezon_ns_set_noise_gate(MezonNSEngine* engine, int enable) {
    if (!engine) return;
    engine->engine.set_noise_gate(enable != 0);
}

void mezon_ns_set_suppression_intensity(MezonNSEngine* engine, float gamma) {
    if (!engine) return;
    engine->engine.set_suppression_intensity(gamma);
}

void mezon_ns_set_model_input_target_dbfs(MezonNSEngine* engine, float target_dbfs) {
    if (!engine) return;
    engine->engine.set_model_input_target_dbfs(target_dbfs);
}
