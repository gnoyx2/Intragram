abstract final class BrowserNotifications {
  static bool get supported => false;
  static Future<void> request() async {}
  static void show(
    String title,
    String body,
    String id,
    void Function()? open,
  ) {}
  static void clear() {}
}
