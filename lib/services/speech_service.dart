import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Parsed bingo call result.
class BingoCall {
  final String letter;
  final int number;

  BingoCall(this.letter, this.number);

  @override
  String toString() => '$letter-$number';
}

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _shouldBeListening = false;
  Timer? _restartTimer;

  final _numberController = StreamController<int>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _textController = StreamController<String>.broadcast();

  Stream<int> get onNumberCalled => _numberController.stream;
  Stream<String> get onStatusChange => _statusController.stream;
  Stream<String> get onTextHeard => _textController.stream;

  bool get isListening => _speech.isListening;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    _isInitialized = await _speech.initialize(
      onStatus: _handleStatus,
      onError: (error) {
        _statusController.add('Error: ${error.errorMsg}');
        // Auto-restart on error if we should be listening
        if (_shouldBeListening) {
          _scheduleRestart();
        }
      },
    );
    return _isInitialized;
  }

  void _handleStatus(String status) {
    _statusController.add(status);
    // Auto-restart when recognition stops but we want it running
    if (status == 'done' && _shouldBeListening) {
      _scheduleRestart();
    }
  }

  void _scheduleRestart() {
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 500), () {
      if (_shouldBeListening) {
        _startRecognition();
      }
    });
  }

  Future<void> startListening() async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) {
        _statusController.add('Speech recognition not available');
        return;
      }
    }

    _shouldBeListening = true;
    await _startRecognition();
  }

  Future<void> _startRecognition() async {
    if (_speech.isListening) return;

    await _speech.listen(
      onResult: (result) {
        final text = result.recognizedWords;
        if (text.isNotEmpty) {
          _textController.add(text);
          // Only parse and call numbers on FINAL results.
          // Partial results change as speech is recognized
          // (e.g., "5" → "50" → "57"), so acting on them
          // causes false calls.
          if (result.finalResult) {
            final calls = parseBingoCalls(text);
            for (final call in calls) {
              _numberController.add(call.number);
            }
          }
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  Future<void> stopListening() async {
    _shouldBeListening = false;
    _restartTimer?.cancel();
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  /// Parse bingo calls from recognized speech text.
  /// Only matches explicit letter + number patterns:
  ///   "B 12", "B12", "B-12", "under the B 12", "bee 12"
  static List<BingoCall> parseBingoCalls(String text) {
    final calls = <BingoCall>[];
    final normalized = text.toUpperCase();

    // Map common speech-to-text mishearings of bingo letters
    // "bee" → B, "eye" → I, "in" → N, "gee/she" → G, "oh" → O
    var cleaned = normalized;
    cleaned = cleaned.replaceAll(RegExp(r'\bBEE\b'), 'B');
    cleaned = cleaned.replaceAll(RegExp(r'\bEYE\b'), 'I');
    cleaned = cleaned.replaceAll(RegExp(r'\bGEE\b'), 'G');
    cleaned = cleaned.replaceAll(RegExp(r'\bOH\b'), 'O');

    // Pattern 1: Letter followed by number — "B 12", "B12", "B-12"
    final letterNumber = RegExp(r'\b([BINGO])[\s\-]*(\d{1,2})\b');
    for (final match in letterNumber.allMatches(cleaned)) {
      final letter = match.group(1)!;
      final number = int.tryParse(match.group(2)!);
      if (number != null && _isValidBingoNumber(letter, number)) {
        calls.add(BingoCall(letter, number));
      }
    }

    if (calls.isNotEmpty) return calls;

    // Pattern 2: "Under the [letter], [number]"
    final underThe = RegExp(r'UNDER\s+THE\s+([BINGO])[\s,]*(\d{1,2})');
    for (final match in underThe.allMatches(cleaned)) {
      final letter = match.group(1)!;
      final number = int.tryParse(match.group(2)!);
      if (number != null && _isValidBingoNumber(letter, number)) {
        calls.add(BingoCall(letter, number));
      }
    }

    // No fallback patterns — require an explicit letter.
    // This prevents ambient speech from triggering false calls.
    return calls;
  }

  static bool _isValidBingoNumber(String letter, int number) {
    switch (letter) {
      case 'B':
        return number >= 1 && number <= 15;
      case 'I':
        return number >= 16 && number <= 30;
      case 'N':
        return number >= 31 && number <= 45;
      case 'G':
        return number >= 46 && number <= 60;
      case 'O':
        return number >= 61 && number <= 75;
      default:
        return false;
    }
  }

  void dispose() {
    _restartTimer?.cancel();
    _shouldBeListening = false;
    _speech.stop();
    _numberController.close();
    _statusController.close();
    _textController.close();
  }
}
