import 'package:shared_preferences/shared_preferences.dart';

Future<String?> readCachedFile(String filename) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('cached_file_$filename');
  } catch (_) {}
  return null;
}

Future<void> writeCachedFile(String filename, String content) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_file_$filename', content);
  } catch (_) {}
}

Future<void> clearCachedFile(String filename) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_file_$filename');
  } catch (_) {}
}
