#ifndef MEZON_FAST_FFT_HPP
#define MEZON_FAST_FFT_HPP

#include <vector>
#include <cmath>
#include <complex>
#include <cstring>
#include <algorithm>

namespace mezon {

class FastRealFFT512 {
public:
    static constexpr int N = 512;
    static constexpr int FREQ_BINS = 257;

    FastRealFFT512() {
        // 1. Precompute bit reversal permutation
        bit_rev_.resize(N);
        for (int i = 0; i < N; ++i) {
            int rev = 0;
            int temp = i;
            for (int bit = 0; bit < 9; ++bit) { // 2^9 = 512
                rev = (rev << 1) | (temp & 1);
                temp >>= 1;
            }
            bit_rev_[i] = rev;
        }

        // 2. Precompute twiddle factors: exp(-2*pi*i*k/N)
        twiddle_re_.resize(N / 2);
        twiddle_im_.resize(N / 2);
        for (int k = 0; k < N / 2; ++k) {
            double angle = -2.0 * M_PI * k / N;
            twiddle_re_[k] = static_cast<float>(std::cos(angle));
            twiddle_im_[k] = static_cast<float>(std::sin(angle));
        }

        // 3. Precompute Hann analysis and synthesis window (length 400, periodic=True matches PyTorch)
        window_.resize(400);
        for (int i = 0; i < 400; ++i) {
            window_[i] = 0.5f * (1.0f - std::cos(2.0f * static_cast<float>(M_PI) * i / 400.0f));
        }

        // Scratch buffers (preallocated to ensure zero allocations on audio thread)
        re_.resize(N);
        im_.resize(N);
        temp_re_.resize(N);
        temp_im_.resize(N);
    }

    const std::vector<float>& window() const { return window_; }

    /**
     * Compute Real-to-Complex forward FFT.
     * in: 512 real samples
     * out_mag: 257 magnitude bins
     * out_phase: 257 phase bins
     */
    void forward(const float* in, float* out_mag, float* out_phase) {
        // Bit-reversal copy
        for (int i = 0; i < N; ++i) {
            re_[bit_rev_[i]] = in[i];
            im_[bit_rev_[i]] = 0.0f;
        }

        // Cooley-Tukey Radix-2 FFT
        for (int len = 2; len <= N; len <<= 1) {
            int half = len >> 1;
            int step = N / len;
            for (int i = 0; i < N; i += len) {
                for (int j = 0; j < half; ++j) {
                    int k = j * step;
                    float u_re = re_[i + j];
                    float u_im = im_[i + j];
                    float v_re = re_[i + j + half] * twiddle_re_[k] - im_[i + j + half] * twiddle_im_[k];
                    float v_im = re_[i + j + half] * twiddle_im_[k] + im_[i + j + half] * twiddle_re_[k];

                    re_[i + j] = u_re + v_re;
                    im_[i + j] = u_im + v_im;
                    re_[i + j + half] = u_re - v_re;
                    im_[i + j + half] = u_im - v_im;
                }
            }
        }

        // Compute magnitude and phase for bins 0..256
        for (int k = 0; k < FREQ_BINS; ++k) {
            float r = re_[k];
            float i = im_[k];
            out_mag[k] = std::sqrt(r * r + i * i);
            out_phase[k] = std::atan2(i, r);
        }
    }

    /**
     * Compute Complex-to-Real inverse FFT.
     * in_mag: 257 magnitude bins
     * in_phase: 257 phase bins
     * out: 512 real samples
     */
    void inverse(const float* in_mag, const float* in_phase, float* out) {
        // Reconstruct full Hermitian symmetric spectrum
        for (int k = 0; k < FREQ_BINS; ++k) {
            float r = in_mag[k] * std::cos(in_phase[k]);
            float i = in_mag[k] * std::sin(in_phase[k]);
            re_[k] = r;
            im_[k] = -i; // Conjugate for IFFT
        }
        for (int k = FREQ_BINS; k < N; ++k) {
            re_[k] = re_[N - k];
            im_[k] = -im_[N - k];
        }

        // Bit-reversal copy into preallocated scratch
        for (int i = 0; i < N; ++i) {
            temp_re_[bit_rev_[i]] = re_[i];
            temp_im_[bit_rev_[i]] = im_[i];
        }
        re_ = temp_re_;
        im_ = temp_im_;

        // Cooley-Tukey Radix-2
        for (int len = 2; len <= N; len <<= 1) {
            int half = len >> 1;
            int step = N / len;
            for (int i = 0; i < N; i += len) {
                for (int j = 0; j < half; ++j) {
                    int k = j * step;
                    float u_re = re_[i + j];
                    float u_im = im_[i + j];
                    float v_re = re_[i + j + half] * twiddle_re_[k] - im_[i + j + half] * twiddle_im_[k];
                    float v_im = re_[i + j + half] * twiddle_im_[k] + im_[i + j + half] * twiddle_re_[k];

                    re_[i + j] = u_re + v_re;
                    im_[i + j] = u_im + v_im;
                    re_[i + j + half] = u_re - v_re;
                    im_[i + j + half] = u_im - v_im;
                }
            }
        }

        // Scale by 1/N
        constexpr float inv_n = 1.0f / N;
        for (int i = 0; i < N; ++i) {
            out[i] = re_[i] * inv_n;
        }
    }

private:
    std::vector<int> bit_rev_;
    std::vector<float> twiddle_re_;
    std::vector<float> twiddle_im_;
    std::vector<float> window_;
    std::vector<float> re_;
    std::vector<float> im_;
    std::vector<float> temp_re_;
    std::vector<float> temp_im_;
};

} // namespace mezon

#endif // MEZON_FAST_FFT_HPP
