package cc.blit.groglog.ui

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

/** The five tabs as Navigation 3 keys. Pages pushed within a tab get keys of their own beside these. */
@Serializable
sealed interface Tab : NavKey {
    @Serializable data object Log : Tab
    @Serializable data object Calendar : Tab
    @Serializable data object Day : Tab
    @Serializable data object Reports : Tab
    @Serializable data object Setup : Tab
}
