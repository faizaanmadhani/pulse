enum DeviceConnectionState {
  connected,
  syncing,
  offline,
  standby,
}

class ConnectedDevice {
  final String id;
  final String name;
  final String category;
  final String protocol; // Bluetooth BLE / ANT+ / USB-Direct
  final DeviceConnectionState state;
  final int batteryPercent;
  final String lastSyncTime;
  final String firmwareVersion;
  final String telemetryChannels;

  const ConnectedDevice({
    required this.id,
    required this.name,
    required this.category,
    required this.protocol,
    required this.state,
    required this.batteryPercent,
    required this.lastSyncTime,
    required this.firmwareVersion,
    required this.telemetryChannels,
  });
}

class IngestedFitFile {
  final String fileName;
  final String fileSize;
  final DateTime importedAt;
  final String sportType;
  final int totalDataPoints;
  final String parsedDuration;
  final double distanceKm;
  final bool integrityVerified;
  final String checksumSha;

  const IngestedFitFile({
    required this.fileName,
    required this.fileSize,
    required this.importedAt,
    required this.sportType,
    required this.totalDataPoints,
    required this.parsedDuration,
    required this.distanceKm,
    required this.integrityVerified,
    required this.checksumSha,
  });
}
