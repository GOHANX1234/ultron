/// LLM provider preset configurations.
class ApiPreset {
  final String name;
  final String baseUrl;
  final String defaultModel;
  final String icon;

  const ApiPreset({
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
    required this.icon,
  });
}

abstract class ApiPresets {
  static const List<ApiPreset> all = [
    ApiPreset(
      name: 'Local (LM Studio)',
      baseUrl: 'http://10.0.2.2:1234/v1',
      defaultModel: 'local-model',
      icon: '🖥️',
    ),
    ApiPreset(
      name: 'Ollama',
      baseUrl: 'http://10.0.2.2:11434/v1',
      defaultModel: 'gemma3:4b',
      icon: '🦙',
    ),
    ApiPreset(
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      defaultModel: 'deepseek-chat',
      icon: '🔮',
    ),
    ApiPreset(
      name: 'Groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      defaultModel: 'llama-3.3-70b-versatile',
      icon: '⚡',
    ),
    ApiPreset(
      name: 'NVIDIA NIM',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      defaultModel: 'meta/llama-3.1-70b-instruct',
      icon: '🟢',
    ),
    ApiPreset(
      name: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      defaultModel: 'openai/gpt-4o-mini',
      icon: '🔄',
    ),
  ];
}
