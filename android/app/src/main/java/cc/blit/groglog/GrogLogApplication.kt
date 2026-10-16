package cc.blit.groglog

import android.app.Application
import cc.blit.groglog.widget.Widgets

class GrogLogApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        Widgets.follow(this, container)
    }
}
