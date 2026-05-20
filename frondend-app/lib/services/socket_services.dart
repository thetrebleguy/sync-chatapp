import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:hirewire/utils/constants.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  WebSocketChannel? channel;

  // 2. A callback function that our screens can hook into to listen for incoming messages
  Function(Map<String, dynamic>)? onMessageReceived;

  // 3. Accept user_id so the Go backend knows exactly who this socket pipe belongs to!
  void connect(String userId) {
    // If already connected, don't spin up duplicate sockets
    if (channel != null) return;

    final wsUrlWithAuth = "${API.wsUrl}?user_id=$userId";
    channel = WebSocketChannel.connect(Uri.parse(wsUrlWithAuth));

    // 4. Start listening to the stream globally
    channel!.stream.listen(
      (message) {
        try {
          final Map<String, dynamic> data = jsonDecode(message);
          if (onMessageReceived != null) {
            onMessageReceived!(
              data,
            ); // Pass data to whatever screen is listening
          }
        } catch (e) {
          print("Error parsing global socket data: $e");
        }
      },
      onError: (err) => print("Global Socket Error: $err"),
      onDone: () {
        print("Global Socket Connection Closed");
        channel = null;
      },
    );
  }

  void sendMessage(String message) {
    channel?.sink.add(message);
  }

  void close() {
    channel?.sink.close(status.goingAway);
    channel = null;
  }
}

class CurrentScreenTracker {
  static String? activeRoomId;
}