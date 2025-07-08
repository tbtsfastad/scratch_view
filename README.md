**Feature**

Scratch card component, supports foreground and background layers as any component, supports clicking to scratch the specified area, supports scratching all at once

**功能**

刮刮卡组件，支持前景和背景层为任意组件，支持点击刮开指定区域，支持一次性刮开全部

**Preview**

**预览**

![](https://github.com/tbtsfastad/scratch_view/blob/master/screenshot-20250708-190111.png?raw=true)

**How to use**

**如何使用**

``` dart
SizedBox(
  width: width,
  height: height,
  child: ScratchView(
    cover: Foreground(),
    behind: Background(),
  ),
)
```

**clicking to scratch the specified area**

**点击刮开指定区域**

``` dart
SizedBox(
  width: width,
  height: height,
  child: ScratchRevealRectButtonView(
    child: SomeTapped(),
  ),
)
```
