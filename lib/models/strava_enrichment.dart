class StravaComment {
  final String id;
  final String authorName;
  final String text;
  final DateTime createdAt;

  const StravaComment({
    required this.id,
    required this.authorName,
    required this.text,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'authorName': authorName,
        'text': text,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory StravaComment.fromJson(Map<String, dynamic> json) {
    return StravaComment(
      id: (json['id'] ?? '').toString(),
      authorName: (json['authorName'] as String?) ?? 'Strava Athlete',
      text: (json['text'] as String?) ?? '',
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  factory StravaComment.fromStravaApi(Map<String, dynamic> json) {
    final athlete = json['athlete'];
    String authorName = 'Strava Athlete';
    if (athlete is Map<String, dynamic>) {
      final first = (athlete['firstname'] as String?)?.trim() ?? '';
      final last = (athlete['lastname'] as String?)?.trim() ?? '';
      final combined = '$first $last'.trim();
      if (combined.isNotEmpty) {
        authorName = combined;
      }
    }
    return StravaComment(
      id: (json['id'] ?? '').toString(),
      authorName: authorName,
      text: (json['text'] as String?) ?? '',
      createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class StravaSegmentEffort {
  final String id;
  final String name;
  final double distanceM;
  final int elapsedSec;
  final double avgGrade;
  final int? prRank;
  final bool isKom;
  final double? avgWatts;

  const StravaSegmentEffort({
    required this.id,
    required this.name,
    required this.distanceM,
    required this.elapsedSec,
    required this.avgGrade,
    this.prRank,
    this.isKom = false,
    this.avgWatts,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'distanceM': distanceM,
        'elapsedSec': elapsedSec,
        'avgGrade': avgGrade,
        'prRank': prRank,
        'isKom': isKom,
        'avgWatts': avgWatts,
      };

  factory StravaSegmentEffort.fromJson(Map<String, dynamic> json) {
    return StravaSegmentEffort(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] as String?) ?? '',
      distanceM: (json['distanceM'] as num?)?.toDouble() ?? 0.0,
      elapsedSec: (json['elapsedSec'] as num?)?.toInt() ?? 0,
      avgGrade: (json['avgGrade'] as num?)?.toDouble() ?? 0.0,
      prRank: (json['prRank'] as num?)?.toInt(),
      isKom: (json['isKom'] as bool?) ?? false,
      avgWatts: (json['avgWatts'] as num?)?.toDouble(),
    );
  }

  factory StravaSegmentEffort.fromStravaApi(Map<String, dynamic> json) {
    final segment = json['segment'] is Map<String, dynamic>
        ? json['segment'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final komRank = (json['kom_rank'] as num?)?.toInt();
    bool isKom = komRank == 1;
    if (!isKom && json['achievements'] is List) {
      for (final item in (json['achievements'] as List)) {
        if (item is Map<String, dynamic>) {
          final rank = (item['rank'] as num?)?.toInt();
          final type = (item['type'] as String?)?.toLowerCase();
          final typeId = (item['type_id'] as num?)?.toInt();
          if (rank == 1 && (type == 'overall' || typeId == 2)) {
            isKom = true;
            break;
          }
        }
      }
    }

    return StravaSegmentEffort(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] as String?) ?? (segment['name'] as String?) ?? 'Segment',
      distanceM: (json['distance'] as num?)?.toDouble() ??
          (segment['distance'] as num?)?.toDouble() ??
          0.0,
      elapsedSec: (json['elapsed_time'] as num?)?.toInt() ?? 0,
      avgGrade: (segment['average_grade'] as num?)?.toDouble() ??
          (json['average_grade'] as num?)?.toDouble() ??
          0.0,
      prRank: (json['pr_rank'] as num?)?.toInt(),
      isKom: isKom,
      avgWatts: (json['average_watts'] as num?)?.toDouble(),
    );
  }
}

class StravaBestEffort {
  final String name;
  final double distanceM;
  final int elapsedSec;

  const StravaBestEffort({
    required this.name,
    required this.distanceM,
    required this.elapsedSec,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'distanceM': distanceM,
        'elapsedSec': elapsedSec,
      };

  factory StravaBestEffort.fromJson(Map<String, dynamic> json) {
    return StravaBestEffort(
      name: (json['name'] as String?) ?? '',
      distanceM: (json['distanceM'] as num?)?.toDouble() ?? 0.0,
      elapsedSec: (json['elapsedSec'] as num?)?.toInt() ?? 0,
    );
  }

  factory StravaBestEffort.fromStravaApi(Map<String, dynamic> json) {
    return StravaBestEffort(
      name: (json['name'] as String?) ?? '',
      distanceM: (json['distance'] as num?)?.toDouble() ?? 0.0,
      elapsedSec: (json['elapsed_time'] as num?)?.toInt() ?? 0,
    );
  }
}

class StravaActivityEnrichment {
  final String stravaId;
  final String title;
  final String? description;
  final int kudosCount;
  final int commentCount;
  final List<StravaComment> comments;
  final List<StravaSegmentEffort> segmentEfforts;
  final List<StravaBestEffort> bestEfforts;
  final double? sufferScore;
  final String? gearName;
  final String sportType;
  final DateTime startDate;
  final double distanceM;
  final int movingTimeSec;

  const StravaActivityEnrichment({
    required this.stravaId,
    required this.title,
    this.description,
    required this.kudosCount,
    required this.commentCount,
    this.comments = const [],
    this.segmentEfforts = const [],
    this.bestEfforts = const [],
    this.sufferScore,
    this.gearName,
    required this.sportType,
    required this.startDate,
    required this.distanceM,
    required this.movingTimeSec,
  });

  String get stravaUrl => 'https://www.strava.com/activities/$stravaId';

  StravaActivityEnrichment copyWith({
    String? title,
    String? description,
    int? kudosCount,
    int? commentCount,
    List<StravaComment>? comments,
    List<StravaSegmentEffort>? segmentEfforts,
    List<StravaBestEffort>? bestEfforts,
    double? sufferScore,
    String? gearName,
    String? sportType,
    DateTime? startDate,
    double? distanceM,
    int? movingTimeSec,
  }) {
    return StravaActivityEnrichment(
      stravaId: stravaId,
      title: title ?? this.title,
      description: description ?? this.description,
      kudosCount: kudosCount ?? this.kudosCount,
      commentCount: commentCount ?? this.commentCount,
      comments: comments ?? this.comments,
      segmentEfforts: segmentEfforts ?? this.segmentEfforts,
      bestEfforts: bestEfforts ?? this.bestEfforts,
      sufferScore: sufferScore ?? this.sufferScore,
      gearName: gearName ?? this.gearName,
      sportType: sportType ?? this.sportType,
      startDate: startDate ?? this.startDate,
      distanceM: distanceM ?? this.distanceM,
      movingTimeSec: movingTimeSec ?? this.movingTimeSec,
    );
  }

  Map<String, dynamic> toJson() => {
        'stravaId': stravaId,
        'title': title,
        'description': description,
        'kudosCount': kudosCount,
        'commentCount': commentCount,
        'comments': comments.map((c) => c.toJson()).toList(),
        'segmentEfforts': segmentEfforts.map((s) => s.toJson()).toList(),
        'bestEfforts': bestEfforts.map((b) => b.toJson()).toList(),
        'sufferScore': sufferScore,
        'gearName': gearName,
        'sportType': sportType,
        'startDate': startDate.toUtc().toIso8601String(),
        'distanceM': distanceM,
        'movingTimeSec': movingTimeSec,
      };

  factory StravaActivityEnrichment.fromJson(Map<String, dynamic> json) {
    return StravaActivityEnrichment(
      stravaId: (json['stravaId'] ?? '').toString(),
      title: (json['title'] as String?) ?? '',
      description: json['description'] as String?,
      kudosCount: (json['kudosCount'] as num?)?.toInt() ?? 0,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      comments: (json['comments'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(StravaComment.fromJson)
              .toList() ??
          const [],
      segmentEfforts: (json['segmentEfforts'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(StravaSegmentEffort.fromJson)
              .toList() ??
          const [],
      bestEfforts: (json['bestEfforts'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(StravaBestEffort.fromJson)
              .toList() ??
          const [],
      sufferScore: (json['sufferScore'] as num?)?.toDouble(),
      gearName: json['gearName'] as String?,
      sportType: (json['sportType'] as String?) ?? '',
      startDate: DateTime.tryParse((json['startDate'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      distanceM: (json['distanceM'] as num?)?.toDouble() ?? 0.0,
      movingTimeSec: (json['movingTimeSec'] as num?)?.toInt() ?? 0,
    );
  }

  factory StravaActivityEnrichment.fromStravaApi(Map<String, dynamic> json) {
    String? gearName;
    final gear = json['gear'];
    if (gear is Map<String, dynamic>) {
      final rawName = (gear['name'] as String?)?.trim();
      if (rawName != null && rawName.isNotEmpty) {
        gearName = rawName;
      }
    }

    final rawDescription = (json['description'] as String?)?.trim();
    final sportType = (json['sport_type'] as String?)?.trim().isNotEmpty == true
        ? (json['sport_type'] as String).trim()
        : ((json['type'] as String?)?.trim() ?? '');

    return StravaActivityEnrichment(
      stravaId: (json['id'] ?? '').toString(),
      title: (json['name'] as String?) ?? '',
      description: (rawDescription != null && rawDescription.isNotEmpty)
          ? rawDescription
          : null,
      kudosCount: (json['kudos_count'] as num?)?.toInt() ?? 0,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
      comments: const [],
      segmentEfforts: (json['segment_efforts'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(StravaSegmentEffort.fromStravaApi)
              .toList() ??
          const [],
      bestEfforts: (json['best_efforts'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(StravaBestEffort.fromStravaApi)
              .toList() ??
          const [],
      sufferScore: (json['suffer_score'] as num?)?.toDouble(),
      gearName: gearName,
      sportType: sportType,
      startDate: DateTime.tryParse((json['start_date'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      distanceM: (json['distance'] as num?)?.toDouble() ?? 0.0,
      movingTimeSec: (json['moving_time'] as num?)?.toInt() ?? 0,
    );
  }
}
