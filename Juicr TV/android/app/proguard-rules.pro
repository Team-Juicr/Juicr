# Keep Flutter engine and plugin entry points reachable after R8 minification.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class app.juicr.flutter.MainActivity { *; }

# Keep platform channel method names stable for native playback helpers.
-keepclassmembers class app.juicr.flutter.MainActivity {
    *;
}

# libVLC is reached through the local flutter_vlc_player plugin and LibVLC JNI.
-keep class software.solid.fluttervlcplayer.** { *; }
-keep class org.videolan.libvlc.** { *; }
-keep class org.videolan.libvlc.interfaces.** { *; }
-keepclassmembers class org.videolan.libvlc.** {
    native <methods>;
}
-keepclassmembers class org.videolan.libvlc.interfaces.** {
    *;
}
-dontwarn software.solid.fluttervlcplayer.**
-dontwarn org.videolan.libvlc.**

# Flutter references optional Play Core deferred-component APIs even when the app
# does not use deferred components. Suppress missing optional classes for R8.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
