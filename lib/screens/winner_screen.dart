import 'package:flutter/material.dart';
import '../models/bingo_card.dart';
import '../widgets/bingo_card_widget.dart';

class WinnerScreen extends StatelessWidget {
  final List<BingoCard> winners;
  final WinPattern winPattern;
  final List<(int, int)>? customPattern;
  final Set<int> calledNumbers;

  const WinnerScreen({
    super.key,
    required this.winners,
    required this.winPattern,
    this.customPattern,
    required this.calledNumbers,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('BINGO!'),
        backgroundColor: Colors.amber.shade100,
      ),
      body: Column(
        children: [
          // Winner banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.amber.shade100, Colors.amber.shade50],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                Icon(Icons.celebration, size: 48, color: Colors.amber.shade700),
                const SizedBox(height: 8),
                Text(
                  'BINGO!',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${winners.length} winning card${winners.length > 1 ? 's' : ''} found!',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.amber.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pattern: ${winPattern.label}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.amber.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Instruction
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Verify the highlighted numbers on your physical card before calling BINGO!',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Winner cards
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: winners.length,
              itemBuilder: (context, index) {
                final card = winners[index];
                final winPositions =
                    card.getWinningPositions(winPattern, customPattern);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      BingoCardWidget(
                        card: card,
                        label: 'Winner ${index + 1}',
                        highlightedCells: winPositions,
                      ),
                      const SizedBox(height: 8),
                      _buildWinDetails(context, card, winPositions),
                    ],
                  ),
                );
              },
            ),
          ),
          // Bottom action
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Game'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWinDetails(
      BuildContext context, BingoCard card, List<(int, int)>? winPositions) {
    if (winPositions == null) return const SizedBox.shrink();

    final winningNumbers = <String>[];
    for (final pos in winPositions) {
      final number = card.numbers[pos.$1][pos.$2];
      if (number != null) {
        winningNumbers.add('${BingoCard.letterForNumber(number)}$number');
      } else {
        winningNumbers.add('FREE');
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Winning Numbers:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade800,
                ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: winningNumbers.map((n) {
              return Chip(
                label: Text(n, style: const TextStyle(fontSize: 12)),
                backgroundColor: Colors.amber.shade100,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
