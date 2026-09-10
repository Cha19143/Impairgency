package ph.impairgency.impairgency

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.ContactsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The one piece of native code in the app: the system contact picker.
 *
 * ACTION_PICK on the phone-number table hands back a single row the user
 * chose, with a temporary grant to read it. No READ_CONTACTS permission is
 * needed for that on stock Android; a vendor picker that returns a row the
 * app then cannot read is reported to Dart as `needs_permission`, and Dart
 * asks for it once and retries. See lib/data/contact_picker.dart for why a
 * package was not used instead.
 */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> pick(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A contact is already being chosen.", null)
            return
        }
        val intent = Intent(
            Intent.ACTION_PICK,
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
        )
        // No resolveActivity() check: on API 30+ that answers null for any
        // app not named in <queries>, and a phone with a contacts app would
        // be told it has none. Starting the intent and catching the failure
        // is the honest test.
        pending = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, PICK_CONTACT)
        } catch (e: ActivityNotFoundException) {
            pending = null
            result.error(
                "unavailable",
                "There is no contacts app on this phone to choose from.",
                null,
            )
        } catch (e: Exception) {
            pending = null
            result.error("unavailable", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_CONTACT) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pending ?: return
        pending = null
        val uri: Uri? = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            val projection = arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
            )
            contentResolver.query(uri, projection, null, null, null).use { cursor ->
                if (cursor == null || !cursor.moveToFirst()) {
                    result.success(null)
                    return
                }
                val name = cursor.getString(0) ?: ""
                val number = cursor.getString(1) ?: ""
                result.success(mapOf("name" to name, "number" to number))
            }
        } catch (e: SecurityException) {
            result.error("needs_permission", e.message, null)
        } catch (e: Exception) {
            result.error("unavailable", e.message, null)
        }
    }

    private companion object {
        const val CHANNEL = "ph.impairgency/contacts"
        const val PICK_CONTACT = 0x1C0
    }
}
