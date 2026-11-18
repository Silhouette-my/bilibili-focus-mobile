#!/bin/sh

set -eu

project_root=${SRCROOT:-}
if [ -z "$project_root" ]; then
    script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
    project_root=$(CDPATH= cd -- "$script_directory/.." && pwd)
fi

if [ ! -x "$project_root/gradlew" ]; then
    echo "error: Gradle wrapper not found at $project_root/gradlew" >&2
    exit 1
fi

if [ -z "${JAVA_HOME:-}" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
    android_studio_java_home="/Applications/Android Studio.app/Contents/jbr/Contents/Home"

    if [ -x "$android_studio_java_home/bin/java" ]; then
        JAVA_HOME=$android_studio_java_home
    elif [ -x /usr/libexec/java_home ]; then
        if discovered_java_home=$(/usr/libexec/java_home -v 21 2>/dev/null) &&
            [ -x "$discovered_java_home/bin/java" ]; then
            JAVA_HOME=$discovered_java_home
        else
            echo "error: Java 21 was not found in Android Studio or by /usr/libexec/java_home." >&2
            exit 1
        fi
    else
        echo "error: Java 21 was not found in Android Studio or by /usr/libexec/java_home." >&2
        exit 1
    fi
    export JAVA_HOME
fi

java_version=$("$JAVA_HOME/bin/java" -version 2>&1 | awk -F '"' 'NR == 1 { print $2 }')
java_major=$(printf '%s\n' "$java_version" | awk -F '.' '{ if ($1 == "1") print $2; else print $1 }')

case "$java_major" in
    '' | *[!0-9]*)
        echo "error: Could not determine the Java major version from: $java_version" >&2
        exit 1
        ;;
esac

if [ "$java_major" -lt 17 ] || [ "$java_major" -gt 24 ]; then
    echo "error: Java $java_major is unsupported; use Java 17 through 24." >&2
    exit 1
fi

export OVERRIDE_KOTLIN_BUILD_IDE_SUPPORTED=YES

"$project_root/gradlew" \
    -p "$project_root" \
    :focus-core:embedAndSignAppleFrameworkForXcode
