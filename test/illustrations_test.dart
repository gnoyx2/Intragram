import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/widgets/empty_state_art.dart';
import 'package:intragram/widgets/illustration.dart';

void main() {
  test(
    'every file in assets/illustrations matches IllustrationName 1-to-1',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/illustrations/'));

      final dir = Directory('assets/illustrations');
      expect(dir.existsSync(), isTrue);

      final onDisk =
          dir
              .listSync()
              .whereType<File>()
              .map((f) => f.uri.pathSegments.last)
              .where((name) => !name.startsWith('.'))
              .toList()
            ..sort();
      final wired = IllustrationName.values.map((e) => e.fileName).toList()
        ..sort();
      expect(onDisk, wired);
    },
  );

  test(
    'every illustration PNG is 480x480 with RGBA transparency (color type 6)',
    () {
      const pngSignature = <int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ];
      for (final item in IllustrationName.values) {
        final file = File(item.assetPath);
        expect(file.existsSync(), isTrue, reason: item.assetPath);
        final bytes = file.readAsBytesSync();
        expect(bytes.length, greaterThan(32), reason: item.fileName);
        expect(bytes.sublist(0, 8), pngSignature, reason: item.fileName);
        expect(
          String.fromCharCodes(bytes.sublist(12, 16)),
          'IHDR',
          reason: item.fileName,
        );
        final header = ByteData.sublistView(bytes);
        final width = header.getUint32(16);
        final height = header.getUint32(20);
        final colorType = bytes[25];
        expect(
          (width, height),
          (480, 480),
          reason: '${item.fileName} dimensions',
        );
        expect(
          colorType,
          6,
          reason: '${item.fileName} must be RGBA (color type 6)',
        );
      }
    },
  );

  test('non-radar EmptyStateArt variants map to distinct illustrations', () {
    final mapped = <IllustrationName>{};
    for (final art in EmptyStateArt.values) {
      final ill = art.illustration;
      if (art == EmptyStateArt.radar) {
        expect(ill, isNull);
      } else {
        expect(ill, isNotNull, reason: art.name);
        expect(mapped.add(ill!), isTrue, reason: 'duplicate ${ill.name}');
      }
    }
  });

  testWidgets('Illustration and BrandPigeonIcon exclude semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              BrandPigeonIcon(size: 30),
              Illustration(IllustrationName.chatBubbles, size: 120),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final labels = tester.semantics
        .simulatedAccessibilityTraversal()
        .map((n) => n.label)
        .where((l) => l.isNotEmpty)
        .toList();
    expect(labels, isEmpty);
    handle.dispose();
  });
}
