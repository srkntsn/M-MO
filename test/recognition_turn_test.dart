import 'package:flutter_test/flutter_test.dart';
import 'package:mimo_ai/recognition_turn.dart';

void main() {
  test('final and done deliver the same utterance only once', () {
    final turn = RecognitionTurn();
    final id = turn.begin();
    turn.update(id, 'Merhaba MİMO');
    expect(turn.take(id), 'Merhaba MİMO');
    expect(turn.take(id), isNull);
  });
  test('partial speech survives an end-of-session error', () {
    final turn = RecognitionTurn();
    final id = turn.begin();
    turn.update(id, 'Kameraya bak');
    turn.update(id, '');
    expect(turn.take(id), 'Kameraya bak');
  });
  test('late results from a previous session cannot replace a new turn', () {
    final turn = RecognitionTurn();
    final old = turn.begin();
    final current = turn.begin();
    turn.update(old, 'Eski');
    turn.update(current, 'Yeni');
    expect(turn.take(old), isNull);
    expect(turn.take(current), 'Yeni');
  });
  test('interrupt cancels a pending turn', () {
    final turn = RecognitionTurn();
    final id = turn.begin();
    turn.update(id, 'Merhaba');
    turn.cancel();
    expect(turn.take(id), isNull);
  });
}
