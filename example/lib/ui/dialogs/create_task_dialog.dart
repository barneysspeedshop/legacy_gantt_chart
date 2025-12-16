import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

/// A combined dialog for creating and editing tasks.
class TaskDialog extends StatefulWidget {
  final DateTime? initialTime;
  final String? resourceName;
  final String? rowId;
  final LegacyGanttTask? task;
  final Function(LegacyGanttTask) onSubmit;
  final TimeOfDay defaultStartTime;
  final TimeOfDay defaultEndTime;

  const TaskDialog({
    super.key,
    this.initialTime,
    this.resourceName,
    this.rowId,
    this.task,
    required this.onSubmit,
    required this.defaultStartTime,
    required this.defaultEndTime,
  }) : assert(task != null || (initialTime != null && rowId != null),
            'If creating a new task, initialTime and rowId are required.');

  @override
  State<TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<TaskDialog> {
  late final TextEditingController _nameController;
  late DateTime _startDate;
  late DateTime _endDate;
  String _selectedType = 'task';
  Color? _selectedColor;
  Color? _selectedTextColor;

  @override
  void initState() {
    super.initState();

    if (widget.task != null) {
      // Edit Mode
      _nameController = TextEditingController(text: widget.task!.name);
      _startDate = widget.task!.start;
      _endDate = widget.task!.end;
      _selectedColor = widget.task!.color;
      _selectedTextColor = widget.task!.textColor;

      if (widget.task!.isMilestone) {
        _selectedType = 'milestone';
      } else if (widget.task!.isSummary) {
        _selectedType = 'summary';
      }
    } else {
      // Create Mode
      _nameController =
          TextEditingController(text: widget.resourceName != null ? 'New Task for ${widget.resourceName}' : 'New Task');

      // Select the default text so the user can easily overwrite it.
      _nameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _nameController.text.length,
      );

      // Use the date part from where the user clicked, but apply the default times.
      // We asserted initialTime is not null if task is null.
      final datePart = widget.initialTime!;
      _startDate = DateTime(
        datePart.year,
        datePart.month,
        datePart.day,
        widget.defaultStartTime.hour,
        widget.defaultStartTime.minute,
      );
      _endDate = DateTime(
        datePart.year,
        datePart.month,
        datePart.day,
        widget.defaultEndTime.hour,
        widget.defaultEndTime.minute,
      );

      // Handle overnight case where end time is on the next day.
      if (_endDate.isBefore(_startDate)) {
        _endDate = _endDate.add(const Duration(days: 1));
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_nameController.text.isNotEmpty) {
      if (widget.task != null) {
        // Update existing task
        var newTask = widget.task!.copyWith(
          name: _nameController.text,
          start: _startDate,
          end: _endDate,
          isMilestone: _selectedType == 'milestone',
          isSummary: _selectedType == 'summary',
          color: _selectedColor,
          textColor: _selectedTextColor,
        );

        // Enforce milestone duration logic if type changed to milestone
        if (_selectedType == 'milestone') {
          newTask = newTask.copyWith(end: _startDate);
        } else if (newTask.start == newTask.end && _selectedType != 'milestone') {
          // If converting FROM milestone (or just start==end), ensure visible duration
          newTask = newTask.copyWith(end: newTask.start.add(const Duration(days: 1)));
        }

        widget.onSubmit(newTask);
      } else {
        // Create new task
        final newTask = LegacyGanttTask(
          id: 'new_task_${DateTime.now().millisecondsSinceEpoch}',
          rowId: widget.rowId!, // Asserted not null
          name: _nameController.text,
          start: _startDate,
          end: _endDate,
          isMilestone: _selectedType == 'milestone',
          isSummary: _selectedType == 'summary',
          color: _selectedColor,
          textColor: _selectedTextColor,
        );
        widget.onSubmit(newTask);
      }
      Navigator.pop(context);
    }
  }

  Future<void> _selectDateTime(BuildContext context, bool isStart) async {
    final initialDate = isStart ? _startDate : _endDate;

    final pickedDate = await showDatePicker(
        context: context, initialDate: initialDate, firstDate: DateTime(2000), lastDate: DateTime(2030));
    if (pickedDate == null || !context.mounted) return;

    final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initialDate));
    if (pickedTime == null) return;

    setState(() {
      final newDateTime =
          DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
      if (isStart) {
        _startDate = newDateTime;
        // If it's a milestone, end matches start.
        if (_selectedType == 'milestone') {
          _endDate = _startDate;
        } else if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate.add(const Duration(hours: 1));
        }
      } else {
        // If it's a milestone, disallow changing end date separately? Or just force consistency?
        // Better: prevent regular users from setting end date < start date
        _endDate = newDateTime;
        if (_selectedType == 'milestone') {
          _startDate = _endDate;
        } else if (_startDate.isAfter(_endDate)) {
          _startDate = _endDate.subtract(const Duration(hours: 1));
        }
      }
    });
  }

  Widget _buildColorSelector(String label, Color? selectedValue, ValueChanged<Color?> onChanged, List<Color?> colors) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colors.map((color) {
              if (color == null) {
                return ChoiceChip(
                  label: const Text('Default'),
                  selected: selectedValue == null,
                  onSelected: (selected) {
                    if (selected) onChanged(null);
                  },
                );
              }
              final isSelected = selectedValue == color;
              return GestureDetector(
                onTap: () => onChanged(color),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: Colors.black, width: 2)
                        : Border.all(color: Colors.grey.shade300),
                    boxShadow: [
                      if (isSelected)
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                    ],
                  ),
                  child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                ),
              );
            }).toList(),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final title = widget.task != null ? 'Edit Task' : 'Create Task for ${widget.resourceName ?? "Unknown"}';
    final buttonText = widget.task != null ? 'Save' : 'Create';
    final isMilestone = _selectedType == 'milestone';

    final taskColors = [null, Colors.blue, Colors.red, Colors.green, Colors.orange, Colors.purple, Colors.grey];
    final textColors = [null, Colors.black, Colors.white];

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Task Name'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Type'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedType,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'task', child: Text('Standard Task')),
                  DropdownMenuItem(value: 'milestone', child: Text('Milestone')),
                  DropdownMenuItem(value: 'summary', child: Text('Summary Task')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedType = value;
                      if (_selectedType == 'milestone') {
                        _endDate = _startDate;
                      } else if (_endDate == _startDate) {
                        // Access duration logic for converting back
                        _endDate = _startDate.add(const Duration(days: 1));
                      }
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Start:'),
            TextButton(
                onPressed: () => _selectDateTime(context, true),
                child: Text(DateFormat.yMd().add_jm().format(_startDate)))
          ]),
          // Hide End Date for Milestone? Or show but disable? Or keep synced?
          // Keeping it visible but synced is fine.
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('End:'),
            TextButton(
                onPressed: isMilestone ? null : () => _selectDateTime(context, false),
                child: Text(DateFormat.yMd().add_jm().format(_endDate)))
          ]),
          const SizedBox(height: 16),
          _buildColorSelector('Task Color', _selectedColor, (val) => setState(() => _selectedColor = val), taskColors),
          const SizedBox(height: 16),
          _buildColorSelector(
              'Text Color', _selectedTextColor, (val) => setState(() => _selectedTextColor = val), textColors),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _submit, child: Text(buttonText)),
      ],
    );
  }
}
