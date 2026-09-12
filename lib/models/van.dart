class Van {
  final int id;
  final String code;
  final String mqttPrefix;
  final String? model;
  final String? name;
  // [NEW] Phan quyen chia se van - xem them backend app.py (van_shares).
  // isOwner=true (van cua chinh minh) luon co canControl/canConfigure=true.
  // Van duoc NGUOI KHAC chia se: isOwner=false, ownerUsername la chu thuc su,
  // canControl/canConfigure do CHINH CHU quyet dinh luc chia se - dung de an/
  // khoa cac nut dieu khien/cai dat trong UI (khong phai chan o tang MQTT).
  final bool isOwner;
  final String? ownerUsername;
  final bool canControl;
  final bool canConfigure;

  Van({
    required this.id,
    required this.code,
    required this.mqttPrefix,
    this.model,
    this.name,
    this.isOwner = true,
    this.ownerUsername,
    this.canControl = true,
    this.canConfigure = true,
  });

  factory Van.fromJson(Map<String, dynamic> json) {
    bool asBool(dynamic v, bool fallback) {
      if (v == null) return fallback;
      if (v is bool) return v;
      return v == 1 || v == '1';
    }

    return Van(
      id: json['id'] as int,
      code: json['code'] as String,
      mqttPrefix: json['mqtt_prefix'] as String,
      model: json['model'] as String?,
      name: json['name'] as String?,
      isOwner: asBool(json['is_owner'], true),
      ownerUsername: json['owner_username'] as String?,
      canControl: asBool(json['can_control'], true),
      canConfigure: asBool(json['can_configure'], true),
    );
  }

  String get displayName => (name != null && name!.isNotEmpty) ? name! : code;

  // [FIX] Doi ten ma model theo dong "van 4 met khoi" (van4m3): F021->F041,
  // F023->F043, 5021->S041, 5023->S043 - khop chuoi CH32 firmware thuc su
  // phat ra (main.c/monitor.c), model la gia tri CH32 QUYET DINH, app chi
  // hien thi lai (xem van_list_tab.dart/openEditVanModal uu tien gia tri
  // SONG tu thiet bi thay vi gia tri da luu trong app).
  static const Map<String, String> modelLabels = {
    'F041': 'Van Cơ F041 (4m³)',
    'F043': 'Van Lưu Lượng F043 (4m³)',
    'S041': 'Van Cơ S041 (4m³)',
    'S043': 'Van Lưu Lượng S043 (4m³)',
  };

  String get modelLabel => modelLabels[model] ?? (model ?? '');
}
