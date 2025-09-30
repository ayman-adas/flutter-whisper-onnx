package com.example.bassem_flutter

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException

class WhisperTokenizer(private val context: Context) {
    private var idToPiece: Array<String> = emptyArray()
    private var specialIds: MutableSet<Int> = mutableSetOf()

    // byte<->unicode maps used by GPT-2/Whisper BPE
    private lateinit var byteToUnicode: Map<Int, Char>
    private lateinit var unicodeToByte: Map<Char, Int>

    companion object {
        private const val TAG = "WhisperTokenizer"
        // Common Whisper special tokens
        private const val DEFAULT_VOCAB_SIZE = 51864 // Whisper base vocab size
    }

    fun initialize(): Boolean {
        try {
            Log.d(TAG, "Initializing WhisperTokenizer...")
            
            // Build byte/unicode maps first
            byteToUnicode = buildBytesToUnicode()
            unicodeToByte = byteToUnicode.entries.associate { (b, ch) -> ch to b }
            Log.d(TAG, "Built byte/unicode mappings")

            // Try to load tokenizer.json first, then fallback options
            if (loadFromTokenizerJson()) {
                Log.d(TAG, "Successfully loaded from tokenizer.json")
                return true
            }

            Log.w(TAG, "tokenizer.json failed, trying vocab.json fallback...")
            if (loadFromVocabJson()) {
                Log.d(TAG, "Successfully loaded from vocab.json")
                return true
            }

            Log.e(TAG, "All tokenizer loading methods failed, creating minimal fallback")
            createFallbackTokenizer()
            return false

        } catch (e: Exception) {
            Log.e(TAG, "Critical error during tokenizer initialization: ${e.message}", e)
            createFallbackTokenizer()
            return false
        }
    }

    private fun loadFromTokenizerJson(): Boolean {
        return try {
            val json = context.assets.open("models/whisper_onnx/tokenizer.json")
                .bufferedReader().use { it.readText() }

            val tok = JSONObject(json)

            // 1) Read vocab (piece->id mapping)
            val model = tok.getJSONObject("model")
            val vocabObj = model.getJSONObject("vocab")
            
            // Find the maximum ID to determine vocab size
            val keys = vocabObj.keys()
            var maxId = 0
            val pieceToId = mutableMapOf<String, Int>()
            
            while (keys.hasNext()) {
                val piece = keys.next()
                val id = vocabObj.getInt(piece)
                pieceToId[piece] = id
                maxId = maxOf(maxId, id)
            }

            // Create id->piece array with proper size
            val vocabSize = maxId + 1
            val idToPieceTmp = Array(vocabSize) { "" }
            
            pieceToId.forEach { (piece, id) ->
                if (id >= 0 && id < vocabSize) {
                    idToPieceTmp[id] = piece
                }
            }
            
            idToPiece = idToPieceTmp
            Log.d(TAG, "Loaded vocab with ${pieceToId.size} tokens, max_id=$maxId")

            // 2) Read special tokens
            specialIds.clear()
            if (tok.has("added_tokens")) {
                val arr = tok.getJSONArray("added_tokens")
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    if (obj.optBoolean("special", false)) {
                        val id = obj.getInt("id")
                        specialIds.add(id)
                        Log.v(TAG, "Added special token: ${obj.optString("content", "?")} -> $id")
                    }
                }
            }

            Log.d(TAG, "Loaded ${specialIds.size} special tokens")
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load tokenizer.json: ${e.message}")
            false
        }
    }

    private fun loadFromVocabJson(): Boolean {
        return try {
            val json = context.assets.open("models/whisper_onnx/vocab.json")
                .bufferedReader().use { it.readText() }

            val vocabObj = JSONObject(json)
            val keys = vocabObj.keys()
            var maxId = 0
            val pieceToId = mutableMapOf<String, Int>()

            while (keys.hasNext()) {
                val piece = keys.next()
                val id = vocabObj.getInt(piece)
                pieceToId[piece] = id
                maxId = maxOf(maxId, id)
            }

            val vocabSize = maxId + 1
            val idToPieceTmp = Array(vocabSize) { "" }
            
            pieceToId.forEach { (piece, id) ->
                if (id >= 0 && id < vocabSize) {
                    idToPieceTmp[id] = piece
                }
            }
            
            idToPiece = idToPieceTmp
            
            // For vocab.json, we don't have explicit special token info,
            // so we'll use common Whisper special token IDs
            specialIds.clear()
            addCommonWhisperSpecialTokens()
            
            Log.d(TAG, "Loaded vocab.json with ${pieceToId.size} tokens")
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load vocab.json: ${e.message}")
            false
        }
    }

    private fun addCommonWhisperSpecialTokens() {
        // Common Whisper special token IDs
        val commonSpecialIds = listOf(
            50257, // <|endoftext|>
            50258, // <|startoftranscript|>
            50259, // <|en|> 
            50272, // <|ar|> (Arabic)
            50359, // <|transcribe|>
            50363  // <|notimestamps|>
        )
        
        commonSpecialIds.forEach { id ->
            if (id < idToPiece.size) {
                specialIds.add(id)
            }
        }
    }

    private fun createFallbackTokenizer() {
        Log.w(TAG, "Creating minimal fallback tokenizer")
        
        // Create a minimal tokenizer with basic ASCII tokens
        val vocabSize = 512
        idToPiece = Array(vocabSize) { i -> 
            when {
                i < 256 -> i.toChar().toString()
                else -> "<unk_$i>"
            }
        }
        
        specialIds.clear()
        // Add some basic special tokens
        specialIds.addAll(listOf(256, 257, 258, 259, 260))
    }

    fun getVocabSize(): Int = idToPiece.size

    /**
     * Decode token IDs to UTF-8 text with improved error handling
     */
    fun decode(ids: IntArray, skipSpecialTokens: Boolean = true): String {
        if (ids.isEmpty()) {
            Log.d(TAG, "Empty token array provided")
            return ""
        }

        try {
            // 1) Join token strings (excluding special tokens if requested)
            val sb = StringBuilder()
            var validTokens = 0
            var skippedTokens = 0
            
            for (id in ids) {
                when {
                    id < 0 -> {
                        Log.v(TAG, "Skipping negative token ID: $id")
                        skippedTokens++
                        continue
                    }
                    id >= idToPiece.size -> {
                        Log.v(TAG, "Skipping out-of-bounds token ID: $id (vocab_size=${idToPiece.size})")
                        skippedTokens++
                        continue
                    }
                    skipSpecialTokens && specialIds.contains(id) -> {
                        Log.v(TAG, "Skipping special token ID: $id")
                        skippedTokens++
                        continue
                    }
                    else -> {
                        val piece = idToPiece[id]
                        if (piece.isNotEmpty()) {
                            sb.append(piece)
                            validTokens++
                        }
                    }
                }
            }

            Log.d(TAG, "Decoded $validTokens valid tokens, skipped $skippedTokens tokens")

            if (sb.isEmpty()) {
                Log.w(TAG, "No valid tokens to decode")
                return ""
            }

            // 2) Convert token string back to bytes using unicode mapping
            val tokenString = sb.toString()
            return convertTokenStringToText(tokenString)

        } catch (e: Exception) {
            Log.e(TAG, "Error during decoding: ${e.message}", e)
            return "[DECODE_ERROR]"
        }
    }

    private fun convertTokenStringToText(tokenString: String): String {
        try {
            // Convert each character back to its original byte value
            val bytes = mutableListOf<Byte>()
            
            for (char in tokenString) {
                val byteValue = unicodeToByte[char]
                if (byteValue != null) {
                    bytes.add(byteValue.toByte())
                } else {
                    // Handle unmapped characters - could be actual Unicode content
                    Log.v(TAG, "Unmapped character in token string: '$char' (${char.code})")
                    // Try to encode the character directly as UTF-8
                    val charBytes = char.toString().toByteArray(Charsets.UTF_8)
                    charBytes.forEach { bytes.add(it) }
                }
            }

            // Convert byte list to array and decode as UTF-8
            val byteArray = bytes.toByteArray()
            val result = String(byteArray, Charsets.UTF_8)
            
            Log.d(TAG, "Converted ${tokenString.length} token chars to ${byteArray.size} bytes -> '${result.take(50)}${if (result.length > 50) "..." else ""}'")
            return result
            
        } catch (e: Exception) {
            Log.e(TAG, "Error converting token string to text: ${e.message}", e)
            // Fallback: return the token string as-is
            return tokenString
        }
    }

    /**
     * GPT-2/Whisper bytes->unicode mapping used in BPE to keep everything printable.
     * Matches OpenAI's reference implementation exactly.
     */
    private fun buildBytesToUnicode(): Map<Int, Char> {
        val bs = mutableListOf<Int>()
        val cs = mutableListOf<Int>()

        // Printable ASCII range: ! to ~
        for (i in 33..126) {
            bs.add(i)
            cs.add(i)
        }
        
        // Latin-1 supplement ranges
        for (i in 161..172) {
            bs.add(i)
            cs.add(i)
        }
        for (i in 174..255) {
            bs.add(i)
            cs.add(i)
        }

        // Map remaining bytes to unused Unicode points
        var n = 0
        for (b in 0..255) {
            if (!bs.contains(b)) {
                bs.add(b)
                cs.add(256 + n)
                n++
            }
        }

        // Create final mapping
        val result = mutableMapOf<Int, Char>()
        for (i in bs.indices) {
            result[bs[i]] = cs[i].toChar()
        }
        
        Log.d(TAG, "Built bytes->unicode mapping with ${result.size} entries")
        return result
    }

    /**
     * Get debug info about the tokenizer state
     */
    fun getDebugInfo(): Map<String, Any> {
        return mapOf(
            "vocab_size" to idToPiece.size,
            "special_tokens_count" to specialIds.size,
            "byte_mapping_size" to if (::byteToUnicode.isInitialized) byteToUnicode.size else 0,
            "sample_tokens" to idToPiece.take(10).mapIndexed { i, piece -> "$i->$piece" }
        )
    }}