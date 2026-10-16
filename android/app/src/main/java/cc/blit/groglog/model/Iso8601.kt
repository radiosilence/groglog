package cc.blit.groglog.model

import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/**
 * Dates as iOS's `JSONEncoder` writes them with its `.iso8601` strategy: UTC, whole seconds, `Z`. Reading also takes an
 * offset or fractional seconds, which hand-written imports use.
 */
object Iso8601 {
    fun format(instant: Instant): String = DateTimeFormatter.ISO_INSTANT.format(instant.truncatedTo(ChronoUnit.SECONDS))

    fun parse(string: String): Instant? = runCatching { OffsetDateTime.parse(string).toInstant() }.getOrNull()
}

object Iso8601Serializer : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("cc.blit.groglog.Iso8601", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeString(Iso8601.format(value))
    override fun deserialize(decoder: Decoder): Instant {
        val string = decoder.decodeString()
        return Iso8601.parse(string) ?: throw SerializationException("Expected an ISO 8601 date, got $string")
    }
}
