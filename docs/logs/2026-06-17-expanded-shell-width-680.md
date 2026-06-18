# 2026-06-17 展开态宽度缩小

## 完成内容

- 将默认展开态宽度从 700pt 调整为 680pt，对应左右各缩小 10pt。
- 保持闭合态宽度、hover 预览、点击展开和空壳状态不变。
- 重新打包 `dist/Dynamic Island.app`，并生成当时的历史调试 zip 包。

## 验证

- `swift run DynamicIslandCoreChecks`：通过。
- `swift build --product DynamicIsland`：通过。
- `./script/build_and_run.sh --verify`：通过。

## 未运行

- 未做人工截图对比。

## 风险与后续

- 这次只调整默认展开宽度；大屏动态推荐宽度仍会以 680pt 为下限继续按屏幕尺寸扩展。
