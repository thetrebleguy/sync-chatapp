import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:hirewire/utils/constants.dart';
import 'package:hirewire/screens/chat_screen.dart';

class ExpertInboxWidget extends StatefulWidget {
  const ExpertInboxWidget({super.key});

  @override
  State<ExpertInboxWidget> createState() => _ExpertInboxWidgetState();
}

class _ExpertInboxWidgetState extends State<ExpertInboxWidget> {
  final _storage = const FlutterSecureStorage();
  List<dynamic> _activeRooms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchActiveRooms();
  }

  Future<void> _fetchActiveRooms() async {
    final myId = await _storage.read(key: 'user_id');
    if (myId == null) return;

    try {
      final response = await http.get(
        Uri.parse("${API.baseUrl}/expert-rooms/$myId"),
      );

      if (response.statusCode == 200) {
        setState(() {
          _activeRooms = jsonDecode(response.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error fetching expert inbox: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_activeRooms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                "No active consultations yet",
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "When students text you, rooms will show up here.",
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap:
          true, // Allows it to sit cleanly inside a SingleChildScrollView
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _activeRooms.length,
      itemBuilder: (context, index) {
        final room = _activeRooms[index];
        final studentName = room['student_name'] ?? "Student";
        final roomId = room['room_id'];

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF0A66C2).withOpacity(0.1),
              foregroundColor: const Color(0xFF0A66C2),
              child: Text(
                studentName[0].toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              studentName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: const Text(
              "Tap to join consultation room",
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ChatScreen(roomId: roomId, expertName: studentName),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
