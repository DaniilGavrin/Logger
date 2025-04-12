import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppConfig {
  static final AppConfig _instance = AppConfig._internal();
  factory AppConfig() => _instance;
  AppConfig._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? _serverUrl;

  String? get serverUrl => _serverUrl;

  Future<void> initialize() async {
    _serverUrl = await _storage.read(key: 'server_url');
  }

  Future<void> setServerUrl(String url) async {
    _serverUrl = url;
    await _storage.write(key: 'server_url', value: url);
  }

  Future<void> clearServerUrl() async {
    _serverUrl = null;
    await _storage.delete(key: 'server_url');
  }
}