import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import './models.dart';
import './services.dart';
// import './auth_screen.dart'; 
import 'reports_page.dart';
import 'guide_page.dart';
import 'ui.dart';

class SettingsPage extends StatelessWidget {
  final bool isDarkMode;
  final VoidCallback toggleDarkMode;
  final bool editMode;
  final ValueChanged<bool> onEditModeChanged;
  final List<Goal> allGoals;

  const SettingsPage({
    super.key,
    required this.isDarkMode,
    required this.toggleDarkMode,
    required this.editMode,
    required this.onEditModeChanged,
    required this.allGoals,
  });

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = FirebaseAuth.instance.currentUser;
    final String initials = user?.email != null && user!.email!.isNotEmpty
        ? user.email![0].toUpperCase()
        : "U";

    Goal? activeGoal;
    try {
      activeGoal = allGoals.firstWhere((g) => g.status == GoalStatus.active);
    } catch (e) {
      activeGoal = null;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: GestureDetector(
                // --- FIX: Increased Hit Area & Combined Gestures ---
                behavior: HitTestBehavior.opaque, // Catch all touches in area
                onHorizontalDragEnd: (details) {
                  // Swipe detection
                  if (details.primaryVelocity! > 0) {
                     _showSwitchSnackBar(context, "Switching to Previous Account...");
                     // Add logic here to actually switch if possible
                  } else if (details.primaryVelocity! < 0) {
                     _showSwitchSnackBar(context, "Switching to Next Account...");
                     // Add logic here to actually switch if possible
                  }
                },
                // --- Tap to Change (Preserved) ---
                onTap: () {
                  try {
                    Provider.of<AuthService>(context, listen: false)
                        .signInWithGoogle();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Error switching accounts.")),
                    );
                  }
                },
                child: Container(
                  // Container increases the touch target size
                  padding: const EdgeInsets.all(8.0), 
                  child: CircleAvatar(
                    backgroundColor: Colors.brown.shade400,
                    child: Text(
                      initials, 
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        children: [
          const SizedBox(height: 10),

          SwitchListTile(
            title: const Text("Dark Mode"),
            secondary: const Icon(Icons.dark_mode_outlined),
            value: isDarkMode,
            onChanged: (val) => toggleDarkMode(),
          ),
          SwitchListTile(
            title: const Text("Edit Mode"),
            subtitle: const Text("Allows adding/deleting milestones"),
            secondary: const Icon(Icons.edit_outlined),
            value: editMode,
            onChanged: onEditModeChanged,
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.assessment_rounded),
            title: const Text("Reports"),
            subtitle: const Text("View your weekly and monthly progress"),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ReportsPage())),
          ),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text("Email Weekly Report Now"),
            subtitle: const Text("Trigger AI assessment & email"),
            onTap: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null || user.email == null) {
                _showSwitchSnackBar(context, "You must be logged in.");
                return;
              }
              _showSwitchSnackBar(context, "Generating report... Check your email shortly.");
              final result = await SuggestionService.triggerWeeklyReport(user.uid, user.email!);
              
              if (!context.mounted) return;

              if (result.error != null) {
                _showSwitchSnackBar(context, "Error: ${result.error}");
              } else {
                 _showSwitchSnackBar(context, "Success: ${result.suggestion}");
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text("My Journey"),
            subtitle: const Text("View all your past and present goals"),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MyJourneyPage(allGoals: allGoals))),
          ),
          ListTile(
              leading: const Icon(Icons.notifications_rounded),
              title: const Text("Notifications"),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        NotificationsSettingsPage(activeGoal: activeGoal)));
              }),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: const Text("Help"),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const GuidePage())),
          ),
          ListTile(
            leading: const Icon(Icons.connect_without_contact_rounded),
            title: const Text("Get in Touch"),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GetInTouchPage())),
          ),

          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("Log Out", style: TextStyle(color: Colors.red)),
            onTap: () {
              authService.signOut();
            },
          ),
          
          const SizedBox(height: 20),
          Padding(
             padding: const EdgeInsets.symmetric(horizontal: 16),
             child: Text(
               "App Version 1.9.2", 
               style: TextStyle(color: Colors.grey.shade600, fontSize: 12)
             ),
          ),
        ],
      ),
    );
  }

  void _showSwitchSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}