package cc.blit.groglog

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.aggregate.AggregationResultGroupedByDuration
import androidx.health.connect.client.aggregate.AggregationResultGroupedByPeriod
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.NutritionRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.metadata.DataOrigin
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.AggregateGroupByDurationRequest
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ChangesTokenRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.response.ChangesResponse
import androidx.health.connect.client.response.InsertRecordsResponse
import androidx.health.connect.client.response.ReadRecordResponse
import androidx.health.connect.client.response.ReadRecordsResponse
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import kotlin.reflect.KClass
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Health Connect in memory, holding to the rules GrogLog depends on: an app deletes only the records it wrote, a write
 * with a client record id replaces the app's record with that id, and reads come back a page at a time. A time range
 * matches any record that overlaps it, the broader of the readings Health Connect's documentation allows, so a delete
 * that reaches into a neighbouring day shows up here.
 */
class FakeHealthConnect(var granted: Set<String> = emptySet(), private val pageSize: Int = 3) : HealthConnectClient {
    /** Records other apps wrote, which GrogLog reads. */
    val others = mutableListOf<Record>()

    /** Records GrogLog wrote. */
    val own = mutableListOf<Record>()

    var reads = 0
    private val lock = Mutex()

    /**
     * Metadata as Health Connect hands back another app's record, naming the app that wrote it. Apps cannot set the
     * origin themselves, so the constructor that takes one is internal to the library.
     */
    fun other(source: String): Metadata =
        Metadata::class.java
            .getConstructor(Int::class.java, String::class.java, DataOrigin::class.java, Instant::class.java, String::class.java, Long::class.java, Device::class.java)
            .newInstance(Metadata.RECORDING_METHOD_AUTOMATICALLY_RECORDED, "", DataOrigin(source), Instant.EPOCH, null, 0L, null)

    override val permissionController = object : PermissionController {
        override suspend fun getGrantedPermissions() = granted
        override suspend fun revokeAllPermissions() {
            granted = emptySet()
        }
    }

    override val features = object : HealthConnectFeatures {
        override fun getFeatureStatus(feature: Int) = HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
    }

    override suspend fun insertRecords(records: List<Record>): InsertRecordsResponse {
        // Long enough for a second write to start meanwhile if the caller does not serialise them.
        delay(5)
        lock.withLock {
            for (record in records) {
                val id = record.metadata.clientRecordId
                if (id != null) own.removeAll { it.metadata.clientRecordId == id }
                own += record
            }
        }
        return InsertRecordsResponse(records.map { it.metadata.clientRecordId.orEmpty() })
    }

    override suspend fun deleteRecords(recordType: KClass<out Record>, timeRangeFilter: TimeRangeFilter) {
        delay(5)
        lock.withLock { own.removeAll { recordType.isInstance(it) && it.overlaps(timeRangeFilter) } }
    }

    @Suppress("UNCHECKED_CAST")
    override suspend fun <T : Record> readRecords(request: ReadRecordsRequest<T>): ReadRecordsResponse<T> {
        reads += 1
        val matching = (others + own).filter { request.recordType.isInstance(it) && it.overlaps(request.timeRangeFilter) } as List<T>
        val from = request.pageToken?.toInt() ?: 0
        val to = minOf(matching.size, from + pageSize)
        return ReadRecordsResponse(matching.subList(from, to), if (to < matching.size) to.toString() else null)
    }

    private fun Record.overlaps(filter: TimeRangeFilter): Boolean {
        val from = filter.startTime ?: Instant.MIN
        val to = filter.endTime ?: Instant.MAX
        val (start, end) = when (this) {
            is NutritionRecord -> startTime to endTime
            is SleepSessionRecord -> startTime to endTime
            is HeartRateRecord -> startTime to endTime
            is HeartRateVariabilityRmssdRecord -> return time >= from && time < to
            is RestingHeartRateRecord -> return time >= from && time < to
            else -> error("No time range for $this")
        }
        return start < to && end > from
    }

    override suspend fun updateRecords(records: List<Record>) = TODO()
    override suspend fun deleteRecords(recordType: KClass<out Record>, recordIdsList: List<String>, clientRecordIdsList: List<String>) = TODO()
    override suspend fun <T : Record> readRecord(recordType: KClass<T>, recordId: String): ReadRecordResponse<T> = TODO()
    override suspend fun aggregate(request: AggregateRequest): AggregationResult = TODO()
    override suspend fun aggregateGroupByDuration(request: AggregateGroupByDurationRequest): List<AggregationResultGroupedByDuration> = TODO()
    override suspend fun aggregateGroupByPeriod(request: AggregateGroupByPeriodRequest): List<AggregationResultGroupedByPeriod> = TODO()
    override suspend fun getChangesToken(request: ChangesTokenRequest): String = TODO()
    override suspend fun getChanges(changesToken: String): ChangesResponse = TODO()}
