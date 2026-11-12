//
//  ql_foreground_sync.dart — Android foreground service that keeps the
//  existing WebSocket process alive. This is not vendor push.
//

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channelName = 'qingliao/foreground_sync';
const _prefKey = 'qingliao.foreground_sync.enabled.v1';

class QlForegroundSync {
  QlForegroundSync._();

  static const _channel = MethodChannel(_channelName);
  static bool get isAndroid => Platform.isAndroid;

  static Future<bool> isEnabled() async {
    if (!isAndroid) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    if (value) {
      await start();
    } else {
      await stop();
    }
  }

  static Future<bool> start() async {
    if (!isAndroid) return false;
    if (!await isEnabled()) return false;
    try {
      final result = await _channel.invokeMethod<bool>('start');
      return result == true;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Ignore: the service may already be stopped.
    }
  }

  static Future<bool> isRunning() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isRunning') == true;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> openBatterySettings() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openBatterySettings');
    } on PlatformException {
      // No-op when the settings page cannot be opened.
    }
  }

  static Future<void> openNotificationSettings() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openNotificationSettings');
    } on PlatformException {
      // No-op.
    }
  }
}
