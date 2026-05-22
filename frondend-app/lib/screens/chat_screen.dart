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
            "is_me": msg["sender_id"].toString() == _myUserId.toString(),
          });
        }
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
      final senderId = data["sender_id"]?.toString();

      if (senderId == _myUserId.toString()) {
        return;
      }

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
          // Expands nicely to cover 80% of the screen for an actual readable document view
          height: MediaQuery.of(context).size.height * 0.80,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Grab Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              // Header Layout
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
                        Icon(Icons.picture_as_pdf, color: Color(0xFFD93025)),
                        SizedBox(width: 8),
                        Text(
                          "Live Document Preview",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // 🎯 THE LIVE RENDERING PDF ENGINE VIEWPORT
              Expanded(
                child: Container(
                  color: Colors.grey[100],
                  child: SfPdfViewer.network(
                    url,
                    canShowScrollHead: true,
                    canShowScrollStatus: true,
                    // Shows a clean native loading bar while downloading from Supabase storage bucket
                    onDocumentLoadFailed:
                        (PdfDocumentLoadFailedDetails details) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "Failed to render PDF: ${details.description}",
                              ),
                              backgroundColor: Colors.red,
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

        actions: [
          if (_uploadedDocUrl != null && _uploadedDocUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: IconButton(
                icon: const Icon(
                  Icons.picture_as_pdf_rounded,
                  color: Color(0xFFD93025),
                  size: 28,
                ),
                tooltip: "Review Uploaded Document",
                onPressed: () {
                  _openDocumentViewer(context, _uploadedDocUrl!);
                },
              ),
            ),
        ],
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
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    color: Colors.white,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment
                          .end, // 🎯 Align button to bottom as field grows
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            minLines: 1,
                            maxLines: 4,
                            keyboardType: TextInputType.multiline,
                            decoration: InputDecoration(
                              hintText: "Write your message here...",
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              fillColor: Colors.grey[100],
                              filled: true,
                              isDense:
                                  true, // Allows vertical expansion without padding pops
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical:
                                    10, // Gives a clean height balance for multi-lines
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
