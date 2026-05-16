import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hirewire/utils/constants.dart';

class AuthService {
  final storage = const FlutterSecureStorage();

  Future<bool> register({
    required String email,
    required String password,
    required String user_name,
    required String phone_number,
    required String role,
    required String current_company,
    required String specialization,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("${API.baseUrl}/register"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": email,
          "password": password,
          "user_name": user_name,
          "phone_number": phone_number,
          "role": role,
          "current_company": current_company,
          "specialization": specialization,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final String? retrievedId = data['user_id'] ?? data['id'];

        print("Server sent back ID: $retrievedId");
        if (retrievedId != null) {
          await storage.write(key: 'user_id', value: retrievedId);
          return true;
        }
      }
      return false;
    } catch (e) {
      print("Register Error: $e");
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    final response = await http.post(
      Uri.parse(API.login),
      body: jsonEncode({"email": email, "password": password}),
      headers: {"Content-Type": "application/json"},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await storage.write(key: 'user_id', value: data['user_id']);
      return true;
    }

    return false;
  }
}
