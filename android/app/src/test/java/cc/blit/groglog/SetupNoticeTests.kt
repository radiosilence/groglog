package cc.blit.groglog

import android.net.Uri
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.core.app.ApplicationProvider
import cc.blit.groglog.ui.setup.SetupContent
import cc.blit.groglog.ui.setup.SetupViewModel
import cc.blit.groglog.ui.theme.GrogLogTheme
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.emptyFlow
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class SetupNoticeTests {
    @get:Rule val compose = createComposeRule()

    @Test fun savingABackupSaysSo() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val model = SetupViewModel(database(), prefs(), CoroutineScope(SupervisorJob() + Dispatchers.Default), File(context.cacheDir, "exports"))
        compose.setContent {
            GrogLogTheme { SetupContent(model, isDemo = false, onDemo = {}, onGoal = {}, onDrinks = {}, reselected = emptyFlow()) }
        }
        val file = File(context.cacheDir, "backup.json")
        compose.runOnIdle { model.saveBackup(Uri.fromFile(file), context.contentResolver) }
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Backup saved.").fetchSemanticsNodes().isNotEmpty() }
        assertTrue(file.length() > 0)
    }
}
