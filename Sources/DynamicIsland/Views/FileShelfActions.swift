import DynamicIslandCore
import Foundation

/// 文件架相关的用户操作回调集合，用于简化 IslandOverlayView 的参数签名。
@MainActor
struct FileShelfActions {
    var onSelectItem: @MainActor (TemporaryShelfItem.ID, Bool) -> Void = { _, _ in }
    var onSelectItems: @MainActor ([TemporaryShelfItem.ID], Bool) -> Void = { _, _ in }
    var onRemoveItem: @MainActor (TemporaryShelfItem.ID) -> Void = { _ in }
    var onClearItems: @MainActor () -> Void = {}
    var onDragStarted: @MainActor ([TemporaryShelfItem.ID]) -> Void = { _ in }
    var onDragCompleted: @MainActor ([TemporaryShelfItem.ID], Bool) -> Void = { _, _ in }
    var onFilterChange: @MainActor (TemporaryFileShelfFilter) -> Void = { _ in }
    var onClearSelection: @MainActor () -> Void = {}
    var onToggleOverlay: @MainActor () -> Void = {}
    var onDoneOverlay: @MainActor () -> Void = {}
}
