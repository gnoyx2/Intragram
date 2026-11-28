import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/portal_page.dart';

void main() {
  test(
    'inline hashes match the LF text a browser hashes when assets use CRLF',
    () async {
      final page = await buildPortalPage(
        shell:
            '<html>\r\n<style>/*__APP_CSS__*/</style>\r\n'
            '<script>/*__APP_JS__*/</script>\r\n</html>',
        css: 'a{}\r\nb{}\r',
        js: 'let a = 1;\r\nlet b = 2;\r\n',
      );
      expect(page.html, isNot(contains('\r')));
      Future<String> hashOf(String text) async =>
          base64Encode((await Sha256().hash(utf8.encode(text))).bytes);
      expect(
        page.directives,
        contains(
          "script-src 'sha256-${await hashOf('let a = 1;\nlet b = 2;\n')}'",
        ),
      );
      expect(
        page.directives,
        contains("style-src 'sha256-${await hashOf('a{}\nb{}\n')}'"),
      );
    },
  );
}
