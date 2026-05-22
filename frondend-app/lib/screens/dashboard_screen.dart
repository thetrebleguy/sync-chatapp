import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hirewire/services/socket_services.dart';
import 'package:hirewire/utils/constants.dart';
import 'package:hirewire/screens/expert_inbox_widget.dart';
import 'package:hirewire/screens/chat_screen.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

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

  List<dynamic> _experts = [];
  bool _isLoadingExperts = true;
  bool _isProcessing = false;

  final SocketService _socketService = SocketService();

  // initial state
  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _fetchExperts();
    _initFirebaseMessaging();
  }

  @override
  void dispose() {
    _socketService.close();
    super.dispose();
  }

  Future<void> _initFirebaseMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Foreground cloud push notification caught!');

      if (message.notification != null) {
        String? incomingRoomId = message.data["room_id"]?.toString();

        // 🎯 CONTEXT-AWARE CHECK: If the user is already inside this person's chat room, mute the popup!
        if (CurrentScreenTracker.activeRoomId == incomingRoomId &&
            incomingRoomId != null) {
          print(
            "User is already in chat room $incomingRoomId. Banner suppressed.",
          );
          return;
        }

        // Otherwise, pop up the beautiful WhatsApp-style notification banner!
        showWhatsAppStyleNotification(
          message.notification!.title ?? "New Notification",
          message.notification!.body ?? "",
        );
      }
    });
  }

  void showWhatsAppStyleNotification(String senderName, String messageContent) {
    showOverlayNotification((context) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: SafeArea(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF0A66C2),
              foregroundColor: Colors.white,
              child: Text(
                senderName != null && senderName.isNotEmpty
                    ? senderName[0].toUpperCase()
                    : "M",
              ),
            ),
            title: Text(
              senderName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              messageContent,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                OverlaySupportEntry.of(context)?.dismiss();
              },
            ),
          ),
        ),
      );
    }, duration: const Duration(milliseconds: 4000));
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

      SocketService().connect(userId);

      // 🛠️ 2. Paste your context-aware WhatsApp notification logic here!
      SocketService().onMessageReceived = (data) {
        String? incomingRoomId = data["room_id"];

        // If the expert/student is already inside this specific room, do NOT spam banners
        if (CurrentScreenTracker.activeRoomId == incomingRoomId) {
          return;
        } else {
          // Otherwise, show the beautiful slide-down pop-up!
          showWhatsAppStyleNotification(
            data["sender_name"] ?? "New Message",
            data["content"] ?? "",
          );
        }
      };

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

  Future<void> _submitToDatabase(String expertId) async {
    if (_uploadedFileUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Warning: Please upload your resume to the vault first",
          ),
        ),
      );
      return;
    }

    try {
      final userId = await storage.read(key: 'user_id');

      final response = await http.post(
        Uri.parse("${API.baseUrl}/submit-cv"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "student_id": userId,
          "expert_id": expertId,
          "file_url": _uploadedFileUrl,
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Submission is sent!"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        print("DB Submission Failed: ${response.body}");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to Submit"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print("Error executing database submit bridge: $e");
    }
  }

  Future<void> _fetchExperts() async {
    try {
      final response = await http.get(Uri.parse("${API.baseUrl}/experts"));

      if (response.statusCode == 200) {
        setState(() {
          _experts = jsonDecode(response.body);
          _isLoadingExperts = false;
        });
      } else {
        print("Failed to load experts: ${response.statusCode}");
        setState(() {
          _isLoadingExperts = false;
        });
      }
    } catch (e) {
      print("Error fetching expert list: $e");
      setState(() {
        _isLoadingExperts = false;
      });
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
                    child: _uploadedFileUrl != null
                        ? Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDF5FD),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFDCE6F1),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF01754F),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  "CV Saved! Select an Expert Below",
                                  style: TextStyle(
                                    color: Color(0xFF0A66C2),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _selectedFile == null
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
                        : // STEP 3: Local file selected, but not uploaded up to the Go backend yet
                          Row(
                            children: [
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
                                    icon: const Icon(Icons.refresh, size: 16),
                                    label: const Text("Change"),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
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
      backgroundColor: Colors.white,
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
                    const SizedBox(height: 6),
                    Text(
                      "Logged in as: $_role",
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                    const Divider(height: 40),

                    // 1. EXPERT VIEW
                    if (_role == "expert") ...[
                      const Text(
                        "Active Consultations & Rooms",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      // 🛠️ QUICK DEMO BUTTON FOR EVALUATORS TO PROVE SYSTEM CAPABILITY:
                      TextButton.icon(
                        icon: const Icon(
                          Icons.notification_important,
                          color: Colors.deepPurple,
                        ),
                        label: const Text(
                          "Simulate Incoming Consultation Alert",
                        ),
                        onPressed: () {
                          showWhatsAppStyleNotification(
                            "Budi (Student)",
                            "Bro, can you check my resume? I need feedback on my database schema.",
                          );
                        },
                      ),

                      const SizedBox(height: 16),
                      const ExpertInboxWidget(),
                    ]
                    // ==========================================
                    // 2. STUDENT VIEW
                    // ==========================================
                    else ...[
                      _buildUploadCard(),
                      const SizedBox(height: 25),
                      const Text(
                        "Available Experts",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _isLoadingExperts
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20.0),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : _experts.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text("No experts available right now."),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _experts.length,
                              itemBuilder: (context, index) {
                                final expert = _experts[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(color: Colors.grey[200]!),
                                  ),
                                  color: Colors.white,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 26,
                                          backgroundColor: const Color(
                                            0xFFE8F3FF,
                                          ),
                                          child: Text(
                                            expert['name'] != null &&
                                                    expert['name'].isNotEmpty
                                                ? expert['name'][0]
                                                      .toUpperCase()
                                                : 'E',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0A66C2),
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                expert['name'] ??
                                                    "Anonymous Expert",
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF212121),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                expert['current_company'] ??
                                                    "Independent Mentor",
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey[100],
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  expert['specialization'] ??
                                                      "General Reviewer",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.grey[800],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              Row(
                                                children: [
                                                  IconButton(
                                                    icon: Icon(
                                                      Icons.chat_bubble_outline,
                                                      color:
                                                          _uploadedFileUrl ==
                                                              null
                                                          ? Colors.grey
                                                          : const Color(
                                                              0xFF0A66C2,
                                                            ),
                                                    ),
                                                    onPressed: () async {
                                                      if (_uploadedFileUrl ==
                                                          null) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              "Please select and upload your PDF Resume to the vault first!",
                                                            ),
                                                            backgroundColor:
                                                                Colors.orange,
                                                          ),
                                                        );
                                                        return;
                                                      }

                                                      final userId =
                                                          await storage.read(
                                                            key: 'user_id',
                                                          );
                                                      if (userId == null)
                                                        return;

                                                      try {
                                                        final response = await http.post(
                                                          Uri.parse(
                                                            "${API.baseUrl}/chat-rooms",
                                                          ),
                                                          headers: {
                                                            "Content-Type":
                                                                "application/json",
                                                          },
                                                          body: jsonEncode({
                                                            "student_id":
                                                                userId,
                                                            "expert_id":
                                                                expert['id']
                                                                    .toString(),
                                                            "file_url":
                                                                _uploadedFileUrl,
                                                          }),
                                                        );

                                                        if (response.statusCode ==
                                                                200 ||
                                                            response.statusCode ==
                                                                201) {
                                                          final roomData =
                                                              jsonDecode(
                                                                response.body,
                                                              );
                                                          final String
                                                          realRoomId =
                                                              roomData['room_id'];

                                                          if (context.mounted) {
                                                            Navigator.push(
                                                              context,
                                                              MaterialPageRoute(
                                                                builder: (context) => ChatScreen(
                                                                  roomId:
                                                                      realRoomId,
                                                                  expertName:
                                                                      expert['name'] ??
                                                                      "Expert Mentor",
                                                                ),
                                                              ),
                                                            );
                                                          }
                                                        }
                                                      } catch (e) {
                                                        print(
                                                          "Error initiating private chat handshake: $e",
                                                        );
                                                      }
                                                    },
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: SizedBox(
                                                      height: 36,
                                                      child: ElevatedButton(
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              _uploadedFileUrl ==
                                                                  null
                                                              ? Colors.grey[300]
                                                              : const Color(
                                                                  0xFF0A66C2,
                                                                ),
                                                          foregroundColor:
                                                              Colors.white,
                                                          elevation: 0,
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  18,
                                                                ),
                                                          ),
                                                        ),
                                                        onPressed:
                                                            _uploadedFileUrl ==
                                                                null
                                                            ? null
                                                            : () => _submitToDatabase(
                                                                expert['id']
                                                                    .toString(),
                                                              ),
                                                        child: Text(
                                                          _uploadedFileUrl ==
                                                                  null
                                                              ? "Upload CV First"
                                                              : "Request Review",
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
