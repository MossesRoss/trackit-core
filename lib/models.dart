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

  TimeSession({
    required this.timestamp,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'durationInSeconds': duration.inSeconds,
      };

  factory TimeSession.fromJson(Map<String, dynamic> json) => TimeSession(
        timestamp: DateTime.parse(json['timestamp']),
        duration: Duration(seconds: json['durationInSeconds']),
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

// Represents a milestone within a larger goal.
class Milestone {
  String id;
  String title;
  DateTime deadline;
  List<Checkpoint> checkpoints;
  List<String> completedCheckpointIds;
  bool isUnlocked;
  int timeSpentSeconds;
  DateTime? completedAt;

  Milestone({
    required this.title,
    required this.deadline,
    required this.checkpoints,
    List<String> completedCheckpointIds = const [],
    this.isUnlocked = false,
    String? id,
    this.timeSpentSeconds = 0,
    this.completedAt,
  })  : id = id ?? UniqueKey().toString(),
        completedCheckpointIds = List<String>.from(completedCheckpointIds);

  Duration get timeSpent => Duration(seconds: timeSpentSeconds);

  DateTime? get lastWorkedOn => null; // Kept for API compatibility, but unused locally now

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
        'timeSpentSeconds': timeSpentSeconds,
        'completedAt': completedAt?.toIso8601String(),
      };

  factory Milestone.fromJson(Map<String, dynamic> json) {
    int migratedTimeSpent = json['timeSpentSeconds'] ?? 0;
    
    // Migration: if old timeLog exists, sum its durations
    if (json['timeLog'] != null) {
      final log = (json['timeLog'] as List).map((s) => TimeSession.fromJson(s));
      for (var session in log) {
        migratedTimeSpent += session.duration.inSeconds;
      }
    } else if ((json['timeSpent'] ?? 0) > 0) {
       migratedTimeSpent += (json['timeSpent'] as num).toInt();
    }

    return Milestone(
      id: json['id'],
      title: json['title'],
      deadline: DateTime.parse(json['deadline']),
      checkpoints: List<Checkpoint>.from(
          (json['checkpoints'] as List).map((c) => Checkpoint.fromJson(c))),
      completedCheckpointIds: List<String>.from(json['completedCheckpointIds']),
      timeSpentSeconds: migratedTimeSpent,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : null,
    );
  }
}
