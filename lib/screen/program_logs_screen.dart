import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:logger/model/log_entry.dart';
import 'package:logger/model/program.dart';
import 'package:logger/service/ws_connection.dart';

class ProgramLogsScreen extends StatefulWidget {
  final Program program;
  final WSConnection ws;
  final Stream stream;

  const ProgramLogsScreen({
    super.key,
    required this.program,
    required this.ws,
    required this.stream,
  });

  @override
  _ProgramLogsScreenState createState() => _ProgramLogsScreenState();
}

class _ProgramLogsScreenState extends State<ProgramLogsScreen> {
  late Timer _refreshTimer;
  List<LogEntry> _logs = [];
  bool _isLoading = true;
  String? _error;
  StreamSubscription? _logSubscription;
  String? _currentRequestId;

  void _handleError(String? message) {
    if (!mounted) return;
    setState(() {
      _error = message ?? 'Неизвестная ошибка';
      _isLoading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _setupWebSocketListener();
    _loadLogs();
  }

  void _setupWebSocketListener() {
    _logSubscription = widget.stream.listen((event) {
      try {
        final data = jsonDecode(event);
        if (!mounted) return;

        switch (data['type']) {
          case 'logs': // Обрабатываем ответ с логами
            if (data['request_id'] == _currentRequestId) {
              _handleLogsData(data['data']);
            }
            break;
          case 'pong': // Обрабатываем pong-сообщения
            print('Соединение активно');
            break;
          case 'error':
            _handleError(data['message']?.toString());
            break;
          default:
            print('Unknown message type: ${data['type']}');
        }
      } catch (e) {
        _handleError('Ошибка обработки данных: $e');
      }
    });
  }

  void _handleLogsData(dynamic data) {
    if (data is! List) {
      _handleError('Неверный формат логов');
      return;
    }

    final parsedLogs = data
        .whereType<Map<String, dynamic>>()
        .map((log) => LogEntry.fromJson(log))
        .toList();

    if (!mounted) return;
    setState(() {
      _logs = parsedLogs;
      _isLoading = false;
      _error = null;
    });
  }

  void _loadLogs() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    print('📤 Отправка запроса логов для ${widget.program.id}');

    // Проверяем, что WebSocket-соединение активно
    if (widget.ws.isConnected) {
      // Отправка запроса на получение логов
      widget.ws.send(jsonEncode({
        'type': 'get_logs',
        'program_id': widget.program.id,
        'request_id': requestId,
      }));
      print('📤 Запрос отправлен');
    } else {
      print('Ошибка: Нет соединения с сервером');
      setState(() {
        _error = 'Нет соединения с сервером';
        _isLoading = false;
      });

      // Попытка переподключения
      print('Попытка переподключения...');
      await widget.ws.connect(Uri.parse("ws://localhost:8080/ws"));

      // После переподключения отправляем запрос на получение логов
      if (widget.ws.isConnected) {
        widget.ws.send(jsonEncode({
          'type': 'get_logs',
          'program_id': widget.program.id,
          'request_id': requestId,
        }));
        print('📤 Запрос отправлен после переподключения');
      } else {
        print('Ошибка: Не удалось переподключиться');
        setState(() {
          _error = 'Не удалось переподключиться';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    //_refreshTimer.cancel();
    //_logSubscription?.cancel();
    //super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.program.name),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadLogs,
          ),
        ],
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) return Center(child: CircularProgressIndicator());

    if (_error != null) return _buildErrorWidget();

    if (_logs.isEmpty) return _buildEmptyWidget();

    return ListView.builder(
      itemCount: _logs.length,
      itemBuilder: (ctx, i) => _buildLogItem(_logs[i]),
    );
  }

  Widget _buildErrorWidget() => Center(
    child: Padding(
      padding: EdgeInsets.all(20),
      child: Text(_error!, textAlign: TextAlign.center),
    ),
  );

  Widget _buildEmptyWidget() => Center(
    child: Text('Нет логов', style: TextStyle(color: Colors.grey)),
  );

  Widget _buildLogItem(LogEntry log) => Card(
    child: ListTile(
      leading: Icon(
        _getLevelIcon(log.level),
        color: _getLevelColor(log.level),
      ),
      title: Text(log.message),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(log.timestamp.toString()),
          if (log.metadata != null)
            Text('Metadata: ${log.metadata}'),
        ],
      ),
    ),
  );

  Color _getLevelColor(String level) => const {
    'error': Colors.red,
    'warning': Colors.orange,
    'info': Colors.blue,
  }[level.toLowerCase()] ?? Colors.grey;

  IconData _getLevelIcon(String level) => const {
    'error': Icons.error,
    'warning': Icons.warning,
    'info': Icons.info,
  }[level.toLowerCase()] ?? Icons.help;
}
