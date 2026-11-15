part of 'browser_received_files_web.dart';

// 탭마다 OPFS 하위 폴더를 쓰고 탭이 살아 있는 동안 Web Lock을 쥠. 탭이 닫히거나 죽으면 브라우저가 잠금을 풀어
// 다음에 연 탭이 그 폴더(저장 안 한 수신 파일)를 지움. 잠금이 없는 브라우저는 OPFS 대신 메모리로 받음
final String _session = List<String>.generate(
  8,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
Future<bool>? _sessionLock;

Future<web.FileSystemDirectoryHandle?> _sessionDir() async {
  final root = await _tempRoot(create: true);
  if (root == null || !await (_sessionLock ??= _holdSessionLock())) {
    return null;
  }
  return root
      .getDirectoryHandle(
        _session,
        web.FileSystemGetDirectoryOptions(create: true),
      )
      .toDart;
}

Future<bool> _holdSessionLock() {
  final locks = _SafeNavigator(web.window.navigator).locks;
  final granted = Completer<bool>();
  if (locks == null) return Future.value(false);
  // 끝나지 않는 약속을 돌려줘서 페이지가 끝날 때까지 잠금을 쥠
  final hold = ((JSAny? _) {
    granted.complete(true);
    return Completer<void>().future.toJS;
  }).toJS;
  unawaited(
    locks
        .request('${BrowserReceivedFiles.tempDirName}-$_session', hold)
        .toDart
        .then<void>(
          (_) {},
          onError: (Object _) {
            if (!granted.isCompleted) granted.complete(false);
          },
        ),
  );
  return granted.future;
}

// 시작 때 잠금이 풀린(주인 탭이 끝난) 폴더와 옛 형식 파일만 지움. 살아 있는 다른 탭의 폴더는 건드리지 않음
Future<void> _sweepStaleTemp() async {
  final locks = _SafeNavigator(web.window.navigator).locks;
  final root = await _tempRoot(create: false);
  if (locks == null || root == null) return;
  final names = <String>[];
  try {
    final entries = root.callMethod<JSObject>('keys'.toJS);
    while (true) {
      final step = await entries
          .callMethod<JSPromise<JSObject>>('next'.toJS)
          .toDart;
      if (step.getProperty<JSBoolean?>('done'.toJS)?.toDart ?? true) break;
      names.add(step.getProperty<JSString>('value'.toJS).toDart);
    }
  } on Object {
    return;
  }
  for (final name in names.where((name) => name != _session)) {
    final remove =
        ((JSAny? lock) => lock == null
                ? null
                : root
                      .removeEntry(
                        name,
                        web.FileSystemRemoveOptions(recursive: true),
                      )
                      .toDart
                      .then<JSAny?>((_) => null)
                      .toJS)
            .toJS;
    try {
      await locks
          .request(
            '${BrowserReceivedFiles.tempDirName}-$name',
            web.LockOptions(ifAvailable: true),
            remove,
          )
          .toDart;
    } on Object {
      // 다음 시작 때 다시 시도함
    }
  }
}

Future<web.FileSystemDirectoryHandle?> _tempRoot({required bool create}) async {
  final storage = _SafeNavigator(web.window.navigator).storage;
  if (storage == null || storage.getDirectory == null) return null;
  try {
    final root = await storage.callGetDirectory().toDart;
    return await root
        .getDirectoryHandle(
          BrowserReceivedFiles.tempDirName,
          web.FileSystemGetDirectoryOptions(create: create),
        )
        .toDart;
  } on Object {
    return null;
  }
}
