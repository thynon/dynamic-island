import Combine
import Foundation
import DynamicIslandCore

@MainActor
final class TemporaryFileShelfStore: ObservableObject {
    @Published private(set) var shelf: TemporaryFileShelf

    init(shelf: TemporaryFileShelf = TemporaryFileShelf()) {
        self.shelf = shelf
    }

    func addFileURLs(_ fileURLs: [URL], now: Date = Date()) {
        shelf.addFileURLs(fileURLs, now: now)
    }

    func removeItem(id: TemporaryShelfItem.ID) {
        shelf.removeItem(id: id)
    }

    func removeItems(ids: Set<TemporaryShelfItem.ID>) {
        shelf.removeItems(ids: ids)
    }

    func clear() {
        shelf.clear()
    }

    func pruneExpired(now: Date = Date()) {
        shelf.pruneExpired(now: now)
    }
}
