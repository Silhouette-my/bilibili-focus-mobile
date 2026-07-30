package org.bilibilifocus.core.service

import platform.Foundation.NSDate
import platform.Foundation.NSTimeZone
import platform.Foundation.localTimeZone
import platform.Foundation.secondsFromGMT
import platform.Foundation.timeIntervalSince1970

actual fun currentTimezoneOffsetMinutes(): Int {
    return -(NSTimeZone.localTimeZone.secondsFromGMT / 60).toInt()
}

actual fun currentEpochSeconds(): Long = NSDate().timeIntervalSince1970.toLong()
