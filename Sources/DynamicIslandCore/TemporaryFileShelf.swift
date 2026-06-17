import Foundation

public enum TemporaryShelfFileCategory: String, CaseIterable, Equatable, Hashable, Sendable {
    case images
    case documents
    case spreadsheets
    case presentations
    case other

    public var title: String {
        switch self {
        case .images:
            "Images"
        case .documents:
            "Documents"
        case .spreadsheets:
            "Spreadsheets"
        case .presentations:
            "Presentations"
        case .other:
            "Other"
        }
    }

    public static func from(fileExtension: String?) -> TemporaryShelfFileCategory {
        switch fileExtension?.lowercased() {
        case "png", "jpg", "jpeg", "heic", "gif", "webp", "svg":
            .images
        case "pdf", "doc", "docx", "txt", "md", "pages", "rtf":
            .documents
        case "xls", "xlsx", "csv", "numbers", "tsv":
            .spreadsheets
        case "ppt", "pptx", "key":
            .presentations
        default:
            .other
        }
    }
}

public enum TemporaryFileShelfFilter: String, CaseIterable, Equatable, Hashable, Sendable {
    case all
    case images
    case documents
    case spreadsheets
    case presentations
    case other

    public var title: String {
        switch self {
        case .all:
            "All"
        case .images:
            "Images"
        case .documents:
            "Documents"
        case .spreadsheets:
            "Sheets"
        case .presentations:
            "Slides"
        case .other:
            "Other"
        }
    }

    public func matches(_ category: TemporaryShelfFileCategory) -> Bool {
        switch self {
        case .all:
            true
        case .images:
            category == .images
        case .documents:
            category == .documents
        case .spreadsheets:
            category == .spreadsheets
        case .presentations:
            category == .presentations
        case .other:
            category == .other
        }
    }
}

public struct TemporaryShelfItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let fileURL: URL
    public let displayName: String
    public let fileExtension: String?
    public let category: TemporaryShelfFileCategory
    public let addedAt: Date
    public let expiresAt: Date

    public init(fileURL: URL, addedAt: Date, expiresAt: Date) {
        let resolvedURL = fileURL.standardizedFileURL
        self.id = resolvedURL.path
        self.fileURL = resolvedURL
        displayName = resolvedURL.lastPathComponent.isEmpty ? resolvedURL.path : resolvedURL.lastPathComponent
        fileExtension = resolvedURL.pathExtension.isEmpty ? nil : resolvedURL.pathExtension
        category = TemporaryShelfFileCategory.from(fileExtension: fileExtension)
        self.addedAt = addedAt
        self.expiresAt = expiresAt
    }
}

public struct TemporaryFileShelfSelection: Equatable, Sendable {
    public private(set) var selectedItemIDs: Set<TemporaryShelfItem.ID>

    public init(selectedItemIDs: Set<TemporaryShelfItem.ID> = []) {
        self.selectedItemIDs = selectedItemIDs
    }

    public mutating func selectOnly(_ id: TemporaryShelfItem.ID) {
        selectedItemIDs = [id]
    }

    public mutating func select(_ ids: Set<TemporaryShelfItem.ID>) {
        selectedItemIDs = ids
    }

    public mutating func clear() {
        selectedItemIDs.removeAll()
    }

    public mutating func retainOnly<S: Sequence>(itemIDs: S) where S.Element == TemporaryShelfItem.ID {
        selectedItemIDs.formIntersection(Set(itemIDs))
    }
}

public struct TemporaryFileShelf: Equatable, Sendable {
    public static let itemLifetime: TimeInterval = 24 * 60 * 60

    public private(set) var items: [TemporaryShelfItem]

    public init(items: [TemporaryShelfItem] = [], now: Date = Date()) {
        self.items = items.filter { $0.expiresAt > now }
    }

    public var hasItems: Bool {
        !items.isEmpty
    }

    public mutating func addFileURLs(_ fileURLs: [URL], now: Date = Date()) {
        pruneExpired(now: now)

        for fileURL in fileURLs {
            let item = TemporaryShelfItem(
                fileURL: fileURL,
                addedAt: now,
                expiresAt: now.addingTimeInterval(Self.itemLifetime)
            )

            if let existingIndex = items.firstIndex(where: { $0.id == item.id }) {
                items[existingIndex] = item
            } else {
                items.append(item)
            }
        }
    }

    public mutating func removeItem(id: TemporaryShelfItem.ID) {
        items.removeAll { $0.id == id }
    }

    public mutating func clear() {
        items.removeAll()
    }

    public mutating func pruneExpired(now: Date = Date()) {
        items.removeAll { $0.expiresAt <= now }
    }
}
