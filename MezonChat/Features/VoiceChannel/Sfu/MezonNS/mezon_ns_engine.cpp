#include "mezon_ns_engine.hpp"
#include "fast_fft.hpp"
#include <onnxruntime_cxx_api.h>
#include <iostream>
#include <algorithm>
#include <cmath>

namespace mezon {

struct NoiseSuppressionEngine::OnnxImpl {
    Ort::Env env;
    std::unique_ptr<Ort::Session> session;
    Ort::MemoryInfo memory_info;

    // Pre-allocated I/O bindings and ping-pong buffers for zero-allocation streaming
    bool use_io_binding = false;
    int ping_pong_index = 0;
    size_t num_inputs = 0;

    std::vector<float> input_frame;
    std::vector<float> mask_output;
    std::vector<float> h_buf[2];
    std::vector<float> conv_buf[2];

    std::unique_ptr<Ort::IoBinding> io_binding[2];

    OnnxImpl()
        : env(ORT_LOGGING_LEVEL_WARNING, "MezonNS"),
          memory_info(Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault)) {
        input_frame.assign(FREQ_BINS, 0.0f);
        mask_output.assign(FREQ_BINS, 0.0f);
        h_buf[0].assign(NUM_GRU_LAYERS * 1 * GRU_HIDDEN_SIZE, 0.0f);
        h_buf[1].assign(NUM_GRU_LAYERS * 1 * GRU_HIDDEN_SIZE, 0.0f);
        conv_buf[0].assign(CONV_STATE_SIZE, 0.0f);
        conv_buf[1].assign(CONV_STATE_SIZE, 0.0f);
    }

    void reset() {
        ping_pong_index = 0;
        std::fill(h_buf[0].begin(), h_buf[0].end(), 0.0f);
        std::fill(h_buf[1].begin(), h_buf[1].end(), 0.0f);
        std::fill(conv_buf[0].begin(), conv_buf[0].end(), 0.0f);
        std::fill(conv_buf[1].begin(), conv_buf[1].end(), 0.0f);
    }

    void setup_bindings() {
        if (!session) return;
        try {
            num_inputs = session->GetInputCount();
            int64_t frame_shape[] = {1, 1, 1, FREQ_BINS};
            int64_t h_shape[] = {NUM_GRU_LAYERS, 1, GRU_HIDDEN_SIZE};
            int64_t conv_shape[] = {1, CONV_STATE_SIZE};

            reset();

            for (int i = 0; i < 2; ++i) {
                io_binding[i] = std::make_unique<Ort::IoBinding>(*session);

                int other = 1 - i;

                Ort::Value val_frame = Ort::Value::CreateTensor<float>(
                    memory_info, input_frame.data(), input_frame.size(), frame_shape, 4);
                Ort::Value val_h_in = Ort::Value::CreateTensor<float>(
                    memory_info, h_buf[i].data(), h_buf[i].size(), h_shape, 3);
                Ort::Value val_mask = Ort::Value::CreateTensor<float>(
                    memory_info, mask_output.data(), mask_output.size(), frame_shape, 4);
                Ort::Value val_h_out = Ort::Value::CreateTensor<float>(
                    memory_info, h_buf[other].data(), h_buf[other].size(), h_shape, 3);

                io_binding[i]->BindInput("frame_input", val_frame);
                io_binding[i]->BindInput("h_in", val_h_in);
                io_binding[i]->BindOutput("mask_output", val_mask);
                io_binding[i]->BindOutput("h_out", val_h_out);

                if (num_inputs >= 3) {
                    Ort::Value val_conv_in = Ort::Value::CreateTensor<float>(
                        memory_info, conv_buf[i].data(), conv_buf[i].size(), conv_shape, 2);
                    Ort::Value val_conv_out = Ort::Value::CreateTensor<float>(
                        memory_info, conv_buf[other].data(), conv_buf[other].size(), conv_shape, 2);
                    io_binding[i]->BindInput("conv_state_in", val_conv_in);
                    io_binding[i]->BindOutput("conv_state_out", val_conv_out);
                }
            }
            use_io_binding = true;
        } catch (const std::exception& e) {
            std::cerr << "[MezonNS] IoBinding setup failed (" << e.what() << "), falling back to standard Run." << std::endl;
            use_io_binding = false;
        }
    }
};

NoiseSuppressionEngine::NoiseSuppressionEngine()
    : fft_(std::make_unique<FastRealFFT512>()),
      onnx_(std::make_unique<OnnxImpl>()) {
    mezon_ns_config_init(&config_);
    init_buffers();
}

NoiseSuppressionEngine::~NoiseSuppressionEngine() = default;

void NoiseSuppressionEngine::init_buffers() {
    input_buffer_.assign(WIN_LENGTH, 0.0f);
    output_buffer_.assign(WIN_LENGTH + HOP_LENGTH, 0.0f);
    windowed_frame_.assign(FFT_SIZE, 0.0f);
    mag_spec_.assign(FREQ_BINS, 0.0f);
    model_mag_spec_.assign(FREQ_BINS, 0.0f);
    phase_spec_.assign(FREQ_BINS, 0.0f);
    clean_mag_spec_.assign(FREQ_BINS, 0.0f);
    synth_frame_.assign(FFT_SIZE, 0.0f);

    gru_hidden_state_.assign(NUM_GRU_LAYERS * 1 * GRU_HIDDEN_SIZE, 0.0f);
    conv_state_.assign(CONV_STATE_SIZE, 0.0f);
    float_scratch_in_.assign(HOP_LENGTH, 0.0f);
    float_scratch_out_.assign(HOP_LENGTH, 0.0f);

    // Precompute WOLA (Weighted Overlap-Add) synthesis normalization envelope
    // With win_length=400, hop_length=160 (overlap 2.5x), normalizing by the periodic
    // sum of squared window factors eliminates cyclic ripple and yields 140+ dB reconstruction SNR.
    wola_norm_factors_.assign(HOP_LENGTH, 1.0f);
    const auto& win = fft_->window();
    for (int i = 0; i < HOP_LENGTH; ++i) {
        float sum_sq = 0.0f;
        for (int k = 0; i + k * HOP_LENGTH < WIN_LENGTH; ++k) {
            float w = win[i + k * HOP_LENGTH];
            sum_sq += w * w;
        }
        wola_norm_factors_[i] = (sum_sq > 1e-8f) ? (1.0f / sum_sq) : 1.0f;
    }
}

bool NoiseSuppressionEngine::init(const char* model_path, const MezonNSConfig* config) {
    if (config) {
        config_ = *config;
    }

    try {
        Ort::SessionOptions session_options;
        session_options.SetIntraOpNumThreads(config_.num_threads > 0 ? config_.num_threads : 1);
        session_options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

        #ifdef _WIN32
        std::wstring wpath(model_path, model_path + strlen(model_path));
        onnx_->session = std::make_unique<Ort::Session>(onnx_->env, wpath.c_str(), session_options);
        #else
        onnx_->session = std::make_unique<Ort::Session>(onnx_->env, model_path, session_options);
        #endif

        onnx_->setup_bindings();
        reset();
        return true;
    } catch (const std::exception& e) {
        std::cerr << "[MezonNS] Failed to load ONNX model from file: " << e.what() << std::endl;
        return false;
    }
}

bool NoiseSuppressionEngine::init_from_memory(const void* model_data, size_t model_size, const MezonNSConfig* config) {
    if (config) {
        config_ = *config;
    }

    try {
        Ort::SessionOptions session_options;
        session_options.SetIntraOpNumThreads(config_.num_threads > 0 ? config_.num_threads : 1);
        session_options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

        onnx_->session = std::make_unique<Ort::Session>(
            onnx_->env,
            model_data,
            model_size,
            session_options
        );

        onnx_->setup_bindings();
        reset();
        return true;
    } catch (const std::exception& e) {
        std::cerr << "[MezonNS] Failed to load ONNX model from memory: " << e.what() << std::endl;
        return false;
    }
}

void NoiseSuppressionEngine::reset() {
    std::fill(input_buffer_.begin(), input_buffer_.end(), 0.0f);
    std::fill(output_buffer_.begin(), output_buffer_.end(), 0.0f);
    std::fill(gru_hidden_state_.begin(), gru_hidden_state_.end(), 0.0f);
    std::fill(conv_state_.begin(), conv_state_.end(), 0.0f);
    noise_floor_ = 0.0005f;
    speech_peak_ = 0.015f;
    vad_state_ = 0.0f;
    hangover_frames_ = 0;
    startup_frames_ = 0;
    model_level_rms_ = 0.0f;
    if (onnx_) {
        onnx_->reset();
    }
}

void NoiseSuppressionEngine::set_model_input_target_dbfs(float target_dbfs) {
    model_target_rms_ = (std::isfinite(target_dbfs) && target_dbfs < 0.0f)
        ? std::pow(10.0f, target_dbfs / 20.0f)
        : 0.0f;
    model_level_rms_ = 0.0f;
}

void NoiseSuppressionEngine::run_onnx_inference(const float* mag_in, float* mask_out) {
    if (!onnx_->session) {
        // Fallback: pass-through if model not loaded
        std::fill(mask_out, mask_out + FREQ_BINS, 1.0f);
        return;
    }

    if (onnx_->use_io_binding) {
        // Zero-allocation, zero-memcpy stateful inference via pre-bound ping-pong tensors
        std::memcpy(onnx_->input_frame.data(), mag_in, FREQ_BINS * sizeof(float));
        onnx_->session->Run(Ort::RunOptions{nullptr}, *onnx_->io_binding[onnx_->ping_pong_index]);
        std::memcpy(mask_out, onnx_->mask_output.data(), FREQ_BINS * sizeof(float));
        onnx_->ping_pong_index ^= 1;
        return;
    }

    const size_t num_inputs = onnx_->session->GetInputCount();

    // Input shapes
    const std::vector<int64_t> input_shape = {1, 1, 1, FREQ_BINS};
    const std::vector<int64_t> h_shape = {NUM_GRU_LAYERS, 1, GRU_HIDDEN_SIZE};

    // Create tensors referencing existing memory (zero-copy)
    Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
        onnx_->memory_info,
        const_cast<float*>(mag_in),
        FREQ_BINS,
        input_shape.data(),
        input_shape.size()
    );

    Ort::Value h_tensor = Ort::Value::CreateTensor<float>(
        onnx_->memory_info,
        gru_hidden_state_.data(),
        gru_hidden_state_.size(),
        h_shape.data(),
        h_shape.size()
    );

    if (num_inputs >= 3) {
        // Stateful Causal Convolution model (preserves full 16-frame receptive field)
        const std::vector<int64_t> conv_shape = {1, static_cast<int64_t>(conv_state_.size())};
        Ort::Value conv_tensor = Ort::Value::CreateTensor<float>(
            onnx_->memory_info,
            conv_state_.data(),
            conv_state_.size(),
            conv_shape.data(),
            conv_shape.size()
        );

        const char* input_names[] = {"frame_input", "h_in", "conv_state_in"};
        const char* output_names[] = {"mask_output", "h_out", "conv_state_out"};
        Ort::Value input_tensors[] = {std::move(input_tensor), std::move(h_tensor), std::move(conv_tensor)};

        auto output_tensors = onnx_->session->Run(
            Ort::RunOptions{nullptr},
            input_names,
            input_tensors,
            3,
            output_names,
            3
        );

        // Extract mask output
        const float* out_mask_ptr = output_tensors[0].GetTensorData<float>();
        std::memcpy(mask_out, out_mask_ptr, FREQ_BINS * sizeof(float));

        // Update internal recurrent state h_out
        const float* h_out_ptr = output_tensors[1].GetTensorData<float>();
        std::memcpy(gru_hidden_state_.data(), h_out_ptr, gru_hidden_state_.size() * sizeof(float));

        // Update internal convolution state conv_state_out
        const float* conv_out_ptr = output_tensors[2].GetTensorData<float>();
        std::memcpy(conv_state_.data(), conv_out_ptr, conv_state_.size() * sizeof(float));
    } else {
        // Legacy 2-input model fallback
        const char* input_names[] = {"frame_input", "h_in"};
        const char* output_names[] = {"mask_output", "h_out"};
        Ort::Value input_tensors[] = {std::move(input_tensor), std::move(h_tensor)};

        auto output_tensors = onnx_->session->Run(
            Ort::RunOptions{nullptr},
            input_names,
            input_tensors,
            2,
            output_names,
            2
        );

        const float* out_mask_ptr = output_tensors[0].GetTensorData<float>();
        std::memcpy(mask_out, out_mask_ptr, FREQ_BINS * sizeof(float));

        const float* h_out_ptr = output_tensors[1].GetTensorData<float>();
        std::memcpy(gru_hidden_state_.data(), h_out_ptr, gru_hidden_state_.size() * sizeof(float));
    }
}

int NoiseSuppressionEngine::process_frame_float(const float* in_frame, float* out_frame) {
    const auto& win = fft_->window();

    // 0. Zero-allocation adaptive noise floor tracking & VAD gate
    float gate = 1.0f;
    if (config_.enable_noise_gate) {
        float sum_sq = 0.0f;
        for (int i = 0; i < HOP_LENGTH; ++i) {
            sum_sq += in_frame[i] * in_frame[i];
        }
        float frame_rms = std::sqrt(sum_sq / static_cast<float>(HOP_LENGTH));

        // 1. Startup calibration: seed noise floor to actual ambient room level
        if (startup_frames_ < 30) {
            ++startup_frames_;
            if (frame_rms < 0.01f) {
                noise_floor_ = (startup_frames_ == 1) ? frame_rms : (0.90f * noise_floor_ + 0.10f * frame_rms);
            }
        }

        // 2. Unconditional downward tracking (valleys are always noise)
        if (frame_rms < noise_floor_) {
            noise_floor_ = 0.95f * noise_floor_ + 0.05f * frame_rms;
        }

        // 3. SNR tracking with instant attack and hangover
        float snr_ratio = frame_rms / std::max(1e-6f, noise_floor_);

        if (frame_rms > speech_peak_) {
            speech_peak_ = 0.20f * speech_peak_ + 0.80f * frame_rms;
        } else if (vad_state_ > 0.5f) {
            speech_peak_ = 0.999f * speech_peak_ + 0.001f * frame_rms;
        } else if (speech_peak_ > 0.015f) {
            speech_peak_ = 0.9995f * speech_peak_ + 0.0005f * 0.015f;
        }

        const float peak_ratio = frame_rms / std::max(1e-5f, speech_peak_);
        const bool speech_detected = (snr_ratio > 1.8f) && (frame_rms > 0.001f) &&
                                     (peak_ratio >= 0.18f || frame_rms >= 0.008f);

        if (speech_detected) {
            hangover_frames_ = 25; // 250ms hangover
            vad_state_ = 1.0f;      // Instant attack: don't clip consonants
        } else {
            if (hangover_frames_ > 0) {
                --hangover_frames_;
                vad_state_ = 1.0f;  // Hold open during hangover
            } else {
                vad_state_ = 0.85f * vad_state_; // Smooth release
            }

            // 5. Adapt upward ONLY during confirmed silence/pauses
            if (hangover_frames_ == 0 && vad_state_ < 0.1f) {
                noise_floor_ = 0.995f * noise_floor_ + 0.005f * frame_rms;
            }
        }

        // 6. Soft floor: clamp between -18 dB (0.125f) and 0 dB (1.0f)
        gate = 0.125f + 0.875f * vad_state_;
    }

    // 1. Shift input buffer and append new hop_length samples
    std::memmove(input_buffer_.data(), input_buffer_.data() + HOP_LENGTH, (WIN_LENGTH - HOP_LENGTH) * sizeof(float));
    std::memcpy(input_buffer_.data() + (WIN_LENGTH - HOP_LENGTH), in_frame, HOP_LENGTH * sizeof(float));

    // 2. Apply analysis window
    for (int i = 0; i < WIN_LENGTH; ++i) {
        windowed_frame_[i] = input_buffer_[i] * win[i];
    }
    std::fill(windowed_frame_.begin() + WIN_LENGTH, windowed_frame_.end(), 0.0f);

    // 3. Real FFT -> Mag & Phase
    fft_->forward(windowed_frame_.data(), mag_spec_.data(), phase_spec_.data());

    // Safety clamp: floor small magnitude bins to 1e-5 to prevent unconstrained
    // compression explosion in power-law compression (mag^0.3)
    for (int k = 0; k < FREQ_BINS; ++k) {
        if (mag_spec_[k] < 1e-5f) {
            mag_spec_[k] = 1e-5f;
        }
    }

    // Normalize only the model input for quiet microphones. Reconstruct from
    // the original spectrum, so transmitted PCM is not amplified directly.
    const float* model_input = mag_spec_.data();
    if (model_target_rms_ > 0.0f) {
        float sum_sq = 0.0f;
        float peak = 0.0f;
        for (int i = 0; i < HOP_LENGTH; ++i) {
            sum_sq += in_frame[i] * in_frame[i];
            peak = std::max(peak, std::abs(in_frame[i]));
        }
        const float frame_rms = std::sqrt(sum_sq / static_cast<float>(HOP_LENGTH));
        model_level_rms_ = std::max(frame_rms, model_level_rms_ * 0.995f);
        const float level_gain = std::clamp(
            model_target_rms_ / std::max(model_level_rms_, 1e-5f), 1.0f, 16.0f);
        const float gain = std::min(level_gain, std::max(1.0f, 0.8f / std::max(peak, 1e-5f)));
        for (int k = 0; k < FREQ_BINS; ++k) {
            model_mag_spec_[k] = mag_spec_[k] * gain;
        }
        model_input = model_mag_spec_.data();
    }

    // 4. Neural Network Inference -> Mask
    float mask[FREQ_BINS];
    run_onnx_inference(model_input, mask);

    // If model is not loaded, pass-through directly (ideal STFT/iSTFT verification mode)
    if (!onnx_->session) {
        fft_->inverse(mag_spec_.data(), phase_spec_.data(), synth_frame_.data());
        for (int i = 0; i < WIN_LENGTH; ++i) {
            output_buffer_[i] += synth_frame_[i] * win[i];
        }
        for (int i = 0; i < HOP_LENGTH; ++i) {
            out_frame[i] = output_buffer_[i] * wola_norm_factors_[i];
        }
        std::memmove(output_buffer_.data(), output_buffer_.data() + HOP_LENGTH, (output_buffer_.size() - HOP_LENGTH) * sizeof(float));
        std::fill(output_buffer_.end() - HOP_LENGTH, output_buffer_.end(), 0.0f);
        return 0;
    }

    // 5. Apply Gain Mask with psychoacoustic gamma shaping, sub-80Hz rumble cut, and VAD gating
    float min_gain = 0.0f;
    if (config_.attenuation_limit_db > 0.0f) {
        min_gain = std::pow(10.0f, -config_.attenuation_limit_db / 20.0f);
    }
    const float gamma = (config_.suppression_intensity > 0.0f) ? config_.suppression_intensity : 1.0f;

    for (int k = 0; k < FREQ_BINS; ++k) {
        if (!std::isfinite(mask[k])) return -2;
        // Clamp sigmoid rounding before mask shaping, matching the web engine.
        float m = std::clamp(mask[k], 0.0f, 1.0f);

        // 5a. Attenuate sub-80Hz mechanical rumble (< 93.75 Hz: bins 0, 1, 2)
        // 74.2% of fan noise energy is concentrated in bins 0-2; vocal fundamental F0 > 85Hz.
        if (k < 3) {
            m *= 0.001f;
        }

        // 5b. Psychoacoustic gamma power shaping
        if (gamma != 1.0f) {
            m = std::pow(m, gamma);
        }

        // 5c. Smooth VAD noise gate
        m *= gate;

        // 5d. Optional floor clamping
        if (min_gain > 0.0f && m < min_gain) {
            m = min_gain;
        }

        clean_mag_spec_[k] = mag_spec_[k] * m;
    }

    // 6. Inverse FFT
    fft_->inverse(clean_mag_spec_.data(), phase_spec_.data(), synth_frame_.data());

    // 7. Synthesis windowing and overlap-add
    for (int i = 0; i < WIN_LENGTH; ++i) {
        output_buffer_[i] += synth_frame_[i] * win[i];
    }

    // 8. Copy output chunk with WOLA synthesis normalization (eliminates 17.2% cyclic ripple)
    for (int i = 0; i < HOP_LENGTH; ++i) {
        out_frame[i] = output_buffer_[i] * wola_norm_factors_[i];
    }

    // 9. Shift output buffer
    std::memmove(output_buffer_.data(), output_buffer_.data() + HOP_LENGTH, (output_buffer_.size() - HOP_LENGTH) * sizeof(float));
    std::fill(output_buffer_.end() - HOP_LENGTH, output_buffer_.end(), 0.0f);

    return 0;
}

int NoiseSuppressionEngine::process_frame_int16(const int16_t* in_frame, int16_t* out_frame) {
    // Convert int16 to normalized float
    constexpr float scale_in = 1.0f / 32768.0f;
    for (int i = 0; i < HOP_LENGTH; ++i) {
        float_scratch_in_[i] = in_frame[i] * scale_in;
    }

    const int result = process_frame_float(float_scratch_in_.data(), float_scratch_out_.data());
    if (result != 0) return result;

    // Convert float back to int16 with clipping
    constexpr float scale_out = 32767.0f;
    for (int i = 0; i < HOP_LENGTH; ++i) {
        float val = float_scratch_out_[i] * scale_out;
        if (!std::isfinite(val)) val = 0.0f;
        val = std::max(-32768.0f, std::min(32767.0f, val));
        out_frame[i] = static_cast<int16_t>(val);
    }

    return 0;
}

} // namespace mezon
