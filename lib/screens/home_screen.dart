import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/game_state.dart';
import '../widgets/bingo_card_widget.dart';
import 'scan_screen.dart';
import 'game_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gameState = context.watch<GameState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bingo Assistant'),
        centerTitle: true,
        actions: [
          if (gameState.cards.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear all cards',
              onPressed: () => _confirmClearAll(context, gameState),
            ),
        ],
      ),
      body: gameState.cards.isEmpty ? _buildEmptyState(context) : _buildCardList(context, gameState),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (gameState.cards.isNotEmpty)
            FloatingActionButton.extended(
              heroTag: 'start_game',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GameScreen()),
                );
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Game'),
            ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'scan_card',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ScanScreen()),
              );
            },
            tooltip: 'Scan a bingo card',
            child: const Icon(Icons.camera_alt),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_view_rounded,
                size: 80,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 24),
            Text(
              'No Bingo Cards',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Take a photo of your bingo card(s) to get started. '
              'The app will read the numbers and create a digital copy.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ScanScreen()),
                );
              },
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan Card'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardList(BuildContext context, GameState gameState) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: gameState.cards.length,
      itemBuilder: (context, index) {
        final card = gameState.cards[index];
        return Dismissible(
          key: Key(card.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.red,
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) {
            gameState.removeCard(index);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Card removed')),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: BingoCardWidget(
              card: card,
              label: 'Card ${index + 1}',
            ),
          ),
        );
      },
    );
  }

  void _confirmClearAll(BuildContext context, GameState gameState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Cards?'),
        content: const Text('This will remove all scanned cards.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              gameState.clearAll();
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
