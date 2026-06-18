import CoreGraphics

public enum IslandMusicSkipDirection: Equatable, Sendable {
    case previous
    case next
}

public enum MusicSkipGestureState: Equatable, Sendable {
    case idle
    case tracking(direction: IslandMusicSkipDirection, progress: CGFloat)
    case armed(direction: IslandMusicSkipDirection, progress: CGFloat)
    case cancelled(direction: IslandMusicSkipDirection)
    case committed(direction: IslandMusicSkipDirection)
}

public struct MusicSkipGestureStateMachine: Equatable, Sendable {
    public let commitDistance: CGFloat
    public let cancelDistance: CGFloat
    public private(set) var state: MusicSkipGestureState

    private var lockedDirection: IslandMusicSkipDirection?

    public init(commitDistance: CGFloat, cancelDistance: CGFloat) {
        self.commitDistance = max(1, commitDistance)
        self.cancelDistance = max(0, min(cancelDistance, commitDistance))
        self.state = .idle
        self.lockedDirection = nil
    }

    public var isArmed: Bool {
        if case .armed = state { return true }
        return false
    }

    public func currentDirection() -> IslandMusicSkipDirection? {
        switch state {
        case .idle:
            return lockedDirection
        case .tracking(let direction, _),
             .armed(let direction, _),
             .cancelled(let direction),
             .committed(let direction):
            return direction
        }
    }

    @discardableResult
    public mutating func update(accumulatedDeltaX: CGFloat) -> MusicSkipGestureState {
        if case .cancelled = state { return state }
        if case .committed = state { return state }

        let direction = lockedDirection ?? Self.direction(for: accumulatedDeltaX)
        lockedDirection = direction

        let distance = max(0, directionalDistance(accumulatedDeltaX, for: direction))
        let progress = min(distance / commitDistance, 1)

        if case .armed = state {
            if distance <= cancelDistance {
                state = .cancelled(direction: direction)
            } else {
                state = .armed(direction: direction, progress: progress)
            }
            return state
        }

        if progress >= 1 {
            state = .armed(direction: direction, progress: 1)
        } else {
            state = .tracking(direction: direction, progress: progress)
        }
        return state
    }

    @discardableResult
    public mutating func finish(shouldCommit: Bool) -> MusicSkipGestureState {
        switch state {
        case .armed(let direction, _) where shouldCommit:
            state = .committed(direction: direction)
        case .armed(let direction, _), .tracking(let direction, _), .cancelled(let direction):
            state = .cancelled(direction: direction)
        case .committed, .idle:
            break
        }
        return state
    }

    public mutating func reset() {
        state = .idle
        lockedDirection = nil
    }

    private static func direction(for accumulatedDeltaX: CGFloat) -> IslandMusicSkipDirection {
        accumulatedDeltaX < 0 ? .previous : .next
    }

    private func directionalDistance(_ accumulatedDeltaX: CGFloat, for direction: IslandMusicSkipDirection) -> CGFloat {
        switch direction {
        case .previous:
            return -accumulatedDeltaX
        case .next:
            return accumulatedDeltaX
        }
    }
}
