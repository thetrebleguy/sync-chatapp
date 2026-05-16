import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hirewire/services/socket_services.dart';
import 'package:hirewire/utils/constants.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final storage = const FlutterSecureStorage();
  String _name = "Loading...";
  String _role = "";
  bool _isLoading = true;

  PlatformFile? _selectedFile;
  bool _isUploading = false;
  String? _uploadedFileUrl;

  final SocketService _socketService = SocketService();

  // initial state
  @override
  void initState() {
    super.initState();
    _fetchUserData();

    _socketService.connect();
    _socketService.channel.stream.listen((message) {
      _showNotification(message);
    });
  }

  // shows the snackbar notification
  void _showNotification(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Live Update: $message"),
        backgroundColor: Colors.deepPurple,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _socketService.close();
    super.dispose();
  }

  Future<void> _uploadResume() async {
    if (_selectedFile == null)
      return; // if there is nothing in the file, just return

    // if it exists, then change the state
    setState(() {
      _isUploading = true;
    });

    try {
      // create the multipart req
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${API.baseUrl}/upload'),
      );

      // attach the file bytes safely from mobile memory
      if (_selectedFile!.bytes != null) {
        // if bytes are already in memory (common in some web/desktop pickers)
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            _selectedFile!.bytes!,
            filename: _selectedFile!.name,
          ),
        );
      } else if (_selectedFile!.path != null) {
        // direct path reading for physical Android/iOS devices
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            _selectedFile!.path!,
            filename: _selectedFile!.name,
          ),
        );
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      // if success
      if (response.statusCode == 200) {
        var responseData = json.decode(response.body);
        setState(() {
          _uploadedFileUrl = responseData['file_url'];
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Upload to Cloud Successful")));
        print("Supabase Direct URL: $_uploadedFileUrl");
      } else {
        print("Upload failed with status: ${response.statusCode}");
        print("Error: ${response.body}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Server rejected file structure.")),
        );
      }
    } catch (e) {
      print("Network Error while uploading: $e");
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _fetchUserData() async {
    try {
      final userId = await storage.read(key: 'user_id');

      // check first before sending into the network
      if (userId == null || userId == "null") {
        print("Error: No User ID found in storage!");
        setState(() => _isLoading = false);
        return;
      }

      final response = await http.get(
        Uri.parse("${API.baseUrl}/profile/$userId"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _name = data['user_name'] ?? "No Name";
          _role = data['role'] ?? "user";
          _isLoading = false;
        });
      } else {
        print("Server Error: ${response.statusCode}");
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print("Fetch Error: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickResume() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedFile = result.files.first;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Target selected: ${_selectedFile!.name}")),
      );
    } catch (e) {
      print("Error picking file: $e");
    }
  }

  Widget _buildUploadCard() {
    return Card(
      elevation: 0,
      color: Colors.deepPurple.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.deepPurple.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Submit your CV for Review!",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Upload your resume in PDF format. An expert will review your profile and give you brutal feedback.",
              style: TextStyle(color: Colors.grey[700], fontSize: 14),
            ),
            const SizedBox(height: 16),

            // Render file status panel if item is registered
            if (_selectedFile != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.deepPurple.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf, color: Colors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedFile!.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      "${(_selectedFile!.size / (1024 * 1024)).toStringAsFixed(2)} MB",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            _isUploading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : SizedBox(
                    width: double.infinity,
                    child: _selectedFile == null
                        ? SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _pickResume,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.upload_file),
                              label: const Text("Select PDF Resume"),
                            ),
                          )
                        : Row(
                            children: [
                              // Left Action: Reset / Change selected local file
                              Expanded(
                                flex: 2,
                                child: SizedBox(
                                  height: 48,
                                  child: OutlinedButton.icon(
                                    onPressed: _pickResume,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.grey[700],
                                      side: BorderSide(
                                        color: Colors.grey[400]!,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text("Change"),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Right Action: Ship binary stream up to Go backend
                              Expanded(
                                flex: 3,
                                child: SizedBox(
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    onPressed: _uploadResume,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      elevation: 0,
                                    ),
                                    icon: const Icon(Icons.cloud_upload),
                                    label: const Text("Upload Vault"),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Hirewire ${_role.toUpperCase()}",
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              // <--- FIX 1: Wrap entire layout to make it infinitely scroll-safe
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Hello, $_name! 👋",
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Logged in as: $_role",
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                    const Divider(height: 40),

                    // Active Status Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.description,
                            color: Colors.grey,
                            size: 40,
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Active CV on Review",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  "You have 0 pending reviews.",
                                  style: TextStyle(color: Colors.grey[700]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    if (_role == "student" || _role == "user" || _role == "")
                      _buildUploadCard()
                    else if (_role == "expert") ...[
                      const Text(
                        "Incoming Review Requests",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 3,
                        itemBuilder: (context, index) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(
                                  Icons.picture_as_pdf,
                                  color: Colors.red,
                                ),
                              ),
                              title: Text(
                                "Student Submission #${1024 + index}",
                              ),
                              subtitle: const Text(
                                "Status: Awaiting your analysis",
                              ),
                              trailing: ElevatedButton(
                                onPressed: () {},
                                child: const Text("Review"),
                              ),
                            ),
                          );
                        },
                      ),
                    ],

                    const SizedBox(height: 25),

                    // Test Component Block
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _socketService.sendMessage(
                            "Hello from $_name's Device!",
                          );
                        },
                        icon: const Icon(Icons.bolt),
                        label: const Text("Test Real-Time Connection"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Colors.black, // Dark accent to break up the color
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
