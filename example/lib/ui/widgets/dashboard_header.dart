import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DashboardHeader extends StatelessWidget {
  final DateTime selectedDate;
  final int selectedRange;
  final Function(BuildContext) onSelectDate;
  final Function(int?) onRangeChange;

  const DashboardHeader({
    super.key,
    required this.selectedDate,
    required this.selectedRange,
    required this.onSelectDate,
    required this.onRangeChange,
  });

  static const double _datePickerContainerPaddingVertical = 8.0;
  static const double _datePickerContainerPaddingHorizontal = 10.0;
  static const double _datePickerIconSize = 16.0;
  static const double _datePickerIconSpacing = 8.0;
  static const double _datePickerTextFontSize = 12.0;
  static const double _dropdownSpacing = 6.0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final iconColor = Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => onSelectDate(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: _datePickerContainerPaddingHorizontal, vertical: _datePickerContainerPaddingVertical),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month, size: _datePickerIconSize, color: iconColor),
                      const SizedBox(width: _datePickerIconSpacing),
                      Expanded(
                        child: Text(
                          DateFormat('MM/dd/yyyy').format(selectedDate),
                          style: textTheme.bodyLarge?.copyWith(fontSize: _datePickerTextFontSize),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: _dropdownSpacing),
            Expanded(
              child: Container(
                height: 37,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: _datePickerContainerPaddingHorizontal),
                child: DropdownButtonFormField<int>(
                  alignment: Alignment.center,
                  isDense: true,
                  initialValue: selectedRange,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  items: const [
                    DropdownMenuItem(value: 7, child: Text('7 days')),
                    DropdownMenuItem(value: 14, child: Text('14 days')),
                    DropdownMenuItem(value: 30, child: Text('30 days')),
                  ],
                  onChanged: onRangeChange,
                  style: textTheme.bodyLarge?.copyWith(fontSize: _datePickerTextFontSize),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
