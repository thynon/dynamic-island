import Foundation

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

    public mutating func toggle(_ id: TemporaryShelfItem.ID) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    public mutating func clear() {
        selectedItemIDs.removeAll()
    }

    public mutating func retainOnly<S: Sequence>(itemIDs: S) where S.Element == TemporaryShelfItem.ID {
        selectedItemIDs.formIntersection(Set(itemIDs))
    }
}
