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

  // Debounce: track the pending call and a timer.
  // When a partial result detects a bingo call, we start a short timer.
  // If the detected number changes before the timer fires, we reset it.
  // This prevents "O 70" from committing when the recognizer is still
  // working toward "O 74".
  BingoCall? _pendingCall;
  Timer? _callDebounce;
  final Set<int> _emittedThisSession = {};

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
        if (_shouldBeListening) {
          _scheduleRestart();
        }
      },
    );
    return _isInitialized;
  }

  void _handleStatus(String status) {
    _statusController.add(status);
    if (status == 'done' && _shouldBeListening) {
      // Commit any pending call before restarting
      _commitPending();
      _emittedThisSession.clear();
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

  void _commitPending() {
    _callDebounce?.cancel();
    if (_pendingCall != null) {
      _numberController.add(_pendingCall!.number);
      _emittedThisSession.add(_pendingCall!.number);
      _pendingCall = null;
    }
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
    _emittedThisSession.clear();
    _pendingCall = null;
    await _startRecognition();
  }

  Future<void> _startRecognition() async {
    if (_speech.isListening) return;

    await _speech.listen(
      onResult: (result) {
        final text = result.recognizedWords;
        if (text.isEmpty) return;

        _textController.add(text);

        // Parse all bingo calls, take only the LAST one
        // (the most recently spoken call in accumulated text)
        final calls = parseBingoCalls(text);
        final lastCall = calls.isNotEmpty ? calls.last : null;

        if (result.finalResult) {
          // Final result: commit immediately
          _callDebounce?.cancel();
          _pendingCall = null;
          if (lastCall != null &&
              !_emittedThisSession.contains(lastCall.number)) {
            _numberController.add(lastCall.number);
            _emittedThisSession.add(lastCall.number);
          }
        } else if (lastCall != null &&
            !_emittedThisSession.contains(lastCall.number)) {
          // Partial result: debounce to let the number stabilize.
          // If the number changes, restart the timer.
          if (_pendingCall?.number != lastCall.number) {
            _pendingCall = lastCall;
            _callDebounce?.cancel();
            _callDebounce =
                Timer(const Duration(milliseconds: 800), () {
              if (_pendingCall != null &&
                  !_emittedThisSession.contains(_pendingCall!.number)) {
                _numberController.add(_pendingCall!.number);
                _emittedThisSession.add(_pendingCall!.number);
                _pendingCall = null;
              }
            });
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
    _commitPending();
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  /// Parse bingo calls from recognized speech text.
  /// Only matches explicit letter + number patterns.
  static List<BingoCall> parseBingoCalls(String text) {
    final calls = <BingoCall>[];
    final normalized = text.toUpperCase();

    // Map common speech-to-text mishearings of bingo letters
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
    _callDebounce?.cancel();
    _shouldBeListening = false;
    _speech.stop();
    _numberController.close();
    _statusController.close();
    _textController.close();
  }
}
