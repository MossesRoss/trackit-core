/*
 * @author Mosses
 * @version 1.4.4
 * --- CHANGELOG ---
 * v1.4.4:
 * - [FIX] Re-implemented `_RedirectingClient` to *manually* handle 302
 * redirects for POST requests, as the underlying http client does not
 * honor `followRedirects` for POST. This fixes the "HTTP Error 302" log.
 * v1.4.3:
 * - [FEAT] Changed all AI-related error handling in `_callAppsScript` to
 * return a user-friendly "Upgrade to Pro..." message instead of
 * a technical error.
 * - [FEAT] Updated `getMonthlyReportSummary` fallback to also show the
 * "Upgrade to Pro" message.
 * v1.4.2:
 * - [FIX] Added `_RedirectingClient` class to handle HTTP 302 redirects from
 * Google Apps Script.
 * - [FIX] Updated `SuggestionService._callAppsScript` to use the new
 * `_RedirectingClient`, which should resolve network errors.
 */

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';
// --- FIX: Import for 'compute' function ---
import 'package:flutter/foundation.dart'
    show ChangeNotifier, debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http; // Kept for Apps Script calls
import 'package:intl/intl.dart';
import './models.dart';
import './notification_service.dart'; // Import the new service
import 'dart:async'; // --- ADDED for redirect client ---

// --- NEW: This is the fix for the HTTP 302 Redirect Error ---
// This class wraps the default HTTP client and manually follows redirects
// for POST requests.
class _RedirectingClient extends http.BaseClient {
  final http.Client _inner;
  _RedirectingClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // --- FIX: Handle POST redirects manually ---
    if (request.method == 'POST') {
      // Tell the inner client NOT to follow redirects, as we'll do it.
      request.followRedirects = false;

      final response = await _inner.send(request);

      // Check for redirect status codes
      if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 307) {
        final location = response.headers['location'];
        if (location != null) {
          debugPrint(
              "Redirecting client: POST got ${response.statusCode}, manually following to $location");

          // Create a new GET request to the redirect location.
          // This is standard browser behavior for 302 on a POST.
          final newUri = Uri.parse(location);
          final newRequest = http.Request('GET', newUri)
            // Copy over headers, but remove headers specific to POST/body
            ..headers.addAll(Map.from(request.headers)
              ..remove('host')
              ..remove('content-length')
              ..remove('content-type'));

          // Send the new GET request
          return _inner.send(newRequest);
        }
      }
      // If not a redirect, return the original response
      return response;
    }
    // --- End of new logic ---

    // For non-POST requests (like GET), let the inner client handle
    // redirects normally.
    request.followRedirects = true;
    request.maxRedirects = 5;
    return _inner.send(request);
  }
}
// --- End of new class ---

// We will now use Firestore Aggregations directly, so _processPeriodData is deprecated.
// Keeping a lightweight helper if needed, but the main logic is moved to FirestoreService.

// --- Auth Service (Updated) ---
class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final _storage = const FlutterSecureStorage();
  User? _user;

  AuthService() {
    _auth.authStateChanges().listen((user) {
      _user = user;
      notifyListeners();
    });
  }

  User? get currentUser => _user;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw e.message ?? 'An unknown error occurred.';
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw e.message ?? 'An unknown error occurred.';
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      // --- FIX: Force account picker to always appear ---
      await _googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return; // User cancelled the sign-in
      }
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw e.message ??
          'An unknown error occurred while signing in with Google.';
    } catch (e) {
      debugPrint("Google Sign-in Error: $e");
      throw 'Google Sign-in failed. If on Android, ensure your SHA-1 is added to the Firebase Console.';
    }
  }

  Future<void> signOut() async {
    // --- FIX: Clear cache for the current user *before* signing out ---
    try {
      final currentUserUid = _auth.currentUser?.uid;
      if (currentUserUid != null) {
        final userCacheKey = 'all_goals_cache_$currentUserUid';
        await _storage.delete(key: userCacheKey);
        debugPrint("Cleared cache for user $currentUserUid");

        // --- FIX: Also clear timer recovery keys ---
        // (Keys are from main.dart)
        await _storage.delete(key: 'recovery_time_seconds');
        await _storage.delete(key: 'recovery_milestone_id');
        debugPrint("Cleared timer recovery keys.");
      }
    } catch (e) {
      debugPrint("Error clearing user cache on sign-out: $e");
    }
    // --- End of fix ---

    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}

// --- FIX: Add the missing FirestoreService class back in ---
class FirestoreService {
  final String? uid;
  final _storage = const FlutterSecureStorage();
  FirestoreService(this.uid);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  // --- FIX: Remove static cache key ---
  // static const _localCacheKey = 'all_goals_cache';

  // --- FIX: Create a user-specific getter for the cache key ---
  String get _userCacheKey {
    // If uid is null, return a key that will never be found/set.
    if (uid == null) return 'all_goals_cache_anonymous';
    return 'all_goals_cache_$uid';
  }

  Future<void> archiveGoal(Goal goal) async {
    if (uid == null) return;
    // --- FIX: Save to user-specific subcollection ---
    final archiveDoc = _db
        .collection('users')
        .doc(uid)
        .collection('archived_goals')
        .doc(goal.id);
    goal.isArchived = true;
    await archiveDoc.set(goal.toJson());
  }

  Future<void> saveGoals(List<Goal> allGoals) async {
    if (uid == null) return;
    final userDoc = _db.collection('users').doc(uid);

    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) {
      await userDoc.set({'email': user!.email}, SetOptions(merge: true));
    }

    final goalsCollection = userDoc.collection('goals');
    // Write all goals in a batch for efficiency
    final batch = _db.batch();
    for (var goal in allGoals) {
      goal.userId = uid;
      final docRef = goalsCollection.doc(goal.id);
      batch.set(docRef, goal.toJson());
    }
    await batch.commit();

    // Update the local cache
    await _cacheGoals(allGoals);
  }

  /// Helper to update the SharedPreferences cache
  Future<void> _cacheGoals(List<Goal> goals) async {
    // --- FIX: Don't cache if UID is null (e.g., logged out) ---
    if (uid == null) return;
    final String goalsJson = json.encode(goals.map((g) => g.toJson()).toList());
    // --- FIX: Use user-specific cache key ---
    await _storage.write(key: _userCacheKey, value: goalsJson);
  }

  Future<List<Goal>> loadGoals() async {
    // --- FIX: If no user, return empty list immediately ---
    if (uid == null) return [];

    // --- FIX: Use user-specific cache key ---
    final String? localGoalsJson = await _storage.read(key: _userCacheKey);

    if (localGoalsJson != null) {
      final List<dynamic> decodedJson = json.decode(localGoalsJson);
      return decodedJson.map((g) => Goal.fromJson(g)).toList();
    }

    // No local cache found for this user, fetch from Firestore
    // (uid is guaranteed to be non-null here)
    final goalsCollection =
        _db.collection('users').doc(uid).collection('goals');
    final snapshot = await goalsCollection.get();
    final goals =
        snapshot.docs.map((doc) => Goal.fromJson(doc.data())).toList();

    // Save to cache
    await _cacheGoals(goals);
    return goals;
  }


  /// --- NEW: Provides a real-time stream of all goals ---
  Stream<List<Goal>> getGoalsStream() {
    if (uid == null) {
      debugPrint("getGoalsStream: No UID, returning empty stream.");
      return Stream.value([]);
    }
    final goalsCollection =
        _db.collection('users').doc(uid).collection('goals');
    return goalsCollection.snapshots().map((snapshot) {
      debugPrint("getGoalsStream: Received new goals snapshot.");
      final goals =
          snapshot.docs.map((doc) => Goal.fromJson(doc.data())).toList();
      // Update cache in the background (will now use user-specific key)
      _cacheGoals(goals);
      return goals;
    });
  }

  Future<void> addTimeSession(String goalId, String milestoneId, Duration duration) async {
    if (uid == null || duration.inSeconds <= 0) return;
    
    // Split the duration across midnight boundaries if necessary to ensure perfect daily metrics
    final end = DateTime.now();
    final start = end.subtract(duration);
    final nextMidnight = DateTime(start.year, start.month, start.day + 1);

    if (end.isAfter(nextMidnight)) {
      // Crosses midnight! Split into two sessions.
      final durationBeforeMidnight = nextMidnight.difference(start);
      final durationAfterMidnight = end.difference(nextMidnight);
      
      await _saveTimeSession(goalId, milestoneId, durationBeforeMidnight, start);
      await _saveTimeSession(goalId, milestoneId, durationAfterMidnight, nextMidnight);
    } else {
      await _saveTimeSession(goalId, milestoneId, duration, start);
    }
  }

  Future<void> _saveTimeSession(String goalId, String milestoneId, Duration duration, DateTime timestamp) async {
    await _db.collection('users').doc(uid).collection('time_sessions').add({
      'goalId': goalId,
      'milestoneId': milestoneId,
      'durationInSeconds': duration.inSeconds,
      'timestamp': timestamp.toIso8601String(),
    });
  }

  Future<void> recordTaskCompletion(String goalId, String milestoneId, String checkpointId, bool isCompleted) async {
    if (uid == null) return;
    final docRef = _db.collection('users').doc(uid).collection('completed_tasks').doc(checkpointId);
    
    if (isCompleted) {
      await docRef.set({
        'goalId': goalId,
        'milestoneId': milestoneId,
        'completedAt': DateTime.now().toIso8601String(),
      });
    } else {
      await docRef.delete();
    }
  }

  Future<void> recordTaskCheckin(String goalId, String milestoneId, String checkpointId, TaskCheckinStatus status) async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).collection('task_checkins').add({
      'goalId': goalId,
      'milestoneId': milestoneId,
      'checkpointId': checkpointId,
      'status': status.index,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>> _getAggregatedMetrics(DateTime start, DateTime end) async {
    if (uid == null) return {'timeSpent': Duration.zero, 'tasksCompleted': 0, 'checkinCounts': {}};

    final startStr = start.toIso8601String();
    final endStr = end.toIso8601String();

    // 1. Aggregate Time Spent using Firestore sum()
    final timeQuery = await _db.collection('users').doc(uid).collection('time_sessions')
      .where('timestamp', isGreaterThanOrEqualTo: startStr)
      .where('timestamp', isLessThan: endStr)
      .aggregate(sum('durationInSeconds'))
      .get();
    
    final totalSeconds = (timeQuery.getSum('durationInSeconds') ?? 0).toInt();

    // 2. Aggregate Tasks Completed using Firestore count()
    final tasksQuery = await _db.collection('users').doc(uid).collection('completed_tasks')
      .where('completedAt', isGreaterThanOrEqualTo: startStr)
      .where('completedAt', isLessThan: endStr)
      .count()
      .get();
    
    final completedCount = tasksQuery.count ?? 0;

    // 3. Aggregate Checkin Counts (Done, Doing, Will Do, Wont Do)
    // We still have to fetch the docs for this, but it's a small bounded list.
    final checkinsQuery = await _db.collection('users').doc(uid).collection('task_checkins')
      .where('timestamp', isGreaterThanOrEqualTo: startStr)
      .where('timestamp', isLessThan: endStr)
      .get();
    
    Map<TaskCheckinStatus, int> checkinCounts = {
      for (var status in TaskCheckinStatus.values) status: 0
    };
    for (var doc in checkinsQuery.docs) {
      final statusIndex = doc.data()['status'] as int?;
      if (statusIndex != null) {
        final status = TaskCheckinStatus.values[statusIndex];
        checkinCounts[status] = (checkinCounts[status] ?? 0) + 1;
      }
    }

    return {
      'timeSpent': Duration(seconds: totalSeconds),
      'tasksCompleted': completedCount,
      'checkinCounts': checkinCounts,
    };
  }

  Stream<Map<String, dynamic>> getWeeklyReport() async* {
    if (uid == null) yield* Stream.empty();
    
    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));
    final startOfLastWeek = startOfWeek.subtract(const Duration(days: 7));

    // Yield initial empty while loading
    yield const {};

    final currentPeriod = await _getAggregatedMetrics(startOfWeek, endOfWeek);
    final previousPeriod = await _getAggregatedMetrics(startOfLastWeek, startOfWeek);

    yield {'currentPeriod': currentPeriod, 'previousPeriod': previousPeriod};
  }

  Stream<Map<String, dynamic>> getMonthlyReport() async* {
    if (uid == null) yield* Stream.empty();
    
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);
    final startOfLastMonth = DateTime(now.year, now.month - 1, 1);

    yield const {};

    final currentPeriod = await _getAggregatedMetrics(startOfMonth, endOfMonth);
    final previousPeriod = await _getAggregatedMetrics(startOfLastMonth, startOfMonth);

    final summary = await SuggestionService.getMonthlyReportSummary(currentPeriod, previousPeriod);

    yield {
      'currentPeriod': currentPeriod,
      'previousPeriod': previousPeriod,
      'summary': summary
    };
  }

  Stream<Map<String, dynamic>> getYearlyReport() async* {
    if (uid == null) yield* Stream.empty();
    
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    final endOfYear = DateTime(now.year, 12, 31);
    final startOfLastYear = DateTime(now.year - 1, 1, 1);

    yield const {};

    final currentPeriod = await _getAggregatedMetrics(startOfYear, endOfYear);
    final previousPeriod = await _getAggregatedMetrics(startOfLastYear, startOfYear);

    final querySnapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('archived_goals')
        .where('createdAt', isGreaterThanOrEqualTo: startOfYear.toIso8601String())
        .where('createdAt', isLessThanOrEqualTo: endOfYear.toIso8601String())
        .get();

    final archivedGoals = querySnapshot.docs.map((doc) => Goal.fromJson(doc.data())).toList();

    yield {
      'currentPeriod': currentPeriod,
      'previousPeriod': previousPeriod,
      'archivedGoals': archivedGoals
    };
  }
}

class SuggestionResult {
  final String? suggestion;
  final String? error;

  SuggestionResult({this.suggestion, this.error});
}

class SuggestionService {
  // --- NEW: Create an instance of the redirecting client ---
  static final http.Client _client = _RedirectingClient(http.Client());

  static const String _appsScriptUrl = String.fromEnvironment(
    'APPS_SCRIPT_URL',
    defaultValue: 'https://placeholder.com/error', // A fallback
  );

  // --- NEW: Define the user-facing error message ---
  static const String _proMessage =
      "AI features are currently unavailable.";

  /// Calls the Google Apps Script backend proxy.
  /// This is the new single point of contact for all AI features.
  static Future<SuggestionResult> _callAppsScript(
      String action, Map<String, dynamic> body) async {
    // Add the specific action to the request body
    body['action'] = action;

    // Get the current user's Firebase Auth ID Token.
    // This securely proves to your backend *who* is making the call.
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();

    try {
      // --- FIX: Use `_client.post` instead of `http.post` ---
      final response = await _client.post(
        Uri.parse(_appsScriptUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken', // Send the token for verification
        },
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['error'] != null) {
          debugPrint("Google Apps Script Error: ${data['error']}");
          // --- UPDATED: Return pro message ---
          return SuggestionResult(error: _proMessage);
        }
        return SuggestionResult(suggestion: data['suggestion']);
      } else {
        // Handle non-200 HTTP responses
        debugPrint(
            "Apps Script HTTP Error ${response.statusCode}: ${response.body}");
        // --- UPDATED: Return pro message ---
        return SuggestionResult(error: _proMessage);
      }
    } catch (e) {
      // Handle network or connection errors
      debugPrint("Apps Script connection error: $e");
      // --- UPDATED: Return pro message ---
      return SuggestionResult(error: _proMessage);
    }
  }

  static Future<SuggestionResult> getSuggestion(
      Goal? activeGoal, Milestone? nextMilestone) async {
    if (activeGoal == null || nextMilestone == null) {
      return SuggestionResult(
          suggestion:
              "All tasks complete! Great job on finishing your milestones.");
    }

    final nextCheckpoint = nextMilestone.checkpoints.firstWhere(
      (c) => !nextMilestone.completedCheckpointIds.contains(c.id),
      orElse: () => Checkpoint(title: "No more tasks in this milestone"),
    );

    if (nextCheckpoint.title == "No more tasks in this milestone") {
      return SuggestionResult(
          suggestion:
              "Milestone '${nextMilestone.title}' is complete! Well done!");
    }

    // Schedule notification (this can happen in parallel)
    final payload = {
      'goalId': activeGoal.id,
      'milestoneId': nextMilestone.id,
      'checkpointId': nextCheckpoint.id,
    };
    NotificationService().showTaskCheckinNotification(
        id: 101, // Unique ID for this type of notification
        title: "How's it going?",
        body: "Progress on: ${nextCheckpoint.title}",
        payload: json.encode(payload));

    final prompt =
        "My current milestone is '${nextMilestone.title}' due on ${DateFormat.yMMMd().format(nextMilestone.deadline)}. My next task is: ${nextCheckpoint.title}. What is a single, concise, and actionable tip to help me with this specific task? Keep it short and motivating.";

    // Call the new Apps Script backend
    debugPrint("Requesting suggestion from backend...");
    return _callAppsScript('getSuggestion', {'prompt': prompt});
  }

  static Future<SuggestionResult> getTaskSuggestions(
      String goalTitle, String milestoneTitle) async {
    debugPrint("Requesting task suggestions from backend...");
    // Call the new Apps Script backend
    return _callAppsScript('getTaskSuggestions', {
      'goalTitle': goalTitle,
      'milestoneTitle': milestoneTitle,
    });
  }

  static Future<String> getMonthlyReportSummary(
      Map<String, dynamic> currentData,
      Map<String, dynamic> previousData) async {
    debugPrint("Requesting monthly summary from backend...");

    // Convert Duration objects to seconds
    final currentDataInSeconds = Map<String, dynamic>.from(currentData);
    currentDataInSeconds['timeSpent'] =
        (currentData['timeSpent'] as Duration).inSeconds;

    final previousDataInSeconds = Map<String, dynamic>.from(previousData);
    previousDataInSeconds['timeSpent'] =
        (previousData['timeSpent'] as Duration).inSeconds;

    // Call the new Apps Script backend
    final result = await _callAppsScript('getMonthlyReportSummary', {
      'currentData': currentDataInSeconds,
      'previousData': previousDataInSeconds,
    });

    // --- UPDATED: Check for error and return it, or return fallback ---
    if (result.error != null) {
      return result.error!;
    }
    return result.suggestion ?? _proMessage;
  }

  /// Triggers the weekly report via the backend
  static Future<SuggestionResult> triggerWeeklyReport(String userId, String email) async {
    debugPrint("Triggering weekly report for $email...");
    return _callAppsScript('triggerWeeklyReport', {
      'userId': userId,
      'email': email,
    });
  }
}

// --- Quote Service for Fallback Content (unchanged) ---
class QuoteService {
  static const String _quoteIndexKey = 'last_quote_index';
  static const List<String> _quotes = [
    "The secret of getting ahead is getting started. – Mark Twain",
    "It does not matter how slowly you go as long as you do not stop. – Confucius",
    "Your time is limited, so don't waste it living someone else's life. – Steve Jobs",
    "The only way to do great work is to love what you do. – Steve Jobs",
    "The future belongs to those who believe in the beauty of their dreams. – Eleanor Roosevelt",
    "Success is not final; failure is not fatal: It is the courage to continue that counts. – Winston Churchill",
    "Believe you can and you're halfway there. – Theodore Roosevelt",
    "The best way to predict the future is to create it. – Peter Drucker",
    "A year from now you may wish you had started today. – Karen Lamb",
    "The journey of a thousand miles begins with a single step. – Laozi"
  ];

  static Future<String> getQuote() async {
    const storage = FlutterSecureStorage();
    final lastIndexString = await storage.read(key: _quoteIndexKey);
    int lastIndex = -1;
    if (lastIndexString != null) {
      lastIndex = int.parse(lastIndexString);
    }

    // Increment index and loop back to 0 if at the end
    int nextIndex = (lastIndex + 1) % _quotes.length;

    await storage.write(key: _quoteIndexKey, value: nextIndex.toString());
    return _quotes[nextIndex];
  }
}
