import 'package:flutter/material.dart';
import '../models/bingo_card.dart';

class BingoCardWidget extends StatelessWidget {
  final BingoCard card;
  final bool interactive;
  final void Function(int row, int col)? onCellTap;
  final List<(int, int)>? highlightedCells;
  final String? label;

  const BingoCardWidget({
    super.key,
    required this.card,
    this.interactive = false,
    this.onCellTap,
    this.highlightedCells,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(label!,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
            // BINGO header
            _buildHeader(theme),
            const SizedBox(height: 2),
            // 5x5 grid
            ...List.generate(5, (row) => _buildRow(theme, row)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: BingoCard.columnLetters.map((letter) {
        return Expanded(
          child: Container(
            height: 32,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                letter,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRow(ThemeData theme, int row) {
    return Row(
      children: List.generate(5, (col) {
        final number = card.numbers[row][col];
        final isMarked = card.marked[row][col];
        final isFreeSpace = row == 2 && col == 2;
        final isHighlighted = highlightedCells?.contains((row, col)) ?? false;

        Color bgColor;
        if (isHighlighted) {
          bgColor = Colors.amber.shade300;
        } else if (isMarked) {
          bgColor = theme.colorScheme.primaryContainer;
        } else {
          bgColor = theme.colorScheme.surface;
        }

        return Expanded(
          child: GestureDetector(
            onTap: interactive ? () => onCellTap?.call(row, col) : null,
            child: Container(
              height: 44,
              margin: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.3),
                ),
              ),
              child: Center(
                child: isFreeSpace
                    ? Text('FREE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ))
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            number?.toString() ?? '',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isMarked
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          if (isMarked && !isFreeSpace)
                            Icon(
                              Icons.circle,
                              size: 36,
                              color: theme.colorScheme.primary
                                  .withOpacity(0.2),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
