package com.local.secure_id

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep vault contents out of the recent-apps thumbnail and screenshots.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
