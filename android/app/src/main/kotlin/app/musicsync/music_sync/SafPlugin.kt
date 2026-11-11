package app.musicsync.music_sync

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.InputStream
import java.io.OutputStream

class SafPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var pendingPick: MethodChannel.Result? = null

    private val reads = HashMap<Int, InputStream>()
    private val writes = HashMap<Int, OutputStream>()
    private var nextHandle = 1

    companion object {
        private const val REQ_PICK_TREE = 4401
        private const val CHUNK = 1 shl 20 // 1 MiB
        private val COLS = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "music_sync/saf")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PICK_TREE) return false
        val res = pendingPick
        pendingPick = null
        if (res == null) return true
        val uri = data?.data
        if (resultCode == Activity.RESULT_OK && uri != null && context != null) {
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            runCatching {
                context!!.contentResolver.takePersistableUriPermission(uri, flags)
            }
            res.success(mapOf("uri" to uri.toString(), "name" to treeName(uri)))
        } else {
            res.success(null)
        }
        return true
    }

    private fun treeName(treeUri: Uri): String {
        val id = DocumentsContract.getTreeDocumentId(treeUri)
        return id.substringAfterLast('/').ifBlank { "USB drive" }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val cr = context?.contentResolver
        if (cr == null) {
            result.error("no-context", "plugin not attached", null)
            return
        }
        try {
            when (call.method) {
                "pickTree" -> {
                    val act = activity
                    if (act == null) {
                        result.error("no-activity", "no activity", null)
                        return
                    }
                    pendingPick = result
                    act.startActivityForResult(
                        Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), REQ_PICK_TREE)
                }
                "hasPersistedPermission" -> {
                    val uri = Uri.parse(call.argument<String>("uri")!!)
                    val has = cr.persistedUriPermissions.any {
                        it.uri.toString() == uri.toString() && it.isReadPermission
                    }
                    result.success(has)
                }
                "listDir" -> {
                    val tree = Uri.parse(call.argument<String>("tree")!!)
                    val uri = Uri.parse(call.argument<String>("uri")!!)
                    result.success(listChildren(cr, tree, uri))
                }
                "child" -> {
                    val tree = Uri.parse(call.argument<String>("tree")!!)
                    val parent = Uri.parse(call.argument<String>("parent")!!)
                    val name = call.argument<String>("name")!!
                    result.success(findChild(cr, tree, parent, name))
                }
                "mkdir" -> {
                    val parent = Uri.parse(call.argument<String>("parent")!!)
                    val name = call.argument<String>("name")!!
                    val created = DocumentsContract.createDocument(
                        cr, parent, DocumentsContract.Document.MIME_TYPE_DIR, name)
                    result.success(created?.toString())
                }
                "create" -> {
                    val tree = Uri.parse(call.argument<String>("tree")!!)
                    val parent = Uri.parse(call.argument<String>("parent")!!)
                    val name = call.argument<String>("name")!!
                    // remove an existing file with the same name so the new
                    // file lands at exactly this path (no "name (1)" suffix)
                    findChild(cr, tree, parent, name)?.let { existing ->
                        runCatching { DocumentsContract.deleteDocument(cr, Uri.parse(existing)) }
                    }
                    val ext = name.substringAfterLast('.', "").lowercase()
                    val mime = MimeTypeMap.getSingleton()
                        .getMimeTypeFromExtension(ext) ?: "application/octet-stream"
                    val created = DocumentsContract.createDocument(cr, parent, mime, name)
                    result.success(created?.toString())
                }
                "delete" -> {
                    val uri = Uri.parse(call.argument<String>("uri")!!)
                    result.success(DocumentsContract.deleteDocument(cr, uri))
                }
                "openRead" -> {
                    val uri = Uri.parse(call.argument<String>("uri")!!)
                    val stream = cr.openInputStream(uri)
                    if (stream == null) {
                        result.success(null)
                    } else {
                        val h = nextHandle++
                        reads[h] = stream
                        result.success(h)
                    }
                }
                "readChunk" -> {
                    val h = call.argument<Int>("handle")!!
                    val stream = reads[h]
                    if (stream == null) {
                        result.success(null)
                    } else {
                        val buf = ByteArray(CHUNK)
                        val n = stream.read(buf)
                        if (n < 0) {
                            runCatching { stream.close() }
                            reads.remove(h)
                            result.success(null)
                        } else {
                            result.success(buf.copyOf(n))
                        }
                    }
                }
                "closeRead" -> {
                    val h = call.argument<Int>("handle")!!
                    reads.remove(h)?.let { runCatching { it.close() } }
                    result.success(null)
                }
                "openWrite" -> {
                    val uri = Uri.parse(call.argument<String>("uri")!!)
                    val stream = cr.openOutputStream(uri, "wt")
                    if (stream == null) {
                        result.success(null)
                    } else {
                        val h = nextHandle++
                        writes[h] = stream
                        result.success(h)
                    }
                }
                "writeChunk" -> {
                    val h = call.argument<Int>("handle")!!
                    val bytes = call.argument<ByteArray>("bytes")!!
                    writes[h]?.let {
                        it.write(bytes)
                        it.flush()
                    }
                    result.success(null)
                }
                "closeWrite" -> {
                    val h = call.argument<Int>("handle")!!
                    writes.remove(h)?.let { runCatching { it.close() } }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("saf-error", "${call.method}: ${t.message}", null)
        }
    }

    private fun childrenUri(tree: Uri, docUri: Uri): Uri =
        DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, DocumentsContract.getDocumentId(docUri))

    private fun listChildren(
        cr: android.content.ContentResolver,
        tree: Uri,
        docUri: Uri,
    ): List<Map<String, Any>> {
        val out = ArrayList<Map<String, Any>>()
        cr.query(childrenUri(tree, docUri), COLS, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                val mime = c.getString(4) ?: ""
                out.add(
                    mapOf(
                        "uri" to c.getString(0), // replaced below with full uri
                        "name" to c.getString(1),
                        "size" to (c.getLong(2)),
                        "mtime" to (c.getLong(3)),
                        "dir" to (mime == DocumentsContract.Document.MIME_TYPE_DIR),
                        "docId" to c.getString(0),
                    )
                )
            }
        }
        // build full child document uris
        return out.map { m ->
            val docId = m["docId"] as String
            m - "docId" + ("uri" to DocumentsContract.buildDocumentUriUsingTree(tree, docId).toString())
        }
    }

    private fun findChild(
        cr: android.content.ContentResolver,
        tree: Uri,
        parent: Uri,
        name: String,
    ): String? {
        cr.query(childrenUri(tree, parent), COLS, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                if (c.getString(1) == name) {
                    return DocumentsContract.buildDocumentUriUsingTree(
                        tree, c.getString(0)).toString()
                }
            }
        }
        return null
    }
}
