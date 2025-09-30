package com.example.bassem_flutter

import android.content.Context
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import ai.onnxruntime.*
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.nio.IntBuffer
import android.util.Log
import kotlin.math.*

/** WhisperOnnxPlugin */
class WhisperOnnxPlugin: FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var ortEnvironment: OrtEnvironment? = null
    private var encoderSession: OrtSession? = null
    private var decoderSession: OrtSession? = null
    private var tokenizer: WhisperTokenizer? = null
    private var isInitialized = false

    companion object {
        private const val TAG = "WhisperOnnxPlugin"
        private const val CHANNEL_NAME = "whisper_onnx"
        // IMPORTANT: no leading slash, or Android will ignore filesDir
        private const val MODEL_DIR = "models"

        // Model configuration - Whisper Tiny
        private const val SAMPLE_RATE = 16000
        private const val N_MELS = 80
        private const val N_FFT = 400
        private const val HOP_LENGTH = 160
        private const val CHUNK_LENGTH = 30 // seconds
        private const val MAX_NEW_TOKENS = 128
        private const val N_AUDIO_CTX = 3000 // Whisper context length
        private const val N_TEXT_CTX = 448 // Text context length

        // Special tokens for Arabic Whisper
        private const val START_OF_TRANSCRIPT = 50258
        private const val ARABIC_TOKEN = 50272
        private const val TRANSCRIBE_TOKEN = 50359
        private const val END_OF_TEXT = 50257
        private const val NO_TIMESTAMPS = 50363
    }

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext

        // Initialize ONNX Runtime environment
        ortEnvironment = OrtEnvironment.getEnvironment()
        Log.d(TAG, "WhisperOnnxPlugin attached to engine")
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "initializeModel" -> {
                GlobalScope.launch(Dispatchers.IO) {
                    try {
                        initializeModel()
                        withContext(Dispatchers.Main) {
                            result.success("Model initialized successfully")
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("INIT_ERROR", "Failed to initialize model: ${e.message}", null)
                        }
                    }
                }
            }
            
            "transcribeAudio" -> {
                val audioData = call.argument<FloatArray>("audioData")
                if (audioData == null) {
                    result.error("INVALID_ARGUMENT", "Audio data is required", null)
                    return
                }

                GlobalScope.launch(Dispatchers.IO) {
                    try {
                        val transcription = transcribeAudio(audioData)
                        withContext(Dispatchers.Main) {
                            result.success(transcription)
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("TRANSCRIPTION_ERROR", "Failed to transcribe: ${e.message}", null)
                        }
                    }
                }
            }

            // NEW: Handle mel spectrogram directly from Rust
            "transcribeMel" -> {
                val melData = call.argument<FloatArray>("mel")
                val nFrames = call.argument<Int>("nFrames")
                
                if (melData == null || nFrames == null) {
                    result.error("INVALID_ARGUMENT", "Mel data and nFrames are required", null)
                    return
                }

                GlobalScope.launch(Dispatchers.IO) {
                    try {
                        val transcription = transcribeFromMelSpectrogram(melData, nFrames)
                        withContext(Dispatchers.Main) {
                            result.success(transcription)
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("TRANSCRIPTION_ERROR", "Failed to transcribe from mel: ${e.message}", null)
                        }
                    }
                }
            }

            "isModelInitialized" -> {
                result.success(isInitialized)
            }
            "getModelInfo" -> {
                val info = mapOf(
                    "sampleRate" to SAMPLE_RATE,
                    "maxChunkLength" to CHUNK_LENGTH,
                    "modelType" to "whisper-tiny-ar-quran",
                    "language" to "ar"
                )
                result.success(info)
            }
            "getAndroidVersion" -> {
                result.success(android.os.Build.VERSION.SDK_INT)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private suspend fun initializeModel() {
        if (isInitialized) return

        Log.d(TAG, "Starting model initialization...")

        // Create model directory
        val modelDir = File(context.filesDir, MODEL_DIR)
        if (!modelDir.exists()) {
            modelDir.mkdirs()
        }

        // Copy model files from assets
        copyModelFiles(modelDir)

        // Initialize tokenizer first
        tokenizer = WhisperTokenizer(context)
        val tokenizerSuccess = tokenizer?.initialize() ?: false

        if (!tokenizerSuccess) {
            throw Exception("Failed to initialize tokenizer - required for real transcription")
        }

        Log.d(TAG, "Tokenizer initialized successfully")

        // Create session options with better configuration
        val sessionOptions = OrtSession.SessionOptions().apply {
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            setIntraOpNumThreads(4) // Increase threads for better performance
            setInterOpNumThreads(2)

            // Enable CPU optimizations
            addConfigEntry("session.disable_prepacking", "0")
            addConfigEntry("session.use_env_allocators", "1")
            addConfigEntry("session.memory.enable_memory_arena_shrinkage", "cpu:0")

            // Additional optimizations
            addConfigEntry("session.use_ort_model_bytes_directly", "1")
            addConfigEntry("session.use_ort_model_bytes_for_initializers", "1")
        }

        try {
            // Load encoder (required for real transcription)
            val encoderPath = File(modelDir, "encoder_model.onnx")
            if (!encoderPath.exists()) {
                throw Exception("encoder_model.onnx not found - required for real transcription")
            }

            encoderSession = ortEnvironment?.createSession(encoderPath.absolutePath, sessionOptions)
            Log.d(TAG, "Encoder session created successfully")

            // Load decoder (required for real transcription)
            val decoderPath = File(modelDir, "decoder_model.onnx")
            if (!decoderPath.exists()) {
                throw Exception("decoder_model.onnx not found - required for real transcription")
            }

            decoderSession = ortEnvironment?.createSession(decoderPath.absolutePath, sessionOptions)
            Log.d(TAG, "Decoder session created successfully")

            // Verify model inputs/outputs
            verifyModelStructure()

            isInitialized = true
            Log.d(TAG, "Model initialization completed successfully - ready for real transcription")

        } catch (e: OrtException) {
            throw Exception("ONNX Runtime error during initialization: ${e.message}")
        }
    }

    private fun verifyModelStructure() {
        val encoder = encoderSession ?: throw Exception("Encoder session not initialized")
        val decoder = decoderSession ?: throw Exception("Decoder session not initialized")

        // Check encoder inputs/outputs
        val encoderInputInfo = encoder.inputInfo
        val encoderOutputInfo = encoder.outputInfo

        Log.d(TAG, "Encoder inputs: ${encoderInputInfo.keys}")
        Log.d(TAG, "Encoder outputs: ${encoderOutputInfo.keys}")

        // Check decoder inputs/outputs
        val decoderInputInfo = decoder.inputInfo
        val decoderOutputInfo = decoder.outputInfo

        Log.d(TAG, "Decoder inputs: ${decoderInputInfo.keys}")
        Log.d(TAG, "Decoder outputs: ${decoderOutputInfo.keys}")
    }

    private fun copyModelFiles(modelDir: File) {
        val requiredFiles = listOf(
            "encoder_model.onnx",
            "decoder_model.onnx",
            "tokenizer.json"
        )

        val optionalFiles = listOf(
            "config.json",
            "generation_config.json",
            "vocab.json",
            "merges.txt",
            "normalizer.json",
            "preprocessor_config.json",
            "added_tokens.json",
            "special_tokens_map.json",
            "tokenizer_config.json",
            "ort_config.json"
        )

        // Check required files first
        for (fileName in requiredFiles) {
            val file = File(modelDir, fileName)
            if (!file.exists()) {
                try {
                    context.assets.open("models/whisper_onnx/$fileName").use { inputStream ->
                        FileOutputStream(file).use { outputStream ->
                            inputStream.copyTo(outputStream)
                        }
                    }
                    Log.d(TAG, "Copied required file $fileName")
                } catch (e: IOException) {
                    throw Exception("Required model file $fileName not found in assets: ${e.message}")
                }
            }
        }

        // Copy optional files
        for (fileName in optionalFiles) {
            val file = File(modelDir, fileName)
            if (!file.exists()) {
                try {
                    context.assets.open("models/whisper_onnx/$fileName").use { inputStream ->
                        FileOutputStream(file).use { outputStream ->
                            inputStream.copyTo(outputStream)
                        }
                    }
                    Log.d(TAG, "Copied optional file $fileName")
                } catch (e: IOException) {
                    Log.w(TAG, "Optional file $fileName not found: ${e.message}")
                }
            }
        }
    }

    // NEW: Method to handle mel spectrogram directly from Rust
    private suspend fun transcribeFromMelSpectrogram(melData: FloatArray, nFrames: Int): String {
        if (!isInitialized) {
            throw Exception("Model not initialized")
        }

        if (encoderSession == null || decoderSession == null) {
            throw Exception("Encoder or decoder session not available")
        }

        Log.d(TAG, "Starting transcription from mel spectrogram with $nFrames frames")

        // Validate mel spectrogram dimensions
        val expectedSize = N_MELS * N_AUDIO_CTX
        if (melData.size != expectedSize) {
            Log.w(TAG, "Mel data size ${melData.size} doesn't match expected $expectedSize, adjusting...")
            
            // Pad or trim to expected size
            val adjustedMelData = when {
                melData.size > expectedSize -> melData.sliceArray(0 until expectedSize)
                melData.size < expectedSize -> melData + FloatArray(expectedSize - melData.size) { 0f }
                else -> melData
            }
            
            // Run encoder with adjusted data
            val encoderOutput = runEncoder(adjustedMelData, nFrames)
            
            try {
                // Run decoder
                val transcription = runDecoderWithRealLogic(encoderOutput)
                Log.d(TAG, "Mel transcription completed: $transcription")
                return transcription
            } finally {
                encoderOutput.close()
            }
        } else {
            // Run encoder with original data
            val encoderOutput = runEncoder(melData, nFrames)
            
            try {
                // Run decoder
                val transcription = runDecoderWithRealLogic(encoderOutput)
                Log.d(TAG, "Mel transcription completed: $transcription")
                return transcription
            } finally {
                encoderOutput.close()
            }
        }
    }

    private suspend fun transcribeAudio(audioData: FloatArray): String {
        if (!isInitialized) {
            throw Exception("Model not initialized")
        }

        if (encoderSession == null || decoderSession == null) {
            throw Exception("Encoder or decoder session not available")
        }

        Log.d(TAG, "Starting real transcription for audio of length ${audioData.size}")

        // Pad or trim audio to exactly 30 seconds
        val expectedLength = SAMPLE_RATE * CHUNK_LENGTH
        val processedAudio = when {
            audioData.size > expectedLength -> {
                Log.d(TAG, "Trimming audio from ${audioData.size} to $expectedLength samples")
                audioData.sliceArray(0 until expectedLength)
            }
            audioData.size < expectedLength -> {
                Log.d(TAG, "Padding audio from ${audioData.size} to $expectedLength samples")
                audioData + FloatArray(expectedLength - audioData.size) { 0f }
            }
            else -> audioData
        }

        // Preprocess audio to mel spectrogram
        val features = preprocessAudio(processedAudio)

        // Run encoder
        val encoderOutput = runEncoder(features.data, features.nFrames)

        try {
            // Run decoder with proper beam search or greedy decoding
            val transcription = runDecoderWithRealLogic(encoderOutput)

            Log.d(TAG, "Real transcription completed: $transcription")
            return transcription

        } finally {
            encoderOutput.close()
        }
    }

    private data class Features(val data: FloatArray, val nFrames: Int)

    private fun preprocessAudio(audioData: FloatArray): Features {
        // 1) compute mel spectrogram as [N_MELS x T] for the actual audio
        val mel = computeMelSpectrogram(audioData) // Array<N_MELS>[T]

        val T = mel[0].size
        val usedFrames = min(T, N_AUDIO_CTX) // real frames

        // 2) log10 and fixed normalization
        val MEAN = -4.2677393f
        val STD  =  4.5689974f

        // 3) flatten to [N_MELS * N_AUDIO_CTX], padding the time axis with zeros
        val flat = FloatArray(N_MELS * N_AUDIO_CTX)
        var k = 0
        for (m in 0 until N_MELS) {
            for (t in 0 until N_AUDIO_CTX) {
                val v = if (t < T) {
                    val clamped = max(mel[m][t], 1e-10f)
                    (log10(clamped) - MEAN) / STD
                } else {
                    0f
                }
                flat[k++] = v
            }
        }
        return Features(flat, usedFrames)
    }

    private fun computeMelSpectrogram(audio: FloatArray): Array<FloatArray> {
        // Simplified mel spectrogram computation
        val hopCount = (audio.size + HOP_LENGTH - 1) / HOP_LENGTH
        val timeSteps = minOf(hopCount, N_AUDIO_CTX)

        val melSpectrogram = Array(N_MELS) { FloatArray(timeSteps) }

        // Simple STFT approximation (replace with proper implementation)
        for (t in 0 until timeSteps) {
            val startSample = t * HOP_LENGTH
            val endSample = minOf(startSample + N_FFT, audio.size)

            // Extract window
            val window = FloatArray(N_FFT) { 0f }
            for (i in 0 until (endSample - startSample)) {
                if (startSample + i < audio.size) {
                    // Apply Hanning window
                    val hannWindow = 0.5f * (1f - cos(2f * Math.PI.toFloat() * i / (N_FFT - 1)))
                    window[i] = audio[startSample + i] * hannWindow
                }
            }

            // Compute magnitude spectrum (simplified)
            for (mel in 0 until N_MELS) {
                var magnitude = 0f
                val freqStart = mel * N_FFT / (2 * N_MELS)
                val freqEnd = (mel + 1) * N_FFT / (2 * N_MELS)

                for (freq in freqStart until freqEnd) {
                    if (freq < window.size / 2) {
                        magnitude += window[freq] * window[freq]
                    }
                }

                melSpectrogram[mel][t] = sqrt(magnitude / (freqEnd - freqStart))
            }
        }

        return melSpectrogram
    }

    private suspend fun runEncoder(inputFeatures: FloatArray, nFrames: Int): OnnxTensor {
        val encoder = encoderSession ?: error("Encoder session not available")
        val env = ortEnvironment ?: error("ORT not initialized")

        val shape = longArrayOf(1L, N_MELS.toLong(), N_AUDIO_CTX.toLong())
        val inputTensor = OnnxTensor.createTensor(env, FloatBuffer.wrap(inputFeatures), shape)

        // 1 for real frames, 0 for padded
        val mask = FloatArray(N_AUDIO_CTX) { i -> if (i < nFrames) 1f else 0f }
        val maskTensor = OnnxTensor.createTensor(env, FloatBuffer.wrap(mask), longArrayOf(1L, N_AUDIO_CTX.toLong()))

        val inputs = mutableMapOf<String, OnnxTensor>("input_features" to inputTensor)

        // Add the mask only if the model has such an input
        val encInputs = encoder.inputInfo.keys
        val maskName = when {
            encInputs.contains("attention_mask") -> "attention_mask"
            encInputs.contains("encoder_attention_mask") -> "encoder_attention_mask"
            encInputs.contains("audio_attention_mask") -> "audio_attention_mask"
            else -> null
        }
        if (maskName != null) inputs[maskName] = maskTensor

        val outputs = encoder.run(inputs)

        // clone output to return a standalone tensor
        val hs = outputs[0] as OnnxTensor
        val outShape = hs.info.shape
        val buf = hs.floatBuffer.duplicate().apply { rewind() }
        val data = FloatArray(buf.remaining())
        buf.get(data)

        // Close once (avoid "Closing an already closed tensor")
        outputs.close()
        inputTensor.close()
        if (maskName != null) maskTensor.close()

        return OnnxTensor.createTensor(env, FloatBuffer.wrap(data), outShape)
    }

    private suspend fun runDecoderWithRealLogic(encoderHiddenStates: OnnxTensor): String {
        val decoder = decoderSession ?: throw Exception("Decoder session not available")
        val environment = ortEnvironment ?: throw Exception("ONNX Runtime environment not initialized")
        val tokenizer = tokenizer ?: throw Exception("Tokenizer not available")

        Log.d(TAG, "Starting decoder with real logic")

        // Initialize sequence with proper start tokens
        val startTokens = intArrayOf(
            START_OF_TRANSCRIPT,
            ARABIC_TOKEN,
            TRANSCRIBE_TOKEN,
            NO_TIMESTAMPS
        )

        var inputIds = startTokens.toMutableList()
        val generatedTokens = mutableListOf<Int>()

        // Greedy decoding without KV-cache
        for (step in 0 until MAX_NEW_TOKENS) {
            Log.v(TAG, "Decoder step $step, current sequence length: ${inputIds.size}")

            // Prepare input tensors
            val inputShape = longArrayOf(1, inputIds.size.toLong())
            val idsLong: LongArray = inputIds.map { it.toLong() }.toLongArray()
            val inputTensor = OnnxTensor.createTensor(
                environment,
                LongBuffer.wrap(idsLong),
                inputShape
            )
            
            try {
                // IMPORTANT: pass only the inputs the decoder expects (usually 1 or 2).
                // Many Whisper decoder ONNX exports expect just: input_ids, encoder_hidden_states
                val decoderInputs = mutableMapOf<String, OnnxTensor>(
                    "input_ids" to inputTensor,
                    "encoder_hidden_states" to encoderHiddenStates
                )

                Log.v(TAG, "Running decoder inference for step $step")
                val outputs = decoder.run(decoderInputs)

                try {
                    val logitsTensor = outputs[0] as OnnxTensor
                    val tensorShape = logitsTensor.info.shape
                    val buf = logitsTensor.floatBuffer.duplicate()
                    buf.rewind()
                    val total = buf.remaining()
                    val tensorData = FloatArray(total)
                    buf.get(tensorData)

                    // Expected shape: [batch_size, sequence_length, vocab_size]
                    val batchSize = tensorShape[0].toInt()
                    val seqLength = tensorShape[1].toInt()
                    val vocabSize = tensorShape[2].toInt()

                    // Extract logits for the last token in the sequence
                    val lastTokenIndex = (0 * seqLength * vocabSize) + ((seqLength - 1) * vocabSize)
                    val logits = FloatArray(vocabSize) { i ->
                        val idx = lastTokenIndex + i
                        if (idx < tensorData.size) tensorData[idx] else Float.NEGATIVE_INFINITY
                    }

                    // Greedy
                    val nextTokenId = sampleNextToken(logits, temperature = 0.0f)

                    Log.v(TAG, "Generated token: $nextTokenId")

                    // Check for end conditions
                    if (nextTokenId == END_OF_TEXT ||
                        nextTokenId < 0 ||
                        nextTokenId >= tokenizer.getVocabSize()
                    ) {
                        Log.d(TAG, "End of generation detected at step $step")
                        break
                    }

                    // Add token to sequence
                    inputIds.add(nextTokenId)
                    generatedTokens.add(nextTokenId)

                    // Optional: Early stopping for repeated tokens
                    if (generatedTokens.size > 10 &&
                        generatedTokens.takeLast(5).all { it == nextTokenId }
                    ) {
                        Log.d(TAG, "Stopping due to repeated tokens")
                        break
                    }

                } finally {
                    outputs.close()
                }

            } finally {
                inputTensor.close()
            }
        }

        Log.d(TAG, "Generated ${generatedTokens.size} tokens")

        // Decode the generated tokens (excluding start tokens)
        val textTokens = generatedTokens.toIntArray()
        val decodedText = tokenizer.decode(textTokens, skipSpecialTokens = true)

        return decodedText.trim()
    }

    private fun sampleNextToken(logits: FloatArray, temperature: Float = 0.0f): Int {
        if (temperature == 0.0f) {
            // Greedy decoding - return argmax
            return logits.indices.maxByOrNull { logits[it] } ?: END_OF_TEXT
        } else {
            // Temperature sampling
            val scaledLogits = logits.map { it / temperature }.toFloatArray()
            val maxLogit = scaledLogits.maxOrNull() ?: 0f

            // Apply softmax with numerical stability
            val expLogits = scaledLogits.map { exp(it - maxLogit) }
            val sumExp = expLogits.sum()
            val probabilities = expLogits.map { it / sumExp }

            // Sample from the probability distribution
            val randomValue = kotlin.random.Random.nextFloat()
            var cumulativeProb = 0f

            for (i in probabilities.indices) {
                cumulativeProb += probabilities[i]
                if (randomValue <= cumulativeProb) {
                    return i
                }
            }

            return logits.indices.maxByOrNull { logits[it] } ?: END_OF_TEXT
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)

        // Clean up resources
        encoderSession?.close()
        decoderSession?.close()
        ortEnvironment?.close()

        isInitialized = false
        Log.d(TAG, "WhisperOnnxPlugin detached from engine")
    }
}