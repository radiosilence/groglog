# Room, kotlinx.serialization, Navigation 3, Glance and Health Connect ship their own consumer rules, which R8 applies
# from their AARs. What follows is only what those rules do not cover.

# Glance makes a widget's ActionCallback by reflection, from its class name, when a tile is tapped. Its own rules do not
# keep the constructor, so R8 full mode drops it and every tap fails with NoSuchMethodException.
-keep class * implements androidx.glance.appwidget.action.ActionCallback {
    <init>();
}
