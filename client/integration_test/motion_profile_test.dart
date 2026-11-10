import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qingliao/ui/home/chat_list_widgets.dart';
import 'package:qingliao/ui/chat/chat_widgets.dart';
import 'package:qingliao/ui/motion/tg_motion.dart';
import 'package:qingliao/ui/theme/tg_tokens.dart';

// Device/profile-only synthetic motion scene; no server, user data or credentials.
// Results are not a measurement of network/database or a Xiaomi certification.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('motion scene FrameTiming capture (profile device required)', (
    tester,
  ) async {
    final frames = <FrameTiming>[];
    void collect(List<FrameTiming> value) => frames.addAll(value);
    WidgetsBinding.instance.addTimingsCallback(collect);
    addTearDown(() => WidgetsBinding.instance.removeTimingsCallback(collect));
    await tester.pumpWidget(const _Bench());
    await tester.pumpAndSettle();
    frames.clear();
    for (var i = 0; i < 12; i++) {
      await tester.tap(find.text('动画场景0'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('弹出菜单'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 400));
      await tester.pumpAndSettle();
      await tester.flingFrom(const Offset(8, 220), const Offset(300, 0), 1400);
      await tester.pumpAndSettle();
      expect(find.text('动画场景0'), findsOneWidget);
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(
      frames,
      isNotEmpty,
      reason:
          'Use an actual profile/release renderer, not headless widget_test',
    );
    Map<String, Object> stats(List<int> values) {
      values.sort();
      int p(double q) => values[(q * (values.length - 1)).round()];
      return {'p50_us': p(.5), 'p95_us': p(.95), 'p99_us': p(.99)};
    }

    binding.reportData = {
      'scene': 'synthetic_tg_motion_12_cycles',
      'frames': frames.length,
      'build': stats(
        frames.map((f) => f.buildDuration.inMicroseconds).toList(),
      ),
      'raster': stats(
        frames.map((f) => f.rasterDuration.inMicroseconds).toList(),
      ),
      'total': stats(frames.map((f) => f.totalSpan.inMicroseconds).toList()),
      'stage_over_8333us': frames
          .where(
            (f) =>
                math.max(
                  f.buildDuration.inMicroseconds,
                  f.rasterDuration.inMicroseconds,
                ) >
                8333,
          )
          .length,
    };
    debugPrint('MOTION_FRAME_REPORT ${binding.reportData}');
  });
}

class _Bench extends StatelessWidget {
  const _Bench();
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: TgTokens.background,
      colorScheme: const ColorScheme.dark(
        primary: TgTokens.accent,
        surface: TgTokens.card,
      ),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: ListView(
          children: [
            for (var i = 0; i < 40; i++)
              TgChatRow(
                avatar: CircleAvatar(child: Text('$i')),
                title: '动画场景$i',
                preview: '不连接服务器的组件性能场景',
                time: '12:00',
                unread: i % 7,
                onLongPress: () {},
                onTap: () =>
                    Navigator.push(context, TgPageRoute(page: const _Scene())),
              ),
          ],
        ),
      ),
    ),
  );
}

class _Scene extends StatelessWidget {
  const _Scene();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('动效场景'),
      actions: [
        TgIconButton(
          tooltip: '弹出菜单',
          icon: Icons.more_vert_rounded,
          onPressed: () => showTgPopup(
            context: context,
            builder: (context) => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(title: Text('静音')),
                ListTile(title: Text('搜索')),
              ],
            ),
          ),
        ),
      ],
    ),
    body: Stack(
      children: [
        const Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: TgWallpaper(dark: true)),
          ),
        ),
        ListView(
          children: [
            for (var j = 0; j < 30; j++)
              Align(
                alignment: j.isEven
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(16),
                  decoration: ShapeDecoration(
                    color: TgTokens.card,
                    shape: TgBubbleShape(mine: j.isEven),
                  ),
                  child: Text('帧时序样本 $j'),
                ),
              ),
          ],
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: TgGlass(
            margin: EdgeInsets.all(12),
            padding: EdgeInsets.all(20),
            child: Text('浮动输入栏与模糊合成'),
          ),
        ),
      ],
    ),
  );
}
