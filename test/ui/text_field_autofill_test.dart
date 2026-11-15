import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 웹 엔진은 autofill이 켜진 입력칸을 <form>으로 옮기는데, 그 사이 blur로 편집이 끝나면
// placeElement가 사라진 요소에 focus를 걸다 null check 예외를 냄 (Flutter 3.44 web).
// 메시지·연결 코드·PIN이 브라우저 자동완성과 비밀번호 관리자에 남지 않게 전부 끔
void main() {
  test('every text field opts out of platform autofill', () {
    final field = RegExp(r'(?<![A-Za-z])(?:Cupertino)?TextField\(');
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    // 아래 위젯은 autofill을 끌 수 없거나 따로 챙겨야 함: 쓰려면 이 검사부터 넓힐 것
    final unguarded = RegExp(
      r'(?<![A-Za-z])(?:TextFormField|CupertinoSearchTextField|SearchBar|'
      r'SearchAnchor|Autocomplete|DropdownMenu)\(',
    );
    var fields = 0;
    for (final file in files) {
      final src = file.readAsStringSync();
      expect(unguarded.hasMatch(src), isFalse, reason: file.path);
      for (final match in field.allMatches(src)) {
        fields++;
        final line = '\n'.allMatches(src.substring(0, match.start)).length + 1;
        expect(
          _arguments(src, match.end),
          contains('autofillHints: null'),
          reason: '${file.path}:$line',
        );
      }
    }
    expect(fields, greaterThan(10));
  });
}

String _arguments(String src, int start) {
  var depth = 1;
  for (var i = start; i < src.length; i++) {
    if (src[i] == '(') depth++;
    if (src[i] == ')' && --depth == 0) return src.substring(start, i);
  }
  return src.substring(start);
}
