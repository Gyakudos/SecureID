package com.local.secure_id

import android.os.Build
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Log
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TRUST_CHANNEL)
            .setMethodCallHandler { call, result -> handleTrustCall(call, result) }
    }

    /**
     * Seals the local trusted-device list with a non-authentication Keystore
     * key. Trust keys only authorise transport; they can never decrypt a vault.
     */
    private fun handleTrustCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "seal" -> {
                val data = call.argument<ByteArray>("data")
                if (data == null || data.isEmpty()) {
                    result.error("bad_args", "Nothing to protect.", null)
                    return
                }
                try {
                    result.success(sealTrust(data))
                } catch (exception: Exception) {
                    Log.e(TAG, "Could not seal trusted devices", exception)
                    result.error(
                        "failed",
                        "Could not protect the trusted-device list.",
                        null,
                    )
                }
            }
            "unseal" -> {
                val data = call.argument<ByteArray>("data")
                if (data == null || data.isEmpty()) {
                    result.error("bad_args", "The record is empty.", null)
                    return
                }
                try {
                    result.success(unsealTrust(data))
                } catch (exception: Exception) {
                    Log.e(TAG, "Could not unseal trusted devices", exception)
                    result.error(
                        "failed",
                        "The trusted-device list could not be read on this phone.",
                        null,
                    )
                }
            }
            "deleteKey" -> {
                deleteTrustKey()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun sealTrust(plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateTrustKey())
        cipher.updateAAD(TRUST_AAD)
        val iv = cipher.iv
        val ciphertext = cipher.doFinal(plaintext)
        return ByteArray(iv.size + ciphertext.size).also { output ->
            System.arraycopy(iv, 0, output, 0, iv.size)
            System.arraycopy(ciphertext, 0, output, iv.size, ciphertext.size)
        }
    }

    private fun unsealTrust(data: ByteArray): ByteArray {
        if (data.size <= IV_LENGTH) {
            throw IllegalArgumentException("The trusted-device record is incomplete.")
        }
        val key = getTrustKey()
            ?: throw IllegalStateException("The trusted-device key is missing.")
        val iv = data.copyOfRange(0, IV_LENGTH)
        val ciphertext = data.copyOfRange(IV_LENGTH, data.size)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
        cipher.updateAAD(TRUST_AAD)
        return cipher.doFinal(ciphertext)
    }

    private fun getOrCreateTrustKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        try {
            val existing = keyStore.getEntry(TRUST_KEY_ALIAS, null)
            if (existing is KeyStore.SecretKeyEntry) return existing.secretKey
        } catch (_: UnrecoverableKeyException) {
            keyStore.deleteEntry(TRUST_KEY_ALIAS)
        }

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE,
        )
        val builder = KeyGenParameterSpec.Builder(
            TRUST_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(false)
        generator.init(builder.build())
        return generator.generateKey()
    }

    private fun getTrustKey(): SecretKey? {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val entry = keyStore.getEntry(TRUST_KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
        return entry?.secretKey
    }

    private fun deleteTrustKey() {
        try {
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            if (keyStore.containsAlias(TRUST_KEY_ALIAS)) {
                keyStore.deleteEntry(TRUST_KEY_ALIAS)
            }
        } catch (_: Exception) {
            // Nothing to delete.
        }
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(availabilityStatus() == STATUS_OK)
            "availability" -> {
                val status = availabilityStatus()
                Log.i(TAG, "Biometric availability: $status")
                result.success(status)
            }
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

    /**
     * Reports the exact biometric state instead of a bare boolean, so the Dart
     * side can tell "no hardware" apart from a temporary lockout.
     */
    private fun availabilityStatus(): String {
        return try {
            when (
                BiometricManager.from(this)
                    .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            ) {
                BiometricManager.BIOMETRIC_SUCCESS -> STATUS_OK
                BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> "no_hardware"
                BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> "hw_unavailable"
                BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "none_enrolled"
                BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED ->
                    "security_update_required"
                BiometricManager.BIOMETRIC_ERROR_UNSUPPORTED -> "unsupported"
                else -> "unknown"
            }
        } catch (exception: Exception) {
            Log.w(TAG, "Biometric availability check failed", exception)
            "error"
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
            Log.e(TAG, "Could not wrap the vault key", exception)
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
            Log.e(TAG, "Could not unwrap the vault key", exception)
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
                    Log.w(TAG, "Biometric prompt succeeded without a cipher")
                    pending.error("failed", failureMessage, null)
                    return
                }
                try {
                    pending.success(complete(authenticatedCipher))
                } catch (exception: Exception) {
                    Log.e(TAG, "Biometric operation failed after authentication", exception)
                    pending.error(errorCode(exception), errorMessage(exception), null)
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                val pending = pendingResult
                pendingResult = null
                if (pending == null) return
                Log.w(TAG, "Biometric prompt error $errorCode: $errString")
                pending.error(
                    promptErrorCode(errorCode),
                    promptErrorMessage(errorCode, errString),
                    null,
                )
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

    private fun promptErrorCode(errorCode: Int): String {
        return when (errorCode) {
            BiometricPrompt.ERROR_NEGATIVE_BUTTON,
            BiometricPrompt.ERROR_USER_CANCELED,
            BiometricPrompt.ERROR_CANCELED,
            -> "cancelled"
            BiometricPrompt.ERROR_LOCKOUT -> "locked_out"
            BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "locked_out_permanent"
            BiometricPrompt.ERROR_NO_BIOMETRICS -> "none_enrolled"
            BiometricPrompt.ERROR_HW_NOT_PRESENT -> "no_hardware"
            BiometricPrompt.ERROR_HW_UNAVAILABLE -> "hw_unavailable"
            BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED -> "security_update_required"
            BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL -> "no_device_credential"
            else -> "auth_failed"
        }
    }

    private fun promptErrorMessage(errorCode: Int, fallback: CharSequence): String {
        return when (errorCode) {
            BiometricPrompt.ERROR_NO_BIOMETRICS ->
                "No fingerprint or face is enrolled on this phone. Add one in " +
                    "Android Settings first."
            BiometricPrompt.ERROR_HW_NOT_PRESENT ->
                "This phone does not have biometric hardware."
            BiometricPrompt.ERROR_HW_UNAVAILABLE ->
                "Biometric hardware is temporarily unavailable. Try again."
            BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED ->
                "Your phone needs a security update before biometrics can be used."
            BiometricPrompt.ERROR_LOCKOUT ->
                "Too many attempts. Use your master password, then try again later."
            BiometricPrompt.ERROR_LOCKOUT_PERMANENT ->
                "Biometrics are locked. Use your master password, then re-enable " +
                    "biometric unlock."
            BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL ->
                "Set a screen lock on this phone, then add a fingerprint or face."
            else -> fallback.toString().ifBlank {
                "Biometric unlock failed. Use your master password."
            }
        }
    }

    private fun errorCode(exception: Exception): String {
        return when (exception) {
            is KeyPermanentlyInvalidatedException,
            is UnrecoverableKeyException,
            is java.security.InvalidKeyException,
            -> "key_invalidated"
            is javax.crypto.AEADBadTagException,
            is IllegalArgumentException,
            -> "bad_data"
            else -> "failed"
        }
    }

    private fun errorMessage(exception: Exception): String {
        return when (exception) {
            is KeyPermanentlyInvalidatedException,
            is UnrecoverableKeyException,
            is java.security.InvalidKeyException,
            -> "Biometrics changed on this phone. Use your master password, then " +
                "enable biometric unlock again."
            is javax.crypto.AEADBadTagException ->
                "The biometric record could not be read. Use your master password, " +
                    "then enable biometric unlock again."
            else -> "Biometric unlock failed. Use your master password."
        }
    }

    companion object {
        private const val TAG = "SecureIDBiometric"
        private const val CHANNEL = "com.local.secure_id/biometric"
        private const val TRUST_CHANNEL = "com.local.secure_id/trust_store"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_LENGTH = 12
        private const val STATUS_OK = "ok"
        private const val TRUST_KEY_ALIAS = "secureid_trust_store_v1"
        private val AAD = "secureid-pin-v1".toByteArray(Charsets.UTF_8)
        private val TRUST_AAD = "secureid-trust-store-v1".toByteArray(Charsets.UTF_8)
    }
}
