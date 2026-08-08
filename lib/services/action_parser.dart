import 'dart:convert';
import 'dart:developer' as developer;

/// Parses LLM text responses into structured action JSON maps.
///
/// Extracted from [TaskExecutor] to improve single-responsibility and testability.
class ActionParser {
  /// Extract a JSON object from LLM response text.
  ///
  /// Handles responses wrapped in markdown code fences (```json ... ```)
  /// or embedded within conversational text.
  static String extractJson(String text) {
    // 1. Try to find a markdown json code block first
    final codeBlockRegex = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```');
    final match = codeBlockRegex.firstMatch(text);
    if (match != null) {
      return match.group(1)!;
    }

    // 2. Fallback: find the first { and the last }
    final startIndex = text.indexOf('{');
    final endIndex = text.lastIndexOf('}');
    if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
      return text.substring(startIndex, endIndex + 1);
    }

    return text.trim();
  }

  /// Parse the extracted JSON into an action map.
  ///
  /// Returns null if parsing fails. Callers should handle null by retrying.
  static Map<String, dynamic>? parseAction(String response) {
    try {
      final jsonStr = extractJson(response);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      developer.log(
        'ActionParser.parseAction: Failed to parse — $e',
        name: 'Ultron-3',
      );
      return null;
    }
  }

  /// Extract the standard fields from a parsed action map with safe defaults.
  static ({
    String action,
    Map<String, dynamic> params,
    String reasoning,
    bool isComplete,
  }) extractFields(Map<String, dynamic> json) {
    return (
      action: json['action'] as String? ?? 'done',
      params: (json['params'] as Map?)?.cast<String, dynamic>() ?? {},
      reasoning: json['reasoning'] as String? ?? '',
      isComplete: json['is_complete'] == true,
    );
  }
}
