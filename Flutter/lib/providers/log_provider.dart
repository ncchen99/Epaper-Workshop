import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';

/// A single log entry
class LogEntry {
  final DateTime timestamp;
  final String message;
  final LogLevel level;

  const LogEntry({
    required this.timestamp,
    required this.message,
    this.level = LogLevel.info,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

enum LogLevel { info, success, warning, error }

/// State containing log entries
class LogState {
  final List<LogEntry> entries;

  const LogState({this.entries = const []});

  LogState copyWith({List<LogEntry>? entries}) {
    return LogState(entries: entries ?? this.entries);
  }
}

/// Notifier for managing log entries
class LogNotifier extends StateNotifier<LogState> {
  LogNotifier() : super(const LogState());

  /// Add a new log entry
  void log(String message, {LogLevel level = LogLevel.info}) {
    final newEntry = LogEntry(
      timestamp: DateTime.now(),
      message: message,
      level: level,
    );

    // Keep only the last N entries
    final updatedEntries = [...state.entries, newEntry];
    if (updatedEntries.length > AppConfig.maxLogEntries) {
      updatedEntries.removeRange(
        0,
        updatedEntries.length - AppConfig.maxLogEntries,
      );
    }

    state = state.copyWith(entries: updatedEntries);
  }

  /// Log info message
  void info(String message) => log(message, level: LogLevel.info);

  /// Log success message
  void success(String message) => log(message, level: LogLevel.success);

  /// Log warning message
  void warning(String message) => log(message, level: LogLevel.warning);

  /// Log error message
  void error(String message) => log(message, level: LogLevel.error);

  /// Clear all logs
  void clear() {
    state = const LogState();
  }
}

/// Provider for log state
final logProvider = StateNotifierProvider<LogNotifier, LogState>((ref) {
  return LogNotifier();
});
