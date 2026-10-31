# mole-gui

这个窗口调用本机的 Mole CLI（`mo`），不是官方的 Mole for Mac。上游是 <https://github.com/tw93/Mole>。

本仓库不附带 Mole 源码，也不会替你执行安装脚本。

## 打开

```bash
make
open build/mole-gui.app
```

`make` 会先跑检查，再用 Swift 编译出 `build/mole-gui.app`。这台机器如果只有 Command Line Tools、没有完整 Xcode，`xcodebuild` 不可用，就用上面的命令。
