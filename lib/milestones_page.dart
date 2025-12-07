import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import './models.dart';
import './services.dart';

class MilestonesPage extends StatefulWidget {
  final Goal? activeGoal;
  final Function(Milestone) onAddMilestone;
  final Function(Milestone, String) onToggleCheckpoint;
  final Function(String) onDeleteMilestone;
  final bool editMode;

  const MilestonesPage({
    super.key,
    this.activeGoal,
    required this.onAddMilestone,
    required this.onToggleCheckpoint,
    required this.onDeleteMilestone,
    required this.editMode,
  });

  @override
  State<MilestonesPage> createState() => MilestonesPageState();
}

class MilestonesPageState extends State<MilestonesPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _iconAnimationController;
  late Animation<double> _iconAnimation;

  @override
  void initState() {
    super.initState();
    _iconAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _iconAnimation = Tween(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(
        parent: _iconAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    if (widget.activeGoal != null && widget.activeGoal!.milestones.isEmpty) {
      _iconAnimationController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant MilestonesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeGoal != null && widget.activeGoal!.milestones.isEmpty) {
      _iconAnimationController.repeat(reverse: true);
    } else {
      _iconAnimationController.stop();
      _iconAnimationController.reset();
    }
  }

  @override
  void dispose() {
    _iconAnimationController.dispose();
    super.dispose();
  }

  void showAddMilestoneDialog(BuildContext context) {
    _iconAnimationController.stop();
    _iconAnimationController.reset();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: AddMilestoneForm(
          onAdd: widget.onAddMilestone,
          goalTitle: widget.activeGoal?.title ?? "your goal",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color lineColor = Theme.of(context).dividerColor;

    if (widget.activeGoal == null) {
      return const Center(
          child: Text("Set a main goal on the Home page first."));
    }

    if (widget.activeGoal!.milestones.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            "Your goal is set!\n\nTap the '+' button above to add your first milestone.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  height: 1.5,
                ),
          ),
        ),
      );
    }

    // --- LOGIC: Split the Army ---
    // 1. Incomplete: Kept in user-defined order (Draggable).
    // 2. Completed: Sorted by Date (Oldest -> Newest).
    
    final allMilestones = widget.activeGoal!.milestones;
    List<Milestone> incomplete = [];
    List<Milestone> completed = [];

    for (var m in allMilestones) {
      if (m.isCompleted) {
        completed.add(m);
      } else {
        incomplete.add(m);
      }
    }

    // Sort completed by deadline (Oldest First)
    completed.sort((a, b) => a.deadline.compareTo(b.deadline));

    // Combine for saving logic later
    void updateOrder() {
      // Reconstruct the master list: Incomplete first, then Completed
      widget.activeGoal!.milestones = [...incomplete, ...completed];
      // Trigger a save by passing a dummy update
      if (incomplete.isNotEmpty) {
        widget.onAddMilestone(incomplete.first);
      } else if (completed.isNotEmpty) {
        widget.onAddMilestone(completed.first);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Milestones'),
        actions: [
          if (widget.editMode)
            ScaleTransition(
              scale: _iconAnimation,
              child: IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded),
                onPressed: () => showAddMilestoneDialog(context),
                tooltip: 'Add Milestone',
              ),
            ),
        ],
      ),
      // --- UI: Scrollable Container ---
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // --- SECTION 1: INCOMPLETE (Draggable) ---
            if (widget.editMode && incomplete.isNotEmpty)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false, // We use custom handles
                itemCount: incomplete.length,
                onReorder: (oldIndex, newIndex) {
                  if (oldIndex < newIndex) {
                    newIndex -= 1;
                  }
                  final Milestone item = incomplete.removeAt(oldIndex);
                  incomplete.insert(newIndex, item);
                  updateOrder(); // Save changes
                },
                itemBuilder: (context, index) {
                  final milestone = incomplete[index];
                  // Wrap in ReorderableDragStartListener
                  return ReorderableDragStartListener(
                    key: ValueKey(milestone.id),
                    index: index,
                    child: MilestoneNode(
                      key: ValueKey(milestone.id),
                      milestone: milestone,
                      isFirst: index == 0,
                      // Only last if completed list is empty
                      isLast: index == incomplete.length - 1 && completed.isEmpty,
                      onToggleCheckpoint: widget.onToggleCheckpoint,
                      onDelete: () => widget.onDeleteMilestone(milestone.id),
                      editMode: widget.editMode,
                      lineColor: lineColor,
                      showDragHandle: true, // Show handle
                    ),
                  );
                },
              )
            else
              // Non-Edit Mode or Empty Incomplete List
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: incomplete.length,
                itemBuilder: (context, index) {
                  final milestone = incomplete[index];
                  return MilestoneNode(
                    key: ValueKey('${milestone.id}-view'),
                    milestone: milestone,
                    isFirst: index == 0,
                    isLast: index == incomplete.length - 1 && completed.isEmpty,
                    onToggleCheckpoint: widget.onToggleCheckpoint,
                    onDelete: () => widget.onDeleteMilestone(milestone.id),
                    editMode: widget.editMode,
                    lineColor: lineColor,
                  );
                },
              ),

            // --- SECTION 2: COMPLETED (Fixed) ---
            if (completed.isNotEmpty) ...[
              if (incomplete.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text("COMPLETED", 
                          style: TextStyle(
                            color: Theme.of(context).disabledColor, 
                            fontWeight: FontWeight.bold,
                            fontSize: 12
                          )
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: completed.length,
                itemBuilder: (context, index) {
                  final milestone = completed[index];
                  return MilestoneNode(
                    key: ValueKey(milestone.id),
                    milestone: milestone,
                    // First if incomplete is empty and this is index 0
                    isFirst: index == 0 && incomplete.isEmpty,
                    isLast: index == completed.length - 1,
                    onToggleCheckpoint: widget.onToggleCheckpoint,
                    onDelete: () => widget.onDeleteMilestone(milestone.id),
                    editMode: widget.editMode,
                    lineColor: lineColor,
                    showDragHandle: false, // Never draggable
                  );
                },
              ),
            ],
            
            // Add extra padding at bottom for FAB or just visual space
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// --- MilestoneNode (With Flexible Text Fix) ---
class MilestoneNode extends StatelessWidget {
  final Milestone milestone;
  final bool isFirst;
  final bool isLast;
  final Function(Milestone, String) onToggleCheckpoint;
  final VoidCallback onDelete;
  final bool editMode;
  final Color lineColor;
  final bool showDragHandle;

  const MilestoneNode({
    super.key,
    required this.milestone,
    required this.isFirst,
    required this.isLast,
    required this.onToggleCheckpoint,
    required this.onDelete,
    required this.editMode,
    required this.lineColor,
    this.showDragHandle = false,
  });

  String _formatDuration(Duration duration) {
    if (duration.inMinutes == 0) return "${duration.inSeconds}s";
    if (duration.inHours == 0) {
      return "${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s";
    }
    return "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";
  }

  Future<void> _confirmToggle(
      BuildContext context, Checkpoint checkpoint) async {
    if (editMode) {
      onToggleCheckpoint(milestone, checkpoint.id);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(milestone.completedCheckpointIds.contains(checkpoint.id)
            ? "Mark as Incomplete?"
            : "Mark as Complete?"),
        content: const Text(
            "Are you sure you want to change the status of this task?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Confirm")),
        ],
      ),
    );
    if (confirm == true) {
      onToggleCheckpoint(milestone, checkpoint.id);
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Milestone?'),
        content: Text(
            "Are you sure you want to delete '${milestone.title}'? This action cannot be undone."),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        onDelete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = milestone.isCompleted
        ? Colors.green
        : milestone.isUnlocked
            ? Theme.of(context).colorScheme.primary
            : Colors.grey;

    final Color lightColor;
    if (milestone.isCompleted) {
      lightColor = Colors.green.withAlpha(26);
    } else if (milestone.isUnlocked) {
      lightColor = Theme.of(context).colorScheme.primary.withAlpha(26);
    } else {
      lightColor =
          Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(128);
    }

    final Color? subtitleColor = milestone.isUnlocked
        ? Theme.of(context).textTheme.bodySmall?.color
        : Theme.of(context).disabledColor;

    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 40,
          child: CustomPaint(
            painter: LinePainter(
              isFirst: isFirst,
              isLast: isLast,
              lineColor: lineColor,
              dotColor: primaryColor,
              icon: milestone.isCompleted
                  ? Icons.check_rounded
                  : milestone.isUnlocked
                      ? Icons.flag_rounded
                      : Icons.lock_rounded,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 40.0),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            child: Card(
              elevation: 1,
              color: lightColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: primaryColor.withAlpha(128)),
              ),
              child: ExpansionTile(
                enabled: milestone.isUnlocked || editMode,
                shape: const Border(),
                collapsedShape: const Border(),
                // Drag handle icon logic
                leading: showDragHandle 
                    ? const Icon(Icons.drag_indicator) 
                    : null,
                title: Text(milestone.title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: milestone.isUnlocked
                            ? null
                            : Theme.of(context).disabledColor)),
                subtitle: Row(
                  children: [
                    // --- FIX: Wrapped text in Flexible to avoid RenderFlex overflow ---
                    Flexible(
                      child: Text(
                        'Due: ${DateFormat.yMMMd().format(milestone.deadline)}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: milestone.isUnlocked
                                ? null
                                : Theme.of(context).disabledColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (milestone.timeSpent > Duration.zero) ...[
                      Icon(Icons.timer_outlined,
                          size: 14, color: subtitleColor),
                      const SizedBox(width: 4),
                      Text(_formatDuration(milestone.timeSpent),
                          style: TextStyle(color: subtitleColor)),
                    ]
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0).copyWith(top: 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (milestone.checkpoints.isNotEmpty) ...[
                          LinearProgressIndicator(
                            value: milestone.progress,
                            backgroundColor: Theme.of(context).dividerColor,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(primaryColor),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Column(
                          children: milestone.checkpoints
                              .map((task) => CheckboxListTile(
                                    value: milestone.completedCheckpointIds
                                        .contains(task.id),
                                    title: Text(task.title,
                                        style: TextStyle(
                                            decoration: milestone
                                                    .completedCheckpointIds
                                                    .contains(task.id)
                                                ? TextDecoration.lineThrough
                                                : null)),
                                    onChanged: milestone.isUnlocked
                                        ? (val) => _confirmToggle(context, task)
                                        : null,
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    activeColor: primaryColor,
                                  ))
                              .toList(),
                        ),
                        if (editMode)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => _confirmDelete(context),
                              child: const Text("Delete",
                                  style: TextStyle(color: Colors.red)),
                            ),
                          )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class LinePainter extends CustomPainter {
  final bool isFirst;
  final bool isLast;
  final Color lineColor;
  final Color dotColor;
  final IconData icon;

  final double dotY = 40.0;
  final double dotRadius = 10.0;
  final double iconSize = 12.0;

  LinePainter({
    required this.isFirst,
    required this.isLast,
    required this.lineColor,
    required this.dotColor,
    required this.icon,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double centerX = size.width / 2;

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 2;

    if (!isFirst) {
      canvas.drawLine(
          Offset(centerX, 0), Offset(centerX, dotY - dotRadius), paint);
    }
    if (!isLast) {
      canvas.drawLine(Offset(centerX, dotY + dotRadius),
          Offset(centerX, size.height), paint);
    }

    final dotPaint = Paint()..color = dotColor;
    canvas.drawCircle(Offset(centerX, dotY), dotRadius, dotPaint);

    final textPainter = TextPainter(
      textDirection: ui.TextDirection.ltr,
    );
    const iconColor = Colors.white;

    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        color: iconColor,
        fontSize: iconSize,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
      ),
    );

    textPainter.layout();
    final iconOffset = Offset(
      centerX - textPainter.width / 2,
      dotY - textPainter.height / 2,
    );
    textPainter.paint(canvas, iconOffset);
  }

  @override
  bool shouldRepaint(covariant LinePainter oldDelegate) {
    return oldDelegate.isFirst != isFirst ||
        oldDelegate.isLast != isLast ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.dotColor != dotColor ||
        oldDelegate.icon != icon;
  }
}

class AddMilestoneForm extends StatefulWidget {
  final Function(Milestone) onAdd;
  final String goalTitle;
  const AddMilestoneForm(
      {super.key, required this.onAdd, required this.goalTitle});

  @override
  State<AddMilestoneForm> createState() => _AddMilestoneFormState();
}

class _AddMilestoneFormState extends State<AddMilestoneForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _tasksController = TextEditingController();
  DateTime? _selectedDate;
  bool _dateSubmittedOnce = false;
  bool _isSuggestingTasks = false;

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (pickedDate != null && pickedDate != _selectedDate) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  Future<void> _getTaskSuggestions() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Please enter a milestone title first."),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    setState(() => _isSuggestingTasks = true);
    final result = await SuggestionService.getTaskSuggestions(
        widget.goalTitle, _titleController.text.trim());
    if (mounted) {
      setState(() {
        if (result.suggestion != null) {
          try {
            final decoded = json.decode(result.suggestion!);
            final suggestions = List<String>.from(decoded['tasks']);
            if (suggestions.isNotEmpty) {
              _tasksController.text = suggestions.join('\n');
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Error: Could not understand AI response."),
              backgroundColor: Colors.red,
            ));
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Could not get suggestions."),
            backgroundColor: Colors.red,
          ));
        }
        _isSuggestingTasks = false;
      });
    }
  }

  void _submit() {
    setState(() {
      _dateSubmittedOnce = true;
    });

    if (!_formKey.currentState!.validate() || _selectedDate == null) {
      return;
    }

    final checkpoints = _tasksController.text
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .map((title) => Checkpoint(title: title))
        .toList();

    final newMilestone = Milestone(
      title: _titleController.text,
      deadline: _selectedDate!,
      checkpoints: checkpoints,
    );
    widget.onAdd(newMilestone);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("New Milestone",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                    labelText: 'Title', border: OutlineInputBorder()),
                validator: (value) => value == null || value.isEmpty
                    ? 'Please enter a title'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tasksController,
                decoration: const InputDecoration(
                    labelText: 'Tasks (one per line)',
                    border: OutlineInputBorder()),
                maxLines: 3,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _isSuggestingTasks
                    ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : TextButton.icon(
                        onPressed: _getTaskSuggestions,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                        label: const Text("Suggest Tasks"),
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedDate == null
                          ? 'No date chosen'
                          : 'Due: ${DateFormat.yMMMd().format(_selectedDate!)}',
                      style: TextStyle(
                        color: _selectedDate == null && _dateSubmittedOnce
                            ? Colors.red
                            : null,
                      ),
                    ),
                  ),
                  TextButton(
                      onPressed: _pickDate, child: const Text('Choose Date')),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  child: const Text('Add Milestone'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}