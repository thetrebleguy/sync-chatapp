import 'dashboard_screen.dart';
import 'package:flutter/material.dart';
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
  List<String> _specialties = [
    "UI/UX",
    "DevOps",
    "Game Dev",
    "Web Dev",
    "Frontend",
    "Backend",
    "FullStack",
  ];
  String _selectedSpecialty = "UI/UX";
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

    // print("Step 1: Auth attempt finished. Success = $success");
    if (success) {
      // navigate to dashboard screen
      if (!mounted) return;

      // print("Step 2: Navigating to Dashboard...");
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

  Widget _buildCustomTextField({
    required TextEditingController controller,
    required String labelText,
    bool obscureText = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: const TextStyle(color: Color(0xFF8E9AA8)),
          filled: true,
          fillColor: const Color(0xFF141C33), // Dark Card Surface
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white10),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFF3131), width: 1.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1D), // Deep Charcoal Blue
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // BRAND LOGO TAGLINE
              const Text(
                "REDLINE",
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF3131), // Neon Red Tagline
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "From Red, on Line, to Point",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF8E9AA8),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 40),

              // DYNAMIC HEADER
              Text(
                _isLogin ? "Welcome Back" : "Create Account",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              // FORM FIELDS
              if (!_isLogin) ...[
                _buildCustomTextField(
                  controller: _nameController,
                  labelText: "Full Name",
                ),
                _buildCustomTextField(
                  controller: _phoneController,
                  labelText: "Phone Number",
                ),
              ],

              _buildCustomTextField(
                controller: _emailController,
                labelText: "Email Address",
              ),
              _buildCustomTextField(
                controller: _passwordController,
                labelText: "Password",
                obscureText: true,
              ),

              // CONDITIONAL REGISTRATION DROPDOWNS
              if (!_isLogin) ...[
                const SizedBox(height: 12),
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(canvasColor: const Color(0xFF141C33)),
                  child: DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: InputDecoration(
                      labelText: "Select Role",
                      labelStyle: const TextStyle(color: Color(0xFF8E9AA8)),
                      filled: true,
                      fillColor: const Color(0xFF141C33),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: "student",
                        child: Text(
                          "Student",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      DropdownMenuItem(
                        value: "expert",
                        child: Text(
                          "Expert / Mentor",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                    onChanged: (val) =>
                        setState(() => _selectedRole = val ?? "student"),
                  ),
                ),
                if (_selectedRole == "expert") ...[
                  const SizedBox(height: 12),
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(canvasColor: const Color(0xFF141C33)),
                    child: DropdownButtonFormField<String>(
                      value: _selectedSpecialty,
                      decoration: InputDecoration(
                        labelText: "Specialty Field",
                        labelStyle: const TextStyle(color: Color(0xFF8E9AA8)),
                        filled: true,
                        fillColor: const Color(0xFF141C33),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: _specialties
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedSpecialty = val ?? "Web Dev"),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: const Text(
                      "Working at a company?",
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    activeColor: const Color(0xFFFF3131),
                    value: _isWorking,
                    onChanged: (val) =>
                        setState(() => _isWorking = val ?? false),
                  ),
                  if (_isWorking)
                    _buildCustomTextField(
                      controller: _companyController,
                      labelText: "Company Name",
                    ),
                ],
              ],

              // BUTTON TO CLICK
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _handleAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(
                      0xFFFF3131,
                    ), // Fixed from Purple to Neon Red
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _isLogin ? "Login" : "Register",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(
                  _isLogin
                      ? "Don't have an account? Register"
                      : "Already have an account? Login",
                  style: const TextStyle(color: Color(0xFF8E9AA8)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
