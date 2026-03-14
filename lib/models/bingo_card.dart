import 'dart:math';

enum WinPattern {
  anyLine,
  fourCorners,
  blackout,
  xPattern,
  plusSign,
  letterT,
  letterL,
  custom,
}

extension WinPatternLabel on WinPattern {
  String get label {
    switch (this) {
      case WinPattern.anyLine:
        return 'Any Line';
      case WinPattern.fourCorners:
        return '4 Corners';
      case WinPattern.blackout:
        return 'Blackout';
      case WinPattern.xPattern:
        return 'X Pattern';
      case WinPattern.plusSign:
        return 'Plus Sign';
      case WinPattern.letterT:
        return 'Letter T';
      case WinPattern.letterL:
        return 'Letter L';
      case WinPattern.custom:
        return 'Custom';
    }
  }

  /// Returns the set of (row, col) positions required for this pattern.
  /// For anyLine, returns null since it checks multiple possible lines.
  List<List<(int, int)>>? get requiredPositions {
    switch (this) {
      case WinPattern.anyLine:
        // 5 rows + 5 cols + 2 diagonals = 12 possible lines
        final lines = <List<(int, int)>>[];
        for (int i = 0; i < 5; i++) {
          lines.add([(i, 0), (i, 1), (i, 2), (i, 3), (i, 4)]); // row
          lines.add([(0, i), (1, i), (2, i), (3, i), (4, i)]); // col
        }
        lines.add([(0, 0), (1, 1), (2, 2), (3, 3), (4, 4)]); // diagonal
        lines.add([(0, 4), (1, 3), (2, 2), (3, 1), (4, 0)]); // anti-diagonal
        return lines;
      case WinPattern.fourCorners:
        return [
          [(0, 0), (0, 4), (4, 0), (4, 4)]
        ];
      case WinPattern.blackout:
        final all = <(int, int)>[];
        for (int r = 0; r < 5; r++) {
          for (int c = 0; c < 5; c++) {
            all.add((r, c));
          }
        }
        return [all];
      case WinPattern.xPattern:
        return [
          [(0, 0), (0, 4), (1, 1), (1, 3), (2, 2), (3, 1), (3, 3), (4, 0), (4, 4)]
        ];
      case WinPattern.plusSign:
        return [
          [(0, 2), (1, 2), (2, 0), (2, 1), (2, 2), (2, 3), (2, 4), (3, 2), (4, 2)]
        ];
      case WinPattern.letterT:
        return [
          [(0, 0), (0, 1), (0, 2), (0, 3), (0, 4), (1, 2), (2, 2), (3, 2), (4, 2)]
        ];
      case WinPattern.letterL:
        return [
          [(0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (4, 1), (4, 2), (4, 3), (4, 4)]
        ];
      case WinPattern.custom:
        return null;
    }
  }
}

class BingoCard {
  final String id;
  /// 5x5 grid of numbers. null means free space.
  final List<List<int?>> numbers;
  /// 5x5 grid tracking which cells are marked.
  final List<List<bool>> marked;

  BingoCard({
    String? id,
    required this.numbers,
    List<List<bool>>? marked,
  })  : id = id ?? _generateId(),
        marked = marked ?? _defaultMarked();

  static String _generateId() {
    final r = Random();
    return DateTime.now().millisecondsSinceEpoch.toString() +
        r.nextInt(9999).toString().padLeft(4, '0');
  }

  static List<List<bool>> _defaultMarked() {
    final m = List.generate(5, (_) => List.filled(5, false));
    m[2][2] = true; // Free space is always marked
    return m;
  }

  /// Create a copy with updated marked state.
  BingoCard copyWithMarked(List<List<bool>> newMarked) {
    return BingoCard(id: id, numbers: numbers, marked: newMarked);
  }

  /// Mark a specific number on this card if it exists.
  /// Returns a new BingoCard with updated marks.
  BingoCard markNumber(int number) {
    final newMarked = List.generate(5, (r) => List<bool>.from(marked[r]));
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 5; c++) {
        if (numbers[r][c] == number) {
          newMarked[r][c] = true;
        }
      }
    }
    return BingoCard(id: id, numbers: numbers, marked: newMarked);
  }

  /// Check if this card is a winner for the given pattern.
  bool isWinner(WinPattern pattern, [List<(int, int)>? customPattern]) {
    if (pattern == WinPattern.custom && customPattern != null) {
      return customPattern.every((pos) => marked[pos.$1][pos.$2]);
    }

    final positions = pattern.requiredPositions;
    if (positions == null) return false;

    // For anyLine, any ONE of the lines being complete is a win
    for (final line in positions) {
      if (line.every((pos) => marked[pos.$1][pos.$2])) {
        return true;
      }
    }
    return false;
  }

  /// Get the winning line positions (for highlighting).
  List<(int, int)>? getWinningPositions(WinPattern pattern,
      [List<(int, int)>? customPattern]) {
    if (pattern == WinPattern.custom && customPattern != null) {
      if (customPattern.every((pos) => marked[pos.$1][pos.$2])) {
        return customPattern;
      }
      return null;
    }

    final positions = pattern.requiredPositions;
    if (positions == null) return null;

    for (final line in positions) {
      if (line.every((pos) => marked[pos.$1][pos.$2])) {
        return line;
      }
    }
    return null;
  }

  /// Create an empty card for editing.
  static BingoCard empty() {
    final numbers = List.generate(5, (_) => List<int?>.filled(5, null));
    return BingoCard(numbers: numbers);
  }

  /// Create a random bingo card (for testing).
  static BingoCard random() {
    final rng = Random();
    final numbers = List.generate(5, (col) {
      final min = col * 15 + 1;
      final max = col * 15 + 15;
      final available = List.generate(max - min + 1, (i) => i + min);
      available.shuffle(rng);
      return available.take(5).toList();
    });
    // Transpose: numbers[col] -> grid[row][col]
    final grid = List.generate(
        5, (row) => List.generate(5, (col) => numbers[col][row] as int?));
    grid[2][2] = null; // Free space
    return BingoCard(numbers: grid);
  }

  static const columnLetters = ['B', 'I', 'N', 'G', 'O'];

  /// Get the column letter for a given number.
  static String letterForNumber(int number) {
    if (number >= 1 && number <= 15) return 'B';
    if (number >= 16 && number <= 30) return 'I';
    if (number >= 31 && number <= 45) return 'N';
    if (number >= 46 && number <= 60) return 'G';
    if (number >= 61 && number <= 75) return 'O';
    return '?';
  }
}
