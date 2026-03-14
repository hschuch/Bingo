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
          final calls = parseBingoCalls(text);
          for (final call in calls) {
            _numberController.add(call.number);
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
  static List<BingoCall> parseBingoCalls(String text) {
    final calls = <BingoCall>[];
    final normalized = text.toUpperCase();

    // Pattern 1: Letter followed by number — "B 12", "B12", "B-12"
    final letterNumber = RegExp(r'\b([BINGO])[\s\-]*(\d{1,2})\b');
    for (final match in letterNumber.allMatches(normalized)) {
      final letter = match.group(1)!;
      final number = int.tryParse(match.group(2)!);
      if (number != null && _isValidBingoNumber(letter, number)) {
        calls.add(BingoCall(letter, number));
      }
    }

    if (calls.isNotEmpty) return calls;

    // Pattern 2: "Under the [letter], [number]"
    final underThe = RegExp(r'UNDER\s+THE\s+([BINGO])[\s,]*(\d{1,2})');
    for (final match in underThe.allMatches(normalized)) {
      final letter = match.group(1)!;
      final number = int.tryParse(match.group(2)!);
      if (number != null && _isValidBingoNumber(letter, number)) {
        calls.add(BingoCall(letter, number));
      }
    }

    if (calls.isNotEmpty) return calls;

    // Pattern 3: Just a number with context — try to infer letter
    final justNumber = RegExp(r'\b(\d{1,2})\b');
    for (final match in justNumber.allMatches(normalized)) {
      final number = int.tryParse(match.group(1)!);
      if (number != null && number >= 1 && number <= 75) {
        // Check if any bingo letter appears nearby in the text
        final letter = _inferLetter(number);
        if (letter != null) {
          calls.add(BingoCall(letter, number));
        }
      }
    }

    // Pattern 4: Handle spoken word numbers
    final wordCalls = _parseWordNumbers(normalized);
    calls.addAll(wordCalls);

    return calls;
  }

  static String? _inferLetter(int number) {
    if (number >= 1 && number <= 15) return 'B';
    if (number >= 16 && number <= 30) return 'I';
    if (number >= 31 && number <= 45) return 'N';
    if (number >= 46 && number <= 60) return 'G';
    if (number >= 61 && number <= 75) return 'O';
    return null;
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

  static final _wordNumbers = {
    'ONE': 1, 'TWO': 2, 'THREE': 3, 'FOUR': 4, 'FIVE': 5,
    'SIX': 6, 'SEVEN': 7, 'EIGHT': 8, 'NINE': 9, 'TEN': 10,
    'ELEVEN': 11, 'TWELVE': 12, 'THIRTEEN': 13, 'FOURTEEN': 14,
    'FIFTEEN': 15, 'SIXTEEN': 16, 'SEVENTEEN': 17, 'EIGHTEEN': 18,
    'NINETEEN': 19, 'TWENTY': 20, 'THIRTY': 30, 'FORTY': 40,
    'FIFTY': 50, 'SIXTY': 60, 'SEVENTY': 70,
  };

  static List<BingoCall> _parseWordNumbers(String text) {
    final calls = <BingoCall>[];

    // Look for letter followed by word number
    for (final letter in ['B', 'I', 'N', 'G', 'O']) {
      final pattern = RegExp('$letter\\s+([A-Z\\s]+)');
      for (final match in pattern.allMatches(text)) {
        final wordPart = match.group(1)!.trim();
        final number = _wordsToNumber(wordPart);
        if (number != null && _isValidBingoNumber(letter, number)) {
          calls.add(BingoCall(letter, number));
        }
      }
    }

    return calls;
  }

  static int? _wordsToNumber(String words) {
    // Try direct match first
    if (_wordNumbers.containsKey(words)) return _wordNumbers[words];

    // Try compound: "TWENTY ONE", "THIRTY FIVE", etc.
    final parts = words.split(RegExp(r'\s+'));
    if (parts.length == 2) {
      final tens = _wordNumbers[parts[0]];
      final ones = _wordNumbers[parts[1]];
      if (tens != null && ones != null && tens >= 20 && ones <= 9) {
        return tens + ones;
      }
    }

    return null;
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
