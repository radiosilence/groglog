package cc.blit.groglog.model

import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/**
 * Dates as iOS's `JSONEncoder` writes them with its `.iso8601` strategy: UTC, whole seconds, `Z`. Reading also takes an
 * offset or fractional seconds, which hand-written imports use.
 */
object Iso8601 {
    fun format(instant: Instant): String = DateTimeFormatter.ISO_INSTANT.format(instant.truncatedTo(ChronoUnit.SECONDS))

    fun parse(string: String): Instant? = runCatching { OffsetDateTime.parse(string).toInstant() }.getOrNull()
}
