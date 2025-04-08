class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;
  final dynamic metadata;
  final int programId;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.metadata,
    required this.programId,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: _parseDateTime(json['timestamp']),
      level: _parseString(json['level'], fallback: 'unknown'),
      message: _parseString(json['message'], fallback: ''),
      metadata: json['metadata'],
      programId: _parseInt(json['program_id']),
    );
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'level': level,
    'message': message,
    'metadata': metadata,
    'program_id': programId,
  };

  static DateTime _parseDateTime(dynamic value) {
    try {
      return DateTime.parse(value.toString()).toLocal();
    } catch (e) {
      return DateTime(1970);
    }
  }

  static String _parseString(dynamic value, {String fallback = ''}) {
    return value?.toString() ?? fallback;
  }

  static int _parseInt(dynamic value) {
    return (value as num?)?.toInt() ?? 0;
  }

  @override
  String toString() {
    return '''
LogEntry {
  timestamp: $timestamp,
  level: $level,
  message: $message,
  programId: $programId,
  metadata: ${metadata ?? 'none'}
}
    ''';
  }
}