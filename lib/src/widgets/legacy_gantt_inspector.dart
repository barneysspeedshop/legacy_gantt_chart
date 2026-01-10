import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../legacy_gantt_chart.dart';

class LegacyGanttInspector extends StatelessWidget {
  final String taskId;
  final LegacyGanttTask task;
  final CausalIntegrityAudit auditEngine;

  const LegacyGanttInspector({
    super.key,
    required this.taskId,
    required this.task,
    required this.auditEngine,
  });

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 800,
            height: 600,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.monitor_heart, color: Colors.blueGrey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Causal Integrity Inspector: ${task.name ?? taskId}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontFamily: 'RobotoMono'),
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
                  ],
                ),
                const TabBar(
                  labelColor: Colors.blue,
                  unselectedLabelColor: Colors.grey,
                  tabs: [
                    Tab(icon: Icon(Icons.fingerprint), text: 'Current Provenance'),
                    Tab(icon: Icon(Icons.history), text: 'Session History'),
                    Tab(icon: Icon(Icons.account_tree), text: 'Causal Graph'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildProvenanceTab(context),
                      _buildHistoryTab(context),
                      _buildGraphTab(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildProvenanceTab(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoCard(
            context,
            'Global State',
            [
              _buildFieldRow('ID', task.id),
              _buildFieldRow('Last Updated', task.lastUpdated.toString()),
              _buildFieldRow('Last Updated By', task.lastUpdatedBy ?? 'Unknown'),
            ],
          ),
          const SizedBox(height: 16),
          Text('Field-Level Provenance (LWW Winners)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...task.fieldTimestamps.entries.map((e) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(e.value.toString(), style: const TextStyle(fontFamily: 'RobotoMono')),
                  trailing: Chip(
                    label: Text(e.value.nodeId),
                    avatar: const Icon(Icons.person, size: 16),
                  ),
                ),
              )),
          if (task.fieldTimestamps.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No field-level provenance data available (Legacy or initial sync).'),
            ),
        ],
      );

  Widget _buildHistoryTab(BuildContext context) {
    final history = auditEngine.getHistoryForTask(taskId);
    if (history.isEmpty) {
      return const Center(child: Text('No session history recorded for this task.'));
    }

    return ListView.builder(
      itemCount: history.length,
      itemBuilder: (context, index) {
        final op = history[index];
        return Card(
          child: ExpansionTile(
            leading: Text(
              DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(op.timestamp.millis)),
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
            title: Text(op.type),
            subtitle: Text('Actor: ${op.actorId} | HLC: ${op.timestamp}'),
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black12,
                width: double.infinity,
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(op.data),
                  style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGraphTab(BuildContext context) {
    final history = auditEngine.getHistoryForTask(taskId);
    if (history.length < 2) {
      return const Center(child: Text('Not enough history to visualize causal graph.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Conflict Resolution Log', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        for (var i = 0; i < history.length - 1; i++) ...[
          _buildConflictRow(context, history[i], history[i + 1]),
          const Divider(),
        ]
      ],
    );
  }

  Widget _buildConflictRow(BuildContext context, Operation opA, Operation opB) {
    final fieldCandidates = opB.data.keys.where((k) => k != 'id' && k != 'data').toList();
    if (fieldCandidates.isEmpty) return const SizedBox.shrink();

    final field = fieldCandidates.first;
    final analysis = auditEngine.analyzeConflict(opA, opB, field);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          border: Border(left: BorderSide(color: analysis.winner == opB ? Colors.green : Colors.orange, width: 4))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Comparing ${opA.timestamp.counter} vs ${opB.timestamp.counter} on field "$field"'),
          const SizedBox(height: 4),
          Text(
            'Winner: ${analysis.winner == opB ? "Incoming (Op B)" : "Existing (Op A)"}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(analysis.reason, style: const TextStyle(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const Divider(),
              ...children,
            ],
          ),
        ),
      );

  Widget _buildFieldRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            SelectableText(value, style: const TextStyle(fontFamily: 'RobotoMono')),
          ],
        ),
      );
}
