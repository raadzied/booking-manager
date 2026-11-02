// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

const _storageKey = 'booking_manager_data_v1';

Future<String?> readStoredData() async => html.window.localStorage[_storageKey];

Future<void> writeStoredData(String value) async {
  html.window.localStorage[_storageKey] = value;
}
