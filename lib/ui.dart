/*
 * @author Mosses
 * @version 1.9.1
 * --- CHANGELOG ---
 * v1.9.1:
 * - [REFACTOR] REMOVED MilestonesPage, SettingsPage, MilestoneNode, LinePainter, 
 * AddMilestoneForm. These have been moved to their own files to prevent conflicts
 * and enable new features (Drag & Drop, Swipe).
 * - [FIX] Added import to `milestones_page.dart` so GoalDetailsPage works.
 */
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import './models.dart';
import './services.dart';
import './notification_service.dart';
import 'milestones_page.dart'; // NEW IMPORT: To access MilestoneNode

// --- Keys for SharedPreferences Timer Recovery ---
const String kRecoveryTimeKey = 'recovery_time_seconds';
const String kRecoveryMilestoneKey = 'recovery_milestone_id';

class HomePage extends StatefulWidget {
  final Goal? activeGoal;
  final Function(String) onSetGoal;
  final Function(String, Duration) onTimeAdd;
  final VoidCallback onGiveUp;

  const HomePage(
      {super.key,
      this.activeGoal,
      required this.onSetGoal,
      required this.onTimeAdd,
      required this.onGiveUp});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _suggestion = "";
  bool _isLoading = true;

  Milestone? get _nextMilestone {
    if (widget.activeGoal == null) return null;
    for (final milestone in widget.activeGoal!.milestones) {
      if (!milestone.isCompleted) {
        return milestone;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _fetchSuggestion();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeGoal?.id != widget.activeGoal?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fetchSuggestion();
        }
      });
    }
  }

  Future<void> _fetchSuggestion() async {
    setState(() => _isLoading = true);

    if (_nextMilestone == null) {
      if (mounted) {
        setState(() {
          _suggestion = "";
          _isLoading = false;
        });
      }
      return;
    }

    const storage = FlutterSecureStorage();
    final String currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final String? currentMilestoneId = _nextMilestone?.id;

    final String? cachedDate = await storage.read(key: 'suggestion_cache_date');
    final String? cachedMilestoneId =
        await storage.read(key: 'suggestion_cache_milestone_id');
    final String? cachedSuggestion =
        await storage.read(key: 'suggestion_cache_content');

    if (cachedDate == currentDate &&
        cachedMilestoneId == currentMilestoneId &&
        cachedSuggestion != null) {
      if (mounted) {
        setState(() {
          _suggestion = cachedSuggestion;
          _isLoading = false;
        });
      }
      return;
    }

    final result = await SuggestionService.getSuggestion(
        widget.activeGoal, _nextMilestone);

    if (mounted) {
      String textToShow;
      if (result.suggestion != null) {
        textToShow = result.suggestion!;
        await storage.write(key: 'suggestion_cache_date', value: currentDate);
        await storage.write(
            key: 'suggestion_cache_milestone_id',
            value: currentMilestoneId ?? '');
        await storage.write(key: 'suggestion_cache_content', value: textToShow);
      } else {
        if (result.error == "NO_API_KEY") {
          textToShow =
              "AI features are offline. (Dev: Check _appsScriptUrl in services.dart)";
          debugPrint("CRITICAL: _appsScriptUrl is not set in services.dart");
        } else {
          textToShow = await QuoteService.getQuote();
        }
      }

      setState(() {
        _suggestion = textToShow;
        _isLoading = false;
      });
    }
  }

  Widget _buildGoalDisplay(
      bool isPortrait, double timerSize, double spacerHeight) {
    if (widget.activeGoal!.milestones.isEmpty) {
      return const Center(
        child: Text(
          "Goal set! Go to the Milestones page to add your first task.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
        ),
      );
    }
    if (_nextMilestone == null) {
      return const Center(
        child: Text(
          "All milestones complete! 🎉",
          style: TextStyle(fontSize: 18),
        ),
      );
    }

    final Widget timerWidget = GoalTimerCircle(
      key: ValueKey(widget.activeGoal!.totalTimeSpent.inSeconds),
      goal: widget.activeGoal!,
      nextMilestone: _nextMilestone!,
      onTimeAdd: widget.onTimeAdd,
      size: timerSize,
    );

    final Widget suggestionWidget = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Text(
            _suggestion,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                color: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withAlpha(204)),
          );

    if (isPortrait) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: spacerHeight),
          timerWidget,
          SizedBox(height: spacerHeight),
          suggestionWidget,
        ],
      );
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          timerWidget,
          SizedBox(width: spacerHeight * 2),
          Flexible(
            child: suggestionWidget,
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.activeGoal?.title ?? 'Track It'),
        actions: [
          if (widget.activeGoal != null)
            IconButton(
              icon: const Icon(Icons.outlined_flag_rounded),
              tooltip: 'Give Up Goal',
              onPressed: widget.onGiveUp,
            ),
        ],
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isPortrait = orientation == Orientation.portrait;
          final double timerSize = isPortrait ? 200.0 : 140.0;
          final double spacerHeight = isPortrait ? 40.0 : 20.0;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: widget.activeGoal == null
                    ? GoalSetterCard(onSetGoal: widget.onSetGoal)
                    : _buildGoalDisplay(isPortrait, timerSize, spacerHeight),
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- GoalTimerCircle ---
class GoalTimerCircle extends StatefulWidget {
  final Goal goal;
  final Milestone nextMilestone;
  final Function(String, Duration) onTimeAdd;
  final double size;

  const GoalTimerCircle({
    super.key,
    required this.goal,
    required this.nextMilestone,
    required this.onTimeAdd,
    required this.size,
  });

  @override
  State<GoalTimerCircle> createState() => _GoalTimerCircleState();
}

class _GoalTimerCircleState extends State<GoalTimerCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  Timer? _timer;
  int _secondsElapsed = 0;
  bool _isTimerRunning = false;
  bool _showTimer = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..addListener(() {
        setState(() {});
      });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _timer?.cancel();
    if (_isTimerRunning) {
      NotificationService().cancelFocusNotification();
    }
    super.dispose();
  }

  void _startTimer() async {
    setState(() {
      _isTimerRunning = true;
      _showTimer = true;
    });
    _animationController.value = 1.5;

    const storage = FlutterSecureStorage();
    await storage.delete(key: kRecoveryTimeKey);
    await storage.delete(key: kRecoveryMilestoneKey);

    NotificationService().showFocusNotification(
      widget.nextMilestone.title,
      json.encode({'action': 'OPEN_HOME'}),
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsElapsed++;
      });
      if (_secondsElapsed % 5 == 0) {
        storage.write(key: kRecoveryTimeKey, value: _secondsElapsed.toString());
        storage.write(
            key: kRecoveryMilestoneKey, value: widget.nextMilestone.id);
      }
    });
  }

  void _stopTimer() async {
    _timer?.cancel();
    NotificationService().cancelFocusNotification();

    const storage = FlutterSecureStorage();
    await storage.delete(key: kRecoveryTimeKey);
    await storage.delete(key: kRecoveryMilestoneKey);

    if (_secondsElapsed > 0) {
      widget.onTimeAdd(
          widget.nextMilestone.id, Duration(seconds: _secondsElapsed));
    }

    setState(() {
      _secondsElapsed = 0;
      _isTimerRunning = false;
      _showTimer = false;
      _animationController.reset();
    });
  }

  void _onLongPress() {
    if (_isTimerRunning) {
      _stopTimer();
    } else {
      _startTimer();
    }
  }

  void _onTap() {
    if (_isTimerRunning) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Hold the circle to stop the session."),
        duration: Duration(seconds: 2),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Hold the circle to start a focus session."),
        duration: Duration(seconds: 2),
      ));
    }
  }

  String _formatTotalTime(Duration duration) {
    if (duration.inHours > 0) {
      return "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";
    }
    if (duration.inMinutes > 0) {
      return "${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s";
    }
    if (duration.inSeconds > 0) {
      return "${duration.inSeconds}s";
    }
    return "0m 0s";
  }

  String _formatRunningTime(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    final String totalTimeText = _formatTotalTime(widget.goal.totalTimeSpent);
    final double baseFontSize = widget.size / 5.5; 
    final double fontSize = totalTimeText.length > 8
        ? baseFontSize * 0.83
        : baseFontSize; 

    final TextStyle numberStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      color: primaryColor,
    );
    final TextStyle unitStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.normal,
      color: primaryColor.withAlpha(128),
    );

    final List<TextSpan> spans = [];
    final RegExp simpleRegex = RegExp(r'(\d+)([hms])');
    final parts =
        totalTimeText.split(' '); 

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      final match = simpleRegex.firstMatch(part); 

      if (match != null) {
        spans.add(TextSpan(text: match.group(1), style: numberStyle));
        spans.add(TextSpan(text: match.group(2), style: unitStyle));
        if (i < parts.length - 1) {
          spans.add(TextSpan(text: ' ', style: numberStyle));
        }
      } else {
        spans.add(TextSpan(text: part, style: numberStyle));
      }
    }

    return GestureDetector(
      onLongPress: _onLongPress,
      onTap: _onTap,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: CircularProgressIndicator(
                value: _animationController.value,
                strokeWidth: 10,
                backgroundColor: Theme.of(context).dividerColor,
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
            Container(
              width: widget.size - 20,
              height: widget.size - 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withAlpha(26),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              firstChild: Text(
                _formatRunningTime(_secondsElapsed),
                style: TextStyle(
                  fontSize: widget.size / 5.5,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                  fontFamily: 'monospace',
                ),
              ),
              secondChild: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: spans,
                ),
              ),
              crossFadeState: _showTimer
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
            ),
          ],
        ),
      ),
    );
  }
}

// --- MyJourneyPage ---
class MyJourneyPage extends StatelessWidget {
  final List<Goal> allGoals;
  const MyJourneyPage({super.key, required this.allGoals});

  @override
  Widget build(BuildContext context) {
    List<Goal> sortedGoals = List.from(allGoals);
    sortedGoals.sort((a, b) {
      if (a.status == GoalStatus.active) return -1;
      if (b.status == GoalStatus.active) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });

    return Scaffold(
      appBar: AppBar(title: const Text("My Journey")),
      body: sortedGoals.isEmpty
          ? const Center(child: Text("Your journey hasn't started yet!"))
          : ListView.builder(
              itemCount: sortedGoals.length,
              itemBuilder: (context, index) {
                final goal = sortedGoals[index];
                Color color;
                IconData icon;
                final String statusText = goal.status.name[0].toUpperCase() +
                    goal.status.name.substring(1);

                switch (goal.status) {
                  case GoalStatus.active:
                    color = Colors.amber.shade700;
                    icon = Icons.flag_rounded;
                    break;
                  case GoalStatus.achieved:
                    color = Colors.green;
                    icon = Icons.check_circle_rounded;
                    break;
                  case GoalStatus.givenUp:
                    color = Colors.red;
                    icon = Icons.cancel_rounded;
                    break;
                }
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => GoalDetailsPage(goal: goal),
                      ));
                    },
                    child: ListTile(
                      leading: Icon(icon, color: color),
                      title: Text(goal.title,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          "Set on: ${DateFormat.yMMMd().format(goal.createdAt)}"),
                      trailing: Text(statusText.toUpperCase(),
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// --- GoalDetailsPage ---
class GoalDetailsPage extends StatelessWidget {
  final Goal goal;
  const GoalDetailsPage({super.key, required this.goal});

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";
    }
    if (duration.inMinutes > 0) {
      return "${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s";
    }
    return "${duration.inSeconds}s";
  }

  @override
  Widget build(BuildContext context) {
    final Color lineColor = Theme.of(context).dividerColor;

    Color statusColor;
    IconData statusIcon;
    final String statusText =
        goal.status.name[0].toUpperCase() + goal.status.name.substring(1);

    switch (goal.status) {
      case GoalStatus.active:
        statusColor = Colors.amber.shade700;
        statusIcon = Icons.flag_rounded;
        break;
      case GoalStatus.achieved:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_rounded;
        break;
      case GoalStatus.givenUp:
        statusColor = Colors.red;
        statusIcon = Icons.cancel_rounded;
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(goal.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Goal Summary",
                      style: Theme.of(context).textTheme.titleLarge),
                  const Divider(height: 24),
                  _DetailRow(
                    icon: statusIcon,
                    iconColor: statusColor,
                    title: "Status",
                    value: statusText,
                  ),
                  _DetailRow(
                    icon: Icons.calendar_today_rounded,
                    title: "Created On",
                    value: DateFormat.yMMMd().format(goal.createdAt),
                  ),
                  _DetailRow(
                    icon: Icons.timer_rounded,
                    title: "Total Time Spent",
                    value: _formatDuration(goal.totalTimeSpent),
                  ),
                  _DetailRow(
                    icon: Icons.task_alt_rounded,
                    title: "Tasks Completed",
                    value: "${goal.completedTasks} / ${goal.totalTasks}",
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text("Milestones", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),

          if (goal.milestones.isEmpty)
            const Center(
              child: Text("No milestones were added for this goal."),
            )
          else
            ...goal.milestones.map((milestone) {
              final index = goal.milestones.indexOf(milestone);
              return MilestoneNode(
                key: ValueKey(milestone.id),
                milestone: milestone,
                isFirst: index == 0,
                isLast: index == goal.milestones.length - 1,
                onToggleCheckpoint: (m, c) {}, 
                onDelete: () {}, 
                editMode: false, 
                lineColor: lineColor,
              );
            }),
        ],
      ),
    );
  }
}

// --- Helper widget for GoalDetailsPage ---
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? iconColor;

  const _DetailRow(
      {required this.icon,
      required this.title,
      required this.value,
      this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon,
              color: iconColor ?? Theme.of(context).colorScheme.primary,
              size: 20),
          const SizedBox(width: 16),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// --- GoalSetterCard ---
class GoalSetterCard extends StatefulWidget {
  final Function(String) onSetGoal;
  final bool isNewGoal;
  const GoalSetterCard(
      {super.key, required this.onSetGoal, this.isNewGoal = false});

  @override
  State<GoalSetterCard> createState() => _GoalSetterCardState();
}

class _GoalSetterCardState extends State<GoalSetterCard> {
  final _controller = TextEditingController();

  void _submit() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onSetGoal(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isNewGoal)
              const Text("Previous Goal Achieved!",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green)),
            const SizedBox(height: 8),
            Text(
                widget.isNewGoal
                    ? "What's your next big goal?"
                    : "What is your main goal?",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: "e.g., Launch My App",
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submit,
              child: const Text("Set New Goal"),
            ),
          ],
        ),
      ),
    );
  }
}

// --- NotificationsSettingsPage (Unchanged logic) ---
class NotificationsSettingsPage extends StatefulWidget {
  final Goal? activeGoal;
  const NotificationsSettingsPage({super.key, this.activeGoal});

  @override
  NotificationsSettingsPageState createState() =>
      NotificationsSettingsPageState();
}

class NotificationsSettingsPageState extends State<NotificationsSettingsPage> {
  int _notificationCount = 1;
  List<TimeOfDay> _notificationTimes = [const TimeOfDay(hour: 9, minute: 0)];
  bool _isLoading = true;
  bool _hasExactAlarmPermission = false;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    var status = await Permission.scheduleExactAlarm.status;
    if (status.isDenied) {
      status = await Permission.scheduleExactAlarm.request();
    }
    if (mounted) {
      setState(() {
        _hasExactAlarmPermission = status.isGranted;
      });
    }
  }

  Future<void> _loadSettings() async {
    final notificationCountString =
        await _storage.read(key: 'notification_count');
    final timeStringsJson = await _storage.read(key: 'notification_times');

    setState(() {
      _notificationCount = notificationCountString != null
          ? int.parse(notificationCountString)
          : 1;
      if (timeStringsJson != null) {
        final List<String> timeStrings =
            List<String>.from(json.decode(timeStringsJson));
        _notificationTimes = timeStrings.map((t) {
          final parts = t.split(':');
          return TimeOfDay(
              hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }).toList();
      } else {
        _notificationTimes = [const TimeOfDay(hour: 9, minute: 0)];
      }
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    await _storage.write(
        key: 'notification_count', value: _notificationCount.toString());
    final timeStrings =
        _notificationTimes.map((t) => '${t.hour}:${t.minute}').toList();
    await _storage.write(
        key: 'notification_times', value: json.encode(timeStrings));
  }

  void _updateAndSaveChanges() async {
    if (!_hasExactAlarmPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.red,
          content: Text("Permission denied. Cannot schedule notifications.")));
      return;
    }

    final oldNotificationCountString =
        await _storage.read(key: 'notification_count');
    final int oldNotificationCount = oldNotificationCountString != null
        ? int.parse(oldNotificationCountString)
        : 0;

    for (int i = 0; i < oldNotificationCount; i++) {
      await NotificationService().cancelNotification(i);
    }

    for (int i = 0; i < _notificationCount; i++) {
      String payload = '';
      if (widget.activeGoal != null) {
        final nextMilestone = widget.activeGoal!.milestones.firstWhere(
            (m) => !m.isCompleted,
            orElse: () => Milestone(
                title: '', deadline: DateTime.now(), checkpoints: []));
        if (nextMilestone.title.isNotEmpty) {
          final nextCheckpoint = nextMilestone.checkpoints.firstWhere(
              (c) => !nextMilestone.completedCheckpointIds.contains(c.id),
              orElse: () => Checkpoint(title: ''));
          if (nextCheckpoint.title.isNotEmpty) {
            payload = json.encode({
              'goalId': widget.activeGoal!.id,
              'milestoneId': nextMilestone.id,
              'checkpointId': nextCheckpoint.id,
            });
          }
        }
      }

      await NotificationService().scheduleReminderNotification(
        id: i,
        title: 'Milestone Reminder',
        body: 'How are you doing with your goals today?',
        payload: payload,
        hour: _notificationTimes[i].hour,
        minute: _notificationTimes[i].minute,
      );
    }

    await _saveSettings();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Notification settings saved!")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Notifications")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_hasExactAlarmPermission)
                  Card(
                    color: Colors.red.shade100,
                    child: const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          Text("Permission Required",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red)),
                          SizedBox(height: 8),
                          Text(
                            "This app needs permission to schedule exact alarms for notifications to work correctly. Please grant this permission in your phone's settings.",
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 8),
                          TextButton(
                              onPressed: openAppSettings,
                              child: Text("Open Settings"))
                        ],
                      ),
                    ),
                  ),
                Text("Number of daily reminders: $_notificationCount"),
                Slider(
                  value: _notificationCount.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  label: _notificationCount.toString(),
                  onChanged: (value) {
                    setState(() {
                      final newCount = value.toInt();
                      while (_notificationTimes.length < newCount) {
                        _notificationTimes
                            .add(const TimeOfDay(hour: 9, minute: 0));
                      }
                      while (_notificationTimes.length > newCount) {
                        _notificationTimes.removeLast();
                      }
                      _notificationCount = newCount;
                    });
                  },
                ),
                const Divider(),
                for (int i = 0; i < _notificationCount; i++)
                  ListTile(
                    title: Text("Reminder ${i + 1}"),
                    trailing: Text(_notificationTimes[i].format(context)),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _notificationTimes[i],
                      );
                      if (time != null) {
                        setState(() {
                          _notificationTimes[i] = time;
                        });
                      }
                    },
                  ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _updateAndSaveChanges,
                  child: const Text("Save Settings"),
                )
              ],
            ),
    );
  }
}

// --- GetInTouchPage (Unchanged) ---
class GetInTouchPage extends StatelessWidget {
  const GetInTouchPage({super.key});

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Get in Touch")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.email_rounded),
                title: const Text("Contact Us"),
                subtitle: const Text("For feedback or support"),
                onTap: () => _launchURL(
                    "mailto:pachamangacorp@gmail.com?subject=Feedback for Milestone App"),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.favorite_rounded, color: Colors.red),
                title: const Text("Donate"),
                subtitle: const Text("Support the development"),
                onTap: () => _launchURL(
                    "https://drive.google.com/file/d/1b2s0u5msfpqn7finiw8Vx1ELgbWUrbW9/view?usp=sharing"),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.code_rounded),
                title: const Text("Contribute"),
                subtitle: const Text("Help improve the app on GitHub"),
                onTap: () => _launchURL(
                    "https://github.com/MossesRoss/trackit/edit/main/main.dart"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}