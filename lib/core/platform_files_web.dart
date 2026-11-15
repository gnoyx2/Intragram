import 'dart:async';
import 'dart:convert';
import 'dart:io' show FileSystemException, OSError;
import 'dart:js_interop';

import 'package:web/web.dart' as web;

export 'dart:io' show FileSystemException, OSError;

// Only native app-private JSON files use this browser backend. Received files
// use an explicit browser download and are never persisted through this cache.
abstract final class BrowserPrivateFiles {
  static web.IDBDatabase? _database;
  static final _files = <String, String>{};
  static final _versions = <String, int>{};

  static Future<void> initialize() async {
    _database?.close();
    _files.clear();
    _versions.clear();
    final request = web.window.indexedDB.open('intragram-native-vault-v1', 1);
    request.onupgradeneeded = ((web.Event _) {
      final db = request.result as web.IDBDatabase;
      db.createObjectStore('files');
    }).toJS;
    _database = await _result(request) as web.IDBDatabase;
    final store = _database!.transaction('files'.toJS).objectStore('files');
    final keyRequest = _result(store.getAllKeys());
    final valueRequest = _result(store.getAll());
    final keys = await keyRequest as JSArray<JSAny?>;
    final values = await valueRequest as JSArray<JSAny?>;
    for (var i = 0; i < keys.length; i++) {
      final path = (keys[i] as JSString).toDart;
      final record = jsonDecode((values[i] as JSString).toDart) as Map;
      if (record['data'] != null) _files[path] = record['data'] as String;
      _versions[path] = record['revision'] as int;
    }
  }

  static Future<JSAny?> _result(web.IDBRequest request) {
    final result = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => result.complete(request.result)).toJS;
    request.onerror = ((web.Event _) => result.completeError(
      const FileSystemException('Browser storage is unavailable'),
    )).toJS;
    return result.future;
  }

  static Future<void> _commit(String path, String? data) async {
    final db = _database;
    if (db == null) {
      throw const FileSystemException('Browser storage is closed');
    }
    final expected = _versions[path] ?? 0;
    final tx = db.transaction('files'.toJS, 'readwrite');
    final done = Completer<void>();
    Object? failure;
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx.onabort = ((web.Event _) => done.completeError(
      failure ?? const FileSystemException('Browser storage write failed'),
    )).toJS;
    tx.onerror = ((web.Event _) {}).toJS;
    final store = tx.objectStore('files');
    final request = store.get(path.toJS);
    request.onsuccess = ((web.Event _) {
      final raw = request.result;
      final revision = raw.isUndefinedOrNull
          ? 0
          : (jsonDecode((raw as JSString).toDart) as Map)['revision'] as int;
      if (revision != expected) {
        failure = const FileSystemException(
          'Another tab changed this archive; reload before saving',
        );
        tx.abort();
        return;
      }
      // A tombstone makes a stale tab fail instead of resurrecting an erased vault.
      store.put(
        jsonEncode({'revision': expected + 1, 'data': data}).toJS,
        path.toJS,
      );
    }).toJS;
    await done.future;
    if (data == null) {
      _files.remove(path);
      _versions[path] = expected + 1;
    } else {
      _files[path] = data;
      _versions[path] = expected + 1;
    }
  }
}

class File {
  File(this.path);
  final String path;
  Directory get parent => Directory(path.substring(0, path.lastIndexOf('/')));
  bool existsSync() => BrowserPrivateFiles._files.containsKey(path);
  Future<String> readAsString({Encoding encoding = utf8}) async {
    final value = BrowserPrivateFiles._files[path];
    if (value == null) {
      throw FileSystemException(
        'File is absent',
        path,
        const OSError('not found', 2),
      );
    }
    return value;
  }

  Future<File> writeAsString(
    String value, {
    bool flush = false,
    Encoding encoding = utf8,
  }) async {
    if (path.endsWith('.tmp')) {
      BrowserPrivateFiles._files[path] = value;
    } else {
      await BrowserPrivateFiles._commit(path, value);
    }
    return this;
  }

  Future<File> rename(String target) async {
    final value = await readAsString();
    await BrowserPrivateFiles._commit(target, value);
    BrowserPrivateFiles._files.remove(path);
    return File(target);
  }

  Future<File> delete({bool recursive = false}) async {
    if (!existsSync()) {
      throw FileSystemException(
        'File is absent',
        path,
        const OSError('not found', 2),
      );
    }
    if (path.endsWith('.tmp')) {
      BrowserPrivateFiles._files.remove(path);
    } else {
      await BrowserPrivateFiles._commit(path, null);
    }
    return this;
  }
}

class Directory {
  Directory(this.path);
  final String path;
  Future<Directory> create({bool recursive = false}) async => this;
}
