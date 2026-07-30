import SwiftUI
import DynamicIslandCore

struct DataPrimaryContentView: View {
    let presentation: UsagePresentationState
    let selectedTimeRange: UsageTimeRange
    let isActive: Bool
    let isTimeRangeDrawerPresented: Bool
    let onTimeRangeDrawerPresentationChange: @MainActor (Bool) -> Void
    let onSelectTimeRange: @MainActor (UsageTimeRange) -> Void
    let onRefresh: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Namespace private var glassNamespace

    private let timeRangeOptions = UsageTimeRange.allCases
    private let triggerWidth: CGFloat = 72
    private let controlHeight: CGFloat = 24
    private let controlSpacing: CGFloat = 6
    private let drawerGap: CGFloat = 5

    private var drawerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var triggerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private var displayedSnapshot: UsageSnapshot? {
        switch presentation {
        case .idle, .loading(previous: nil):
            nil
        case .loading(previous: .some(let snapshot)):
            snapshot
        case .available(let snapshot), .empty(let snapshot), .partial(let snapshot):
            snapshot
        case .failed:
            nil
        }
    }

    private var isRefreshing: Bool {
        if case .loading(previous: .some) = presentation {
            return true
        }
        return false
    }

    private var isPartial: Bool {
        displayedSnapshot?.completeness == .partial
    }

    private var showsFailure: Bool {
        if case .failed = presentation {
            return true
        }
        return false
    }

    private var drawerTransition: AnyTransition {
        accessibilityReduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .top))
    }

    private var controlForeground: Color {
        .white.opacity(colorSchemeContrast == .increased ? 1 : 0.88)
    }

    private var titleForegroundColor: Color {
        .white.opacity(colorSchemeContrast == .increased ? 0.96 : 0.72)
    }

    private var secondaryForegroundColor: Color {
        .white.opacity(colorSchemeContrast == .increased ? 0.84 : 0.58)
    }

    private var tertiaryForegroundColor: Color {
        .white.opacity(colorSchemeContrast == .increased ? 0.68 : 0.38)
    }

    private var fallbackStrokeColor: Color {
        .white.opacity(colorSchemeContrast == .increased ? 0.48 : 0.16)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                statisticsCard
                    .zIndex(0)

                if isTimeRangeDrawerPresented {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            setDrawerPresented(false)
                        }
                        .zIndex(1)
                }

                controls
                    .padding(.top, 8)
                    .padding(.trailing, 8)
                    .zIndex(2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statisticsCard: some View {
        ZStack {
            drawerShape
                .fill(.white.opacity(colorSchemeContrast == .increased ? 0.065 : 0.035))
                .overlay(
                    drawerShape
                        .stroke(.white.opacity(colorSchemeContrast == .increased ? 0.20 : 0.08), lineWidth: 0.7)
                )

            if let snapshot = displayedSnapshot {
                snapshotContent(snapshot)
            } else {
                unavailableContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func snapshotContent(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            snapshotHeader(snapshot)

            metricGrid(snapshot)

            cacheHitFooter(snapshot)
        }
        .padding(8)
    }

    private func snapshotHeader(_ snapshot: UsageSnapshot) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("⚡ 真实消耗 Tokens")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(titleForegroundColor)

                    if isPartial {
                        Label("不完整", systemImage: "info.circle")
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                            .foregroundStyle(tertiaryForegroundColor)
                            .help("部分来源或时间覆盖不可用，当前只显示已确认的 Token 数据。")
                            .accessibilityHint("部分来源或时间覆盖不可用，当前只显示已确认的数据。")
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(UsageTokenFormatter.exact(snapshot.tokens.realTotal))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.38, green: 0.64, blue: 1))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(UsageTokenFormatter.approximate(snapshot.tokens.realTotal))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(tertiaryForegroundColor)
                        .monospacedDigit()
                }

                Text("请求 \(UsageTokenFormatter.exact(snapshot.requestCount)) · 估算成本 \(formattedCost(snapshot.estimatedCostUSD))")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(tertiaryForegroundColor)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 132)
        }
    }

    private func metricGrid(_ snapshot: UsageSnapshot) -> some View {
        GeometryReader { proxy in
            let usesFourColumnLayout = proxy.size.width >= 560
            LazyVGrid(
                columns: metricColumns(usesFourColumnLayout: usesFourColumnLayout),
                alignment: .leading,
                spacing: 4
            ) {
                metricCell("新增输入", value: snapshot.tokens.freshInput, color: .white)
                metricCell("Output", value: snapshot.tokens.output, color: Color(red: 0.72, green: 0.48, blue: 1))
                metricCell("创建缓存", value: snapshot.tokens.cacheCreation, color: .white)
                metricCell("缓存命中", value: snapshot.tokens.cacheRead, color: .white)
            }
        }
        .frame(height: 58)
    }

    private func metricColumns(usesFourColumnLayout: Bool) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 128), spacing: 6),
            count: usesFourColumnLayout ? 4 : 2
        )
    }

    private func metricCell(_ title: String, value: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .foregroundStyle(tertiaryForegroundColor)

            Text(UsageTokenFormatter.compact(value))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(color.opacity(0.88))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cacheHitFooter(_ snapshot: UsageSnapshot) -> some View {
        let cacheHitText = snapshot.cacheHitRate.map { String(format: "%.1f%%", $0 * 100) } ?? "N/A"

        return HStack(spacing: 7) {
            Text("缓存命中率 \(cacheHitText)")
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryForegroundColor)
                .monospacedDigit()
                .frame(width: 88, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.07))

                    Capsule(style: .continuous)
                        .fill(Color(red: 0.35, green: 0.88, blue: 0.62).opacity(0.78))
                        .frame(width: proxy.size.width * min(max(snapshot.cacheHitRate ?? 0, 0), 1))
                }
            }
            .frame(height: 3)
        }
        .frame(height: 13)
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("⚡ 真实消耗 Tokens")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(titleForegroundColor)

            Text("—")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(secondaryForegroundColor)
                .monospacedDigit()

            Spacer(minLength: 0)

            Label(
                showsFailure ? "统计数据暂不可用" : "正在统计…",
                systemImage: showsFailure ? "exclamationmark.circle" : "hourglass"
            )
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(secondaryForegroundColor)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel(showsFailure ? "统计数据暂不可用，请刷新重试" : "正在统计 Token 用量")

            Spacer(minLength: 0)

            Text("缓存命中率 N/A")
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .foregroundStyle(tertiaryForegroundColor)
                .monospacedDigit()
        }
        .padding(8)
    }

    @ViewBuilder
    private var controls: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !accessibilityReduceTransparency {
            nativeLiquidGlassControls
        } else {
            fallbackControls
        }
        #else
        fallbackControls
        #endif
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    private var nativeLiquidGlassControls: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(alignment: .top, spacing: controlSpacing) {
                timeRangeTrigger
                    .glassEffect(.regular.interactive(), in: triggerShape)
                    .glassEffectID(DataGlassEffectID.trigger, in: glassNamespace)

                refreshButton
                    .glassEffect(.regular.interactive(), in: Circle())
                    .glassEffectID(DataGlassEffectID.refresh, in: glassNamespace)
            }
            .overlay(alignment: .topTrailing) {
                if isTimeRangeDrawerPresented {
                    timeRangeDrawerContent
                        .padding(4)
                        .frame(width: triggerWidth)
                        .glassEffect(.regular.interactive(), in: drawerShape)
                        .glassEffectID(DataGlassEffectID.drawer, in: glassNamespace)
                        .glassEffectTransition(accessibilityReduceMotion ? .identity : .materialize)
                        .transition(accessibilityReduceMotion ? .opacity : .identity)
                        .offset(
                            x: -(controlHeight + controlSpacing),
                            y: controlHeight + drawerGap
                        )
                }
            }
        }
    }
    #endif

    private var fallbackControls: some View {
        HStack(alignment: .top, spacing: controlSpacing) {
            timeRangeTrigger
                .background {
                    fallbackBackground(triggerShape)
                }
                .overlay(
                    triggerShape
                        .stroke(fallbackStrokeColor, lineWidth: colorSchemeContrast == .increased ? 1 : 0.7)
                )
                .shadow(color: .black.opacity(0.24), radius: 4, y: 2)

            refreshButton
                .background {
                    fallbackBackground(Circle())
                }
                .overlay(
                    Circle()
                        .stroke(fallbackStrokeColor, lineWidth: colorSchemeContrast == .increased ? 1 : 0.7)
                )
                .shadow(color: .black.opacity(0.24), radius: 4, y: 2)
        }
        .overlay(alignment: .topTrailing) {
            if isTimeRangeDrawerPresented {
                timeRangeDrawerContent
                    .padding(4)
                    .frame(width: triggerWidth)
                    .background {
                        fallbackBackground(drawerShape)
                    }
                    .overlay(
                        drawerShape
                            .stroke(fallbackStrokeColor, lineWidth: colorSchemeContrast == .increased ? 1 : 0.7)
                    )
                    .shadow(color: .black.opacity(0.32), radius: 8, y: 4)
                    .transition(drawerTransition)
                    .offset(
                        x: -(controlHeight + controlSpacing),
                        y: controlHeight + drawerGap
                    )
            }
        }
    }

    @ViewBuilder
    private func fallbackBackground<S: Shape>(_ shape: S) -> some View {
        if accessibilityReduceTransparency {
            shape
                .fill(Color.black.opacity(colorSchemeContrast == .increased ? 1 : 0.94))
        } else {
            shape
                .fill(.thinMaterial)
        }
    }

    private var timeRangeTrigger: some View {
        Button {
            setDrawerPresented(!isTimeRangeDrawerPresented)
        } label: {
            ZStack {
                Text(selectedTimeRange.displayName)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 7)
                    .accessibilityHidden(true)
            }
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(controlForeground)
            .frame(width: triggerWidth, height: controlHeight)
            .contentShape(triggerShape)
        }
        .buttonStyle(IslandPressButtonStyle())
        .help("选择统计时间范围")
        .accessibilityLabel("选择统计时间范围，当前 \(selectedTimeRange.displayName)")
    }

    private var refreshButton: some View {
        Button(action: refresh) {
            Image(systemName: isRefreshing ? "hourglass" : "arrow.clockwise")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(controlForeground)
                .frame(width: controlHeight, height: controlHeight)
                .contentShape(Circle())
        }
        .buttonStyle(IslandPressButtonStyle())
        .help(isRefreshing ? "正在刷新统计" : "刷新统计")
        .accessibilityLabel(isRefreshing ? "正在刷新 Token 用量" : "刷新 Token 用量")
    }

    private var timeRangeDrawerContent: some View {
        VStack(spacing: 1) {
            ForEach(timeRangeOptions) { range in
                timeRangeOption(range)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func timeRangeOption(_ range: UsageTimeRange) -> some View {
        Button {
            selectTimeRange(range)
        } label: {
            ZStack {
                Text(range.displayName)
                    .frame(maxWidth: .infinity, alignment: .center)

                if range == selectedTimeRange {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: 9.5, weight: range == selectedTimeRange ? .semibold : .medium, design: .rounded))
            .foregroundStyle(
                range == selectedTimeRange
                    ? Color(red: 0.48, green: 0.70, blue: 1)
                    : controlForeground
            )
            .padding(.horizontal, 5)
            .frame(height: controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressButtonStyle())
        .accessibilityLabel(range == selectedTimeRange ? "\(range.displayName)，已选择" : range.displayName)
    }

    @MainActor
    private func selectTimeRange(_ range: UsageTimeRange) {
        setDrawerPresented(false)
        onSelectTimeRange(range)
    }

    @MainActor
    private func refresh() {
        setDrawerPresented(false)
        onRefresh()
    }

    @MainActor
    private func setDrawerPresented(_ isPresented: Bool) {
        onTimeRangeDrawerPresentationChange(isPresented)
    }

    private func formattedCost(_ cost: Decimal?) -> String {
        guard let cost else { return "N/A" }
        return "$" + NSDecimalNumber(decimal: cost).stringValue
    }
}

#if compiler(>=6.2)
private enum DataGlassEffectID: String, Hashable, Sendable {
    case trigger
    case drawer
    case refresh
}
#endif
