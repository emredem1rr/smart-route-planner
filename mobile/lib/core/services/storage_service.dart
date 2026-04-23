import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _tokenKey  = 'auth_token';
  static const String _nameKey   = 'user_name';
  static const String _emailKey  = 'user_email';
  static const String _userIdKey = 'user_id';

  Future<void> saveSession({
    required String token,
    required String name,
    required String email,
    required int    userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey,  token);
    await prefs.setString(_nameKey,   name);
    await prefs.setString(_emailKey,  email);
    await prefs.setInt   (_userIdKey, userId);
  }

  Future<void> updateName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name);
  }

  Future<String?> getToken() async =>
      (await SharedPreferences.getInstance()).getString(_tokenKey);

  Future<int?> getUserId() async =>
      (await SharedPreferences.getInstance()).getInt(_userIdKey);

  Future<String?> getUserName() async =>
      (await SharedPreferences.getInstance()).getString(_nameKey);

  Future<String?> getUserEmail() async =>
      (await SharedPreferences.getInstance()).getString(_emailKey);

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<String?> getString(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  Future<void> setString(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  Future<void> clearSession() async =>
      (await SharedPreferences.getInstance()).clear();
}