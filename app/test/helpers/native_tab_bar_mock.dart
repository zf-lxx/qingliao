import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Channel contract only. This does not render UIKit or prove glass appearance.
class NativeTabBarMock {
  NativeTabBarMock(this.messenger, {this.supported = true});

  final TestDefaultBinaryMessenger messenger;
  final bool supported;
  final created = <Map<Object?, Object?>>[];
  final updates = <Map<Object?, Object?>>[];
  final channels = <MethodChannel>[];
  int? id;

  Map<Object?, Object?> get latest =>
      updates.isEmpty ? created.last : updates.last;

  void install() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('qingliao/native_tab_bar'),
      (call) async => call.method == 'isSupported' ? supported : null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method != 'create') return null;
      final args = call.arguments as Map;
      final viewId = args['id'] as int;
      final native = args['viewType'] == 'qingliao/native_tab_bar';
      final channel = MethodChannel(
        native
            ? 'qingliao/native_tab_bar/$viewId'
            : 'qingliao/native_glass/$viewId',
      );
      channels.add(channel);
      if (native) {
        id = viewId;
        created.add(
          const StandardMessageCodec().decodeMessage(
                ByteData.sublistView(args['params'] as Uint8List),
              )
              as Map<Object?, Object?>,
        );
      }
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (native && call.method == 'update') {
          updates.add(Map<Object?, Object?>.from(call.arguments as Map));
        }
        return null;
      });
      return null;
    });
  }

  Future<void> send(String method, Object? arguments) async {
    final done = Completer<void>();
    await messenger.handlePlatformMessage(
      'qingliao/native_tab_bar/$id',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) => done.complete(),
    );
    await done.future;
  }

  void dispose() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('qingliao/native_tab_bar'),
      null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  }
}
