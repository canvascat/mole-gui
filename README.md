# mole-gui

这个窗口调用本机的 Mole CLI（`mo`），不是官方的 Mole for Mac。上游是 <https://github.com/tw93/Mole>。

本仓库不附带 Mole 源码，也不会替你执行安装脚本。

## 打开

```bash
make
open build/mole-gui.app
```

`make` 会先用 `swift test` 跑检查，再用 `swift build` 编译出 `build/mole-gui.app`。有完整 Xcode 时产出 arm64 + x86_64 通用二进制；只有 Command Line Tools 时只编 arm64。

## 开发

这是一个 Swift Package，没有 `.xcodeproj`：

- `Sources/MoleGUIKit`：界面和逻辑，SwiftUI 预览写在这里
- `Sources/MoleGUI`：只负责启动的可执行入口
- `Tests/MoleGUIKitTests`：Swift Testing 测试

用 Xcode 开发：

```bash
open Package.swift
```

在 Xcode 里选 `mole-gui` scheme 运行即可调试。Xcode 直接运行的是裸可执行文件，不带 `Info.plist`，所以 Dock 名称等和 `make` 打出的 `.app` 会略有不同。

## 许可证

与上游 [tw93/Mole](https://github.com/tw93/Mole) 一致，采用 GNU GPL v3，全文见 [LICENSE](LICENSE)。
