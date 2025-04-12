import 'package:intl/intl.dart';

class LogEntry {
  static const Set<String> validLevels = {'info', 'warning', 'error'};

  final DateTime timestamp;
  final String level;
  final String message;
  final Map<String, dynamic>? metadata;
  final int programId;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.metadata,
    required this.programId,
  }) {
    // Валидация уровня логирования
    if (!validLevels.contains(level.toLowerCase())) {
      throw ArgumentError('Недопустимый уровень логирования: $level');
    }
  }

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    try {
      return LogEntry(
        timestamp: _parseDateTime(json['timestamp']),
        level: _parseLevel(json['level']),
        message: _parseMessage(json['message']),
        metadata: _parseMetadata(json['metadata']),
        programId: _parseProgramId(json['program_id']),
      );
    } catch (e) {
      throw FormatException('Ошибка парсинга LogEntry: ${e.toString()}');
    }
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'level': level,
    'message': message,
    'metadata': metadata,
    'program_id': programId,
  };

  // region Парсеры
  static DateTime _parseDateTime(dynamic value) {
    try {
      return DateTime.parse(value.toString()).toLocal();
    } catch (e) {
      throw FormatException('Неверный формат времени: $value');
    }
  }

  static String _parseLevel(dynamic value) {
    final level = value?.toString().toLowerCase() ?? 'unknown';
    if (!validLevels.contains(level)) {
      throw FormatException('Недопустимый уровень: $level');
    }
    return level;
  }

  static String _parseMessage(dynamic value) {
    final message = value?.toString().trim() ?? '';
    if (message.isEmpty) {
      throw FormatException('Сообщение лога не может быть пустым');
    }
    return message;
  }

  static Map<String, dynamic>? _parseMetadata(dynamic value) {
    if (value == null) return null;
    if (value is! Map) {
      throw FormatException('Метаданные должны быть объектом');
    }
    return Map<String, dynamic>.from(value);
  }

  static int _parseProgramId(dynamic value) {
    final id = int.tryParse(value.toString()) ?? 0;
    if (id <= 0) {
      throw FormatException('Некорректный ID программы: $value');
    }
    return id;
  }
  // endregion

  @override
  String toString() {
    final meta = metadata?.entries
        .map((e) => '    ${e.key}: ${e.value}')
        .join('\n') ?? '    отсутствуют';

    return '''
LogEntry [
  Время:    ${DateFormat('dd.MM.yyyy HH:mm:ss').format(timestamp)}
  Уровень:  ${level.toUpperCase()}
  Программа: #$programId
  Сообщение: $message
  Метаданные:
$meta
]
''';
  }
}