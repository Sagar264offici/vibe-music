# Flutter keep rules (R8 strips things Flutter needs by default otherwise)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# just_audio_background / audio_service: service + reflection on media classes
-keep class com.ryanheise.audioservice.** { *; }
-keep class androidx.media.** { *; }

# JNI bridges used by just_audio
-keepclasseswithmembernames class * {
    native <methods>;
}
