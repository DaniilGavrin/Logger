import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logger/model/program.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ProgramLogsScreen extends StatelessWidget {
  final Program program;
  final WebSocketChannel ws;

  ProgramLogsScreen({required this.program, required this.ws});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(program.name),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('ID программы:', program.id.toString()),
            _buildInfoRow('Описание:', program.description),
            SizedBox(height: 20),
            Text(
              'Логи программы:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  // Заглушка для будущих логов
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'Логи будут отображаться здесь',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }
}