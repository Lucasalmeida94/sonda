package com.palascoding.sonda

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sonda/uwb")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                            packageManager.hasSystemFeature(PackageManager.FEATURE_UWB)
                    )
                    else -> result.notImplemented()
                }
            }
    }
}
