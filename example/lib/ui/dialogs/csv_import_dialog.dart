import 'package:flutter/material.dart';
import '../../utils/csv_importer.dart';

class CsvImportDialog extends StatefulWidget {
  final List<List<dynamic>> rows;

  const CsvImportDialog({super.key, required this.rows});

  @override
  State<CsvImportDialog> createState() => _CsvImportDialogState();
}

class _CsvImportDialogState extends State<CsvImportDialog> {
  // Column indices
  int? _nameColIndex;
  int? _startColIndex;
  int? _endColIndex;
  int? _resourceColIndex;
  int? _progressColIndex;
  String _closedStatusValue = 'Closed';
  int? _keyColIndex;
  int? _parentColIndex;
  String _openStatusValue = 'Open';

  List<String> _headers = [];
  List<List<dynamic>> _dataRows = [];

  @override
  void initState() {
    super.initState();
    if (widget.rows.isNotEmpty) {
      // Assume first row is header
      _headers = widget.rows.first.map((e) => e.toString()).toList();
      if (widget.rows.length > 1) {
        _dataRows = widget.rows.sublist(1);
      }
      _autoGuessMapping();
    }
  }

  void _autoGuessMapping() {
    final lowerHeaders = _headers.map((e) => e.toLowerCase()).toList();

    // Helper to find index containing term
    int? find(List<String> terms) {
      for (final term in terms) {
        final index = lowerHeaders.indexWhere((h) => h.contains(term));
        if (index != -1) return index;
      }
      return null;
    }

    _nameColIndex = find(['summary', 'task', 'name', 'title']);
    _startColIndex = find(['inferred start', 'start', 'begin']);
    _endColIndex = find(['inferred due', 'target', 'end', 'finish', 'due']);
    _resourceColIndex = find(['assignee', 'owner', 'resource', 'team']);
    _progressColIndex = find(['progress', 'completion', 'status', 'done']);
    _keyColIndex = find(['key', 'issue key', 'id']);
    _parentColIndex = find(['parent', 'parent key', 'parent id']);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return AlertDialog(
        title: const Text('Import CSV'),
        content: const Text('The CSV file is empty.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Import CSV'),
      content: SizedBox(
        width: 800,
        height: 600,
        child: Column(
          children: [
            _buildMappingSection(),
            const Divider(height: 32),
            Expanded(child: _buildPreviewSection()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _canImport ? _onImport : null,
          child: const Text('Import'),
        ),
      ],
    );
  }

  bool get _canImport => _nameColIndex != null && _startColIndex != null && _endColIndex != null;

  void _onImport() {
    final mapping = CsvImportMapping(
      nameColumnIndex: _nameColIndex,
      startColumnIndex: _startColIndex,
      endColumnIndex: _endColIndex,
      resourceColumnIndex: _resourceColIndex,
      progressColumnIndex: _progressColIndex,
      closedStatusValue: _closedStatusValue,
      keyColumnIndex: _keyColIndex,
      parentColumnIndex: _parentColIndex,
      openStatusValue: _openStatusValue,
    );
    Navigator.of(context).pop(mapping);
  }

  Widget _buildMappingSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Column Mapping', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildDropdown('Task Name *', _nameColIndex, (v) => setState(() => _nameColIndex = v))),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildDropdown('Start Date *', _startColIndex, (v) => setState(() => _startColIndex = v))),
              const SizedBox(width: 16),
              Expanded(child: _buildDropdown('End Date *', _endColIndex, (v) => setState(() => _endColIndex = v))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _buildDropdown(
                      'Unique Key (e.g. Issue Key)', _keyColIndex, (v) => setState(() => _keyColIndex = v))),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildDropdown(
                      'Parent Ref / Dependency', _parentColIndex, (v) => setState(() => _parentColIndex = v))),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _buildDropdown(
                      'Resource / Team', _resourceColIndex, (v) => setState(() => _resourceColIndex = v))),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildDropdown(
                      'Progress / Status', _progressColIndex, (v) => setState(() => _progressColIndex = v))),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Value for 100% completion (e.g. "Closed")',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 4),
                    TextFormField(
                      initialValue: _closedStatusValue,
                      enabled: _progressColIndex != null,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        hintText: 'e.g. Closed',
                      ),
                      onChanged: (v) => _closedStatusValue = v,
                    ),
                    const SizedBox(height: 16),
                    const Text('Value for "Open" Status (Keep Row if No Dates)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 4),
                    TextFormField(
                      initialValue: _openStatusValue,
                      enabled: _progressColIndex != null,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        hintText: 'e.g. Open',
                      ),
                      onChanged: (v) => _openStatusValue = v,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );

  Widget _buildDropdown(String label, int? value, ValueChanged<int?> onChanged) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          DropdownButtonFormField<int>(
            initialValue: value,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            ),
            items: [
              const DropdownMenuItem<int>(value: null, child: Text('(Ignore)', overflow: TextOverflow.ellipsis)),
              ...List.generate(
                  _headers.length,
                  (index) => DropdownMenuItem(
                        value: index,
                        child: Text(
                          _headers[index],
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
            ],
            onChanged: onChanged,
          ),
        ],
      );

  Widget _buildPreviewSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Preview (First 10 rows)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  border: TableBorder.all(color: Theme.of(context).dividerColor),
                  columns: _headers
                      .map((h) => DataColumn(label: Text(h, style: const TextStyle(fontWeight: FontWeight.bold))))
                      .toList(),
                  rows: _dataRows
                      .take(10)
                      .map((row) => DataRow(
                            cells: List.generate(_headers.length, (index) {
                              final cellValue = index < row.length ? row[index].toString() : '';
                              return DataCell(
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 200),
                                  child: Text(
                                    cellValue,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              );
                            }),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
        ],
      );
}
