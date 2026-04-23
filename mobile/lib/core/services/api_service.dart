import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import '../models/optimize_request_model.dart';
import '../models/route_result_model.dart';

class ApiService {
  static final String _pythonBase = Platform.isAndroid
      ? 'http://10.0.2.2:8000'
      : 'http://172.20.10.2:8000';

  Future<OptimizeResponse> optimize(OptimizeRequest request) async {
    try {
      final response = await http.post(
        Uri.parse('$_pythonBase/optimize'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(request.toJson()),
      ).timeout(const Duration(seconds: 120));

      final json = jsonDecode(response.body);
      return OptimizeResponse.fromJson(json);
    } catch (e) {
      return OptimizeResponse(
        success: false,
        error: 'Optimizasyon servisi bağlantı hatası: $e',
      );
    }
  }
}