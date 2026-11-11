# 资源许可与 Android 字体策略

Android 客户端**不打包任何自带正文字体或 emoji 字体**，使用手机系统字体（如小米 MiSans / Noto CJK）与系统彩色表情；避免额外约 24 MB 字体压缩数据。

Linux 桌面通过 `lib/ui/theme/desktop_fonts.dart` 从系统路径加载 Noto CJK 与 Noto Color Emoji，注册为 ChatSans/ChatEmoji。测试复用同一加载器。这些文件不在 pubspec、不在 APK；Android 仍用系统字体。

Noto 字体遵循 SIL OFL 1.1；历史引用的许可文本保留在 `assets/fonts/CJK_LICENSE.txt`、`EMOJI_LICENSE.txt`。
上游：https://github.com/notofonts/noto-cjk 、https://github.com/googlefonts/noto-emoji

`assets/stickers/sun.json`、`moon.json`、`mint.json` 沿用动效 demo 的原创几何笑脸，非 Telegram 素材；CC0 1.0。本客户端当前未启用动态贴纸发送/播放，也未将这些文件列入发布资源。
https://creativecommons.org/publicdomain/zero/1.0/legalcode
