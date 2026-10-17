package cc.blit.groglog.model

import cc.blit.groglog.core.CategoryKind
import cc.blit.groglog.core.VesselKind
import cc.blit.groglog.core.categoryDefaultAbv
import cc.blit.groglog.core.categoryDefaultVessel
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

object Units {
    /** UK units: 10 ml of pure alcohol. */
    fun of(ml: Double, abv: Double) = ml * abv / 1000

    /** Whether a typed strength is one a drink can have: above zero and at most pure alcohol. */
    fun isStrength(abv: Double) = abv > 0 && abv <= 100

    /** Ethanol at 0.789 g/ml and 7 kcal/g, plus the category's non-alcohol calories. */
    fun kcal(ml: Double, abv: Double, category: DrinkCategory) = ml * abv / 100 * 0.789 * 7 + ml * category.kcalPerMl

    /** UK Chief Medical Officers' low-risk weekly guideline. */
    const val WEEKLY_GUIDELINE = 14.0

    const val UNIT_ML = 10.0

    /** A standard drink elsewhere: 14 g of alcohol, which at 0.789 g/ml is 17.7 ml, nearly two UK units. */
    const val STANDARD_DRINK_ML = 14 / 0.789
}

/** Packs 0–1 colour components as an opaque ARGB colour, so the model carries colours without depending on Compose. */
private fun rgb(red: Double, green: Double, blue: Double): Int =
    (0xFF shl 24) or (Math.round(red * 255).toInt() shl 16) or (Math.round(green * 255).toInt() shl 8) or Math.round(blue * 255).toInt()

@Serializable
enum class DrinkCategory(val raw: String) {
    @SerialName("beer") BEER("beer"),
    @SerialName("stout") STOUT("stout"),
    @SerialName("cider") CIDER("cider"),
    @SerialName("redWine") RED_WINE("redWine"),
    @SerialName("whiteWine") WHITE_WINE("whiteWine"),
    @SerialName("rose") ROSE("rose"),
    @SerialName("bubbles") BUBBLES("bubbles"),
    @SerialName("spirit") SPIRIT("spirit"),
    @SerialName("alcopop") ALCOPOP("alcopop"),
    @SerialName("cocktail") COCKTAIL("cocktail"),
    @SerialName("fortified") FORTIFIED("fortified"),

    /** A bare unit count, for when the drinks themselves were not recorded, such as imports. */
    @SerialName("units") UNITS("units");

    val label: String
        get() = when (this) {
            BEER -> "Beer"
            STOUT -> "Stout"
            CIDER -> "Cider"
            RED_WINE -> "Red wine"
            WHITE_WINE -> "White wine"
            ROSE -> "Rosé"
            BUBBLES -> "Bubbles"
            SPIRIT -> "Spirits"
            ALCOPOP -> "Alcopop"
            COCKTAIL -> "Cocktail"
            FORTIFIED -> "Port & sherry"
            UNITS -> "Units"
        }

    /** The drink's colour in a glass, as ARGB. */
    val liquid: Int
        get() = when (this) {
            BEER -> rgb(0.96, 0.68, 0.20)
            STOUT -> rgb(0.16, 0.09, 0.06)
            CIDER -> rgb(0.90, 0.76, 0.28)
            RED_WINE -> rgb(0.56, 0.08, 0.20)
            WHITE_WINE -> rgb(0.95, 0.87, 0.52)
            ROSE -> rgb(0.97, 0.58, 0.62)
            BUBBLES -> rgb(0.98, 0.85, 0.48)
            SPIRIT -> rgb(0.80, 0.50, 0.20)
            ALCOPOP -> rgb(0.30, 0.70, 0.92)
            COCKTAIL -> rgb(0.93, 0.35, 0.55)
            FORTIFIED -> rgb(0.42, 0.10, 0.16)
            UNITS -> rgb(0.97, 0.64, 0.20)
        }

    /** Non-alcohol calories per ml, tuned so common serves land near Drinkaware's reference figures. */
    val kcalPerMl: Double
        get() = when (this) {
            BEER -> 0.10
            STOUT -> 0.12
            CIDER -> 0.13
            RED_WINE, WHITE_WINE -> 0.15
            ROSE -> 0.18
            BUBBLES -> 0.05
            SPIRIT, UNITS -> 0.0
            ALCOPOP, COCKTAIL -> 0.40
            FORTIFIED -> 0.50
        }

    val isFizzy: Boolean get() = this in setOf(BEER, CIDER, BUBBLES, ALCOPOP)
    val hasHead: Boolean get() = this in setOf(BEER, STOUT, CIDER)

    /** The core's, which a restore also uses for a pour that gives no vessel. */
    val defaultVessel: Vessel get() = Vessel.of(categoryDefaultVessel(kind))

    /** Drinkaware's standard strengths, used for the generic drinks and for a restored pour that gives no strength. */
    val defaultABV: Double get() = categoryDefaultAbv(kind)

    /** The same kind as the shared core names it. */
    val kind: CategoryKind
        get() = when (this) {
            BEER -> CategoryKind.BEER
            STOUT -> CategoryKind.STOUT
            CIDER -> CategoryKind.CIDER
            RED_WINE -> CategoryKind.RED_WINE
            WHITE_WINE -> CategoryKind.WHITE_WINE
            ROSE -> CategoryKind.ROSE
            BUBBLES -> CategoryKind.BUBBLES
            SPIRIT -> CategoryKind.SPIRIT
            ALCOPOP -> CategoryKind.ALCOPOP
            COCKTAIL -> CategoryKind.COCKTAIL
            FORTIFIED -> CategoryKind.FORTIFIED
            UNITS -> CategoryKind.UNITS
        }

    /** The sizes this kind of drink usually comes in. */
    val serves: List<ServeSize>
        get() {
            val sizes: List<Pair<Vessel, Double>> = when (this) {
                BEER -> listOf(Vessel.PINT to 568.0, Vessel.HALF to 284.0, Vessel.CAN to 330.0, Vessel.CAN to 440.0, Vessel.CAN to 500.0, Vessel.CAN to 568.0, Vessel.BOTTLE to 330.0, Vessel.BOTTLE to 500.0, Vessel.BOTTLE to 660.0)
                STOUT -> listOf(Vessel.PINT to 568.0, Vessel.HALF to 284.0, Vessel.CAN to 440.0, Vessel.CAN to 500.0)
                CIDER -> listOf(Vessel.PINT to 568.0, Vessel.HALF to 284.0, Vessel.CAN to 440.0, Vessel.CAN to 500.0, Vessel.BOTTLE to 500.0, Vessel.BOTTLE to 568.0)
                RED_WINE, WHITE_WINE, ROSE -> listOf(Vessel.WINE_GLASS to 125.0, Vessel.WINE_GLASS to 175.0, Vessel.WINE_GLASS to 250.0, Vessel.WINE_BOTTLE to 750.0)
                BUBBLES -> listOf(Vessel.FLUTE to 125.0, Vessel.WINE_BOTTLE to 750.0)
                SPIRIT -> listOf(Vessel.SHOT to 25.0, Vessel.SHOT to 35.0, Vessel.WINE_BOTTLE to 700.0)
                ALCOPOP -> listOf(Vessel.BOTTLE to 275.0, Vessel.CAN to 250.0, Vessel.CAN to 330.0)
                COCKTAIL -> listOf(Vessel.COUPE to 150.0, Vessel.TUMBLER to 250.0)
                FORTIFIED -> listOf(Vessel.WINE_GLASS to 50.0, Vessel.WINE_GLASS to 70.0)
                UNITS -> listOf(Vessel.SHOT to 10.0)
            }
            return sizes.map { ServeSize(it.first, it.second) }
        }

    /** "Pint · 4.6%" or "440 ml can · 5%", or "any amount" for bare unit counts. */
    fun serving(vessel: Vessel, ml: Double, abv: Double): String =
        if (this == UNITS) "any amount" else "${vessel.label(ml)} · ${abv.abvText}"

    companion object {
        fun fromRaw(raw: String) = entries.firstOrNull { it.raw == raw }

        fun of(kind: CategoryKind) = when (kind) {
            CategoryKind.BEER -> BEER
            CategoryKind.STOUT -> STOUT
            CategoryKind.CIDER -> CIDER
            CategoryKind.RED_WINE -> RED_WINE
            CategoryKind.WHITE_WINE -> WHITE_WINE
            CategoryKind.ROSE -> ROSE
            CategoryKind.BUBBLES -> BUBBLES
            CategoryKind.SPIRIT -> SPIRIT
            CategoryKind.ALCOPOP -> ALCOPOP
            CategoryKind.COCKTAIL -> COCKTAIL
            CategoryKind.FORTIFIED -> FORTIFIED
            CategoryKind.UNITS -> UNITS
        }
    }
}

/** A vessel at a volume: a size a drink comes in. */
data class ServeSize(val vessel: Vessel, val ml: Double) {
    val label: String get() = vessel.label(ml)
}

@Serializable
enum class Vessel(val raw: String) {
    @SerialName("pint") PINT("pint"),
    @SerialName("half") HALF("half"),
    @SerialName("can") CAN("can"),
    @SerialName("bottle") BOTTLE("bottle"),
    @SerialName("wineBottle") WINE_BOTTLE("wineBottle"),
    @SerialName("wineGlass") WINE_GLASS("wineGlass"),
    @SerialName("flute") FLUTE("flute"),
    @SerialName("shot") SHOT("shot"),
    @SerialName("tumbler") TUMBLER("tumbler"),
    @SerialName("coupe") COUPE("coupe");

    /** How a serve reads on a tile: "Pint", "440 ml can", "175 ml glass", "Single". */
    fun label(ml: Double): String {
        val size = "${ml.toInt()} ml"
        return when (this) {
            PINT -> "Pint"
            HALF -> "Half"
            CAN -> "$size can"
            BOTTLE -> "$size bottle"
            WINE_BOTTLE -> if (ml >= 700) "Bottle" else "$size bottle"
            WINE_GLASS -> "$size glass"
            FLUTE -> "Glass"
            SHOT -> if (ml <= 35) "$size single" else "$size shot"
            TUMBLER -> if (ml == 50.0) "Double" else size
            COUPE -> size
        }
    }

    /** For tight spaces where an icon shows the vessel, so the label gives only the size. */
    fun shortLabel(ml: Double): String = when {
        this == PINT -> "Pint"
        this == HALF -> "Half"
        this == FLUTE -> "Glass"
        this == WINE_BOTTLE && ml >= 700 -> "Bottle"
        this == SHOT && ml <= 35 -> "Single"
        this == TUMBLER && ml == 50.0 -> "Double"
        else -> "${ml.toInt()} ml"
    }

    val volumes: List<Double>
        get() = when (this) {
            PINT -> listOf(568.0)
            HALF -> listOf(284.0)
            CAN -> listOf(330.0, 440.0, 500.0, 568.0)
            BOTTLE -> listOf(275.0, 330.0, 500.0, 660.0)
            WINE_BOTTLE -> listOf(750.0, 375.0)
            WINE_GLASS -> listOf(125.0, 175.0, 250.0)
            FLUTE -> listOf(125.0)
            SHOT -> listOf(25.0, 35.0, 50.0)
            TUMBLER -> listOf(25.0, 50.0, 200.0)
            COUPE -> listOf(100.0, 150.0, 200.0)
        }

    /** The same vessel as the shared core names it. */
    val kind: VesselKind
        get() = when (this) {
            PINT -> VesselKind.PINT
            HALF -> VesselKind.HALF
            CAN -> VesselKind.CAN
            BOTTLE -> VesselKind.BOTTLE
            WINE_BOTTLE -> VesselKind.WINE_BOTTLE
            WINE_GLASS -> VesselKind.WINE_GLASS
            FLUTE -> VesselKind.FLUTE
            SHOT -> VesselKind.SHOT
            TUMBLER -> VesselKind.TUMBLER
            COUPE -> VesselKind.COUPE
        }

    companion object {
        fun fromRaw(raw: String) = entries.firstOrNull { it.raw == raw }

        fun of(kind: VesselKind) = when (kind) {
            VesselKind.PINT -> PINT
            VesselKind.HALF -> HALF
            VesselKind.CAN -> CAN
            VesselKind.BOTTLE -> BOTTLE
            VesselKind.WINE_BOTTLE -> WINE_BOTTLE
            VesselKind.WINE_GLASS -> WINE_GLASS
            VesselKind.FLUTE -> FLUTE
            VesselKind.SHOT -> SHOT
            VesselKind.TUMBLER -> TUMBLER
            VesselKind.COUPE -> COUPE
        }
    }
}
