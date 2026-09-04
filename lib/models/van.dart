class Van {
  final int id;
  final String code;
  final String mqttPrefix;
  final String? model;
  final String? name;

  Van({
    required this.id,
    required this.code,
    required this.mqttPrefix,
    this.model,
    this.name,
  });

  factory Van.fromJson(Map<String, dynamic> json) {
    return Van(
      id: json['id'] as int,
      code: json['code'] as String,
      mqttPrefix: json['mqtt_prefix'] as String,
      model: json['model'] as String?,
      name: json['name'] as String?,
    );
  }

  String get displayName => (name != null && name!.isNotEmpty) ? name! : code;

  static const Map<String, String> modelLabels = {
    'F021': 'Van Cơ F021',
    'F023': 'Van Lưu Lượng F023',
    '5021': 'Van Cơ 5021',
    '5023': 'Van Lưu Lượng 5023',
  };

  String get modelLabel => modelLabels[model] ?? (model ?? '');
}
