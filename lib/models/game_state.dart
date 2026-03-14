import 'package:flutter/foundation.dart';
import 'bingo_card.dart';

class GameState extends ChangeNotifier {
  final List<BingoCard> _cards = [];
  WinPattern _winPattern = WinPattern.anyLine;
  List<(int, int)>? _customPattern;
  final Set<int> _calledNumbers = {};
  bool _isListening = false;
  List<BingoCard> _winners = [];
  String _lastHeardText = '';

  List<BingoCard> get cards => _cards;
  WinPattern get winPattern => _winPattern;
  List<(int, int)>? get customPattern => _customPattern;
  Set<int> get calledNumbers => _calledNumbers;
  bool get isListening => _isListening;
  List<BingoCard> get winners => _winners;
  String get lastHeardText => _lastHeardText;

  void addCard(BingoCard card) {
    _cards.add(card);
    notifyListeners();
  }

  void removeCard(int index) {
    if (index >= 0 && index < _cards.length) {
      _cards.removeAt(index);
      notifyListeners();
    }
  }

  void updateCard(int index, BingoCard card) {
    if (index >= 0 && index < _cards.length) {
      _cards[index] = card;
      notifyListeners();
    }
  }

  void setWinPattern(WinPattern pattern) {
    _winPattern = pattern;
    _customPattern = null;
    notifyListeners();
  }

  void setCustomPattern(List<(int, int)> pattern) {
    _winPattern = WinPattern.custom;
    _customPattern = pattern;
    notifyListeners();
  }

  void setListening(bool listening) {
    _isListening = listening;
    notifyListeners();
  }

  void setLastHeardText(String text) {
    _lastHeardText = text;
    notifyListeners();
  }

  /// Call a number — marks it on all cards and checks for winners.
  void callNumber(int number) {
    if (number < 1 || number > 75) return;
    if (_calledNumbers.contains(number)) return;

    _calledNumbers.add(number);

    // Mark on all cards
    for (int i = 0; i < _cards.length; i++) {
      _cards[i] = _cards[i].markNumber(number);
    }

    // Check for winners
    _checkWinners();

    notifyListeners();
  }

  /// Manually toggle a cell on a specific card.
  void toggleCell(int cardIndex, int row, int col) {
    if (cardIndex < 0 || cardIndex >= _cards.length) return;
    if (row == 2 && col == 2) return; // Can't unmark free space

    final card = _cards[cardIndex];
    final newMarked = List.generate(5, (r) => List<bool>.from(card.marked[r]));
    newMarked[row][col] = !newMarked[row][col];
    _cards[cardIndex] = card.copyWithMarked(newMarked);

    // If marking, also add the number to called numbers
    final number = card.numbers[row][col];
    if (number != null && newMarked[row][col]) {
      _calledNumbers.add(number);
    }

    _checkWinners();
    notifyListeners();
  }

  void _checkWinners() {
    _winners = _cards
        .where((card) => card.isWinner(_winPattern, _customPattern))
        .toList();
  }

  /// Reset the game (keep cards, clear marks and called numbers).
  void resetGame() {
    _calledNumbers.clear();
    _winners.clear();
    _isListening = false;
    _lastHeardText = '';
    for (int i = 0; i < _cards.length; i++) {
      final card = _cards[i];
      final freshMarked = List.generate(5, (_) => List.filled(5, false));
      freshMarked[2][2] = true; // Free space
      _cards[i] = card.copyWithMarked(freshMarked);
    }
    notifyListeners();
  }

  /// Clear all cards and game state.
  void clearAll() {
    _cards.clear();
    _calledNumbers.clear();
    _winners.clear();
    _isListening = false;
    _winPattern = WinPattern.anyLine;
    _customPattern = null;
    _lastHeardText = '';
    notifyListeners();
  }
}
