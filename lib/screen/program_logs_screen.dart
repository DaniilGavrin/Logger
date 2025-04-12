import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

class _ProgramLogsScreenState extends State<ProgramLogsScreen> with WidgetsBindingObserver {
  List<LogEntry> _logs = [];
  bool _isLoading = true;
  String? _error;
  StreamSubscription? _logSubscription;
  String? _currentRequestId;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWebSocket();
    _loadLogs();
  }

  void _initWebSocket() {
    _logSubscription?.cancel();
    _logSubscription = widget.stream.listen(
      _handleMessage,
      onError: _handleError,
      cancelOnError: true,
    );
  }

  void _handleMessage(dynamic event) {
    if (!mounted) return;

    print('Received raw message: $event');

    try {
      final data = jsonDecode(event);
      if (data is! Map<String, dynamic>) return;

      switch (data['type']) {
        case 'logs':
          print('case logs отработан');
          if (data['type'] == 'logs') {
            _handleLogsData(data['data']);
          }
          else if (data['type'] == 'error') {
            _handleError(data['message']?.toString());
          }
          break;
        case 'error':
          _handleError(data['message']?.toString());
          break;
      }
    } catch (e) {
      _handleError('Ошибка обработки: ${e.toString()}');
    }
  }

  void _handleLogsData(dynamic data) {
    if (!mounted || data is! List) return;

    final parsed = data
        .whereType<Map<String, dynamic>>()
        .map(LogEntry.fromJson)
        .toList();

    setState(() {
      _logs = parsed;
      _isLoading = false;
      _error = null;
    });
  }

  void _handleError(dynamic error) {
    if (!mounted) return;
    setState(() {
      _error = error?.toString() ?? 'Неизвестная ошибка';
      _isLoading = false;
    });
  }

  Future<void> _loadLogs() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _currentRequestId = DateTime.now().millisecondsSinceEpoch.toString();
    });

    try {
      if (!widget.ws.isConnected) {
        await widget.ws.connect(Uri.parse("ws://localhost:8080/ws"));
      }

      widget.ws.send(jsonEncode({
        'type': 'get_logs',
        'program_id': widget.program.id,
        'request_id': _currentRequestId,
      }));
    } catch (e) {
      _handleError('Ошибка подключения: ${e.toString()}');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    print('ProgramLogsScreen: didChangeDependencies');
  }

  @override
  void deactivate() {
    print('ProgramLogsScreen: deactivate');
    super.deactivate();
  }

  @override
  void dispose() {
    print('ProgramLogsScreen: dispose start');
    WidgetsBinding.instance.removeObserver(this);
    _logSubscription?.cancel();
    _refreshTimer?.cancel();
    _logSubscription = null;
    _refreshTimer = null;
    super.dispose();
    print('ProgramLogsScreen: dispose complete');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.program.name,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 24,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.deepPurple.shade800, Colors.blueGrey.shade900],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white70),
            onPressed: _isLoading ? null : _loadLogs,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [Colors.blueGrey.shade900, Colors.black87],
            radius: 1.5,
          ),
        ),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) return _buildLoading();
    if (_error != null) return _buildError();
    if (_logs.isEmpty) return _buildEmpty();
    return _buildLogsList();
  }

  Widget _buildLoading() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: Colors.deepPurpleAccent),
        SizedBox(height: 20),
        Text(
          'Загрузка логов...',
          style: TextStyle(color: Colors.white54),
        ),
      ],
    ),
  );

  Widget _buildError() => Center(
    child: Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error, size: 56, color: Colors.deepOrange),
          SizedBox(height: 24),
          Text(_error!, textAlign: TextAlign.center),
          SizedBox(height: 32),
          ElevatedButton.icon(
            icon: Icon(Icons.refresh),
            label: Text('Обновить'),
            onPressed: _loadLogs,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.list_alt, size: 64, color: Colors.white38),
        SizedBox(height: 24),
        Text('Логи отсутствуют', style: TextStyle(fontSize: 22)),
        SizedBox(height: 12),
        Text('Нет записей для отображения', style: TextStyle(color: Colors.white54)),
      ],
    ),
  );

  Widget _buildLogsList() => ListView.builder(
    physics: BouncingScrollPhysics(),
    itemCount: _logs.length,
    itemBuilder: (_, i) => _LogItem(log: _logs[i]),
  );
}

class _LogItem extends StatelessWidget {
  final LogEntry log;

  const _LogItem({required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            _logColor.withOpacity(0.3),
            Colors.black.withOpacity(0.1),
          ],
        ),
        border: Border.all(color: _logColor.withOpacity(0.5)),
      ),
      child: ExpansionTile(
        leading: _buildStatusIndicator(),
        title: Text(log.message, style: TextStyle(color: Colors.white70)),
        subtitle: Text(_formatDate(log.timestamp), style: TextStyle(color: Colors.white54)),
        children: [
          if (log.metadata != null) _buildMetadata(log.metadata!),
          _buildLevelChip(),
        ],
      ),
    );
  }

  Color get _logColor {
    switch (log.level.toLowerCase()) {
      case 'error': return Colors.deepOrange;
      case 'warning': return Colors.amber;
      case 'info': return Colors.cyan;
      default: return Colors.purple;
    }
  }

  Widget _buildStatusIndicator() => CircleAvatar(
    backgroundColor: _logColor,
    child: Icon(_levelIcon, size: 20, color: Colors.white),
  );

  IconData get _levelIcon {
    switch (log.level.toLowerCase()) {
      case 'error': return Icons.error;
      case 'warning': return Icons.warning;
      case 'info': return Icons.info;
      default: return Icons.help;
    }
  }

  Widget _buildMetadata(Map<String, dynamic> metadata) => Padding(
    padding: EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Метаданные:', style: TextStyle(color: Colors.white54)),
        ...metadata.entries.map((e) => ListTile(
          leading: CircleAvatar(radius: 3, backgroundColor: Colors.deepPurple),
          title: Text(e.key.toUpperCase(), style: TextStyle(color: Colors.white54)),
          subtitle: Text(e.value.toString(), style: TextStyle(color: Colors.white38)),
        )),
      ],
    ),
  );

  Widget _buildLevelChip() => Chip(
    label: Text(log.level.toUpperCase()),
    backgroundColor: _logColor.withOpacity(0.2),
    labelStyle: TextStyle(color: _logColor),
    avatar: Icon(Icons.code, size: 16, color: _logColor),
  );

  String _formatDate(DateTime dt) => DateFormat('dd MMM yyyy • HH:mm:ss').format(dt);
}