import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:hirewire/services/socket_services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
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
  String? _uploadedDocUrl;

  String? _lastProcessedMessage;
  DateTime? _lastProcessedTime;

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
    final userId = await _storage.read(key: 'user_id');
    if (userId == null) return;

    final String standardizedUserId = userId.toString().trim();

    setState(() {
      _myUserId = standardizedUserId;
    });

    try {
      // fetch the historical records from postgres endpoint first
      final historyResponse = await http.get(
        Uri.parse("${API.baseUrl}/chat-history/${widget.roomId}"),
      );

      if (historyResponse.statusCode == 200) {
        final List<dynamic> pastMessages = jsonDecode(historyResponse.body);

        setState(() {
          _messages.clear(); // Clear cached/stale iterations
          for (var msg in pastMessages) {
            _messages.add({
              "sender_id": msg["sender_id"],
              "content": msg["content"],
              "is_me": msg["sender_id"].toString().trim() == standardizedUserId,
            });
          }
        });
      }

      final roomResponse = await http.get(
        Uri.parse("${API.baseUrl}/rooms/${widget.roomId}"),
      );

      if (roomResponse.statusCode == 200) {
        final Map<String, dynamic> roomData = jsonDecode(roomResponse.body);
        setState(() {
          _uploadedDocUrl = roomData["file_url"];
        });
      }
    } catch (e) {
      print("Error loading database message history: $e");
    }

    // initialize the live ws channel pool for incoming active text streams
    final wsUrl = Uri.parse("${API.wsUrl}?room_id=${widget.roomId}");
    _channel = WebSocketChannel.connect(wsUrl);

    _channel!.stream.listen((message) {
      final data = jsonDecode(message);
      final incomingSenderId = data["sender_id"]?.toString().trim();

      if (incomingSenderId == standardizedUserId) {
        return; // Absolute block for sender echo replication loop
      }

      // 💡 Clean state updates without needing temporary time delays
      setState(() {
        _messages.add({
          "sender_id": data["sender_id"],
          "content": data["content"],
          "is_me": false,
        });
      });

      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }, onError: (err) => print("Socket Channel Error: $err"));

    setState(() {
      _isLoading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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

    setState(() {
      _messages.add({
        "sender_id": _myUserId,
        "content": messageText,
        "is_me": true,
      });
    });

    _messageController.clear();

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _openDocumentViewer(BuildContext context, String url) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Color(0xFF141C33), // Dark Surface Card Layer
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.picture_as_pdf,
                          color: Color(0xFFFF3131),
                        ), // RedLine Red Accent
                        SizedBox(width: 8),
                        Text(
                          "Live Document Portfolio Preview",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white10),
              Expanded(
                child: Container(
                  color: const Color(
                    0xFF0A0F1D,
                  ), // Deep Dark Canvas for PDF base contrast
                  child: SfPdfViewer.network(
                    url,
                    canShowScrollHead: true,
                    canShowScrollStatus: true,
                    onDocumentLoadFailed:
                        (PdfDocumentLoadFailedDetails details) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "Failed to render PDF: ${details.description}",
                              ),
                              backgroundColor: const Color(0xFFFF3131),
                            ),
                          );
                        },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1D), // Base Dark
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0F1D),
        elevation: 0,
        title: Text(
          widget.expertName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_uploadedDocUrl != null && _uploadedDocUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                icon: const Icon(
                  Icons.picture_as_pdf_rounded,
                  color: Color(0xFFFF3131),
                  size: 26,
                ),
                tooltip: "Review Uploaded Document",
                onPressed: () => _openDocumentViewer(context, _uploadedDocUrl!),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF3131)),
            )
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
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: isMe
                                ? const Color(
                                    0xFFFF3131,
                                  ) // Sender: RedLine Neon Red
                                : const Color(
                                    0xFF141C33,
                                  ), // Recipient: Secondary Elevated Dark Blue
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  color: const Color(0xFF0A0F1D),
                  child: SafeArea(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            style: const TextStyle(color: Colors.white),
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            decoration: InputDecoration(
                              hintText: "Write your message here...",
                              hintStyle: const TextStyle(
                                color: Color(0xFF8E9AA8),
                                fontSize: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              fillColor: const Color(
                                0xFF141C33,
                              ), // Match deep text layer fill
                              filled: true,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(
                            Icons.send,
                            color: Color(
                              0xFFFF3131,
                            ), // Purged LinkedIn Blue for Neon Red
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
