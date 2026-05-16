// import 'dart:convert';
import 'dashboard_screen.dart';
import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import '../utils/constants.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  final _authService = AuthService();

  // for the REGISTERATION
  String _selectedRole = "student";
  List<String> _specialties = ["2D Art", "3D Modelling", "Game Dev", "Web Dev"];
  String _selectedSpecialty = "Web Dev";
  bool _isWorking = false;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _companyController = TextEditingController();

  void _handleAuth() async {
    final email = _emailController.text;
    final password = _passwordController.text;

    bool success;
    if (_isLogin) {
      success = await _authService.login(email, password);
    } else {
      success = await _authService.register(
        email: email,
        password: password,
        user_name: _nameController.text,
        phone_number: _phoneController.text,
        role: _selectedRole.toLowerCase(),
        current_company: _isWorking ? _companyController.text : "None",
        specialization: _selectedSpecialty,
      );
    }

    print("Step 1: Auth attempt finished. Success = $success");
    if (success) {
      // navigate to dashboard screen
      if (!mounted) return;

      print("Step 2: Navigating to Dashboard...");
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
    } else {
      // show error in a snack bar
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Authentication Failed!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 100),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _isLogin ? "Welcome Back" : "Create Account",
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              // EMAIL
              const SizedBox(height: 40),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: "Email",
                  border: OutlineInputBorder(),
                ),
              ),

              // PASSWORD
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Password",
                  border: OutlineInputBorder(),
                ),
              ),

              // NEW-REGISTER ACCOUNT ONLY
              if (!_isLogin) ...[
                // user name
                const SizedBox(height: 20),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: "Full Name",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),

                // phone number
                const SizedBox(height: 20),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: "Phone Number",
                    prefixText: "+62 ",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                // role selection
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  items: ["student", "expert"]
                      .map(
                        (role) => DropdownMenuItem(
                          value: role,
                          child: Text(role == "student" ? "Student" : "Expert"),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setState(() => _selectedRole = val!),
                  decoration: const InputDecoration(
                    labelText: "Select Role",
                    border: OutlineInputBorder(),
                  ),
                ),

                // Specialization
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("My Specialty:"),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  children: _specialties.map((spec) {
                    return ChoiceChip(
                      label: Text(spec),
                      selected: _selectedSpecialty == spec,
                      onSelected: (selected) =>
                          setState(() => _selectedSpecialty = spec),
                    );
                  }).toList(),
                ),

                // Expert-only Company field
                if (_selectedRole == "Expert") ...[
                  const SizedBox(height: 10),
                  SwitchListTile(
                    title: const Text("Working at a company?"),
                    value: _isWorking,
                    onChanged: (val) => setState(() => _isWorking = val),
                  ),
                  if (_isWorking)
                    TextField(
                      controller: _companyController,
                      decoration: const InputDecoration(
                        labelText: "Company Name",
                        border: OutlineInputBorder(),
                      ),
                    ),
                ],
              ],

              // BUTTON TO CLICK
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _handleAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_isLogin ? "Login" : "Register"),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(
                  _isLogin
                      ? "Don't have an account? Register"
                      : "Already have an account? Login",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
