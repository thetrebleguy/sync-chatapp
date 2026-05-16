import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:hirewire/utils/constants.dart';

class SocketService {
  late WebSocketChannel channel;

  void connect() {
    channel = WebSocketChannel.connect(Uri.parse(API.wsUrl));
  }

  void sendMessage(String message) {
    channel.sink.add(message);
  }

  void close() {
    channel.sink.close(status.goingAway);
  }
}
