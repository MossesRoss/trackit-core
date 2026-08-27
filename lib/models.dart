/*
 * @author Mosses
 * @version 1.5.0
 * --- CHANGELOG ---
 * v1.5.0:
 * - [FEAT] Added 'completedAt' timestamp to Milestone model to track 
 * completion dates for the weekly email report.
 * v1.4.0:
 * - [FEAT] Added `TimeSession` class to log individual work sessions
 * with timestamps, enabling accurate period-based reporting.
 * - [FEAT] Added `timeLog` (a List<TimeSession>) to the `Milestone` model.
 * - [FIX] `Milestone.timeSpent` and `Milestone.lastWorkedOn` are now getters
 * that compute their values from the `timeLog`.
 * - [FIX] `Milestone.fromJson` now intelligently migrates old `timeSpent`
 * data into the new `timeLog` model, ensuring backward compatibility.
 * - [FIX] `Milestone.toJson` now saves the new `timeLog`.
 */
import 'package:flutter/material.dart';

// --- NEW: Enum for the status of a task check-in ---
enum TaskCheckinStatus { done, doing, willDo, wontDo }

// --- NEW: Represents a single check-in response from a notification ---
class TaskCheckin {
  final String checkpointId;
  final TaskCheckinStatus status;
  final DateTime timestamp;

  TaskCheckin({
    required this.checkpointId,
    required this.status,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'checkpointId': checkpointId,
        'status': status.index,
        'timestamp': timestamp.toIso8601String(),
      };

  factory TaskCheckin.fromJson(Map<String, dynamic> json) => TaskCheckin(
        checkpointId: json['checkpointId'],
        status: TaskCheckinStatus.values[json['status']],
        timestamp: DateTime.parse(json['timestamp']),
      );
}

// --- NEW: Represents a single timed work session ---
class TimeSession {
  final DateTime timestamp;
  final Duration duration;
  final String? checkpointId; // Optional: tag session to a specific task

  TimeSession({
    required this.timestamp,
    required this.duration,
    this.checkpointId,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'durationSeconds': duration.inSeconds,
        if (checkpointId != null) 'checkpointId': checkpointId,
      };

  factory TimeSession.fromJson(Map<String, dynamic> json) => TimeSession(
        timestamp: DateTime.parse(json['timestamp']),
        duration: Duration(seconds: (json['durationSeconds'] as num).toInt()),
        checkpointId: json['checkpointId'],
      );
}


// Enum for the status of a goal.
enum GoalStatus { active, achieved, givenUp }

// Represents a single checkpoint or task within a milestone.
class Checkpoint {
  final String id;
  final String title;

  Checkpoint({required this.title, String? id})
      : id = id ?? UniqueKey().toString();

  Map<String, dynamic> toJson() => {'id': id, 'title': title};

  factory Checkpoint.fromJson(Map<String, dynamic> json) =>
      Checkpoint(title: json['title'], id: json['id']);
}

// Represents a major goal in the application.
class Goal {
  String id;
  String title;
  List<Milestone> milestones;
  GoalStatus status;
  DateTime createdAt;
  String? userId;
  // --- NEW: Flag to indicate if the goal has been archived ---
  bool isArchived;

  Goal({
    required this.title,
    List<Milestone> milestones = const [],
    this.status = GoalStatus.active,
    String? id,
    DateTime? createdAt,
    this.userId,
    this.isArchived = false, // Default to not archived
  })  : id = id ?? UniqueKey().toString(),
        createdAt = createdAt ?? DateTime.now(),
        milestones = List<Milestone>.from(milestones);

  int get totalTasks =>
      milestones.fold(0, (sum, m) => sum + m.checkpoints.length);
  int get completedTasks =>
      milestones.fold(0, (sum, m) => sum + m.completedCheckpointIds.length);

  // --- FIX: totalTimeSpent now computes from the new milestone log ---
  Duration get totalTimeSpent =>
      milestones.fold(Duration.zero, (sum, m) => sum + m.timeSpent);

  bool get isCompleted =>
      milestones.isNotEmpty && totalTasks > 0 && totalTasks == completedTasks;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'milestones': milestones.map((m) => m.toJson()).toList(),
        'status': status.index,
        'createdAt': createdAt.toIso8601String(),
        'userId': userId,
        'isArchived': isArchived,
      };

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: json['id'],
        title: json['title'],
        milestones: List<Milestone>.from(
            (json['milestones'] as List).map((m) => Milestone.fromJson(m))),
        status: GoalStatus.values[json['status']],
        createdAt: DateTime.parse(json['createdAt']),
        userId: json['userId'],
        isArchived: json['isArchived'] ?? false,
      );
}
class Milestone {
  String id;
  String title;
  DateTime deadline;
  List<Checkpoint> checkpoints;
  List<String> completedCheckpointIds;
  bool isUnlocked;
  List<TimeSession> timeLog; // Changed from timeSpentSeconds
  DateTime? completedAt;

  Milestone({
    required this.title,
    required this.deadline,
    required this.checkpoints,
    List<String> completedCheckpointIds = const [],
    this.isUnlocked = false,
    String? id,
    List<TimeSession>? timeLog,
    this.completedAt,
  })  : id = id ?? UniqueKey().toString(),
        completedCheckpointIds = List<String>.from(completedCheckpointIds),
        timeLog = timeLog ?? [];

  // Computed getters dynamically generated from the timeLog list
  Duration get timeSpent =>
      timeLog.fold(Duration.zero, (sum, session) => sum + session.duration);

  DateTime? get lastWorkedOn => timeLog.isEmpty
      ? null
      : timeLog.map((s) => s.timestamp).reduce((a, b) => a.isAfter(b) ? a : b);

  double get progress => checkpoints.isEmpty
      ? 0.0
      : completedCheckpointIds.length / checkpoints.length;
  bool get isCompleted => checkpoints.isNotEmpty && progress == 1.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'deadline': deadline.toIso8601String(),
        'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
        'completedCheckpointIds': completedCheckpointIds,
        'timeLog': timeLog.map((s) => s.toJson()).toList(),
        'completedAt': completedAt?.toIso8601String(),
      };

  factory Milestone.fromJson(Map<String, dynamic> json) {
    List<TimeSession> migratedTimeLog = [];

    // Migration: if the new timeLog exists, parse it directly
    if (json['timeLog'] != null) {
      migratedTimeLog = (json['timeLog'] as List)
          .map((s) => TimeSession.fromJson(s))
          .toList();
    } else {
      // Backward compatibility: Convert legacy `timeSpentSeconds` into a single bulk session
      int legacySeconds = 0;
      if (json['timeSpentSeconds'] != null) {
        legacySeconds = (json['timeSpentSeconds'] as num).toInt();
      } else if (json['timeSpent'] != null) {
        legacySeconds = (json['timeSpent'] as num).toInt();
      }

      if (legacySeconds > 0) {
        migratedTimeLog.add(TimeSession(
          timestamp: DateTime.now(), // Approximate timestamp for legacy data
          duration: Duration(seconds: legacySeconds),
        ));
      }
    }

    return Milestone(
      id: json['id'],
      title: json['title'],
      deadline: DateTime.parse(json['deadline']),
      checkpoints: List<Checkpoint>.from(
          (json['checkpoints'] as List).map((c) => Checkpoint.fromJson(c))),
      completedCheckpointIds: List<String>.from(json['completedCheckpointIds']),
      timeLog: migratedTimeLog,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : null,
    );
  }
}
