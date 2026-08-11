/*
 * @author Mosses
 * @version 2.0.0
 * --- CHANGELOG ---
 * v2.0.0:
 * - [FEAT] Ironman HUD gesture-based navigation with glassmorphism overlay.
 * - [FEAT] Drag-to-scrub page switching with haptic feedback.
 * v1.9.1:
 * - [FIX] Ensured strict imports for `milestones_page.dart` and `settings_page.dart`.
 * v1.9.0:
 * - [REFACTOR] Replaced `MilestonesPage` from `ui.dart` with local modular file.
 * - [FEAT] Enabled Drag-and-Drop for Milestones.
 * - [FEAT] Added Swipe-to-Switch gesture on Avatar.
 */
import 'dart:ui'; // For ImageFilter (Glassmorphism)
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:io' show Platform;
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
import 'milestones_page.dart'; // NEW: Imported Draggable Milestones
import 'settings_page.dart'; // NEW: Imported Stealth Settings

// --- Keys for SharedPreferences Timer Recovery ---
const String kRecoveryTimeKey = 'recovery_time_seconds';
const String kRecoveryMilestoneKey = 'recovery_milestone_id';
const String _oldLocalCacheKey = 'all_goals_cache';
const String _kThemePersistenceKey = 'theme_mode';
const String _kEditModePersistenceKey = 'edit_mode';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// --- ThemeProvider (Unchanged) ---
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
  int _previewIndex = 0; // Active candidate index while dragging
  List<Goal> _allGoals = [];
  bool _editMode = true;
  bool _isLoading = true;

  // --- JARVIS / HUD Gesture Controller States ---
  bool _isDragging = false;
  bool _isNavUnlocked = false;
  Offset _touchPosition = Offset.zero;
  double _dragStartY = 0;
  double _dragAnchorX = 0;

  final List<String> _pageNames = [
    'HOME',
    'REPORTS',
    'MILESTONES',
    'SETTINGS',
  ];

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
      final recoveredSecondsString =
          await _storage.read(key: kRecoveryTimeKey);
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
      debugPrint(
          "[DEBUG] RECOVERY ERROR: Failed to process recovery data: $e");
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
      String milestoneId, Duration timeToAdd) async {
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

      milestone.timeSpentSeconds += timeToAdd.inSeconds;
    });
    _saveGoals();
  }

  Future<void> recordTaskCheckin(String goalId, String milestoneId,
      String checkpointId, TaskCheckinStatus status) async {
    final persistenceService =
        Provider.of<FirestoreService>(context, listen: false);
    await persistenceService.recordTaskCheckin(
        goalId, milestoneId, checkpointId, status);
  }

  void _updateMilestoneLockStatus() {
    if (_activeGoal == null) return;
    bool currentlyLocked = false;
    for (var m in _activeGoal!.milestones) {
      bool shouldBeUnlocked = !currentlyLocked;
      if (m.isUnlocked != shouldBeUnlocked) {
        m.isUnlocked = shouldBeUnlocked;
      }
      if (!m.isCompleted) {
        currentlyLocked = true;
      }
    }
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
          // 1. Core Page View
          IndexedStack(
            index: _selectedIndex,
            children: pages,
          ),

          // 2. Glassmorphism HUD Fullscreen Preview (Active during unlocked scrub)
          if (_isDragging && _isNavUnlocked)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.4),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _pageNames[_previewIndex],
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                            shadows: [
                              Shadow(
                                color: Colors.cyan,
                                blurRadius: 20,
                              )
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "PAGE ${_previewIndex + 1} OF ${_pageNames.length}",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 3. Dynamic Interactive Touch HUD Ring (Follows Finger)
          if (_isDragging)
            Positioned(
              left: _touchPosition.dx - 35,
              top: _touchPosition.dy - 35,
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 50),
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          _isNavUnlocked ? Colors.cyanAccent : Colors.white70,
                      width: _isNavUnlocked ? 3 : 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_isNavUnlocked ? Colors.cyanAccent : Colors.white)
                                .withValues(alpha: 0.5),
                        blurRadius: _isNavUnlocked ? 25 : 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            _isNavUnlocked ? Colors.cyanAccent : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 4. Ben 10 Style Bottom Omnitrix Dial Overlay (When Unlocked)
          if (_isDragging && _isNavUnlocked)
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_pageNames.length, (index) {
                    final bool isSelected = index == _previewIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: isSelected ? 28 : 10,
                      height: 10,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        color: isSelected ? Colors.cyanAccent : Colors.white24,
                        boxShadow: isSelected
                            ? [
                                const BoxShadow(
                                  color: Colors.cyanAccent,
                                  blurRadius: 10,
                                )
                              ]
                            : [],
                      ),
                    );
                  }),
                ),
              ),
            ),

          // 5. Stealth Touch Zone & Gesture Engine
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 100, // Bottom activation field
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) {
                setState(() {
                  _isDragging = true;
                  _touchPosition = details.globalPosition;
                  _dragStartY = details.globalPosition.dy;
                  _dragAnchorX = details.globalPosition.dx;
                  _isNavUnlocked = false;
                  _previewIndex = _selectedIndex;
                });
                HapticFeedback.selectionClick();
              },
              onPanUpdate: (details) {
                setState(() {
                  _touchPosition = details.globalPosition;
                });

                double dy = details.globalPosition.dy - _dragStartY;

                // Threshold Check: Pull up 40px to unlock HUD
                if (dy < -40 && !_isNavUnlocked) {
                  setState(() {
                    _isNavUnlocked = true;
                    _dragAnchorX = details.globalPosition.dx;
                  });
                  HapticFeedback
                      .heavyImpact(); // Tactile feedback on lock release
                }

                // Scrub Left / Right through pages
                if (_isNavUnlocked) {
                  double dx = details.globalPosition.dx - _dragAnchorX;

                  if (dx > 50) {
                    // Swiped Right -> Previous Page
                    if (_previewIndex > 0) {
                      setState(() {
                        _previewIndex--;
                        _dragAnchorX = details.globalPosition.dx;
                      });
                      HapticFeedback.selectionClick();
                    }
                  } else if (dx < -50) {
                    // Swiped Left -> Next Page
                    if (_previewIndex < pages.length - 1) {
                      setState(() {
                        _previewIndex++;
                        _dragAnchorX = details.globalPosition.dx;
                      });
                      HapticFeedback.selectionClick();
                    }
                  }
                }
              },
              onPanEnd: (_) {
                if (_isNavUnlocked && _previewIndex != _selectedIndex) {
                  setState(() {
                    _selectedIndex = _previewIndex;
                  });
                  HapticFeedback.mediumImpact();
                }

                setState(() {
                  _isDragging = false;
                  _isNavUnlocked = false;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- Check-in Dialog (from notification tap) ---
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
