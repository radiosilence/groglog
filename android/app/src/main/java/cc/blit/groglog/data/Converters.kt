package cc.blit.groglog.data

import androidx.room.TypeConverter
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Vessel
import java.nio.ByteBuffer
import java.time.Instant
import java.util.UUID

/** Ids are 16-byte blobs and times are milliseconds since 1970; enums are stored by the raw values backups use. */
class Converters {
    @TypeConverter
    fun uuid(bytes: ByteArray): UUID = ByteBuffer.wrap(bytes).let { UUID(it.long, it.long) }

    @TypeConverter
    fun bytes(uuid: UUID): ByteArray = ByteBuffer.allocate(16).putLong(uuid.mostSignificantBits).putLong(uuid.leastSignificantBits).array()

    @TypeConverter
    fun instant(millis: Long?): Instant? = millis?.let(Instant::ofEpochMilli)

    @TypeConverter
    fun millis(instant: Instant?): Long? = instant?.toEpochMilli()

    @TypeConverter
    fun category(raw: String): DrinkCategory = DrinkCategory.fromRaw(raw) ?: error("Unknown drink category $raw")

    @TypeConverter
    fun raw(category: DrinkCategory): String = category.raw

    @TypeConverter
    fun vessel(raw: String): Vessel = Vessel.fromRaw(raw) ?: error("Unknown vessel $raw")

    @TypeConverter
    fun raw(vessel: Vessel): String = vessel.raw
}
