package cc.blit.groglog.ui

import androidx.navigation3.runtime.NavKey
import java.util.UUID
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
 * Each tab keeps its pushed pages while another is shown, so the same page can be open in two tabs at once (a drink's
 * editor from the Log and from Setup). Navigation 3 tells entries apart by their keys, so every pushed page carries a
 * `nonce` of its own; equal pages pushed twice are still two entries, each with its own state.
 */
private fun nonce() = UUID.randomUUID().toString()

/** A day opened from the calendar, as `DayKey.number`. */
@Serializable
data class CalendarDay(val day: Int, val nonce: String = nonce()) : NavKey

/**
 * Setup's pages. Other tabs push them too, as iOS presents its sheets: Day opens the goal from its budget and a drink's
 * editor from an entry.
 */
@Serializable
sealed interface SetupRoute : NavKey {
    @Serializable data class Drinks(val nonce: String = nonce()) : SetupRoute

    /** A drink's editor, by `Drink.id`; without one it creates a drink, starting from `name`. */
    @Serializable data class EditDrink(val id: String? = null, val name: String = "", val nonce: String = nonce()) : SetupRoute

    @Serializable data class Goal(val nonce: String = nonce()) : SetupRoute

    @Serializable data class Guidance(val nonce: String = nonce()) : SetupRoute
}
