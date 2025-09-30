package com.example.bassem_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register the custom Whisper plugin
        flutterEngine
            .plugins
            .add(WhisperOnnxPlugin())
    }
}