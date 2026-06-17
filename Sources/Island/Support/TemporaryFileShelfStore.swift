import Foundation
import IslandCore

@MainActor
final class TemporaryFileShelfStore {
    private var shelf = TemporaryFileShelf()

    var items: [TemporaryShelfItem] {
        shelf.items
    }

    var hasItems: Bool {
        shelf.hasItems
    }

    func addFileURLs(_ fileURLs: [URL], now: Date = Date()) -> [TemporaryShelfItem] {
        shelf.addFileURLs(fileURLs, now: now)
        return shelf.items
    }

    func removeItem(id: TemporaryShelfItem.ID, now: Date = Date()) -> [TemporaryShelfItem] {
        shelf.pruneExpired(now: now)
        shelf.removeItem(id: id)
        return shelf.items
    }

    func clear() {
        shelf.clear()
    }

    func pruneExpired(now: Date = Date()) -> [TemporaryShelfItem] {
        shelf.pruneExpired(now: now)
        return shelf.items
    }
}
