/// A device registered with the self-hosted backend (`GET /devices`).
class CloudDevice {
  const CloudDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.appVersion,
    this.lastSyncAt,
    this.current = false,
  });

  final String id;
  final String name;
  final String platform;
  final String appVersion;
  final DateTime? lastSyncAt;
  final bool current;

  factory CloudDevice.fromJson(Map<String, dynamic> json) => CloudDevice(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? 'Unknown device',
    platform: json['platform'] as String? ?? '',
    appVersion: json['appVersion'] as String? ?? '',
    lastSyncAt: DateTime.tryParse(
      (json['lastSyncAt'] as String?) ?? '',
    ),
    current: json['current'] == true,
  );
}

/// Cloud backup schedule (stored in `app_settings` key `backup.schedule`).
enum BackupSchedule {
  manual,
  daily,
  weekly,
  monthly;

  static BackupSchedule fromName(String? name) {
    for (final value in BackupSchedule.values) {
      if (value.name == name) return value;
    }
    return BackupSchedule.manual;
  }

  /// How long a scheduled backup may idle before it is due again.
  /// `manual` never fires automatically.
  Duration get interval => switch (this) {
    BackupSchedule.manual => Duration.zero,
    BackupSchedule.daily => const Duration(days: 1),
    BackupSchedule.weekly => const Duration(days: 7),
    BackupSchedule.monthly => const Duration(days: 30),
  };
}

/// The current cloud-sync state, as surfaced in Settings.
class SyncStatus {
  const SyncStatus({
    required this.enabled,
    this.signedIn = false,
    this.userId,
    this.email,
    this.syncing = false,
    this.lastSyncedAt,
    this.error,
    this.conflictNeedsAttention = false,
    this.devices = const [],
    this.backupSchedule = BackupSchedule.manual,
    this.backupPassphraseSet = false,
    this.lastBackupAt,
  });

  /// Whether the self-hosted API URL is compiled in (`FINFLOW_API_URL`).
  final bool enabled;

  final bool signedIn;
  final String? userId;
  final String? email;

  final bool syncing;
  final DateTime? lastSyncedAt;
  final String? error;

  /// True when the last sync left a conflict that survived rebase — surface
  /// "needs attention" instead of pretending everything converged.
  final bool conflictNeedsAttention;

  /// Devices registered to this account (Settings → devices list).
  final List<CloudDevice> devices;

  /// Cloud backup schedule (Settings → Cloud backup card).
  final BackupSchedule backupSchedule;

  /// Whether the backup passphrase is stored on this device — required for
  /// scheduled backups to run unattended.
  final bool backupPassphraseSet;

  /// When the last cloud backup was created (local time, from `backup.lastRunAt`).
  final DateTime? lastBackupAt;

  SyncStatus copyWith({
    bool? enabled,
    bool? signedIn,
    String? userId,
    String? email,
    bool? syncing,
    DateTime? lastSyncedAt,
    String? error,
    bool? conflictNeedsAttention,
    List<CloudDevice>? devices,
    BackupSchedule? backupSchedule,
    bool? backupPassphraseSet,
    DateTime? lastBackupAt,
    bool clearError = false,
  }) {
    return SyncStatus(
      enabled: enabled ?? this.enabled,
      signedIn: signedIn ?? this.signedIn,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      syncing: syncing ?? this.syncing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      error: clearError ? null : (error ?? this.error),
      conflictNeedsAttention:
          conflictNeedsAttention ?? this.conflictNeedsAttention,
      devices: devices ?? this.devices,
      backupSchedule: backupSchedule ?? this.backupSchedule,
      backupPassphraseSet: backupPassphraseSet ?? this.backupPassphraseSet,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
    );
  }
}
