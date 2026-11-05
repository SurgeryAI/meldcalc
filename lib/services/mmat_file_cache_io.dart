import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String?> readCachedFile(String filename) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) return content;
    }
  } catch (_) {}
  return null;
}

Future<void> writeCachedFile(String filename, String content) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content);
  } catch (_) {}
}

Future<void> clearCachedFile(String filename) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {}
}
