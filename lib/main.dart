import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:logger/screen/log_screen.dart';
import 'package:logger/service/ws_connection.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

void main() {
  runApp(LoggerApp());
  doWhenWindowReady(() {
    final win = appWindow;
    win.size = Size(1200, 800);
    win.alignment = Alignment.center;
    win.title = "Logger";
    win.show();
  });
}

class LoggerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeoLogger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F1A2F),
        useMaterial3: true,
      ),
      home: WindowBorder(
        color: Colors.transparent,
        width: 0,
        child: LoginScreen(),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
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

  void _login(BuildContext context) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    // Получаем экземпляр синглтона
    final wsConnection = WSConnection();

    try {
      await wsConnection.connect(Uri.parse('ws://localhost:8080/ws'));

      // Создаем подписку на сообщения
      final subscription = wsConnection.stream.listen(
            (event) {
          final data = jsonDecode(event);
          if (!mounted) return;

          if (data['status'] == 'ok') {
            Navigator.pushAndRemoveUntil(
              context,
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 800),
                pageBuilder: (_, __, ___) => LogScreen(
                  ws: wsConnection,
                  stream: wsConnection.stream,
                ),
                transitionsBuilder: (_, animation, __, child) {
                  return FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                },
              ),
                  (route) => false,
            );
          } else {
            setState(() {
              _errorText = data['message'];
              _isLoading = false;
            });
            // Закрываем соединение при ошибке аутентификации
            wsConnection.disconnect();
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _errorText = 'Connection Error';
            _isLoading = false;
          });
          wsConnection.disconnect();
        },
      );

      // Отправляем запрос аутентификации
      wsConnection.send(jsonEncode({
        'type': 'auth',
        'username': _usernameController.text,
        'password': _passwordController.text,
      }));

      // Отменяем подписку при уничтожении виджета
      subscription.onDone(() => subscription.cancel());

    } catch (e) {
      setState(() {
        _errorText = 'Connection Error';
        _isLoading = false;
      });
      wsConnection.disconnect();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLogo(),
                    const SizedBox(height: 40),
                    _buildInputFields(),
                    const SizedBox(height: 30),
                    _buildLoginButton(),
                    const SizedBox(height: 40),
                    if (_errorText != null) _buildErrorText(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextField(
            controller: _usernameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Username',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
              prefixIcon: Icon(Icons.person_outline, color: Colors.cyan),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _passwordController,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Password',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
              prefixIcon: Icon(Icons.lock_outline, color: Colors.cyan),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
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
          onTap: _isLoading ? null : () => _login(context),
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