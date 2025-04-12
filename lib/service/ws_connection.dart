import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WSConnection {
  static final WSConnection _instance = WSConnection._internal();
  factory WSConnection() => _instance;
  WSConnection._internal();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  Timer? _pingTimer;

  Stream<String> get messages => _messageController.stream;
  Stream<String> get stream => messages;

  String? _authToken;
  String? _lastUrl;
  final List<String> _messageQueue = [];

  bool _isConnecting = false;
  bool _isReconnecting = false;
  bool _isDisposing = false;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 5;
  final Duration _reconnectDelay = const Duration(seconds: 2);

  bool get isConnected => _channel != null && _channel!.closeCode == null && !_isDisposing;
  bool get isConnecting => _isConnecting;

  StreamSubscription<String> listen(
      void Function(String event) onData, {
        Function? onError,
        void Function()? onDone,
        bool? cancelOnError,
      }) {
    return messages.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError ?? false,
    );
  }

  Future<void> connect(Uri uri, {Duration timeout = const Duration(seconds: 5)}) async {
    if (_isConnecting || _isReconnecting || _reconnectAttempts >= _maxReconnectAttempts) return;

    _isConnecting = true;
    _lastUrl = uri.toString();

    try {
      await _safeDisconnect();
      if (kDebugMode) {
        print('🚀 Connecting to WebSocket: $uri');
      }

      _channel = WebSocketChannel.connect(uri);

      _subscription = _channel!.stream.listen(
            (event) => _handleIncomingData(event),
        onDone: () => _handleConnectionClosed(),
        onError: (error) => _handleSocketError(error),
      );

      _reconnectAttempts = 0;
      _isConnecting = false;

      _sendAuthIfNeeded();
      _sendQueuedMessages();
      _startPingTimer();

      _channel?.sink.done.then((_) {
        if (!_isDisposing) {
          print('Соединение закрыто сервером');
          _handleReconnect();
        }
      });
    } catch (e) {
      _isConnecting = false;
      if (kDebugMode) {
        print('❌ Connection error: $e');
      }
      await _handleReconnect();
    }
  }

  void _handleIncomingData(dynamic data) {
    if (_messageController.isClosed || _isDisposing) return;
    final message = data.toString();
    _messageController.add(message);

    final decoded = jsonDecode(message);
    if (decoded is Map && decoded['type'] == 'pong') {
      if (kDebugMode) {
        print('🏓 Получен Pong от сервера');
      }
      // Можно обновить время последней активности
      return;
    }
  }

  void _handleConnectionClosed() async {
    final closeCode = _channel?.closeCode;
    if (kDebugMode) {
      print('🔌 Connection closed with code: ${closeCode ?? 'unknown'}');
    }

    // Не переподключаемся при нормальном закрытии (1000) или если запрошено отключение
    if (closeCode != 1000 && !_isDisposing) {
      await _handleReconnect();
    }
  }

  void _handleSocketError(dynamic error) {
    if (_isDisposing) return;

    if (kDebugMode) {
      print('⚠️ WebSocket error: $error');
    }
    _handleReconnect();
  }

  Future<void> _safeDisconnect() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _subscription = null;
    _pingTimer?.cancel();
  }

  void send(String message) {
    if (isConnected) {
      if (kDebugMode) print('📤 Sending message: $message');
      _channel!.sink.add(message);
    } else {
      if (kDebugMode) print('📥 Queueing message: $message');
      _messageQueue.add(message);
    }
  }

  void _sendAuthIfNeeded() {
    if (_authToken != null) {
      send(jsonEncode({'type': 'auth', 'token': _authToken}));
    }
  }

  void _sendQueuedMessages() {
    while (_messageQueue.isNotEmpty && isConnected) {
      final message = _messageQueue.removeAt(0);
      send(message);
    }
  }

  Future<void> _handleReconnect() async {
    if (_isReconnecting || _reconnectAttempts >= _maxReconnectAttempts) return;

    _isReconnecting = true;
    _reconnectAttempts++;

    if (kDebugMode) {
      print('🔄 Reconnecting (attempt $_reconnectAttempts)...');
    }

    await Future.delayed(_reconnectDelay);
    if (_lastUrl != null && !_isDisposing) {
      await connect(Uri.parse(_lastUrl!));
    }

    _isReconnecting = false;
  }

  Future<void> disconnect() async {
    if (_isDisposing) return;

    if (kDebugMode) {
      print('🛑 Disconnecting...');
    }

    _isDisposing = true;
    await _safeDisconnect();
    _isDisposing = false;
  }

  void setAuthToken(String token) {
    _authToken = token;
    if (isConnected) {
      _sendAuthIfNeeded();
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (isConnected) {
        send(jsonEncode({'type': 'ping'}));
      }
    });
  }

  void debugState() {
    print('''
    WSConnection State:
    - isConnected: $isConnected
    - isConnecting: $_isConnecting
    - isReconnecting: $_isReconnecting
    - reconnectAttempts: $_reconnectAttempts
    - queueSize: ${_messageQueue.length}
    - channelState: ${_channel?.closeCode ?? 'active'}
    ''');
  }
}