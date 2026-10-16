package cc.blit.groglog.ui

import android.app.Application
import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import androidx.health.connect.client.HealthConnectClient
import androidx.test.core.app.ApplicationProvider
import cc.blit.groglog.ui.setup.openHealthConnect
import cc.blit.groglog.ui.shared.startSafely
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

/** Opening another app never closes this one: an intent nothing answers is reported, not thrown. */
@RunWith(RobolectricTestRunner::class)
class OpeningTests {
    private val app = ApplicationProvider.getApplicationContext<Application>()

    @Test fun anIntentNothingAnswersIsRefusedQuietly() {
        shadowOf(app).checkActivities(true)
        assertFalse(app.startSafely(Intent("cc.blit.groglog.test.NOTHING").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)))
    }

    @Test fun manageOpensHealthConnectsScreenForThisApp() {
        shadowOf(app).checkActivities(true)
        val manage = HealthConnectClient.getHealthConnectManageDataIntent(app)
        // Health Connect, installed: it answers its manage-data action.
        val provider = ComponentName("com.google.android.apps.healthdata", "Manage")
        shadowOf(app.packageManager).addActivityIfNotPresent(provider)
        shadowOf(app.packageManager).addIntentFilterForActivity(provider, IntentFilter(manage.action).apply { addCategory(Intent.CATEGORY_DEFAULT) })
        assertTrue(app.openHealthConnect())
        assertEquals(manage.action, shadowOf(app).nextStartedActivity.action)
    }

    @Test fun withoutHealthConnectManageReportsItCouldNotOpen() {
        shadowOf(app).checkActivities(true)
        assertFalse(app.openHealthConnect())
    }
}
