import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:hirewire/services/socket_services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hirewire/utils/constants.dart';

class ChatScreen extends StatefulWidget {
  final String roomId;
  final String expertName;

  const ChatScreen({super.key, required this.roomId, required this.expertName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  final _storage = const FlutterSecureStorage();
  WebSocketChannel? _channel;
  String? _myUserId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // set the active room tracker so notifications are muted for this room
    CurrentScreenTracker.activeRoomId = widget.roomId;
    _connectToIsolatedRoom();
  }

  @override
  void dispose() {
    // clear it when exiting the chat screen so notifications resume normally!
    CurrentScreenTracker.activeRoomId = null;
    _channel?.sink.close();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _connectToIsolatedRoom() async {
    _myUserId = await _storage.read(key: 'user_id');
    if (_myUserId == null) return;

    try {
      // fetch the historical records from postgres endpoint first
      final historyResponse = await http.get(
        Uri.parse("${API.baseUrl}/chat-history/${widget.roomId}"),
      );

      if (historyResponse.statusCode == 200) {
        final List<dynamic> pastMessages = jsonDecode(historyResponse.body);
        for (var msg in pastMessages) {
          _messages.add({
            "sender_id": msg["sender_id"],
            "content": msg["content"],
            // cast to string to prevent int-vs-string mismatch comparison bugs
            "is_me": msg["sender_id"].toString() == _myUserId.toString(),
          });
        }
      }
    } catch (e) {
      print("Error loading database message history: $e");
    }

    // initialize the live ws channel pool for incoming active text streams
    final wsUrl = Uri.parse("${API.wsUrl}?room_id=${widget.roomId}");
    _channel = WebSocketChannel.connect(wsUrl);

    _channel!.stream.listen((message) {
      final data = jsonDecode(message);
      final senderId = data["sender_id"]?.toString();
      final isNotMe = senderId != _myUserId.toString();

      setState(() {
        _messages.add({
          "sender_id": data["sender_id"],
          "content": data["content"],
          "is_me": !isNotMe,
        });
      });

      // instantly glide down to the newest text block
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }, onError: (err) => print("Socket Channel Error: $err"));

    setState(() {
      _isLoading = false;
    });
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty || _myUserId == null) return;

    final String messageText = _messageController.text.trim();

    final messagePayload = {
      "room_id": widget.roomId,
      "sender_id": _myUserId,
      "content": messageText,
    };

    _channel!.sink.add(jsonEncode(messagePayload));
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.expertName,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = msg["is_me"] == true;

                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isMe
                                ? const Color(0xFF0A66C2)
                                : Colors.grey[200],
                            borderRadius: BorderRadius.circular(16).copyWith(
                              bottomRight: isMe
                                  ? const Radius.circular(0)
                                  : const Radius.circular(16),
                              bottomLeft: isMe
                                  ? const Radius.circular(16)
                                  : const Radius.circular(0),
                            ),
                          ),
                          child: Text(
                            msg["content"] ?? "",
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.black87,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false, // We only care about the bottom screen edge here
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    color: Colors.white,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: InputDecoration(
                              hintText: "Write your message here...",
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              fillColor: Colors.grey[100],
                              filled: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(
                            Icons.send,
                            color: Color(0xFF0A66C2),
                          ),
                          onPressed: _sendMessage,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
