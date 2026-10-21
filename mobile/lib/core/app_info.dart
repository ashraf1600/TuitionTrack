/// The version of this build. Keep in step with `version:` in pubspec.yaml
/// (a test checks it). The server's APP_LATEST_VERSION is compared with this
/// to offer an update.
const appVersion = '1.2.0';

/// Compares two "1.2.3" versions: negative when [a] is older than [b].
/// Missing or non-numeric parts count as 0, so "1.2" equals "1.2.0".
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.trim().split(RegExp(r'[.+-]')).take(3).map((p) => int.tryParse(p) ?? 0).toList();
  final x = parts(a);
  final y = parts(b);
  for (var i = 0; i < 3; i++) {
    final left = i < x.length ? x[i] : 0;
    final right = i < y.length ? y[i] : 0;
    if (left != right) return left.compareTo(right);
  }
  return 0;
}
