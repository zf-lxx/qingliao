import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/update/release_feed.dart';

void main() {
  test('release tags extract 轻聊 versions, not mithka prefixes', () {
    expect(releaseVersionFromTag('mithka-p2-0.3.2'), '0.3.2');
    expect(releaseVersionFromTag('mithka-p3-0.3.3'), '0.3.3');
    expect(releaseVersionFromTag('v0.3.3'), '0.3.3');
    expect(releaseVersionFromTag('0.3.2'), '0.3.2');
    expect(compareReleaseVersions('mithka-p2-0.3.2', '0.3.2'), 0);
    expect(compareReleaseVersions('mithka-p3-0.3.3', '0.3.2'), greaterThan(0));
    expect(compareReleaseVersions('0.3.2', '1.11.8'), lessThan(0));
  });

  test('parseReleaseInfo uses the trailing version, not the tag prefix', () {
    final info = parseReleaseInfo('''
{
  "tag_name": "mithka-p2-0.3.2",
  "assets": [
    {
      "name": "qingliao-mithka-p2-arm64.apk",
      "browser_download_url": "https://github.com/zf-lxx/qingliao/releases/download/mithka-p2-0.3.2/qingliao-mithka-p2-arm64.apk",
      "size": 37615140
    }
  ]
}
''');
    expect(info, isNotNull);
    expect(info!.version, '0.3.2');
    expect(info.assets, hasLength(1));
    expect(releasesPageUrl, 'https://github.com/zf-lxx/qingliao/releases');
  });
}
