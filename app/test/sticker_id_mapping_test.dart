//
//  sticker_id_mapping_test.dart
//
//  The sticker management UI speaks TDLib: it sends `file_id` integers and pack
//  `set_id` integers. 轻聊 stores string ids, and qlPackInt hashes them, so
//  the adapter has to list a pack and match the hash to find the string id
//  again. These tests pin that mapping, because a silent mismatch would make
//  rename/delete/reorder act on the wrong sticker.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/qingliao/ql_engine.dart';

void main() {
  group('pack id hashing is stable and injective enough for lookup', () {
    test('the same id always yields the same int', () {
      expect(qlPackInt('qingliao-basic'), qlPackInt('qingliao-basic'));
    });

    test('different ids yield different ints', () {
      final seen = <int>{};
      for (final id in [
        'qingliao-basic',
        'qingliao-animals',
        'pack-1',
        'pack-2',
        'sticker:abc',
        'sticker:abd',
      ]) {
        expect(seen.add(qlPackInt(id)), isTrue, reason: 'collision on $id');
      }
    });

    test('the hash is never zero, so 0 can mean "no set"', () {
      for (var i = 0; i < 200; i++) {
        expect(qlPackInt('pack-$i'), isNot(0));
      }
    });

    test('sticker ids are encoded with their own prefix', () {
      // The adapter maps a sticker's string id through qlPackInt('sticker:$id'),
      // so the same string with and without the prefix must differ.
      expect(
        qlPackInt('sticker:xyz'),
        isNot(qlPackInt('xyz')),
      );
    });
  });

  group('a file id round-trips to its sticker inside a pack', () {
    // Mirrors what _stickerRef does: build the map the server would return,
    // then find the sticker whose hash matches the integer the UI sent.
    String? findSticker(List<String> stickerIds, int wanted) {
      for (final sid in stickerIds) {
        if (qlPackInt('sticker:$sid') == wanted) return sid;
      }
      return null;
    }

    test('the matching sticker is found', () {
      final ids = ['s1', 's2', 's3'];
      final target = qlPackInt('sticker:s2');
      expect(findSticker(ids, target), 's2');
    });

    test('an unknown id matches nothing', () {
      final ids = ['s1', 's2'];
      expect(findSticker(ids, qlPackInt('sticker:missing')), isNull);
    });

    test('an empty pack matches nothing', () {
      expect(findSticker(const [], qlPackInt('sticker:s1')), isNull);
    });
  });
}
