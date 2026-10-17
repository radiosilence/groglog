# Room, kotlinx.serialization, Navigation 3, Glance and Health Connect ship their own consumer rules, which R8 applies
# from their AARs. What follows is only what those rules do not cover.

# Glance makes a widget's ActionCallback by reflection, from its class name, when a tile is tapped. Its own rules do not
# keep the constructor, so R8 full mode drops it and every tap fails with NoSuchMethodException.
-keep class * implements androidx.glance.appwidget.action.ActionCallback {
    <init>();
}

# JNA reaches the generated bindings' structures and callbacks by reflection.
-keep class com.sun.jna.** { *; }
-keep class * extends com.sun.jna.** { *; }
-keep class cc.blit.groglog.core.** { *; }
-dontwarn java.awt.**
