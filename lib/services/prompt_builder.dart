import 'dart:developer' as developer;

/// Builds system and user prompts for the LLM automation agent.
///
/// Extracted from [TaskExecutor] to improve single-responsibility and testability.
class PromptBuilder {
  /// The base system prompt instructing the LLM on available actions and rules.
  static const String taskSystemPrompt = '''
You are a phone automation agent. You are given a TASK and the current SCREEN content.
You must decide what single action to take next to accomplish the task.

Respond with ONLY a JSON object (no markdown, no code fences):
{
  "action": "action_name",
  "params": {"key": "value"},
  "reasoning": "why you chose this action",
  "is_complete": false
}

Available actions:
- click_text: {"text": "exact text to click"} - Click an element by its visible text
- click_at: {"x": 540, "y": 960} - Click at screen coordinates (use bounds from screen dump)
- type_text: {"text": "hello", "field_hint": "optional hint"} - Type into the focused/first edit field
- press_enter: {} - Press the Enter/Search key on the keyboard to submit a search/form
- scroll: {"direction": "down"} - Scroll down/up on the current view
- swipe: {"startX": 540, "startY": 2000, "endX": 540, "endY": 500} - Swipe from start to end coordinates (e.g. open app drawer, navigate carousels)
- press_back: {} - Press the back button
- press_home: {} - Press the home button
- open_app: {"app_name": "WhatsApp"} - Open an app
- wait: {} - Wait a moment for content to load
- done: {} - Task is complete

Rules:
- You will receive a TEXT DUMP of the accessibility tree containing exact text strings and center coordinates.
- ALWAYS use the text dump to decide your next action.
- If you need to click something, prefer using `click_text`. If the element does not have text, use `click_at` with the coordinates provided in the text dump.
- When typing in a search box, you MUST click it first, wait a step, and THEN type.
- After typing a search query, use `press_enter` once. If the screen does not change, click the exact visible suggestion text. Do not repeat the same submit action more than twice.
- Never scroll or swipe more than three times in a row. After three scrolls, choose the best visible result or take a different action instead of continuing to browse indefinitely.
- Set is_complete=true ONLY when the task is fully done.
- If you need to find something by scrolling, scroll and then check the screen again.
- If you need to open an app (like Wikipedia, Spotify, etc.) and you cannot find it after a couple of scrolls, ASSUME it is not installed. Immediately open Chrome or Google to search for the info on the web instead.
- If stuck after 3 attempts, set is_complete=true and explain in reasoning.
- Keep reasoning very brief (1 sentence)
''';

  /// Build a step prompt including screen content, previous result, and failure hints.
  static String buildStepPrompt({
    required String userGoal,
    required String screenContent,
    required int step,
    required int maxSteps,
    required List<String> results,
    required int consecutiveFailures,
  }) {
    developer.log(
      'PromptBuilder.buildStepPrompt: step=${step + 1}/$maxSteps',
      name: 'Ultron-3',
    );

    final prevResultStr = step > 0 && results.isNotEmpty
        ? '\nPREVIOUS ACTION RESULT: ${results.last}\n'
        : '';

    String failureHint = '';
    if (consecutiveFailures >= 3) {
      failureHint =
          '\n\nWARNING: You have failed $consecutiveFailures times in a row with the same approach. '
          'You MUST try a completely different action. If open_app failed, try press_home and look for the '
          'app icon on the home screen instead. If click_text failed, use click_at with coordinates. '
          'Do NOT repeat the same failed action.';
    }

    return '''TASK: $userGoal

CURRENT SCREEN TEXT DUMP:
$screenContent$prevResultStr$failureHint
Step ${step + 1}/$maxSteps. Look at the text dump and coordinates. What is the next action?''';
  }
}
