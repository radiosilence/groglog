package cc.blit.groglog

import cc.blit.groglog.core.VesselKind
import cc.blit.groglog.core.catalogBrands
import cc.blit.groglog.core.catalogGenericPrice
import cc.blit.groglog.core.ratesPerPound
import cc.blit.groglog.model.Catalog
import cc.blit.groglog.model.CatalogBrand
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.Vessel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** A drink at £0.00 looks free rather than broken, and silently flattens the spend charts. */
class PriceTests {
    private fun genericPrice(name: String, vessel: Vessel, ml: Double) = catalogGenericPrice(name, vessel.kind, ml)

    @Test fun genericsKnowWhatTheirOwnServesCost() {
        assertTrue((genericPrice("Beer", Vessel.PINT, 568.0) ?: 0.0) > 0)
        assertTrue((genericPrice("Beer", Vessel.CAN, 440.0) ?: 0.0) > 0)
        assertTrue((genericPrice("Red wine", Vessel.WINE_GLASS, 175.0) ?: 0.0) > 0)
    }

    @Test fun nothingIsPricedAtZeroRatherThanUnknown() {
        assertNull(genericPrice("Beer", Vessel.WINE_GLASS, 175.0))
        assertNull(genericPrice("Not a drink", Vessel.PINT, 568.0))
        assertNull(Catalog.price("Not a drink", DrinkCategory.BEER, Vessel.PINT, 568.0))
    }

    /** The lookup the reset button goes through. */
    @Test fun aKnownBrandIsPricedAheadOfAnyGeneric() {
        val stella = Catalog.price("Stella Artois", DrinkCategory.BEER, Vessel.PINT, 568.0, "GBP")!!
        assertTrue(stella > 0)
        assertNotEquals(genericPrice("Beer", Vessel.PINT, 568.0), stella)
    }

    @Test fun aBrandPricesASizeItIsntSoldInByVolume() {
        val stella = Catalog.brands.first { it.name == "Stella Artois" }
        assertTrue(Catalog.price(stella, Vessel.PINT, 568.0) > 0)
        // 330 ml is on its list; 568 ml in a can is not, so it's scaled off the first serve.
        assertTrue(Catalog.price(stella, Vessel.BOTTLE, 330.0) > 0)
        assertTrue(Catalog.price(stella, Vessel.CAN, 568.0) > 0)
    }
}

/**
 * Distinguishes a catalogue brand copied in unchanged from one the user has edited. The Drinks screen sorts on it, so a
 * night of logging brands does not bury the drinks the user wrote.
 */
class AdoptedDrinkTests {
    private fun stella(): CatalogBrand = Catalog.brands.first { it.name == "Stella Artois" }
    private fun asahi(): CatalogBrand = Catalog.brands.first { it.name == "Asahi Super Dry" }

    @Test fun aBrandCopiedInAndLeftAloneIsStillTheCatalogues() {
        val brand = stella()
        assertTrue(Catalog.holds(brand.name, brand.category, brand.abv))
    }

    @Test fun changingTheStrengthMakesItYours() {
        val brand = stella()
        assertFalse(Catalog.holds(brand.name, brand.category, brand.abv + 0.1))
    }

    @Test fun renamingItMakesItYours() {
        val brand = stella()
        assertFalse(Catalog.holds("${brand.name} (the good one)", brand.category, brand.abv))
    }

    @Test fun aDrinkYouInventedWasNeverTheCatalogues() {
        assertFalse(Catalog.holds("Dave's shed cider", DrinkCategory.CIDER, 7.0))
    }

    /**
     * A pint doesn't divide into a bottle. Asahi is £7.40 on draught and £1.63 for the 330, and scaling the pint by
     * volume would log the bottle at £4.30.
     */
    @Test fun anotherSizeComesFromTheCatalogueRatherThanTheArithmetic() {
        val asahi = asahi()
        val pint = Drink(name = asahi.name, category = asahi.category, abv = asahi.abv, vessel = Vessel.PINT, volumeMl = 568.0, price = Catalog.price(asahi, Vessel.PINT, 568.0))
        assertTrue(near(pint.price(Vessel.BOTTLE, 330.0), Catalog.price(asahi, Vessel.BOTTLE, 330.0), 0.001))
        assertTrue(pint.price(Vessel.BOTTLE, 330.0) < pint.price * 330 / 568)
        // Its own size keeps its own price.
        assertEquals(pint.price, pint.price(Vessel.PINT, 568.0), 0.0)
    }

    /**
     * A price the user sets applies to the size it was set on. Another size is another product, looked up in the
     * catalogue rather than scaled from this one.
     */
    @Test fun yourOwnPriceHoldsForYourOwnSizeAndNoOther() {
        val asahi = asahi()
        val mine = Drink(name = asahi.name, category = asahi.category, abv = asahi.abv, vessel = Vessel.PINT, volumeMl = 568.0, price = 5.0)
        assertEquals(5.0, mine.price(Vessel.PINT, 568.0), 0.0)
        assertTrue(near(mine.price(Vessel.BOTTLE, 330.0), Catalog.price(asahi, Vessel.BOTTLE, 330.0), 0.001))
    }

    /** A drink priced only in pounds is converted for someone paying in another currency, and never for someone paying in pounds. */
    @Test fun aPriceIsConvertedIntoYourCurrency() {
        val asahi = asahi()
        val pounds = Catalog.price(asahi, Vessel.PINT, 568.0, "GBP")
        val euros = Catalog.price(asahi, Vessel.PINT, 568.0, "EUR")
        val listed = catalogBrands().first { it.name == asahi.name }.markets.first { it.currency == "GBP" }.serves.first { it.vessel == VesselKind.PINT }
        assertEquals(listed.price, pounds, 0.0)
        assertTrue(near(euros, pounds * ratesPerPound().first { it.currency == "EUR" }.perPound, 0.001))
        assertEquals(0.0, Catalog.price(asahi, Vessel.PINT, 568.0, "XXX"), 0.0)
    }

    /** A drink of your own invention has nothing to look up, so its price is all there is to go on. */
    @Test fun aDrinkOfYourOwnIsTheOneThingStillScaled() {
        val shed = Drink(name = "Dave's shed cider", category = DrinkCategory.CIDER, abv = 7.0, vessel = Vessel.BOTTLE, volumeMl = 500.0, price = 3.0)
        assertTrue(near(shed.price(Vessel.BOTTLE, 250.0), 1.5, 0.001))
    }

    /** A size nobody lists scales from the nearest serve of the same kind, not from whatever came first. */
    @Test fun anUnlistedSizeScalesFromItsOwnKindOfServe() {
        val asahi = asahi()
        assertTrue(near(Catalog.price(asahi, Vessel.BOTTLE, 660.0), Catalog.price(asahi, Vessel.BOTTLE, 330.0) * 2, 0.001))
    }
}
