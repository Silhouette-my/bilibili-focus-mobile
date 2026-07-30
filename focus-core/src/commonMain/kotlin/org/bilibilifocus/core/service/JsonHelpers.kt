package org.bilibilifocus.core.service

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive

fun JsonObject.valueAt(vararg path: String): JsonElement? {
    var current: JsonElement = this
    for (key in path) {
        current = (current as? JsonObject)?.get(key) ?: return null
    }
    return current
}

fun JsonObject.stringValueAt(vararg path: String): String? {
    val element = valueAt(*path) ?: return null
    if (element is JsonNull) return null
    return element.jsonPrimitive.content
}

fun JsonObject.intValueAt(vararg path: String): Int? {
    val element = valueAt(*path) ?: return null
    if (element is JsonNull) return null
    val content = element.jsonPrimitive.content
    return content.toIntOrNull()
}

fun JsonObject.longValueAt(vararg path: String): Long? {
    val element = valueAt(*path) ?: return null
    if (element is JsonNull) return null
    val content = element.jsonPrimitive.content
    return content.toLongOrNull()
}

fun JsonObject.arrayValueAt(vararg path: String): List<JsonElement>? {
    val element = valueAt(*path) ?: return null
    return (element as? JsonArray)?.toList()
}

fun JsonObject.dictionaryValueAt(vararg path: String): JsonObject? {
    return valueAt(*path) as? JsonObject
}
