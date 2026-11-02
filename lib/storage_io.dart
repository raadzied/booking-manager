import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> readStoredData() async {
  final directory = await getApplicationSupportDirectory();
  final file =
      File('${directory.path}${Platform.pathSeparator}booking_data.json');
  if (!await file.exists()) return null;
  return file.readAsString();
}

Future<void> writeStoredData(String value) async {
  final directory = await getApplicationSupportDirectory();
  final file =
      File('${directory.path}${Platform.pathSeparator}booking_data.json');
  await file.writeAsString(value, flush: true);
}
