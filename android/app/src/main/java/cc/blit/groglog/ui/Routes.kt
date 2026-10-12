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

/**
 * Setup's pages. Other tabs push them too, as iOS presents its sheets: Day opens the goal from its budget and a drink's
 * editor from an entry.
 */
@Serializable
sealed interface SetupRoute : NavKey {
    @Serializable data object Drinks : SetupRoute

    /** A drink's editor, by `Drink.id`; null creates a drink. */
    @Serializable data class EditDrink(val id: String?) : SetupRoute

    @Serializable data object Goal : SetupRoute

    @Serializable data object Guidance : SetupRoute
}
