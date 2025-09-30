package com.example.bassem_flutter

import kotlin.math.*

/**
 * Audio processing utilities for Whisper model preprocessing
 */
class AudioProcessor {
    companion object {
        private const val N_FFT = 400
        private const val HOP_LENGTH = 160
        private const val N_MELS = 80
        private const val SAMPLE_RATE = 16000
        private const val FMIN = 0.0
        private const val FMAX = 8000.0
        
        /**
         * Compute mel spectrogram from audio signal
         */
        fun computeMelSpectrogram(audio: FloatArray, nMels: Int = N_MELS): Array<FloatArray> {
            // Pad or trim audio to exactly 30 seconds (480,000 samples)
            val targetLength = SAMPLE_RATE * 30
            val paddedAudio = when {
                audio.size > targetLength -> audio.sliceArray(0 until targetLength)
                audio.size < targetLength -> audio + FloatArray(targetLength - audio.size)
                else -> audio
            }
            
            // Use Whisper-compatible mel spectrogram computation
            return computeWhisperMelSpectrogram(paddedAudio, nMels)
        }
        
        private fun computeWhisperMelSpectrogram(audio: FloatArray, nMels: Int): Array<FloatArray> {
            // Whisper uses specific parameters: n_fft=400, hop_length=160, n_mels=80
            val nFrames = 3000  // Force exactly 3000 frames to match Python
            val nFreqs = N_FFT / 2 + 1  // 201 frequency bins
            
            // Create mel spectrogram with proper Whisper preprocessing
            val melSpec = Array(nMels) { FloatArray(nFrames) }
            
            // Hanning window
            val window = FloatArray(N_FFT) { i ->
                0.5f * (1.0f - cos(2.0 * PI * i / (N_FFT - 1)).toFloat())
            }
            
            // Create proper mel filter bank (Whisper-compatible)
            val melFilters = createWhisperMelFilters(nMels, nFreqs)
            
            for (frameIdx in 0 until nFrames) {
                val startSample = frameIdx * HOP_LENGTH
                
                // Extract and window the frame
                val frame = FloatArray(N_FFT)
                for (i in 0 until N_FFT) {
                    if (startSample + i < audio.size) {
                        frame[i] = audio[startSample + i] * window[i]
                    }
                }
                
                // Compute magnitude spectrum (simplified but more accurate)
                val magnitudes = FloatArray(nFreqs)
                for (k in 0 until nFreqs) {
                    var real = 0.0
                    var imag = 0.0
                    
                    for (n in 0 until N_FFT) {
                        val angle = -2.0 * PI * k * n / N_FFT
                        real += frame[n] * cos(angle)
                        imag += frame[n] * sin(angle)
                    }
                    
                    magnitudes[k] = (real * real + imag * imag).toFloat()
                }
                
                // Apply mel filters and convert to log scale
                for (mel in 0 until nMels) {
                    var energy = 0.0f
                    for (freq in 0 until nFreqs) {
                        energy += magnitudes[freq] * melFilters[mel][freq]
                    }
                    // Convert to log scale (Whisper standard)
                    melSpec[mel][frameIdx] = ln(maxOf(energy, 1e-10f))
                }
            }
            
            // Apply Whisper normalization (mean=0, std=1 per mel bin)
            for (mel in 0 until nMels) {
                val values = melSpec[mel]
                val mean = values.average().toFloat()
                val variance = values.map { (it - mean) * (it - mean) }.average().toFloat()
                val std = sqrt(variance + 1e-8f)
                
                for (frame in values.indices) {
                    values[frame] = (values[frame] - mean) / std
                }
            }
            
            return melSpec
        }
        

        
        private fun createWhisperMelFilters(nMels: Int, nFreqs: Int): Array<FloatArray> {
            // Use Whisper's exact mel filter bank parameters
            return createMelFilterBank(nMels, nFreqs, SAMPLE_RATE, FMIN, FMAX)
        }
        
        private fun createMelFilterBank(nMels: Int, nFreqs: Int, sampleRate: Int, fMin: Double, fMax: Double): Array<FloatArray> {
            val melFilters = Array(nMels) { FloatArray(nFreqs) }
            
            // Convert to mel scale
            val melMin = hzToMel(fMin)
            val melMax = hzToMel(fMax)
            
            // Create mel points
            val melPoints = DoubleArray(nMels + 2) { i ->
                melMin + (melMax - melMin) * i / (nMels + 1)
            }
            
            // Convert back to Hz
            val hzPoints = melPoints.map { melToHz(it) }
            
            // Convert to FFT bin indices
            val binPoints = hzPoints.map { hz ->
                ((nFreqs - 1) * 2 * hz / sampleRate).toInt()
            }
            
            // Create triangular filters
            for (m in 0 until nMels) {
                val leftBin = binPoints[m]
                val centerBin = binPoints[m + 1]
                val rightBin = binPoints[m + 2]
                
                for (f in 0 until nFreqs) {
                    when {
                        f < leftBin || f > rightBin -> melFilters[m][f] = 0.0f
                        f <= centerBin -> {
                            melFilters[m][f] = (f - leftBin).toFloat() / (centerBin - leftBin).toFloat()
                        }
                        else -> {
                            melFilters[m][f] = (rightBin - f).toFloat() / (rightBin - centerBin).toFloat()
                        }
                    }
                }
            }
            
            return melFilters
        }
        

        
        private fun hzToMel(hz: Double): Double {
            return 2595.0 * log10(1.0 + hz / 700.0)
        }
        
        private fun melToHz(mel: Double): Double {
            return 700.0 * (10.0.pow(mel / 2595.0) - 1.0)
        }
    }
    

}