import SwiftUI

struct IslandSettingsView: View {
    @ObservedObject var settings: IslandRuntimeSettings
    let onResetDisplay: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Toggle("文件架", isOn: $settings.isFileShelfEnabled)
                .toggleStyle(.switch)

            Toggle("音乐状态", isOn: $settings.isMusicModeEnabled)
                .toggleStyle(.switch)

            Toggle("调试模式", isOn: $settings.isCalibrationModeEnabled)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 5) {
                Text("手势灵敏度")
                    .font(.system(size: 11, weight: .semibold))
                Slider(value: $settings.gestureSensitivity, in: 0.6...1.6, step: 0.1)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("隐藏动画速度")
                    .font(.system(size: 11, weight: .semibold))
                Slider(value: $settings.hideAnimationStrength, in: 0.7...1.4, step: 0.1)
            }

            Divider()

            HStack {
                Button("重置显示器适配") {
                    onResetDisplay()
                }

                Spacer(minLength: 8)

                Button("恢复默认") {
                    settings.reset()
                }
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("设置")
                .font(.system(size: 14, weight: .semibold))
            Text("仅本次启动生效")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
