package com.local.secure_id

import android.os.Build
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.view.WindowManager
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.UnrecoverableKeyException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterFragmentActivity() {
    private var pendingResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep vault contents out of the recent-apps thumbnail and screenshots.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handleCall(call, result) }
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isBiometricAvailable())
            "wrap" -> {
                val alias = call.argument<String>("alias")
                val key = call.argument<ByteArray>("key")
                if (alias == null || key == null) {
                    result.error("bad_args", "Missing key material.", null)
                } else {
                    wrapKey(alias, key, result)
                }
            }
            "unwrap" -> {
                val alias = call.argument<String>("alias")
                val data = call.argument<ByteArray>("data")
                if (alias == null || data == null) {
                    result.error("bad_args", "Missing key material.", null)
                } else {
                    unwrapKey(alias, data, result)
                }
            }
            "deleteKey" -> {
                call.argument<String>("alias")?.let { deleteKey(it) }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun isBiometricAvailable(): Boolean {
        return try {
            BiometricManager.from(this)
                .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
                BiometricManager.BIOMETRIC_SUCCESS
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Encrypts the vault key with a Keystore key that requires biometric
     * authentication. Returns IV + ciphertext + tag.
     */
    private fun wrapKey(alias: String, plaintext: ByteArray, result: MethodChannel.Result) {
        try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            try {
                cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey(alias))
            } catch (_: KeyPermanentlyInvalidatedException) {
                // A new biometric was enrolled. Start fresh with a new key.
                deleteKey(alias)
                cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey(alias))
            }
            cipher.updateAAD(AAD)

            authenticate(cipher, result, "Biometric unlock could not be enabled.") { active ->
                val iv = active.iv
                val ciphertext = active.doFinal(plaintext)
                ByteArray(iv.size + ciphertext.size).also { output ->
                    System.arraycopy(iv, 0, output, 0, iv.size)
                    System.arraycopy(ciphertext, 0, output, iv.size, ciphertext.size)
                }
            }
        } catch (exception: Exception) {
            result.error(errorCode(exception), errorMessage(exception), null)
        }
    }

    /**
     * Decrypts a record produced by [wrapKey] after a biometric prompt.
     */
    private fun unwrapKey(alias: String, data: ByteArray, result: MethodChannel.Result) {
        if (data.size <= IV_LENGTH) {
            result.error("bad_data", "The biometric record is incomplete.", null)
            return
        }
        try {
            val key = getKey(alias)
            if (key == null) {
                result.error(
                    "key_missing",
                    "The biometric key is missing. Use your master password.",
                    null,
                )
                return
            }
            val iv = data.copyOfRange(0, IV_LENGTH)
            val ciphertext = data.copyOfRange(IV_LENGTH, data.size)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
            cipher.updateAAD(AAD)

            authenticate(cipher, result, "Biometric unlock failed.") { active ->
                active.doFinal(ciphertext)
            }
        } catch (exception: Exception) {
            result.error(errorCode(exception), errorMessage(exception), null)
        }
    }

    /**
     * Shows the biometric prompt for [cipher] and completes [result] with the
     * value returned by [complete].
     */
    private fun authenticate(
        cipher: Cipher,
        result: MethodChannel.Result,
        failureMessage: String,
        complete: (Cipher) -> Any,
    ) {
        if (pendingResult != null) {
            result.error("busy", "Another biometric prompt is already open.", null)
            return
        }
        pendingResult = result

        val executor = ContextCompat.getMainExecutor(this)
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                val authenticatedCipher = authResult.cryptoObject?.cipher
                val pending = pendingResult
                pendingResult = null
                if (pending == null) return
                if (authenticatedCipher == null) {
                    pending.error("failed", failureMessage, null)
                    return
                }
                try {
                    pending.success(complete(authenticatedCipher))
                } catch (exception: Exception) {
                    pending.error(errorCode(exception), errorMessage(exception), null)
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                val pending = pendingResult
                pendingResult = null
                if (pending == null) return
                when (errorCode) {
                    BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                    BiometricPrompt.ERROR_USER_CANCELED,
                    BiometricPrompt.ERROR_CANCELED,
                    -> pending.error("cancelled", errString.toString(), null)
                    BiometricPrompt.ERROR_LOCKOUT,
                    BiometricPrompt.ERROR_LOCKOUT_PERMANENT,
                    -> pending.error("locked_out", errString.toString(), null)
                    else -> pending.error("auth_failed", errString.toString(), null)
                }
            }

            override fun onAuthenticationFailed() {
                // The prompt stays open; the user can try again.
            }
        }

        val prompt = BiometricPrompt(this, executor, callback)
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Unlock SecureID")
            .setSubtitle("Confirm your identity to unlock your vault")
            .setNegativeButtonText("Use master password")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .setConfirmationRequired(false)
            .build()

        try {
            prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
        } catch (exception: Exception) {
            pendingResult = null
            result.error(errorCode(exception), errorMessage(exception), null)
        }
    }

    private fun getOrCreateKey(alias: String): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        try {
            val existing = keyStore.getEntry(alias, null)
            if (existing is KeyStore.SecretKeyEntry) return existing.secretKey
        } catch (_: UnrecoverableKeyException) {
            // The key can no longer be used; replace it below.
            keyStore.deleteEntry(alias)
        } catch (_: KeyPermanentlyInvalidatedException) {
            keyStore.deleteEntry(alias)
        }

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE,
        )
        val builder = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                0,
                KeyProperties.AUTH_BIOMETRIC_STRONG,
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }

        generator.init(builder.build())
        return generator.generateKey()
    }

    private fun getKey(alias: String): SecretKey? {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val entry = keyStore.getEntry(alias, null) as? KeyStore.SecretKeyEntry
        return entry?.secretKey
    }

    private fun deleteKey(alias: String) {
        try {
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
        } catch (_: Exception) {
            // Nothing to delete.
        }
    }

    private fun errorCode(exception: Exception): String {
        return when (exception) {
            is KeyPermanentlyInvalidatedException,
            is UnrecoverableKeyException,
            -> "key_invalidated"
            else -> "failed"
        }
    }

    private fun errorMessage(exception: Exception): String {
        return when (exception) {
            is KeyPermanentlyInvalidatedException,
            is UnrecoverableKeyException,
            -> "Biometrics changed on this phone. Use your master password, then " +
                "enable biometric unlock again."
            else -> "Biometric unlock failed. Use your master password."
        }
    }

    companion object {
        private const val CHANNEL = "com.local.secure_id/biometric"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_LENGTH = 12
        private val AAD = "secureid-pin-v1".toByteArray(Charsets.UTF_8)
    }
}
