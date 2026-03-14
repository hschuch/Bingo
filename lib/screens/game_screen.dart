import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bingo_card.dart';
import '../models/game_state.dart';
import '../services/speech_service.dart';
import '../widgets/bingo_card_widget.dart';
import '../widgets/win_pattern_selector.dart';
import 'winner_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final SpeechService _speechService = SpeechService();
  StreamSubscription<int>? _numberSub;
  StreamSubscription<String>? _textSub;
  bool _gameStarted = false;
  bool _showPatternSelector = true;

  @override
  void initState() {
    super.initState();
    _numberSub = _speechService.onNumberCalled.listen(_onNumberCalled);
    _textSub = _speechService.onTextHeard.listen(_onTextHeard);
  }

  void _onTextHeard(String text) {
    if (!mounted) return;
    context.read<GameState>().setLastHeardText(text);
  }

  @override
  void dispose() {
    _numberSub?.cancel();
    _textSub?.cancel();
    _speechService.dispose();
    super.dispose();
  }

  void _onNumberCalled(int number) {
    final gameState = context.read<GameState>();
    gameState.callNumber(number);

    // Check for winners after calling the number
    if (gameState.winners.isNotEmpty) {
      _showWinnerDialog();
    }
  }

  void _showWinnerDialog() {
    final gameState = context.read<GameState>();
    _speechService.stopListening();
    gameState.setListening(false);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WinnerScreen(
          winners: gameState.winners,
          winPattern: gameState.winPattern,
          customPattern: gameState.customPattern,
          calledNumbers: gameState.calledNumbers,
        ),
      ),
    );
  }

  Future<void> _toggleListening() async {
    final gameState = context.read<GameState>();
    if (gameState.isListening) {
      await _speechService.stopListening();
      gameState.setListening(false);
    } else {
      await _speechService.startListening();
      gameState.setListening(true);
    }
  }

  void _startGame() {
    setState(() {
      _gameStarted = true;
      _showPatternSelector = false;
    });
  }

  void _manualCallNumber() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Call a Number'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g., 42',
            labelText: 'Bingo Number (1-75)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final number = int.tryParse(controller.text.trim());
              if (number != null && number >= 1 && number <= 75) {
                context.read<GameState>().callNumber(number);
                Navigator.pop(ctx);
                // Check for winner
                if (context.read<GameState>().winners.isNotEmpty) {
                  _showWinnerDialog();
                }
              }
            },
            child: const Text('Call'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gameState = context.watch<GameState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bingo Game'),
        actions: [
          if (_gameStarted)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset game',
              onPressed: () => _confirmReset(context, gameState),
            ),
        ],
      ),
      body: _showPatternSelector
          ? _buildPatternSelection(gameState)
          : _buildGameView(gameState),
    );
  }

  Widget _buildPatternSelection(GameState gameState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Select the winning pattern for this round:',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          WinPatternSelector(
            selected: gameState.winPattern,
            onSelected: gameState.setWinPattern,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _startGame,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Game'),
          ),
        ],
      ),
    );
  }

  Widget _buildGameView(GameState gameState) {
    return Column(
      children: [
        // Listening controls
        _buildListeningBar(gameState),
        // Called numbers display
        _buildCalledNumbers(gameState),
        // Cards
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: gameState.cards.length,
            itemBuilder: (context, index) {
              final card = gameState.cards[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BingoCardWidget(
                  card: card,
                  label: 'Card ${index + 1}',
                  interactive: true,
                  onCellTap: (row, col) {
                    gameState.toggleCell(index, row, col);
                    if (gameState.winners.isNotEmpty) {
                      _showWinnerDialog();
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildListeningBar(GameState gameState) {
    final isListening = gameState.isListening;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isListening
          ? Colors.green.shade50
          : theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            isListening ? Icons.mic : Icons.mic_off,
            color: isListening ? Colors.green : theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isListening ? 'Listening...' : 'Microphone Off',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isListening ? Colors.green.shade700 : null,
                  ),
                ),
                if (gameState.lastHeardText.isNotEmpty)
                  Text(
                    gameState.lastHeardText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: _toggleListening,
            icon: Icon(isListening ? Icons.stop : Icons.mic),
            label: Text(isListening ? 'Stop' : 'Listen'),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _manualCallNumber,
            icon: const Icon(Icons.dialpad),
            tooltip: 'Manual entry',
          ),
        ],
      ),
    );
  }

  Widget _buildCalledNumbers(GameState gameState) {
    if (gameState.calledNumbers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('No numbers called yet',
            style: TextStyle(fontStyle: FontStyle.italic)),
      );
    }

    final sorted = gameState.calledNumbers.toList()..sort();
    final grouped = <String, List<int>>{};
    for (final n in sorted) {
      final letter = BingoCard.letterForNumber(n);
      grouped.putIfAbsent(letter, () => []).add(n);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Called: ${gameState.calledNumbers.length}',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                'Win: ${gameState.winPattern.label}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: sorted.map((n) {
                return Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${BingoCard.letterForNumber(n)}$n',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmReset(BuildContext context, GameState gameState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Game?'),
        content: const Text(
            'This will clear all called numbers and marks. Your cards will be kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              _speechService.stopListening();
              gameState.resetGame();
              setState(() {
                _gameStarted = false;
                _showPatternSelector = true;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
