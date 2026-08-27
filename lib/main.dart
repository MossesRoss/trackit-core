/*
 * @author Mosses
 * @version 2.0.2
 * --- CHANGELOG ---
 * v2.0.2:
 * - [FIX] Resolved UI pixel overflow in stealth glass ring navigation using FittedBox.
 * - [FEAT] Added intelligent Bottleneck Detection for deferred tasks.
 * - [FEAT] Added Dynamic Baseline Performance Tracking to appreciate high-velocity execution.
 * v2.0.1:
 * - [REFACTOR] Removed intrusive HUD overlays.
 * - [FEAT] Implemented minimalist stealth glass ring navigation.
 */
import 'dart:ui';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'firebase_options.dart';

import './models.dart';
import './services.dart';
import './ui.dart'; // Keeping ui.dart for HomePage only
import './auth_screen.dart';
import './notification_service.dart';
import 'reports_page.dart';
import 'milestones_page.dart';
import 'settings_page.dart';

const String kRecoveryTimeKey = 'recovery_time_seconds';
const String kRecoveryMilestoneKey = 'recovery_milestone_id';
const String _oldLocalCacheKey = 'all_goals_cache';
const String _kThemePersistenceKey = 'theme_mode';
const String _kEditModePersistenceKey = 'edit_mode';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  final _storage = const FlutterSecureStorage();

  ThemeProvider() {
    _loadTheme();
  }

  void _loadTheme() async {
    try {
      final themeIndexString = await _storage.read(key: _kThemePersistenceKey);
      if (themeIndexString != null) {
        final themeIndex = int.parse(themeIndexString);
        _themeMode = ThemeMode.values[themeIndex];
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error loading theme: $e");
    }
  }

  void toggleTheme() async {
    _themeMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();

    try {
      await _storage.write(
          key: _kThemePersistenceKey, value: _themeMode.index.toString());
    } catch (e) {
      debugPrint("Error saving theme: $e");
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  try {
    const storage = FlutterSecureStorage();
    await storage.delete(key: _oldLocalCacheKey);
    debugPrint("MIGRATION: Removed old, non-user-specific goals cache.");
  } catch (e) {
    debugPrint("Error during one-time cache migration: $e");
  }

  await NotificationService().init();

  if (!kIsWeb && Platform.isAndroid) {
    var status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }
  }

  const MethodChannel timezoneChannel =
      MethodChannel('com.example.trackit/timezone');
  String timeZoneName;
  try {
    timeZoneName = await timezoneChannel.invokeMethod('getLocalTimezone');
  } on PlatformException {
    timeZoneName = 'America/Detroit';
    debugPrint("Failed to get native timezone, using default: $timeZoneName");
  } catch (e) {
    timeZoneName = 'America/Detroit';
    debugPrint(
        "Error getting native timezone: $e, using default: $timeZoneName");
  }

  try {
    tz.initializeTimeZones();
    if (!kIsWeb) {
      if (Platform.isAndroid || Platform.isIOS) {
        tz.setLocalLocation(tz.getLocation(timeZoneName));
        debugPrint("Timezone set to: ${tz.local.name}");
      }
    }
  } catch (e) {
    debugPrint("Error initializing/setting timezone: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthService()),
        ProxyProvider<AuthService, FirestoreService>(
            update: (_, auth, previous) {
          debugPrint(
              "ProxyProvider update: auth.currentUser?.uid = ${auth.currentUser?.uid}");
          if (previous == null || previous.uid != auth.currentUser?.uid) {
            return FirestoreService(auth.currentUser?.uid);
          }
          return previous;
        }),
      ],
      child: const MilestoneApp(),
    ),
  );
}

class MilestoneApp extends StatelessWidget {
  const MilestoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: Colors.indigo,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade300),
        ),
      ),
    );
    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: Colors.indigo,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade800),
        ),
      ),
    );

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Track It',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeProvider.themeMode,
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    debugPrint("AuthWrapper build: Listening to auth state.");

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          debugPrint("AuthWrapper: Waiting for auth state...");
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          debugPrint(
              "AuthWrapper: User is logged in (uid: ${snapshot.data?.uid}). Showing MainPage.");
          return const MainPage();
        }
        debugPrint("AuthWrapper: User is logged out. Showing AuthScreen.");
        return const AuthScreen();
      },
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  List<Goal> _allGoals = [];
  bool _editMode = true;
  bool _isLoading = true;
  bool _dismissedBanner = false;

  // --- Analytics & Insights State ---
  final Map<String, int> _taskDelayCounters =
      {}; // Tracks deferred tasks for bottlenecks

  // --- PWA-style Navigation Matrix States ---
  bool _isNavActive = false;
  int? _hoveredTab;
  Offset _pointerPos = Offset.zero;
  Offset _pointerDownPos = Offset.zero;
  bool _longPressArmed = false;

  // Page metadata matching PWA structure
  static const List<Map<String, dynamic>> _navPages = [
    {'id': 0, 'title': 'HOME', 'icon': Icons.home_rounded},
    {'id': 1, 'title': 'REPORTS', 'icon': Icons.bar_chart_rounded},
    {'id': 2, 'title': 'MILESTONES', 'icon': Icons.flag_rounded},
    {'id': 3, 'title': 'SETTINGS', 'icon': Icons.settings_rounded},
  ];

  // Keys for hit-testing nav targets
  final List<GlobalKey> _navTargetKeys = List.generate(4, (_) => GlobalKey());

  Goal? get _activeGoal {
    try {
      return _allGoals.firstWhere((g) => g.status == GoalStatus.active);
    } catch (e) {
      return null;
    }
  }

  final bool _clearCacheOnStartup = false;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _configureSelectNotificationSubject();
    _loadGoalsAndProcessLaunch();
  }

  void _configureSelectNotificationSubject() {
    NotificationService().notificationSubject.stream.listen((response) async {
      debugPrint(
          'NotificationResponse received by listener (app-running): payload=${response.payload}, actionId=${response.actionId}');

      if (_isLaunchNotification(response)) {
        debugPrint(
            "Ignoring notification because it was just processed on launch.");
        return;
      }

      if (mounted) {
        _showCheckinDialog(response);
      }
    });
  }

  NotificationResponse? _processedLaunchNotification;

  bool _isLaunchNotification(NotificationResponse response) {
    if (_processedLaunchNotification == null) {
      return false;
    }
    return _processedLaunchNotification!.payload == response.payload;
  }

  Future<void> _setEditMode(bool newValue) async {
    setState(() {
      _editMode = newValue;
    });

    try {
      await _storage.write(
          key: _kEditModePersistenceKey, value: newValue.toString());
      debugPrint("Saved editMode: $newValue");
    } catch (e) {
      debugPrint("Error saving edit mode preference: $e");
    }
  }

  Future<void> _loadGoalsAndProcessLaunch() async {
    debugPrint("[DEBUG] _loadGoalsAndProcessLaunch: Starting...");
    setState(() => _isLoading = true);

    try {
      debugPrint("[DEBUG] Loading edit mode...");
      final savedEditModeString =
          await _storage.read(key: _kEditModePersistenceKey);
      if (savedEditModeString != null) {
        final savedEditMode = savedEditModeString.toLowerCase() == 'true';
        if (mounted) {
          setState(() {
            _editMode = savedEditMode;
          });
          debugPrint("[DEBUG] Loaded editMode: $_editMode");
        }
      }
    } catch (e) {
      debugPrint("[DEBUG] Error loading edit mode preference: $e");
    }

    try {
      debugPrint("[DEBUG] Loading goals...");
      if (!mounted) return;
      final persistenceService =
          Provider.of<FirestoreService>(context, listen: false);

      if (_clearCacheOnStartup) {
        try {
          if (persistenceService.uid != null) {
            final userCacheKey = 'all_goals_cache_${persistenceService.uid}';
            await _storage.delete(key: userCacheKey);
          }
        } catch (e) {
          debugPrint("[DEBUG] Error clearing cache: $e");
        }
      }

      final goals = await persistenceService.loadGoals();
      if (!mounted) {
        return;
      }

      _allGoals = goals;
      _updateMilestoneLockStatus();
    } catch (e) {
      debugPrint("[DEBUG] Error loading goals: $e");
    }

    try {
      debugPrint("[DEBUG] Processing launch notification...");
      final notificationAppLaunchDetails =
          await NotificationService().getNotificationAppLaunchDetails();

      if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
        final notificationResponse =
            notificationAppLaunchDetails!.notificationResponse;
        if (notificationResponse != null) {
          debugPrint(
              "[DEBUG] App LAUNCHED from notification tap. Processing payload directly...");
          _processedLaunchNotification = notificationResponse;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showCheckinDialog(notificationResponse);
            }
          });
        }
      }
    } catch (e) {
      debugPrint("[DEBUG] Error processing launch notification: $e");
    }

    try {
      debugPrint("[DEBUG] Recovering timer...");
      final recoveredSecondsString = await _storage.read(key: kRecoveryTimeKey);
      final recoveredMilestoneId =
          await _storage.read(key: kRecoveryMilestoneKey);

      if (recoveredSecondsString != null && recoveredMilestoneId != null) {
        final recoveredSeconds = int.parse(recoveredSecondsString);
        if (recoveredSeconds > 0) {
          _addTimeToMilestone(
              recoveredMilestoneId, Duration(seconds: recoveredSeconds));

          await _storage.delete(key: kRecoveryTimeKey);
          await _storage.delete(key: kRecoveryMilestoneKey);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      "Recovered ${recoveredSeconds}s from your last session."),
                  backgroundColor: Colors.green,
                ),
              );
            }
          });
        }
      }
    } catch (e) {
      debugPrint("[DEBUG] RECOVERY ERROR: Failed to process recovery data: $e");
      try {
        await _storage.delete(key: kRecoveryTimeKey);
        await _storage.delete(key: kRecoveryMilestoneKey);
      } catch (clearError) {
        debugPrint(
            "[DEBUG] RECOVERY ERROR: Failed to clear recovery keys during error handling: $clearError");
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
    debugPrint("[DEBUG] _loadGoalsAndProcessLaunch: Finished.");
  }

  Future<void> _saveGoals() async {
    final persistenceService =
        Provider.of<FirestoreService>(context, listen: false);
    await persistenceService.saveGoals(_allGoals);
  }

  void _setMainGoal(String goalTitle) {
    setState(() {
      final currentActiveGoal = _activeGoal;
      if (currentActiveGoal != null) {
        currentActiveGoal.status = GoalStatus.givenUp;
        Provider.of<FirestoreService>(context, listen: false)
            .archiveGoal(currentActiveGoal);
      }
      final newGoal = Goal(title: goalTitle);
      _allGoals.add(newGoal);
      _selectedIndex = 2; // FIX: Go to milestones page
    });
    _saveGoals();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Goal Set!'),
          content: const Text(
              'Your new goal is active. Head to the Milestones page to add your first task!'),
          actions: [
            TextButton(
              child: const Text('Okay'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
    });
  }

  void _giveUpGoal() {
    if (_activeGoal == null) return;

    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text(
            'Are you sure you want to give up on this goal? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Give Up', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        if (!mounted) return;
        setState(() {
          _activeGoal!.status = GoalStatus.givenUp;
          Provider.of<FirestoreService>(context, listen: false)
              .archiveGoal(_activeGoal!);
        });
        _saveGoals();
      }
    });
  }

  void _addMilestone(Milestone milestone) {
    if (_activeGoal == null) return;
    setState(() {
      _activeGoal?.milestones.add(milestone);
      _updateMilestoneLockStatus();
    });
    _saveGoals();
  }

  // Dynamic Baseline Logic (Appreciation Engine)
  void _analyzePerformance(Milestone completedMilestone) {
    if (_activeGoal == null) return;

    // Find previously completed milestones to establish a baseline
    final historicalMilestones = _activeGoal!.milestones
        .where((m) => m.isCompleted && m.id != completedMilestone.id)
        .toList();

    if (historicalMilestones.isNotEmpty) {
      final totalHistoricalTime = historicalMilestones.fold<int>(
          0, (sum, m) => sum + m.timeSpent.inSeconds);
      final averageTime = totalHistoricalTime / historicalMilestones.length;

      // If completed at least 20% faster than the historical average
      if (averageTime > 0 &&
          completedMilestone.timeSpent.inSeconds < averageTime * 0.8) {
        final percentageFaster =
            ((1 - (completedMilestone.timeSpent.inSeconds / averageTime)) * 100)
                .toInt();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.bolt, color: Colors.amber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "High Leverage Execution: You completed this $percentageFaster% faster than your average baseline.",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.indigo.shade800,
              duration: const Duration(seconds: 4),
            ),
          );
        });
      }
    }
  }

  Future<void> _toggleCheckpoint(
      Milestone milestone, String checkpointId) async {
    final persistenceService =
        Provider.of<FirestoreService>(context, listen: false);
    bool isCompleted = false;

    setState(() {
      if (milestone.completedCheckpointIds.contains(checkpointId)) {
        milestone.completedCheckpointIds.remove(checkpointId);
      } else {
        milestone.completedCheckpointIds.add(checkpointId);
        isCompleted = true;
      }

      if (milestone.isCompleted && milestone.completedAt == null) {
        milestone.completedAt = DateTime.now();
        // TRIGGER DYNAMIC BASELINE ANALYSIS
        _analyzePerformance(milestone);
      } else if (!milestone.isCompleted && milestone.completedAt != null) {
        milestone.completedAt = null;
      }
    });

    if (_activeGoal != null) {
      await persistenceService.recordTaskCompletion(
          _activeGoal!.id, milestone.id, checkpointId, isCompleted);
    }

    _updateMilestoneLockStatus();

    final bool didGoalComplete = await _checkForGoalCompletion();
    if (!didGoalComplete) {
      await _saveGoals();
    }
  }

  Future<void> toggleCheckpointByIds(
      String goalId, String milestoneId, String checkpointId) async {
    Goal? goal;
    try {
      goal = _allGoals.firstWhere((g) => g.id == goalId);
    } catch (e) {
      return;
    }

    Milestone? milestone;
    try {
      milestone = goal.milestones.firstWhere((m) => m.id == milestoneId);
    } catch (e) {
      return;
    }

    if (milestone.checkpoints.any((c) => c.id == checkpointId)) {
      await _toggleCheckpoint(milestone, checkpointId);
    }
  }

  Future<bool> _checkForGoalCompletion() async {
    final Goal? goalToComplete = _activeGoal;

    if (goalToComplete != null && goalToComplete.isCompleted) {
      if (!mounted) return false;

      setState(() {
        goalToComplete.status = GoalStatus.achieved;
        _editMode = true;
      });

      try {
        await Provider.of<FirestoreService>(context, listen: false)
            .archiveGoal(goalToComplete);
        await _saveGoals();
      } catch (e) {
        debugPrint("Error during goal completion/archiving: $e");
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Goal Achieved!'),
            content: Text(
                'Congratulations! You have completed all milestones for "${goalToComplete.title}".'),
            actions: [
              TextButton(
                child: const Text('Awesome!'),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      });
      return true;
    }
    return false;
  }

  void _deleteMilestone(String id) {
    if (_activeGoal == null) return;
    setState(() {
      _activeGoal?.milestones.removeWhere((m) => m.id == id);
      _updateMilestoneLockStatus();
    });
    _saveGoals();
  }

  Future<void> _addTimeToMilestone(
      String milestoneId, Duration timeToAdd, {String? checkpointId}) async {
    if (_activeGoal == null || timeToAdd.inSeconds <= 0) return;

    final persistenceService =
        Provider.of<FirestoreService>(context, listen: false);
    await persistenceService.addTimeSession(
        _activeGoal!.id, milestoneId, timeToAdd);

    setState(() {
      Milestone? milestone;
      try {
        milestone =
            _activeGoal!.milestones.firstWhere((m) => m.id == milestoneId);
      } catch (e) {
        return;
      }

      milestone.timeLog.add(TimeSession(
        timestamp: DateTime.now(),
        duration: timeToAdd,
        checkpointId: checkpointId,
      ));
    });
    _saveGoals();
  }

  Future<void> recordTaskCheckin(String goalId, String milestoneId,
      String checkpointId, TaskCheckinStatus status) async {
    final persistenceService =
        Provider.of<FirestoreService>(context, listen: false);

    // Algorithmic Course Correction (Bottleneck Logic)
    if (status == TaskCheckinStatus.willDo) {
      _taskDelayCounters[checkpointId] =
          (_taskDelayCounters[checkpointId] ?? 0) + 1;

      if (_taskDelayCounters[checkpointId]! >= 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row( // FIX: Added const to the Row as requested by IDE
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Bottleneck Detected'),
                ],
              ),
              content: const Text(
                  'You have deferred this task 3 times. If it is not serving the Grand Goal, eliminate it. If it is too complex, break it down into smaller sub-tasks.'),
              actions: [
                TextButton(
                  child: const Text('Acknowledge'),
                  onPressed: () {
                    _taskDelayCounters[checkpointId] = 0; // Reset after warning
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          );
        });
      }
    } else if (status == TaskCheckinStatus.done) {
      _taskDelayCounters.remove(checkpointId); // Clean up on completion
    }

    await persistenceService.recordTaskCheckin(
        goalId, milestoneId, checkpointId, status);
  }

  void _updateMilestoneLockStatus() {
    if (_activeGoal == null) return;
    
    // Changed to unlock all milestones by default, allowing free progression.
    // Previously, this locked subsequent milestones until the current one was completed.
    for (var m in _activeGoal!.milestones) {
      if (!m.isUnlocked) {
        m.isUnlocked = true;
      }
    }
  }

  String _calculateTrajectory(Milestone m) {
    try {
      final totalTasks = m.checkpoints.length;
      final completedTasks = m.completedCheckpointIds.length;
      final timeSpent = m.timeSpent.inSeconds;

      if (totalTasks == 0) return "AWAITING TASKS";
      if (completedTasks == 0) return "TRAJECTORY: AWAITING FIRST COMPLETION";

      final avgTimePerTask = timeSpent / completedTasks;
      final remainingTasks = totalTasks - completedTasks;
      final estimatedRemainingTime = avgTimePerTask * remainingTasks;

      // Target budget: We assume a strict 45 minute (2700 seconds) per task baseline
      final budgetRemaining = 2700 * remainingTasks;

      if (estimatedRemainingTime > budgetRemaining) {
        final excess = estimatedRemainingTime - budgetRemaining;
        return "WARNING: BURN RATE EXCEEDS TARGET (+${(excess/60).toStringAsFixed(0)}m)";
      }
      return "TRAJECTORY: NOMINAL (ETA: ${(estimatedRemainingTime/60).toStringAsFixed(0)}m)";
    } catch (e) {
      return "TRAJECTORY: CALIBRATING...";
    }
  }

  void _showImportJsonDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Import AI Plan (JSON)', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: textController,
          maxLines: 10,
          style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Paste strict JSON schema here...',
            hintStyle: TextStyle(color: Colors.grey[600]),
            filled: true,
            fillColor: Colors.black,
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[800]!)),
            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.indigo)),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Abort', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            child: const Text('Initiate Protocol', style: TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold)),
            onPressed: () {
              try {
                _parseAndImportAIPlan(textController.text);
                Navigator.of(ctx).pop();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text("JSON PARSE ERROR: $e"), 
                  backgroundColor: Colors.red.shade900
                ));
              }
            },
          ),
        ],
      ),
    );
  }

  void _parseAndImportAIPlan(String jsonString) async {
    try {
      final data = json.decode(jsonString);
      final String goalTitle = data['title'] ?? 'AI Strategic Operation';

      setState(() {
        final currentActiveGoal = _activeGoal;
        if (currentActiveGoal != null) {
          currentActiveGoal.status = GoalStatus.givenUp;
          Provider.of<FirestoreService>(context, listen: false).archiveGoal(currentActiveGoal);
        }

        final newGoal = Goal(title: goalTitle);
        
        // Recursively parse milestones and checkpoints
        if (data['milestones'] != null && data['milestones'] is List) {
          for (var mData in data['milestones']) {
            final newMilestone = Milestone(
              title: mData['title'] ?? 'Strategic Phase',
              deadline: DateTime.now().add(const Duration(days: 7)),
              checkpoints: [], // FIX: Provided the required 'checkpoints' parameter
            );
            if (mData['checkpoints'] != null && mData['checkpoints'] is List) {
              for (var cData in mData['checkpoints']) {
                newMilestone.checkpoints.add(Checkpoint(title: cData['title'] ?? 'Action Item'));
              }
            }
            newGoal.milestones.add(newMilestone);
          }
        }
        
        _allGoals.add(newGoal);
        _selectedIndex = 2; // Auto-switch to Milestones page to begin execution
        _dismissedBanner = false; // Reset banner state for the new goal
      });
      
      await _saveGoals();
      
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("AI Plan Acquired. Proceed to Milestones.", style: TextStyle(fontFamily: 'monospace')), 
            backgroundColor: Colors.indigo.shade800
          ),
        );
      }
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("System Failure: Ensure strict JSON format. ($e)"), backgroundColor: Colors.red),
        );
      }
    }
  }


  // --- PWA-style Navigation Handlers ---

  void _onPointerDown(PointerDownEvent event) {
    setState(() {
      _pointerPos = event.position;
      _pointerDownPos = event.position;
      _longPressArmed = true;
    });

    // 500ms long-press to unlock the navigation matrix (matching PWA)
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_longPressArmed && mounted) {
        setState(() {
          _isNavActive = true;
        });
        HapticFeedback.heavyImpact();
      }
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isNavActive) {
      // Cancel long-press if moved too far before activation (15px threshold, matching PWA)
      if (_longPressArmed) {
        final dx = (event.position.dx - _pointerDownPos.dx).abs();
        final dy = (event.position.dy - _pointerDownPos.dy).abs();
        if (dx > 15 || dy > 15) {
          _longPressArmed = false;
        }
      }
      return;
    }

    setState(() {
      _pointerPos = event.position;
    });

    final size = MediaQuery.of(context).size;
    final origin = Offset(size.width / 2, size.height - 48); // Approximate origin of the sensor pad

    final dx = event.position.dx - origin.dx;
    final dy = origin.dy - event.position.dy; // Standard cartesian (y is up)

    final distance = math.sqrt(dx * dx + dy * dy);
    int? newHovered;

    if (distance > 30) { // Deadzone in the center so you have to actually drag out
      final angle = math.atan2(dy, dx);
      final angleDegrees = angle * 180 / math.pi;

      // Only track if moving generally upwards or far enough sideways
      if (dy > -20) {
        double checkAngle = angleDegrees;
        // Normalize slightly negative angles (if dragging straight left/right)
        if (checkAngle < 0 && dx > 0) checkAngle = 0;
        if (checkAngle < 0 && dx < 0) checkAngle = 180;

        // Sector allocation based exactly on your drawn radial arch!
        if (checkAngle > 120) {
          newHovered = 0; // Home (Far Left Sector)
        } else if (checkAngle > 90) {
          newHovered = 1; // Reports (Mid Left Sector)
        } else if (checkAngle > 60) {
          newHovered = 2; // Milestones (Mid Right Sector)
        } else {
          newHovered = 3; // Settings (Far Right Sector)
        }
      }
    }

    if (newHovered != _hoveredTab) {
      setState(() {
        _hoveredTab = newHovered;
      });
      if (newHovered != null) {
        HapticFeedback.selectionClick();
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _longPressArmed = false;

    if (_isNavActive) {
      if (_hoveredTab != null && _hoveredTab != _selectedIndex) {
        setState(() {
          _selectedIndex = _hoveredTab!;
        });
        HapticFeedback.heavyImpact();
      }
      setState(() {
        _isNavActive = false;
        _hoveredTab = null;
      });
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _longPressArmed = false;
    setState(() {
      _isNavActive = false;
      _hoveredTab = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final List<Widget> pages = [
      HomePage(
        activeGoal: _activeGoal,
        onSetGoal: _setMainGoal,
        onTimeAdd: _addTimeToMilestone,
        onGiveUp: _giveUpGoal,
      ),
      const ReportsPage(),
      MilestonesPage(
        activeGoal: _activeGoal,
        onAddMilestone: _addMilestone,
        onToggleCheckpoint: _toggleCheckpoint,
        onDeleteMilestone: _deleteMilestone,
        editMode: _editMode,
      ),
      SettingsPage(
        isDarkMode: themeProvider.isDarkMode,
        toggleDarkMode: themeProvider.toggleTheme,
        editMode: _editMode,
        onEditModeChanged: _setEditMode,
        allGoals: _allGoals,
      ),
    ];

    return Scaffold(
      body: Stack(
        children: [
          // 1. Live Page Layer
          IndexedStack(
            index: _selectedIndex,
            children: pages,
          ),

          // 1.5. Trajectory / Burn Rate HUD (Top Aligned)
          if (_activeGoal != null && _selectedIndex == 0 && !_isNavActive && !_dismissedBanner)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 20,
              right: 20,
              child: Builder(builder: (context) {
                  final activeMilestones = _activeGoal!.milestones.where((m) => !m.isCompleted).toList();
                  if (activeMilestones.isEmpty) return const SizedBox.shrink();
                  
                  final currentMilestone = activeMilestones.first;
                  final trajectoryText = _calculateTrajectory(currentMilestone);
                  final isWarning = trajectoryText.contains("WARNING");

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    padding: const EdgeInsets.only(left: 16, top: 6, bottom: 6, right: 6),
                    decoration: BoxDecoration(
                      color: isWarning ? Colors.red.withOpacity(0.9) : Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isWarning ? Colors.redAccent : Colors.white.withOpacity(0.15),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isWarning ? Colors.red.withOpacity(0.4) : Colors.black.withOpacity(0.5),
                          blurRadius: 15,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isWarning ? Icons.warning_amber_rounded : Icons.track_changes, 
                          color: isWarning ? Colors.white : Colors.greenAccent, 
                          size: 20
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            trajectoryText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            setState(() {
                              _dismissedBanner = true;
                            });
                          },
                        ),
                      ],
                    ),
                  );
                }),
            ),

          // 2. Navigation Overlay Matrix (Visible only when armed)
          if (_isNavActive)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _isNavActive ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        color: Colors.black.withOpacity(0.80),
                        child: Column(
                          children: [
                            // Status text ("AWAITING TARGET" / "DEPLOYING: PAGE")
                            Expanded(
                              flex: 2,
                              child: Center(
                                child: Text(
                                  _hoveredTab != null
                                      ? 'DEPLOYING: ${_navPages[_hoveredTab!]['title']}'
                                      : 'AWAITING TARGET',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    letterSpacing: 4,
                                    color: Colors.white.withOpacity(0.4),
                                  ),
                                ),
                              ),
                            ),

                            // Spatial Targets in arch layout
                            Expanded(
                              flex: 3,
                              child: Align(
                                alignment: const Alignment(0, 0.6),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16), // Reduced padding
                                  child: FittedBox(
                                    // FIX: Prevents overflow on narrow screens
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: List.generate(_navPages.length,
                                          (idx) {
                                        final page = _navPages[idx];
                                        final isHovered = _hoveredTab == idx;
                                        final isCurrent = _selectedIndex == idx;

                                        // Arch layout: outer items at baseline, inner items raised
                                        final double translateY =
                                            (idx == 0 || idx == 3) ? 0 : -32;

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          child: Transform.translate(
                                            offset: Offset(0, translateY),
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 200),
                                              key: _navTargetKeys[idx],
                                              width: 64,
                                              height: 64,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: isHovered
                                                    ? Colors.white
                                                    : Colors.white
                                                        .withOpacity(0.1),
                                                border: (isCurrent &&
                                                        !isHovered)
                                                    ? Border.all(
                                                        color: Colors.white
                                                            .withOpacity(0.3),
                                                        width: 2,
                                                      )
                                                    : null,
                                                boxShadow: isHovered
                                                    ? [
                                                        BoxShadow(
                                                          color: Colors.white
                                                              .withOpacity(0.4),
                                                          blurRadius: 30,
                                                          spreadRadius: 0,
                                                        ),
                                                      ]
                                                    : null,
                                              ),
                                              child: AnimatedScale(
                                                scale: isHovered ? 1.1 : 1.0,
                                                duration: const Duration(
                                                    milliseconds: 200),
                                                child: Icon(
                                                  page['icon'] as IconData,
                                                  size: 24,
                                                  color: isHovered
                                                      ? Colors.black
                                                      : Colors.white
                                                          .withOpacity(0.7),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 3. Pointer Reticle (visible when dragging over overlay)
          if (_isNavActive)
            Positioned(
              left: _pointerPos.dx - 24,
              top: _pointerPos.dy - 24,
              child: IgnorePointer(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 4. Bottom Sensor Pad (Always active, initiates the sequence)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isNavActive
                            ? Colors.transparent
                            : Colors.white.withOpacity(0.05),
                        border: _isNavActive
                            ? null
                            : Border.all(
                                color: Colors.white.withOpacity(0.1),
                                width: 1,
                              ),
                      ),
                      child: _isNavActive
                          ? null
                          : Icon(
                              Icons.my_location_rounded,
                              size: 16,
                              color: Colors.white.withOpacity(0.3),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 5. Stealth AI Import Node
          if (!_isNavActive && _selectedIndex == 0 && _editMode)
            Positioned(
              bottom: 32,
              right: 24,
              child: GestureDetector(
                onTap: _showImportJsonDialog,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.indigo.withOpacity(0.5), width: 1),
                  ),
                  child: Icon(Icons.psychology_alt_rounded, color: Colors.indigo.shade300, size: 24),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showCheckinDialog(NotificationResponse response) async {
    if (!mounted) return;

    if (response.payload == null || response.payload!.isEmpty) return;

    Map<String, dynamic> payloadData;
    String goalId, milestoneId, checkpointId;
    try {
      payloadData = json.decode(response.payload!);
      goalId = payloadData['goalId'];
      milestoneId = payloadData['milestoneId'];
      checkpointId = payloadData['checkpointId'];
    } catch (e) {
      return;
    }

    String checkpointTitle = "your task";
    try {
      final goal = _allGoals.firstWhere((g) => g.id == goalId);
      final milestone = goal.milestones.firstWhere((m) => m.id == milestoneId);
      final checkpoint =
          milestone.checkpoints.firstWhere((c) => c.id == checkpointId);
      checkpointTitle = checkpoint.title;
    } catch (e) {
      // Ignore
    }

    final context = navigatorKey.currentContext;
    if (context == null || !Navigator.of(context).mounted) return;

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text("$checkpointTitle?"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildCheckinButton(
                        dialogContext,
                        "Done",
                        Colors.green,
                        TaskCheckinStatus.done,
                        goalId,
                        milestoneId,
                        checkpointId,
                        toggle: true),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildCheckinButton(
                        dialogContext,
                        "Doing",
                        Colors.blue,
                        TaskCheckinStatus.doing,
                        goalId,
                        milestoneId,
                        checkpointId),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildCheckinButton(
                        dialogContext,
                        "Will Do",
                        Colors.orange,
                        TaskCheckinStatus.willDo,
                        goalId,
                        milestoneId,
                        checkpointId),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildCheckinButton(
                        dialogContext,
                        "Won't Do",
                        Colors.red,
                        TaskCheckinStatus.wontDo,
                        goalId,
                        milestoneId,
                        checkpointId),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCheckinButton(
    BuildContext dialogContext,
    String text,
    MaterialColor color,
    TaskCheckinStatus status,
    String goalId,
    String milestoneId,
    String checkpointId, {
    bool toggle = false,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(6.0),
        height: 100,
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.shade100, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            Navigator.of(dialogContext).pop();
            debugPrint("In-app dialog: '${status.name}' tapped.");
            recordTaskCheckin(goalId, milestoneId, checkpointId, status);
            if (toggle) {
              await toggleCheckpointByIds(goalId, milestoneId, checkpointId);
            }
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_getIconForStatus(status), size: 32, color: color.shade700),
              const SizedBox(height: 8),
              Text(
                text,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color.shade900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForStatus(TaskCheckinStatus status) {
    switch (status) {
      case TaskCheckinStatus.done:
        return Icons.check_circle;
      case TaskCheckinStatus.wontDo:
        return Icons.cancel;
      case TaskCheckinStatus.doing:
        return Icons.directions_run;
      case TaskCheckinStatus.willDo:
        return Icons.calendar_today;
    }
  }
}