import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/model/program.dart';
import 'package:logger/service/ws_connection.dart';
import 'package:logger/screen/log_screen.dart';

class LoginScreen extends StatefulWidget {
  final String? initialServer;
  const LoginScreen({super.key, this.initialServer});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  final WSConnection _wsConnection = WSConnection();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _serverController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _showServerField = false;
  String? _errorText;
  StreamSubscription<dynamic>? _authSubscription;
  final FocusNode _serverFocus = FocusNode();
  bool _rememberMe = true;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadSavedData();
  }

  void _initAnimations() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuint,
    ));

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_controller);
    _controller.forward();
  }

  Future<void> _loadSavedData() async {
    _serverController.text = widget.initialServer ?? await _secureStorage.read(key: 'server_url') ?? '';
    _usernameController.text = await _secureStorage.read(key: 'username') ?? '';
    _passwordController.text = await _secureStorage.read(key: 'password') ?? '';

    if (_serverController.text.isNotEmpty) {
      _tryAutoConnect();
    }
  }

  Future<void> _tryAutoConnect() async {
    if (_serverController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      await _wsConnection.connect(Uri.parse(_serverController.text));

      if (_wsConnection.isConnected &&
          _usernameController.text.isNotEmpty &&
          _passwordController.text.isNotEmpty) {
        _sendAuthRequest();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _showServerField = true;
        _errorText = 'Auto-connect failed: ${e.toString()}';
      });
      FocusScope.of(context).requestFocus(_serverFocus);
    }
  }



  void _sendAuthRequest() {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      _handleAuthError('Credentials not saved');
      return;
    }

    // _authSubscription?.cancel();
    _authSubscription = _wsConnection.listen(
      _handleAuthResponse,
      onError: _handleAuthError,
    );

    _wsConnection.send(jsonEncode({
      'type': 'auth',
      'username': _usernameController.text,
      'password': _passwordController.text,
    }));
  }

  void _handleAuthResponse(dynamic event) {
    if (!mounted) return;

    try {
      final data = jsonDecode(event);
      if (data['type'] == 'auth' && data['status'] == 'ok') {
        _saveCredentials();

        // Закрываем подписку перед переходом
        _authSubscription?.cancel();

        // Переход с сохранением соединения
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 800),
            pageBuilder: (_, __, ___) => LogScreen(
              ws: _wsConnection,
              stream: _wsConnection.stream!, // Добавляем stream
            ),
          ),
        );
      } else {
        setState(() {
          _errorText = data['message'] ?? 'Authentication failed';
          _isLoading = false;
        });
      }
    } catch (e) {
      _handleAuthError('Invalid auth response: ${e.toString()}');
    }
  }

  Future<void> _loadUserPrograms() async {
    try {
      final programs = await _fetchUserPrograms();
      if (programs.isNotEmpty) {
        _navigateToLogScreen(programs.first);
      } else {
        _handleAuthError('No programs available');
      }
    } catch (e) {
      _handleAuthError('Failed to load programs');
    }
  }

  Future<List<Program>> _fetchUserPrograms() async {
    StreamSubscription? responseSubscription;
    try {
      final completer = Completer<List<Program>>();
      const timeoutDuration = Duration(seconds: 15);
      final requestId = DateTime.now().millisecondsSinceEpoch.toString();

      responseSubscription = _wsConnection.stream.listen((data) {
        try {
          final json = jsonDecode(data);
          if (json['type'] == 'programs' && json['request_id'] == requestId) {
            completer.complete(
                (json['data'] as List)
                    .map((p) => Program.fromJson(p))
                    .toList()
            );
          }
        } catch (e) {
          completer.completeError(e);
        }
      });

      _wsConnection.send(jsonEncode({
        'type': 'get_programs',
        'request_id': requestId,
      }));

      return await completer.future.timeout(timeoutDuration, onTimeout: () {
        throw TimeoutException('Server response timeout');
      });
    } on TimeoutException catch (_) {
      if (kDebugMode) print('Timeout fetching programs');
      throw Exception('Timeout');
    } catch (e) {
      throw Exception('Failed to load programs: ${e.toString()}');
    } finally {
      await responseSubscription?.cancel();
    }
  }

  Future<void> _saveCredentials() async {
    if (!_rememberMe) {
      await _secureStorage.delete(key: 'username');
      await _secureStorage.delete(key: 'password');
      return;
    }

    await _secureStorage.write(key: 'server_url', value: _serverController.text);
    await _secureStorage.write(key: 'username', value: _usernameController.text);
    await _secureStorage.write(key: 'password', value: _passwordController.text);
  }

  void _navigateToLogScreen(Program program) {
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 800),
        pageBuilder: (_, __, ___) => LogScreen(
          ws: _wsConnection,
          stream: _wsConnection.stream!,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
          (route) => false,
    );
  }

  void _handleAuthError(Object error) {
    if (!mounted) return;

    if (error.toString().contains('Authentication failed')) {
      _secureStorage.delete(key: 'password');
    }

    setState(() {
      _errorText = error.toString()
          .replaceAll('Exception: ', '')
          .replaceAll('Authentication failed', 'Неверный логин или пароль');

      _isLoading = false;
      _showServerField = true;
    });

    FocusScope.of(context).requestFocus(_serverFocus);
  }

  String? _validateServer(String? value) {
    if (value == null || value.isEmpty) return 'Server address required';
    try {
      final uri = Uri.parse(value);
      if (!['ws', 'wss'].contains(uri.scheme)) return 'Use ws:// or wss://';
      if (uri.host.isEmpty) return 'Invalid host';
      return null;
    } catch (e) {
      return 'Invalid URL format';
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _controller.dispose();
    _serverFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F1A2F),
              Color(0xFF1D2B4A),
            ],
          ),
        ),
        child: Center(
          child: SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyan.withOpacity(0.1),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLogo(),
                      const SizedBox(height: 40),
                      _buildServerField(),
                      _buildInputFields(),
                      _buildRememberMe(),
                      const SizedBox(height: 30),
                      _buildLoginButton(),
                      if (_errorText != null) _buildErrorText(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerField() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      child: _showServerField || _serverController.text.isEmpty
          ? Column(
        children: [
          TextFormField(
            controller: _serverController,
            focusNode: _serverFocus,
            decoration: InputDecoration(
              labelText: 'Server Address',
              hintText: 'ws://your-server.com:8080',
              prefixIcon: const Icon(Icons.public, color: Colors.cyan),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
            keyboardType: TextInputType.url,
            validator: _validateServer,
          ),
          const SizedBox(height: 20),
        ],
      )
          : const SizedBox(),
    );
  }

  Widget _buildLogo() {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Colors.cyan, Colors.blueAccent],
      ).createShader(bounds),
      child: const Column(
        children: [
          Icon(Icons.monitor_heart_outlined, size: 60, color: Colors.white),
          SizedBox(height: 10),
          Text('NEO LOGGER',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              )),
        ],
      ),
    );
  }

  Widget _buildInputFields() {
    return Column(
      children: [
        TextFormField(
          controller: _usernameController,
          decoration: InputDecoration(
            labelText: 'Username',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
            prefixIcon: const Icon(Icons.person_outline, color: Colors.cyan),
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
          ),
          style: const TextStyle(color: Colors.white),
          validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _passwordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Password',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
            prefixIcon: const Icon(Icons.lock_outline, color: Colors.cyan),
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
          ),
          style: const TextStyle(color: Colors.white),
          validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
        ),
      ],
    );
  }

  Widget _buildRememberMe() {
    return Row(
      children: [
        Checkbox(
          value: _rememberMe,
          onChanged: (value) => setState(() => _rememberMe = value!),
          fillColor: MaterialStateProperty.all(Colors.cyan),
        ),
        const Text('Запомнить меня', style: TextStyle(color: Colors.white70)),
      ],
    );
  }

  Widget _buildLoginButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _isLoading ? 60 : 200,
      height: 50,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.cyan, Colors.blueAccent],
        ),
        borderRadius: BorderRadius.circular(_isLoading ? 30 : 15),
        boxShadow: [
          if (!_isLoading)
            BoxShadow(
              color: Colors.cyan.withOpacity(0.4),
              blurRadius: 15,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_isLoading ? 30 : 15),
          onTap: _isLoading ? null : _performLogin,
          child: Center(
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text(
              'ACCESS SYSTEM',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _performLogin() {
    if (_formKey.currentState!.validate()) {
      _saveCredentials();
      _login();
    }
  }

  void _login() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      await _wsConnection.connect(Uri.parse(_serverController.text));
      _sendAuthRequest();
    } catch (e) {
      _handleAuthError(e);
    }
  }

  Widget _buildErrorText() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Text(
        _errorText!,
        style: TextStyle(
          color: Colors.redAccent.withOpacity(0.8),
          fontSize: 14,
        ),
      ),
    );
  }
}