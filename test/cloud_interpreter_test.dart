import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';
import 'package:juice_oracle/state/cloud_interpreter.dart';

http.Client _mockAnthropicClient(String responseText, {int status = 200}) {
  return MockClient((request) async {
    final body = jsonEncode({
      'id': 'msg_test',
      'type': 'message',
      'role': 'assistant',
      'model': CloudInterpreter.model,
      'content': [
        {'type': 'text', 'text': responseText}
      ],
      'stop_reason': 'end_turn',
      'usage': {'input_tokens': 10, 'output_tokens': 10},
    });
    return http.Response(body, status,
        headers: {'content-type': 'application/json'});
  });
}

const _validJson = '{"interpretations":['
    '{"lens":"literal","reading":"The gate holds."},'
    '{"lens":"symbolic","reading":"A door within a door."},'
    '{"lens":"complication","reading":"But the hinge groans."},'
    '{"lens":"foreshadow","reading":"Footsteps, once, behind you."}]}';

void main() {
  test('interpret() parses a successful Claude response', () async {
    final interpreter =
        CloudInterpreter(httpClient: _mockAnthropicClient(_validJson));
    final cards = await interpreter.interpret(
      const OracleSeed(resultText: 'Fate Check — Yes'),
      'sk-ant-test',
    );
    expect(cards, hasLength(4));
    expect(cards.first.lens, 'literal');
    expect(cards.first.reading, 'The gate holds.');
  });

  test('interpret() throws on a non-2xx response', () async {
    final interpreter = CloudInterpreter(
        httpClient: _mockAnthropicClient('{"error":"bad key"}', status: 401));
    expect(
      () => interpreter.interpret(
          const OracleSeed(resultText: 'x'), 'sk-ant-bad'),
      throwsA(anything),
    );
  });
}
