#!/usr/bin/env python3
"""Isolated local Go backend + Android UI/WS acceptance. No deployments/secrets in git."""
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
FLUTTER = '/home/box/sdk/flutter/bin/flutter'
env = dict(os.environ, JAVA_HOME='/home/box/sdk/jdk21', ANDROID_HOME='/home/box/sdk/android', ANDROID_SDK_ROOT='/home/box/sdk/android')
with tempfile.TemporaryDirectory(prefix='qingliao-android-') as work:
    p = Path(work)
    password = secrets.token_urlsafe(24)
    secret = p / 'bootstrap'
    secret.write_text(password)
    secret.chmod(0o600)
    defines = p / 'defines.json'
    defines.write_text(json.dumps({'TEST_SERVER': 'http://10.0.2.2:18112', 'TEST_PASSWORD': password}))
    defines.chmod(0o600)
    binary = p / 'quietchat'
    subprocess.run(['go', 'build', '-o', str(binary), './cmd/server'], cwd=ROOT.parent / 'server', check=True)
    with (p / 'server.log').open('w') as log:
        server = subprocess.Popen([str(binary)], env=dict(env, CHAT_ADDR='127.0.0.1:18112', CHAT_DATA=str(p / 'data'), CHAT_ADMIN_HANDLE='admin', CHAT_ADMIN_PASSWORD_FILE=str(secret)), stdout=log, stderr=log)
        try:
            for _ in range(100):
                if server.poll() is not None:
                    raise RuntimeError('Local Go server failed to start')
                try:
                    with socket.create_connection(('127.0.0.1', 18112), timeout=.2):
                        break
                except OSError:
                    time.sleep(.1)
            subprocess.run([FLUTTER, 'drive', '--driver=test_driver/integration_test.dart', '--target=integration_test/app_test.dart', '-d', os.environ.get('TEST_DEVICE', 'emulator-5584'), f'--dart-define-from-file={defines}'], cwd=ROOT, env=env, check=True)
        finally:
            server.terminate()
            server.wait(timeout=15)
