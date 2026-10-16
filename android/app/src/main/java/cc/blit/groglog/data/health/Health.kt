package cc.blit.groglog.data.health

import android.content.Context
import android.util.Log
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.NutritionRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.health.connect.client.units.Energy
import cc.blit.groglog.data.AppDatabase
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.Nights
import cc.blit.groglog.model.SleepSpan
import cc.blit.groglog.model.SleepStage
import cc.blit.groglog.model.TimeSpan
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.cancellation.CancellationException
import kotlin.reflect.KClass
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Health Connect: each drink's calories copied out, and heart and sleep readings read in for Reports.
 *
 * The log is authoritative and Health Connect only mirrors it. A day is rewritten whole rather than patched, so an edit,
 * an undo or a corrected strength moves the records with it and the copy cannot drift. Health Connect has no alcohol
 * type, so only the energy is copied, as a nutrition record per drink. Failures are logged and swallowed: a refused
 * permission or a missing Health Connect must never block logging a drink.
 *
 * `connect` is null when Health Connect is not installed or not supported; it is asked again each time, since it can
 * be installed while the app runs.
 */
class Health(
    private val database: AppDatabase,
    private val prefs: Prefs,
    private val connect: () -> HealthConnectClient?,
) {
    private val writing = Mutex()

    /** Nights already read, which do not change once they are over: a span's heart rate is fetched once. */
    private val beatsByNight = ConcurrentHashMap<TimeSpan, List<Pair<Instant, Double>>>()

    /** Which permissions have been granted, or null if Health Connect cannot be reached. */
    suspend fun granted(): Set<String>? = guarded("read permissions") { connect()?.permissionController?.getGrantedPermissions() }

    /**
     * Read permissions with reading older data added where Health Connect offers it, so the weekly bars carry on from
     * before the log began. Without it Health Connect gives only the 30 days before the first grant.
     */
    fun withHistory(permissions: Set<String>): Set<String> {
        val history = runCatching {
            connect()?.features?.getFeatureStatus(HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_HISTORY)
        }.getOrNull() == HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
        return if (history) permissions + HISTORY else permissions
    }

    /**
     * Rewrites these days, or with null every day, if copying is on: GrogLog's records out, the current entries in.
     * Health Connect only lets an app delete the records it wrote. Rewrites are serialised: two drinks logged in quick
     * succession each rewrite the day, and run concurrently both would clear it before either wrote, so each would write
     * both drinks.
     */
    suspend fun mirror(days: Set<DayKey>?) = writing.withLock {
        if (!prefs.health.first().copies) return@withLock
        val client = connect() ?: return@withLock
        if (guarded("read permissions") { client.permissionController.getGrantedPermissions() }?.containsAll(COPY) != true) return@withLock
        val clock = prefs.current().clock
        val rows = database.rows()
        if (days == null) {
            // One pass rather than day by day: two round trips a day take minutes on a long log.
            guarded("mirror the log") {
                client.deleteRecords(NutritionRecord::class, TimeRangeFilter.after(Instant.EPOCH))
                rows.entries().mapNotNull(::record).chunked(BATCH).forEach { client.insertRecords(it) }
            }
            return@withLock
        }
        for (day in days.sorted()) {
            guarded("mirror $day") {
                client.deleteRecords(NutritionRecord::class, TimeRangeFilter.between(clock.start(day), clock.end(day)))
                val records = rows.entries(day.number, day.number).mapNotNull(::record)
                if (records.isNotEmpty()) client.insertRecords(records)
            }
        }
    }

    /** Removes GrogLog's records, which Health Connect would otherwise keep reporting after copying stops. */
    suspend fun removeMirror() = writing.withLock {
        guarded("remove the mirror") { connect()?.deleteRecords(NutritionRecord::class, TimeRangeFilter.after(Instant.EPOCH)) }
        Unit
    }

    /**
     * Heart readings and sleep, filed under the nights they followed, as far back as Health Connect allows: readings
     * from before the log began form the baseline. Sleep is also read for heart rate, since it says which beats were
     * asleep. Readings whose permission was refused or withdrawn are simply absent.
     */
    suspend fun nights(clock: DayClock, heart: Boolean, sleep: Boolean): Nights = withContext(Dispatchers.Default) {
        if (!heart && !sleep) return@withContext Nights()
        val client = connect() ?: return@withContext Nights()
        val granted = guarded("read permissions") { client.permissionController.getGrantedPermissions() } ?: return@withContext Nights()
        val now = Instant.now()
        val everything = TimeRangeFilter.before(now)
        val spans = if (read(SleepSessionRecord::class) in granted) {
            guarded("read sleep") { client.all(SleepSessionRecord::class, everything).flatMap(::sleepSpans) } ?: emptyList()
        } else {
            emptyList()
        }
        val reads = { permission: KClass<out Record> -> heart && read(permission) in granted }
        val hrv = if (reads(HeartRateVariabilityRmssdRecord::class)) {
            guarded("read HRV") { client.all(HeartRateVariabilityRmssdRecord::class, everything).map { it.time to it.heartRateVariabilityMillis } }
        } else {
            null
        }
        val resting = if (reads(RestingHeartRateRecord::class)) {
            guarded("read resting heart rate") { client.all(RestingHeartRateRecord::class, everything).map { it.time to it.beatsPerMinute.toDouble() } }
        } else {
            null
        }
        val beats = if (reads(HeartRateRecord::class) && spans.isNotEmpty()) heartRate(client, spans, clock, now) else emptyList()
        val nights = Nights.of(hrv.orEmpty(), resting.orEmpty(), spans, beats, clock)
        if (sleep) nights else Nights(nights.byDay.mapValues { it.value.copy(sleep = null) })
    }

    /**
     * Heart rate inside each recent night's sleep. A watch writes a reading every minute or two for years, so only the
     * nights are fetched, one request each, and only for as long as a chart shows sleeping rate: Health Connect limits
     * how many requests an app makes, which a year of nights would use up.
     */
    private suspend fun heartRate(client: HealthConnectClient, spans: List<SleepSpan>, clock: DayClock, now: Instant): List<Pair<Instant, Double>> {
        val since = now.minus(Duration.ofDays(HEART_RATE_DAYS))
        val nights = Nights.nightSpans(spans, clock).filter { it.end > since }
        // A night still in progress, or synced late, is fetched again; the rest come from the cache.
        val settled = now.minus(Duration.ofHours(36))
        return nights.flatMap { night ->
            beatsByNight[night]?.let { return@flatMap it }
            val beats = guarded("read heart rate") {
                client.all(HeartRateRecord::class, TimeRangeFilter.between(night.start, night.end))
                    .flatMap { record -> record.samples.map { it.time to it.beatsPerMinute.toDouble() } }
                    .filter { it.first in night }
            } ?: return@flatMap emptyList()
            if (night.end < settled) beatsByNight[night] = beats
            beats
        }
    }

    private suspend fun <T> guarded(what: String, body: suspend () -> T): T? =
        try {
            body()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            Log.e(TAG, "Couldn't $what", error)
            null
        }

    companion object {
        private const val TAG = "Health"
        private const val BATCH = 1000
        private const val PAGE = 5000

        /** As far back as any chart draws heart rate while asleep: the monthly progress chart's history. */
        const val HEART_RATE_DAYS = 120L

        val COPY = setOf(HealthPermission.getWritePermission(NutritionRecord::class))
        val SLEEP = setOf(read(SleepSessionRecord::class))

        /** Sleep too, which says which heart rate readings were taken asleep. */
        val HEART = setOf(
            read(HeartRateVariabilityRmssdRecord::class),
            read(RestingHeartRateRecord::class),
            read(HeartRateRecord::class),
            read(SleepSessionRecord::class),
        )
        const val HISTORY = HealthPermission.PERMISSION_READ_HEALTH_DATA_HISTORY

        private fun read(type: KClass<out Record>) = HealthPermission.getReadPermission(type)

        /** On Android 9 to 13 Health Connect is an app from Play, and is reached through its package. */
        const val PROVIDER = "com.google.android.apps.healthdata"

        fun connect(context: Context): () -> HealthConnectClient? {
            var client: HealthConnectClient? = null
            return {
                client ?: if (HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE) {
                    HealthConnectClient.getOrCreate(context).also { client = it }
                } else {
                    null
                }
            }
        }

        /**
         * A drink's calories, at the moment it was logged. Health Connect wants an end after the start; a millisecond
         * keeps the record inside its drinking day, so a day's rewrite never touches its neighbour's. The pour's id
         * makes a write of an existing record replace it rather than add a second.
         */
        fun record(entry: Entry): NutritionRecord? {
            if (entry.kcal <= 0) return null
            val offset = ZoneId.systemDefault().rules.getOffset(entry.timestamp)
            return NutritionRecord(
                startTime = entry.timestamp,
                startZoneOffset = offset,
                endTime = entry.timestamp.plusMillis(1),
                endZoneOffset = offset,
                metadata = Metadata.manualEntry(clientRecordId = entry.id.toString()),
                energy = Energy.kilocalories(entry.kcal),
                name = entry.name,
            )
        }

        /**
         * A session's stages, or the whole session as unstaged sleep when the device gave none. Light sleep is what
         * HealthKit calls core. Time out of bed is left out, as HealthKit's in-bed time is.
         */
        fun sleepSpans(session: SleepSessionRecord): List<SleepSpan> {
            val source = session.metadata.dataOrigin.packageName
            if (session.stages.isEmpty()) return listOf(SleepSpan(TimeSpan(session.startTime, session.endTime), SleepStage.UNSTAGED, source))
            return session.stages.mapNotNull { stage ->
                val kind = when (stage.stage) {
                    SleepSessionRecord.STAGE_TYPE_AWAKE, SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED -> SleepStage.AWAKE
                    SleepSessionRecord.STAGE_TYPE_LIGHT -> SleepStage.CORE
                    SleepSessionRecord.STAGE_TYPE_DEEP -> SleepStage.DEEP
                    SleepSessionRecord.STAGE_TYPE_REM -> SleepStage.REM
                    SleepSessionRecord.STAGE_TYPE_SLEEPING -> SleepStage.UNSTAGED
                    else -> null
                }
                kind?.let { SleepSpan(TimeSpan(stage.startTime, stage.endTime), it, source) }
            }
        }

        private suspend fun <T : Record> HealthConnectClient.all(type: KClass<T>, range: TimeRangeFilter): List<T> {
            val records = mutableListOf<T>()
            var token: String? = null
            do {
                val page = readRecords(ReadRecordsRequest(type, range, pageSize = PAGE, pageToken = token))
                records += page.records
                token = page.pageToken
            } while (!token.isNullOrEmpty())
            return records
        }
    }
}
