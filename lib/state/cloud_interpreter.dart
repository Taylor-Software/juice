import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';
import 'package:http/http.dart' as http;

import '../engine/oracle_interpreter.dart';

/// Optional Claude-backed cloud path for the interpret() seam ONLY. Every
/// other AI seam (voiceLine/summarize/gmChat/narrate/fleshOut/rankSuggestions)
/// stays strictly on-device — see the routing decorator in interpreter.dart.
/// Reuses the existing, provider-agnostic prompt builder + parser from
/// oracle_interpreter.dart; only the transport (Claude vs. local Gemma) is new.
class CloudInterpreter {
  const CloudInterpreter({http.Client? httpClient}) : _httpClient = httpClient;
  final http.Client? _httpClient;

  /// Fast, cheap tier — a 4-lens interpretation doesn't need a larger model,
  /// and the user pays per token on their own key.
  static const model = 'claude-haiku-4-5-20251001';

  Future<List<OracleInterpretation>> interpret(
      OracleSeed seed, String apiKey) async {
    final client = AnthropicClient.withApiKey(apiKey, httpClient: _httpClient);
    try {
      final response = await client.messages.create(MessageCreateRequest(
        model: model,
        maxTokens: 512,
        system: SystemPrompt.text(oracleSystemInstruction),
        messages: [InputMessage.user(buildOraclePrompt(seed))],
      ));
      return parseInterpretations(response.text);
    } finally {
      client.close();
    }
  }
}
