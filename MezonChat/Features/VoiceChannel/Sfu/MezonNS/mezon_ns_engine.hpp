#ifndef MEZON_NS_ENGINE_HPP
#define MEZON_NS_ENGINE_HPP

#include "mezon_ns.h"
#include <string>
#include <vector>
#include <memory>

namespace Ort {
    class Env;
    class Session;
    class MemoryInfo;
}

namespace mezon {

class FastRealFFT512;

class NoiseSuppressionEngine {
public:
    NoiseSuppressionEngine();
    ~NoiseSuppressionEngine();

    bool init(const char* model_path, const MezonNSConfig* config);
    bool init_from_memory(const void* model_data, size_t model_size, const MezonNSConfig* config);

    int process_frame_float(const float* in_frame, float* out_frame);
    int process_frame_int16(const int16_t* in_frame, int16_t* out_frame);

    void reset();

    void set_noise_gate(bool enable) { config_.enable_noise_gate = enable ? 1 : 0; }
    void set_suppression_intensity(float gamma) { config_.suppression_intensity = gamma; }
    void set_model_input_target_dbfs(float target_dbfs);

private:
    void init_buffers();
    void run_onnx_inference(const float* mag_in, float* mask_out);

    MezonNSConfig config_;
    std::unique_ptr<FastRealFFT512> fft_;

    // Audio buffers
    static constexpr int HOP_LENGTH = 160;   // 10ms at 16kHz
    static constexpr int WIN_LENGTH = 400;   // 25ms analysis window
    static constexpr int FFT_SIZE = 512;
    static constexpr int FREQ_BINS = 257;
    static constexpr int NUM_GRU_LAYERS = 2;
    static constexpr int GRU_HIDDEN_SIZE = 256;
    static constexpr int CONV_STATE_SIZE = 172544;

    std::vector<float> input_buffer_;
    std::vector<float> output_buffer_;
    std::vector<float> windowed_frame_;
    std::vector<float> mag_spec_;
    std::vector<float> model_mag_spec_;
    std::vector<float> phase_spec_;
    std::vector<float> clean_mag_spec_;
    std::vector<float> synth_frame_;
    std::vector<float> gru_hidden_state_;
    std::vector<float> conv_state_;
    std::vector<float> wola_norm_factors_;

    // Conversion scratch buffer for int16
    std::vector<float> float_scratch_in_;
    std::vector<float> float_scratch_out_;

    // Adaptive noise floor tracking & VAD state (Zero allocation)
    float noise_floor_ = 0.0005f;
    float speech_peak_ = 0.015f;
    float vad_state_ = 0.0f;
    int hangover_frames_ = 0;
    int startup_frames_ = 0;
    float model_target_rms_ = 0.0f;
    float model_level_rms_ = 0.0f;

    // PIMPL for ONNX Runtime to isolate headers
    struct OnnxImpl;
    std::unique_ptr<OnnxImpl> onnx_;
};

} // namespace mezon

#endif // MEZON_NS_ENGINE_HPP
