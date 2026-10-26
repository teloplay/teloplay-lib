import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/models/statistics_model.dart';

void main() {
  test('StreakInfo default value test', () {
    expect(StreakInfo.empty.currentStreak, 0);
    expect(StreakInfo.empty.longestStreak, 0);
    expect(StreakInfo.empty.isActiveToday, false);
  });
}

