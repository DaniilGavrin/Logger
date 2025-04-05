class Program {
  final int id;
  final String name;
  final String description;
  final int userId;

  Program({
    required this.id,
    required this.name,
    required this.description,
    required this.userId,
  });

  factory Program.fromJson(Map<String, dynamic> json) {
    return Program(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
    );
  }
}