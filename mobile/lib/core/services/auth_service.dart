import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../models/task_model.dart';
import 'storage_service.dart';

class AuthService {
  final StorageService _storage = StorageService();

  // ── Register ───────────────────────────────────────────────
  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name, 'email': email,
          'phone': phone, 'password': password,
        }),
      ).timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      return {
        'success':               json['success'] ?? false,
        'requires_verification': json['requires_verification'] ?? false,
        'error':                 json['error'],
      };
    } catch (e) {
      return {'success': false, 'error': 'Sunucuya bağlanılamadı.'};
    }
  }

  // ── Verify email ───────────────────────────────────────────
  Future<Map<String, dynamic>> verifyEmail({
    required String email,
    required String code,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/auth/verify-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code}),
      ).timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      if (response.statusCode == 200 && json['success'] == true) {
        await _storage.saveSession(
          token:  json['token'],
          name:   json['user']['name'],
          email:  json['user']['email'],
          userId: json['user']['id'],
        );
        return {'success': true};
      }
      return {'success': false, 'error': json['error'] ?? 'Doğrulama başarısız.'};
    } catch (e) {
      return {'success': false, 'error': 'Sunucuya bağlanılamadı.'};
    }
  }

  // ── Resend verification ────────────────────────────────────
  Future<Map<String, dynamic>> resendVerification(String email) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/auth/resend-verification'),
        headers: {'Content-Type': 'application/json'},
        body:    jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      return {'success': json['success'] ?? false, 'error': json['error']};
    } catch (e) {
      return {'success': false, 'error': 'Sunucuya bağlanılamadı.'};
    }
  }

  // ── Login ──────────────────────────────────────────────────
  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'identifier': identifier, 'password': password}),
      ).timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      if (response.statusCode == 200 && json['success'] == true) {
        await _storage.saveSession(
          token:  json['token'],
          name:   json['user']['name'],
          email:  json['user']['email'],
          userId: json['user']['id'],
        );
        return {'success': true};
      }
      return {'success': false, 'error': json['error'] ?? 'Giriş başarısız.'};
    } catch (e) {
      return {'success': false, 'error': 'Sunucuya bağlanılamadı.'};
    }
  }

  // ── Forgot password ────────────────────────────────────────
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body:    jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      return {'success': json['success'] ?? false, 'error': json['error']};
    } catch (e) {
      return {'success': false, 'error': 'Sunucuya bağlanılamadı.'};
    }
  }

  // ── Reset password ─────────────────────────────────────────
  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String resetCode,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email':        email,
          'reset_code':   resetCode,
          'new_password': newPassword,
        }),
      ).timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      return {'success': json['success'] ?? false, 'error': json['error']};
    } catch (e) {
      return {'success': false, 'error': 'Sunucuya bağlanılamadı.'};
    }
  }

  // ── Get tasks by date ──────────────────────────────────────
  Future<List<TaskModel>> getRemoteTasks({
    String? date,
    String? dateFrom,
    String? dateTo,
    String? status,
  }) async {
    try {
      final token  = await _storage.getToken();
      final params = <String, String>{};
      if (date     != null) params['date']      = date;
      if (dateFrom != null) params['date_from'] = dateFrom;
      if (dateTo   != null) params['date_to']   = dateTo;
      if (status   != null) params['status']    = status;
      final uri = Uri.parse('${ApiConstants.baseUrl}/tasks').replace(
        queryParameters: params.isNotEmpty ? params : null,
      );

      final response = await http.get(uri, headers: {
        'Content-Type':  'application/json',
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 30));

      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      final json = jsonDecode(response.body);
      if (response.statusCode == 200 && json['success'] == true) {
        return (json['tasks'] as List)
            .map((t) => TaskModel.fromJson(t))
            .toList();
      }
      return [];
    } catch (e) {
      print('=== GET TASKS ERROR: $e ===');
      return [];
    }
  }

  // ── Get task dates for calendar ────────────────────────────
  Future<List<dynamic>> getTaskDates({
    required int month,
    required int year,
  }) async {
    try {
      final token = await _storage.getToken();
      final uri   = Uri.parse('${ApiConstants.baseUrl}/tasks/dates').replace(
        queryParameters: {
          'month': month.toString(),
          'year':  year.toString(),
        },
      );

      final response = await http.get(uri, headers: {
        'Content-Type':  'application/json',
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      if (response.statusCode == 200 && json['success'] == true) {
        return json['dates'] as List;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ── Save task ──────────────────────────────────────────────
  Future<bool> saveRemoteTask(TaskModel task) async {
    try {
      final token    = await _storage.getToken();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/tasks'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(task.toJson()),
      ).timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      return json['success'] == true;
    } catch (e) {
      return false;
    }
  }

  // ── Update task ────────────────────────────────────────────
  Future<bool> updateRemoteTask(TaskModel task) async {
    try {
      final token    = await _storage.getToken();
      final response = await http.put(
        Uri.parse('${ApiConstants.baseUrl}/tasks/${task.id}'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(task.toJson()),
      ).timeout(const Duration(seconds: 30));

      print('[UpdateTask] status: ${response.statusCode}');
      print('[UpdateTask] body: ${response.body}');

      final json = jsonDecode(response.body);
      return json['success'] == true;
    } catch (e) {
      print('[UpdateTask] error: $e');
      return false;
    }
  }

  // ── Update task status ─────────────────────────────────────
  Future<bool> updateTaskStatus(int taskId, String status) async {
    try {
      final token    = await _storage.getToken();
      final response = await http.patch(
        Uri.parse('${ApiConstants.baseUrl}/tasks/$taskId/status'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'status': status}),
      ).timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      return json['success'] == true;
    } catch (e) {
      return false;
    }
  }

  // ── Delete task ────────────────────────────────────────────
  Future<bool> deleteRemoteTask(int taskId, {bool deleteAll = false}) async {
    try {
      final token    = await _storage.getToken();
      final url      = deleteAll
          ? Uri.parse('${ApiConstants.baseUrl}/tasks/$taskId?delete_all=true')
          : Uri.parse('${ApiConstants.baseUrl}/tasks/$taskId');
      final response = await http.delete(
        url,
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      return json['success'] == true;
    } catch (e) {
      return false;
    }
  }

  // ── Get profile ────────────────────────────────────────────
  Future<Map<String, dynamic>> getProfile() async {
    try {
      final token    = await _storage.getToken();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/profile'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      if (response.statusCode == 200 && json['success'] == true) {
        return {'success': true, 'user': json['user']};
      }
      return {'success': false, 'error': json['error']};
    } catch (e) {
      return {'success': false, 'error': 'Sunucuya bağlanılamadı.'};
    }
  }

  Future<Map<String, dynamic>> updateProfile({
    required String name,
    required String phone,
  }) async {
    try {
      final token    = await _storage.getToken();
      final response = await http.put(
        Uri.parse('${ApiConstants.baseUrl}/profile'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'name': name, 'phone': phone}),
      ).timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      if (json['success'] == true) {
        await _storage.updateName(name);
      }
      return {
        'success': json['success'] ?? false,
        'error':   json['error'],
      };
    } catch (e) {
      return {'success': false, 'error': 'Sunucuya bağlanılamadı.'};
    }
  }

  // ── Change password ────────────────────────────────────────
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final token    = await _storage.getToken();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/profile/change-password'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password':     newPassword,
        }),
      ).timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      return {'success': json['success'] ?? false, 'error': json['error']};
    } catch (e) {
      return {'success': false, 'error': 'Sunucuya bağlanılamadı.'};
    }
  }

  // ── Delete account ─────────────────────────────────────────
  Future<Map<String, dynamic>> deleteAccount(String password) async {
    try {
      final token    = await _storage.getToken();
      final response = await http.delete(
        Uri.parse('${ApiConstants.baseUrl}/profile'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'password': password}),
      ).timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      if (json['success'] == true) await _storage.clearSession();
      return {'success': json['success'] ?? false, 'error': json['error']};
    } catch (e) {
      return {'success': false, 'error': 'Sunucuya bağlanılamadı.'};
    }
  }

  // ── Logout ─────────────────────────────────────────────────
  Future<void> logout() async {
    await _storage.clearSession();
  }
}