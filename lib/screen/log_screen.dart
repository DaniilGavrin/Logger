import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logger/model/program.dart';
import 'package:logger/screen/program_logs_screen.dart';
import 'dart:convert';
import 'package:logger/service/ws_connection.dart';

class LogScreen extends StatefulWidget {
  final WSConnection ws;
  final Stream stream;

  const LogScreen({
    Key? key,
    required this.ws,
    required this.stream,
  }) : super(key: key);

  @override
  _LogScreenState createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> with WidgetsBindingObserver {
  List<Program> programs = [];
  bool _isLoading = true;
  String? _error;
  StreamSubscription? _subscription;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWebSocket();
  }

  void _initWebSocket() {
    _subscription?.cancel();
    _subscription = widget.stream.listen(
      _handleMessage,
      onError: _handleError,
      cancelOnError: true,
    );
    _requestPrograms();
  }

  void _handleMessage(dynamic event) {
    if (!mounted) return;

    try {
      final data = jsonDecode(event);
      if (data is! Map<String, dynamic>) return;

      switch (data['type']) {
        case 'programs':
          _handleProgramsData(data['data']);
          break;
        case 'error':
          _handleError(data['message']?.toString());
          break;
      }
    } catch (e) {
      _handleError('Ошибка обработки: ${e.toString()}');
    }
  }

  void _handleProgramsData(dynamic data) {
    if (!mounted || data is! List) return;

    final parsed = data
        .whereType<Map<String, dynamic>>()
        .map(Program.fromJson)
        .toList();

    setState(() {
      programs = parsed;
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

  void _requestPrograms() {
    if (!mounted) return;

    setState(() => _isLoading = true);
    widget.ws.send(jsonEncode({
      'type': 'get_programs',
      'request_id': DateTime.now().millisecondsSinceEpoch.toString(),
    }));

    _timeoutTimer = Timer(Duration(seconds: 10), () {
      if (mounted && _isLoading) {
        setState(() {
          _error = 'Таймаут получения данных';
          _isLoading = false;
        });
      }
    });
  }

  void _navigateToLogs(Program program) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => ProgramLogsScreen(
          key: ValueKey(program.id),
          program: program,
          ws: widget.ws,
          stream: widget.stream,
        ),
        transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    print('LogScreen: didChangeDependencies (mounted: $mounted)');
  }

  @override
  void deactivate() {
    print('LogScreen: deactivate');
    super.deactivate();
  }

  @override
  void dispose() {
    print('LogScreen: dispose start');
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _timeoutTimer?.cancel();
    _subscription = null;
    _timeoutTimer = null;
    super.dispose();
    print('LogScreen: dispose complete');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Мои программы')),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) return _buildLoader();
    if (_error != null) return _buildError();
    if (programs.isEmpty) return _buildEmpty();
    return _buildProgramsList();
  }

  Widget _buildLoader() => Center(
    child: CircularProgressIndicator(),
  );

  Widget _buildError() => Center(
    child: Padding(
      padding: EdgeInsets.all(20),
      child: Text(
        _error!,
        style: TextStyle(color: Colors.red, fontSize: 16),
        textAlign: TextAlign.center,
      ),
    ),
  );

  Widget _buildEmpty() => Center(
    child: Text(
      'Нет созданных программ',
      style: TextStyle(fontSize: 16, color: Colors.grey),
    ),
  );

  Widget _buildProgramsList() => ListView.separated(
    padding: EdgeInsets.all(16),
    itemCount: programs.length,
    separatorBuilder: (_, __) => SizedBox(height: 12),
    itemBuilder: (_, i) => _ProgramCard(
      program: programs[i],
      onTap: () => _navigateToLogs(programs[i]),
    ),
  );
}

class _ProgramCard extends StatelessWidget {
  final Program program;
  final VoidCallback onTap;

  const _ProgramCard({
    required this.program,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
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
        ),
      ),
    );
  }
}