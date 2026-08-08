class AgentAction {
  final String action;
  final Map<String, dynamic> params;
  final String response;

  AgentAction({
    required this.action,
    required this.params,
    required this.response,
  });

  factory AgentAction.fromJson(Map<String, dynamic> json) {
    return AgentAction(
      action: json['action'] as String? ?? 'general_query',
      params: (json['params'] as Map?)?.cast<String, dynamic>() ?? {},
      response: json['response'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'action': action,
    'params': params,
    'response': response,
  };

  static const List<String> availableActions = [
    'open_app',
    'make_call',
    'send_sms',
    'search_contact',
    'set_alarm',
    'set_volume',
    'set_brightness',
    'read_notifications',
    'read_screen',
    'run_adb_command',
    'general_query',
  ];
}
