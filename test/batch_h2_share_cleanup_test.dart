import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/widgets/task_extras.dart';

/// Sharing an attachment copies it out of memory into a real file. The copy has
/// to go away whatever the share sheet does: a failed share used to leave the
/// file in the temp directory until the OS trimmed the cache.
void main() {
  test('a throwing share still removes the copy', () async {
    String? path;
    await expectLater(
      shareAttachmentFile(
        name: 'chain notes.txt',
        mime: 'text/plain',
        bytes: [1, 2, 3],
        share: (file) async {
          path = file.path;
          expect(
            File(path!).existsSync(),
            isTrue,
            reason: 'the file exists while the share sheet has it',
          );
          expect(file.name, 'chain notes.txt');
          throw const FileSystemException('no share sheet on this device');
        },
      ),
      throwsA(isA<FileSystemException>()),
    );

    final dir = File(path!).parent;
    expect(Directory(dir.path).existsSync(), isFalse);
  });

  test('a successful share also removes the copy', () async {
    String? path;
    await shareAttachmentFile(
      name: '../escape.txt',
      mime: null,
      bytes: [4, 5],
      share: (file) async => path = file.path,
    );

    // A name that walks out of the temp directory is flattened.
    expect(File(path!).parent.path, isNot(contains('..')));
    expect(File(path!).existsSync(), isFalse);
    expect(Directory(File(path!).parent.path).existsSync(), isFalse);
  });
}
