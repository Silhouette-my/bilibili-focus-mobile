package org.bilibilifocus.core.injection

import kotlinx.cinterop.ExperimentalForeignApi
import platform.Foundation.NSBundle
import platform.Foundation.NSString
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.stringWithContentsOfFile

@OptIn(ExperimentalForeignApi::class)
actual fun readBundleResource(name: String): String {
    val parts = name.split(".")
    val fileName = parts.dropLast(1).joinToString(".")
    val ext = parts.lastOrNull() ?: ""

    val bundle = NSBundle.mainBundle
    val path = bundle.pathForResource(fileName, ofType = ext)
        ?: error("Resource not found: $name")

    return NSString.stringWithContentsOfFile(path, NSUTF8StringEncoding, null)
        ?: error("Failed to read resource: $name")
}
