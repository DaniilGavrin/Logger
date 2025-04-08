import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logger/model/program.dart';
import 'package:logger/screen/program_logs_screen.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'package:logger/service/ws_connection.dart';

class LogScreen extends StatefulWidget {
  final WSConnection ws;
  final Stream stream;

  LogScreen({
    required this.ws,
    required this.stream,
  });

  @override
  _LogScreenState createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  List<Program> programs = [];
  bool _isLoading = true;
  String? _error;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _setupWebSocketListener();
    _requestPrograms();
  }

  void _setupWebSocketListener() {
    _subscription = widget.stream.listen((event) { // ✅ Используем переданный поток
      try {
        print('Raw received data: $event');
        final data = jsonDecode(event);
        if (!mounted) return;

        print('Decoded data: $data');

        if (data is! Map<String, dynamic>) {
          throw FormatException('Неверный формат данных');
        }

        switch (data['type']) {
          case 'programs':
            _handleProgramsData(data['data']);
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
    }, onError: (error) {
      if (!mounted) return;
      _handleError('Ошибка соединения: $error');
    });
  }

  void _handleProgramsData(dynamic data) {
    if (data is! List) {
      _handleError('Invalid programs format');
      return;
    }

    final parsedPrograms = data
        .whereType<Map<String, dynamic>>()
        .map((p) => Program.fromJson(p))
        .toList();

    if (!mounted) return;
    setState(() {
      programs = parsedPrograms;
      _isLoading = false;
      _error = null;
    });
  }

  void _handleError(String? message) {
    if (!mounted) return;
    setState(() {
      _error = message ?? 'Unknown error occurred';
      _isLoading = false;
    });
  }

  void _requestPrograms() {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // ✅ Используем переданный экземпляр соединения
    widget.ws.send(jsonEncode({
      'type': 'get_programs',
      'request_id': DateTime.now().millisecondsSinceEpoch.toString(),
    }));

    Future.delayed(Duration(seconds: 10)).then((_) {
      if (_isLoading && mounted) {
        setState(() {
          _error = 'Таймаут получения данных';
          _isLoading = false;
        });
      }
    });
  }

  void _navigateToProgramLogs(BuildContext context, Program program) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProgramLogsScreen(
          program: program,
          ws: widget.ws,
          stream: widget.stream,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Мои программы'),
        actions: [

        ],
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            _error!,
            style: TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (programs.isEmpty) {
      return Center(
        child: Text(
          'Нет созданных программ',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.all(16),
      itemCount: programs.length,
      separatorBuilder: (context, index) => SizedBox(height: 12),
      itemBuilder: (context, index) => _buildProgramCard(programs[index]),
    );
  }

  Widget _buildProgramCard(Program program) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _navigateToProgramLogs(context, program),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.apps, size: 24, color: Colors.indigo),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          program.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (program.description.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              program.description,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Только отменяем подписку, не трогаем соединение
    _subscription?.cancel();
    super.dispose();
  }
}