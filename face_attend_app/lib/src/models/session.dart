class EmployeeProfile {
  const EmployeeProfile({
    required this.id,
    required this.name,
    required this.faceRegistered,
    this.department,
  });

  final int id;
  final String name;
  final String? department;
  final bool faceRegistered;

  factory EmployeeProfile.fromJson(Map<String, dynamic> json) {
    return EmployeeProfile(
      id: json['id'] as int,
      name: json['name'] as String,
      department: json['department'] as String?,
      faceRegistered: json['face_registered'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'department': department,
    'face_registered': faceRegistered,
  };
}

class MobileSession {
  const MobileSession({
    required this.baseUrl,
    required this.db,
    required this.token,
    required this.middlewareUrl,
    required this.middlewareApiKey,
    required this.deviceId,
    required this.deviceName,
  });

  final String baseUrl;
  final String db;
  final String token;
  final String middlewareUrl;
  final String middlewareApiKey;
  final String deviceId;
  final String deviceName;

  factory MobileSession.fromJson(Map<String, dynamic> json) {
    return MobileSession(
      baseUrl: json['base_url'] as String,
      db: json['db'] as String,
      token: json['token'] as String,
      middlewareUrl:
          json['middleware_url'] as String? ?? 'http://127.0.0.1:8019',
      middlewareApiKey: json['middleware_api_key'] as String? ?? 'change-me',
      deviceId: json['device_id'] as String? ?? '',
      deviceName: json['device_name'] as String? ?? 'Shared Scanner',
    );
  }

  Map<String, dynamic> toJson() => {
    'base_url': baseUrl,
    'db': db,
    'token': token,
    'middleware_url': middlewareUrl,
    'middleware_api_key': middlewareApiKey,
    'device_id': deviceId,
    'device_name': deviceName,
  };
}

class AttendanceStatus {
  const AttendanceStatus({
    required this.checkedIn,
    this.attendanceId,
    this.checkIn,
  });

  final bool checkedIn;
  final int? attendanceId;
  final DateTime? checkIn;

  factory AttendanceStatus.fromJson(Map<String, dynamic> json) {
    return AttendanceStatus(
      checkedIn: json['checked_in'] == true,
      attendanceId: json['attendance_id'] as int?,
      checkIn: json['check_in'] == null
          ? null
          : DateTime.tryParse(json['check_in'].toString()),
    );
  }
}

class FaceTemplate {
  const FaceTemplate({
    required this.id,
    required this.modelVersion,
    required this.threshold,
    required this.embeddings,
  });

  final int id;
  final String modelVersion;
  final double threshold;
  final List<List<double>> embeddings;

  factory FaceTemplate.fromJson(Map<String, dynamic> json) {
    final rawEmbeddings = (json['embeddings'] as List<dynamic>? ?? [])
        .map(
          (embedding) => (embedding as List<dynamic>)
              .map((value) => (value as num).toDouble())
              .toList(),
        )
        .toList();
    return FaceTemplate(
      id: json['id'] as int,
      modelVersion: json['model_version'] as String,
      threshold: (json['threshold'] as num).toDouble(),
      embeddings: rawEmbeddings,
    );
  }
}

class PunchResult {
  const PunchResult({
    required this.accepted,
    this.punchType,
    this.logId,
    this.employee,
    this.status,
  });

  final bool accepted;
  final String? punchType;
  final int? logId;
  final EmployeeProfile? employee;
  final AttendanceStatus? status;

  factory PunchResult.fromJson(Map<String, dynamic> json) {
    return PunchResult(
      accepted: json['accepted'] == true,
      punchType: json['punch_type'] as String?,
      logId: json['log_id'] as int?,
      employee: json['employee'] == null
          ? null
          : EmployeeProfile.fromJson(json['employee'] as Map<String, dynamic>),
      status: json['attendance'] == null
          ? null
          : AttendanceStatus.fromJson(
              json['attendance'] as Map<String, dynamic>,
            ),
    );
  }
}
