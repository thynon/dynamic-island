import Darwin
import Foundation
import IslandCore

enum CodexUsageDataSource {
    private static let cache = CodexUsageSummaryCache()
    private static let tokenCountMarker = Array(#""token_count""#.utf8)
    private static let sessionMetaMarker = Array(#""session_meta""#.utf8)

    static func loadSummary(
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        calendar: Calendar = .autoupdatingCurrent
    ) async -> CodexUsageSummary {
        if let summary = await CCSwitchUsageDataSource.loadSummary(calendar: calendar) {
            return summary
        }

        return await fallbackSummary(sessionsDirectory: sessionsDirectory, calendar: calendar)
    }

    private static func fallbackSummary(
        sessionsDirectory: URL,
        calendar: Calendar
    ) async -> CodexUsageSummary {
        await cache.loadSummary(sessionsDirectory: sessionsDirectory, calendar: calendar)
    }

    static func clearCache() async {
        await cache.clear()
    }

    fileprivate static var persistentCacheURL: URL {
        let baseURL = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches", isDirectory: true)

        return baseURL
            .appendingPathComponent("Island", isDirectory: true)
            .appendingPathComponent("codex-usage-cache.json")
    }

    fileprivate static func loadSummarySync(
        sessionsDirectory: URL,
        calendar: Calendar
    ) -> CodexUsageSummary {
        defer {
            reclaimUnusedMallocPages()
        }

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .empty
        }

        var events: [CodexUsageEvent] = []
        let earliestDate = StatsTimeRange.all.startDate(today: Date(), calendar: calendar)

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            events.append(contentsOf: loadEvents(from: fileURL, since: earliestDate).events)
        }

        return CodexUsageSummary.build(events: events, calendar: calendar)
    }

    fileprivate static func reclaimUnusedMallocPages() {
        _ = malloc_zone_pressure_relief(nil, 0)
    }

    fileprivate static func fileSnapshot(sessionsDirectory: URL) -> CodexUsageFileSnapshot {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return CodexUsageFileSnapshot(files: [])
        }

        let files = enumerator.compactMap { item -> CodexUsageFileSignature? in
            guard
                let fileURL = item as? URL,
                fileURL.pathExtension == "jsonl",
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                values.isRegularFile == true
            else {
                return nil
            }

            return CodexUsageFileSignature(
                path: fileURL.path,
                size: Int64(values.fileSize ?? 0),
                modificationTime: values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
            )
        }

        return CodexUsageFileSnapshot(files: files.sorted { $0.path < $1.path })
    }

    fileprivate static func loadEvents(
        from fileURL: URL,
        since earliestDate: Date,
        startingAt offset: Int64 = 0,
        initialModel: String? = nil
    ) -> CodexUsageFileLoadResult {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return CodexUsageFileLoadResult(events: [], model: initialModel)
        }
        defer {
            try? handle.close()
        }

        if offset > 0 {
            try? handle.seek(toOffset: UInt64(offset))
        }

        var model = initialModel
        var previousCumulativeUsage: CodexTokenUsage?
        var events: [CodexUsageEvent] = []
        var remainder = Data()

        while let chunk = try? handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            var buffer = remainder
            buffer.append(chunk)

            guard bufferContainsRelevantUsageMarker(buffer) else {
                if let newlineIndex = buffer.lastIndex(of: 10) {
                    remainder = Data(buffer[buffer.index(after: newlineIndex)...])
                } else {
                    remainder = buffer
                }
                continue
            }

            var lineStart = buffer.startIndex

            while let newlineIndex = buffer[lineStart...].firstIndex(of: 10) {
                processLineData(
                    buffer[lineStart..<newlineIndex],
                    model: &model,
                    previousCumulativeUsage: &previousCumulativeUsage,
                    events: &events,
                    earliestDate: earliestDate
                )
                lineStart = buffer.index(after: newlineIndex)
            }

            remainder = Data(buffer[lineStart...])
        }

        if !remainder.isEmpty {
            processLineData(
                remainder[remainder.startIndex..<remainder.endIndex],
                model: &model,
                previousCumulativeUsage: &previousCumulativeUsage,
                events: &events,
                earliestDate: earliestDate
            )
        }

        return CodexUsageFileLoadResult(events: events, model: model)
    }

    private static func processLineData(
        _ lineData: Data.SubSequence,
        model: inout String?,
        previousCumulativeUsage: inout CodexTokenUsage?,
        events: inout [CodexUsageEvent],
        earliestDate: Date
    ) {
        guard
            !lineData.isEmpty,
            lineDataContainsRelevantUsageMarker(lineData),
            let line = String(data: Data(lineData), encoding: .utf8)
        else {
            return
        }

        if let parsedUsage = autoreleasepool(invoking: { CodexSessionLogParser.parseTokenUsageLine(line) }) {
            let usage: CodexTokenUsage
            if parsedUsage.isCumulative {
                usage = deltaUsage(from: previousCumulativeUsage, to: parsedUsage.event.usage)
                previousCumulativeUsage = parsedUsage.event.usage
            } else {
                usage = parsedUsage.event.usage
            }

            guard !isZeroUsage(usage), parsedUsage.event.timestamp >= earliestDate else {
                return
            }
            events.append(
                CodexUsageEvent(
                    timestamp: parsedUsage.event.timestamp,
                    usage: usage,
                    model: model
                )
            )
            return
        }

        if case .metadata(let metadata)? = autoreleasepool(invoking: { CodexSessionLogParser.parseLine(line) }) {
            model = normalizedModel(metadata.model)
        }
    }

    private static func deltaUsage(from previous: CodexTokenUsage?, to current: CodexTokenUsage) -> CodexTokenUsage {
        guard let previous else {
            return current
        }

        return CodexTokenUsage(
            inputTokens: max(0, current.inputTokens - previous.inputTokens),
            cachedInputTokens: max(0, current.cachedInputTokens - previous.cachedInputTokens),
            outputTokens: max(0, current.outputTokens - previous.outputTokens),
            reasoningOutputTokens: max(0, current.reasoningOutputTokens - previous.reasoningOutputTokens),
            totalTokens: max(0, current.totalTokens - previous.totalTokens)
        )
    }

    private static func isZeroUsage(_ usage: CodexTokenUsage) -> Bool {
        usage.inputTokens == 0
            && usage.cachedInputTokens == 0
            && usage.outputTokens == 0
            && usage.reasoningOutputTokens == 0
            && usage.totalTokens == 0
    }

    private static func lineDataContainsRelevantUsageMarker(_ lineData: Data.SubSequence) -> Bool {
        lineDataContains(lineData, marker: tokenCountMarker)
            || lineDataContains(lineData, marker: sessionMetaMarker)
    }

    private static func bufferContainsRelevantUsageMarker(_ buffer: Data) -> Bool {
        bufferContains(buffer, marker: tokenCountMarker)
            || bufferContains(buffer, marker: sessionMetaMarker)
    }

    private static func bufferContains(_ buffer: Data, marker: [UInt8]) -> Bool {
        guard !marker.isEmpty, buffer.count >= marker.count else {
            return false
        }

        return buffer.withUnsafeBytes { haystack in
            memoryContains(haystack, marker: marker)
        }
    }

    private static func lineDataContains(_ lineData: Data.SubSequence, marker: [UInt8]) -> Bool {
        guard !marker.isEmpty, lineData.count >= marker.count else {
            return false
        }

        if let result = lineData.withContiguousStorageIfAvailable({ haystack in
            memoryContains(
                UnsafeRawBufferPointer(haystack),
                marker: marker
            )
        }) {
            return result
        }

        var matchedCount = 0
        for byte in lineData {
            if byte == marker[matchedCount] {
                matchedCount += 1
                if matchedCount == marker.count {
                    return true
                }
                continue
            }

            matchedCount = byte == marker[0] ? 1 : 0
        }

        return false
    }

    private static func memoryContains(_ haystack: UnsafeRawBufferPointer, marker: [UInt8]) -> Bool {
        guard
            let haystackBaseAddress = haystack.baseAddress,
            haystack.count >= marker.count
        else {
            return false
        }

        return marker.withUnsafeBufferPointer { needle in
            guard let needleBaseAddress = needle.baseAddress else {
                return false
            }

            return memmem(
                haystackBaseAddress,
                haystack.count,
                needleBaseAddress,
                marker.count
            ) != nil
        }
    }

    private static func normalizedModel(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value != "custom" else {
            return nil
        }

        return value
    }
}

fileprivate struct CodexUsageFileSignature: Codable, Equatable, Sendable {
    let path: String
    let size: Int64
    let modificationTime: TimeInterval
}

fileprivate struct CodexUsageFileSnapshot: Equatable, Sendable {
    let files: [CodexUsageFileSignature]
}

fileprivate struct CodexUsageFileLoadResult: Sendable {
    let events: [CodexUsageEvent]
    let model: String?
}

private struct CachedCodexUsageFile: Codable, Equatable, Sendable {
    static let currentParserVersion = 2

    let parserVersion: Int
    let signature: CodexUsageFileSignature
    let events: [CodexUsageEvent]
    let model: String?
}

private actor CodexUsageSummaryCache {
    private var cachedFiles: [String: CachedCodexUsageFile] = [:]
    private var didLoadPersistentCache = false

    func clear() {
        cachedFiles.removeAll(keepingCapacity: false)
        didLoadPersistentCache = false
        CodexUsageDataSource.reclaimUnusedMallocPages()
    }

    func loadSummary(sessionsDirectory: URL, calendar: Calendar) async -> CodexUsageSummary {
        defer {
            CodexUsageDataSource.reclaimUnusedMallocPages()
        }

        loadPersistentCacheIfNeeded()

        let snapshot = CodexUsageDataSource.fileSnapshot(sessionsDirectory: sessionsDirectory)
        let earliestDate = StatsTimeRange.all.startDate(today: Date(), calendar: calendar)
        var nextCache: [String: CachedCodexUsageFile] = [:]
        var events: [CodexUsageEvent] = []

        for signature in snapshot.files {
            if let cached = cachedFiles[signature.path], cached.signature == signature {
                let recentEvents = cached.events.filter { $0.timestamp >= earliestDate }
                nextCache[signature.path] = CachedCodexUsageFile(
                    parserVersion: CachedCodexUsageFile.currentParserVersion,
                    signature: signature,
                    events: recentEvents,
                    model: cached.model
                )
                events.append(contentsOf: recentEvents)
                continue
            }

            let fileURL = URL(fileURLWithPath: signature.path)
            if
                let cached = cachedFiles[signature.path],
                signature.size > cached.signature.size
            {
                let result = await Task.detached(priority: .utility) {
                    CodexUsageDataSource.loadEvents(
                        from: fileURL,
                        since: earliestDate
                    )
                }.value
                let recentEvents = result.events.filter { $0.timestamp >= earliestDate }

                nextCache[signature.path] = CachedCodexUsageFile(
                    parserVersion: CachedCodexUsageFile.currentParserVersion,
                    signature: signature,
                    events: recentEvents,
                    model: result.model
                )
                events.append(contentsOf: recentEvents)
                continue
            }

            let result = await Task.detached(priority: .utility) {
                CodexUsageDataSource.loadEvents(
                    from: fileURL,
                    since: earliestDate
                )
            }.value
            let recentEvents = result.events.filter { $0.timestamp >= earliestDate }
            nextCache[signature.path] = CachedCodexUsageFile(
                parserVersion: CachedCodexUsageFile.currentParserVersion,
                signature: signature,
                events: recentEvents,
                model: result.model
            )
            events.append(contentsOf: recentEvents)
        }

        let shouldPersistCache = nextCache != cachedFiles
        cachedFiles = nextCache
        if shouldPersistCache {
            persistCache(nextCache)
        }
        return CodexUsageSummary.build(events: events, calendar: calendar)
    }

    private func loadPersistentCacheIfNeeded() {
        guard !didLoadPersistentCache else {
            return
        }
        didLoadPersistentCache = true

        let url = CodexUsageDataSource.persistentCacheURL
        guard
            let data = try? Data(contentsOf: url),
            let persistedCache = try? JSONDecoder().decode(
                [String: CachedCodexUsageFile].self,
                from: data
            )
        else {
            return
        }

        cachedFiles = persistedCache.filter { _, cached in
            cached.parserVersion == CachedCodexUsageFile.currentParserVersion
        }
    }

    private func persistCache(_ cache: [String: CachedCodexUsageFile]) {
        let url = CodexUsageDataSource.persistentCacheURL

        Task.detached(priority: .utility) {
            do {
                let directoryURL = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                let data = try encoder.encode(cache)
                try data.write(to: url, options: [.atomic])
                CodexUsageDataSource.reclaimUnusedMallocPages()
            } catch {
                return
            }
        }
    }
}
