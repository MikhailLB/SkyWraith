import 'package:shared_preferences/shared_preferences.dart';

const int kTotalLevels = 40;

/// Stores how far the player has progressed.
class Progress {
  Progress._(this._prefs);

  final SharedPreferences _prefs;

  static const _kUnlocked = 'unlocked_level';
  static const _kCompleted = 'completed_levels';

  static Future<Progress> load() async {
    final prefs = await SharedPreferences.getInstance();
    return Progress._(prefs);
  }

  /// Highest unlocked level (1-based). Level 1 is always available.
  int get unlockedLevel {
    final v = _prefs.getInt(_kUnlocked) ?? 1;
    return v.clamp(1, kTotalLevels);
  }

  Set<int> get completed {
    final list = _prefs.getStringList(_kCompleted) ?? const [];
    return list.map(int.parse).toSet();
  }

  bool isUnlocked(int level) => level <= unlockedLevel;
  bool isCompleted(int level) => completed.contains(level);

  Future<void> markCompleted(int level) async {
    final done = completed..add(level);
    await _prefs.setStringList(
        _kCompleted, done.map((e) => e.toString()).toList());
    final next = (level + 1).clamp(1, kTotalLevels);
    if (next > unlockedLevel) {
      await _prefs.setInt(_kUnlocked, next);
    }
  }
}
