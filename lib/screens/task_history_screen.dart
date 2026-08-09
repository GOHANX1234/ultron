import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/task_history_logger.dart';

class TaskHistoryScreen extends StatefulWidget {
  const TaskHistoryScreen({super.key});

  @override
  State<TaskHistoryScreen> createState() => _TaskHistoryScreenState();
}

class _TaskHistoryScreenState extends State<TaskHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _analytics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final history = await TaskHistoryLogger.readHistory();
    final analytics = await TaskHistoryLogger.getAnalytics();
    setState(() {
      _history = history;
      _analytics = analytics;
      _isLoading = false;
    });
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Task History'),
        content: const Text('Are you sure you want to delete all task history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TaskHistoryLogger.clearHistory();
      _loadHistory();
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Success':
        return Colors.green;
      case 'Failed':
        return Colors.red;
      case 'Cancelled':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Success':
        return Icons.check_circle;
      case 'Failed':
        return Icons.cancel;
      case 'Cancelled':
        return Icons.stop_circle;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AppBar(
              backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
              elevation: 0,
              title: Text('Task History (${_history.length})'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.delete_sweep, color: Colors.red.withValues(alpha: 0.8)),
                      onPressed: _history.isEmpty ? null : _clearHistory,
                      tooltip: 'Clear History',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
            bottom: false,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _history.isEmpty
                    ? Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1)),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.dashboard_customize_rounded, size: 64, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No task history found.',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          if (_analytics != null && _analytics!['totalTasks'] > 0)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                  child: Container(
                                    padding: const EdgeInsets.all(16.0),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                                      children: [
                                        _buildStatColumn('Total', _analytics!['totalTasks'].toString(), isDark: isDark),
                                        _buildStatColumn('Success', _analytics!['successCount'].toString(), color: Colors.green, isDark: isDark),
                                        _buildStatColumn('Failed', _analytics!['failedCount'].toString(), color: Colors.red, isDark: isDark),
                                        _buildStatColumn('Rate', '${(_analytics!['successRate'] * 100).toStringAsFixed(1)}%', isDark: isDark),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _history.length,
                              padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 32),
                              itemBuilder: (context, index) {
                                final task = _history[index];
                                final date = DateTime.tryParse(task['timestamp'] ?? '');
                                final dateStr = date != null
                                    ? DateFormat('MMM d, y h:mm a').format(date)
                                    : 'Unknown Date';
                                final status = task['status'] as String? ?? 'Unknown';

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08)),
                                        ),
                                        child: Theme(
                                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                          child: ExpansionTile(
                                            iconColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                            collapsedIconColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                            leading: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                gradient: RadialGradient(
                                                  colors: [
                                                    _getStatusColor(status).withValues(alpha: 0.3),
                                                    _getStatusColor(status).withValues(alpha: 0.1),
                                                  ],
                                                ),
                                                shape: BoxShape.circle,
                                                border: Border.all(color: _getStatusColor(status).withValues(alpha: 0.5)),
                                              ),
                                              child: Icon(
                                                _getStatusIcon(status),
                                                color: _getStatusColor(status),
                                                size: 24,
                                              ),
                                            ),
                                            title: Text(
                                              task['goal'] ?? 'Unknown Goal',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                            ),
                                            subtitle: Padding(
                                              padding: const EdgeInsets.only(top: 8.0),
                                              child: Row(
                                                children: [
                                                  Text(dateStr, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                                                  const Spacer(),
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(12),
                                                    child: BackdropFilter(
                                                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                                                          borderRadius: BorderRadius.circular(12),
                                                          border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1)),
                                                        ),
                                                        child: Text(
                                                          '${task['total_tokens'] ?? 0} tokens',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: _getStatusColor(status).withValues(alpha: 0.12),
                                                            borderRadius: BorderRadius.circular(8),
                                                            border: Border.all(color: _getStatusColor(status).withValues(alpha: 0.3)),
                                                          ),
                                                          child: Text(
                                                            status.toUpperCase(),
                                                            style: TextStyle(
                                                              color: _getStatusColor(status),
                                                              fontWeight: FontWeight.w800,
                                                              fontSize: 10,
                                                              letterSpacing: 0.5,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        Text(
                                                          'Steps taken: ${task['steps_taken'] ?? 0}',
                                                          style: TextStyle(
                                                            fontWeight: FontWeight.w600,
                                                            fontSize: 13,
                                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 16),
                                                    Text(
                                                      'Execution Trace:',
                                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9)),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    ...((task['trace'] as List<dynamic>?) ?? []).map((t) => Padding(
                                                      padding: const EdgeInsets.only(bottom: 6),
                                                      child: ClipRRect(
                                                        borderRadius: BorderRadius.circular(8),
                                                        child: BackdropFilter(
                                                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                                          child: Container(
                                                            padding: const EdgeInsets.all(10),
                                                            decoration: BoxDecoration(
                                                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
                                                              borderRadius: BorderRadius.circular(8),
                                                              border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05)),
                                                            ),
                                                            child: Text(
                                                              '• $t',
                                                              style: TextStyle(
                                                                fontFamily: 'monospace',
                                                                fontSize: 12,
                                                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    )),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
          ),
      );
    }

  Widget _buildStatColumn(String label, String value, {Color? color, required bool isDark}) {
    final baseColor = color ?? Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                baseColor,
                baseColor.withValues(alpha: 0.6),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
