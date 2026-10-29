/// Owns one recognizer session. A final result and a delayed `done` callback
/// may race, but a spoken turn must be delivered at most once.
class RecognitionTurn {
  int session = 0;
  String text = '';
  bool delivered = false;
  int begin() {
    text = '';
    delivered = false;
    return ++session;
  }

  void update(int id, String words) {
    if (id == session && !delivered && words.trim().isNotEmpty) text = words;
  }

  String? take(int id) {
    if (id != session || delivered || text.trim().isEmpty) return null;
    delivered = true;
    final result = text.trim();
    text = '';
    return result;
  }

  void cancel() {
    session++;
    text = '';
    delivered = true;
  }
}
