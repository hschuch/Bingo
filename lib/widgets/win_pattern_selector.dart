import 'package:flutter/material.dart';
import '../models/bingo_card.dart';

class WinPatternSelector extends StatelessWidget {
  final WinPattern selected;
  final ValueChanged<WinPattern> onSelected;

  const WinPatternSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Win Pattern',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: WinPattern.values
              .where((p) => p != WinPattern.custom)
              .map((pattern) {
            return ChoiceChip(
              label: Text(pattern.label),
              selected: selected == pattern,
              onSelected: (_) => onSelected(pattern),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        _PatternPreview(pattern: selected),
      ],
    );
  }
}

class _PatternPreview extends StatelessWidget {
  final WinPattern pattern;

  const _PatternPreview({required this.pattern});

  @override
  Widget build(BuildContext context) {
    final positions = pattern.requiredPositions;
    if (positions == null) return const SizedBox.shrink();

    // For anyLine, show a sample (first row)
    final displayPositions =
        pattern == WinPattern.anyLine ? positions.first : positions.first;

    final theme = Theme.of(context);
    return Center(
      child: SizedBox(
        width: 150,
        height: 150,
        child: Column(
          children: List.generate(5, (row) {
            return Expanded(
              child: Row(
                children: List.generate(5, (col) {
                  final isRequired = displayPositions.contains((row, col));
                  final isFree = row == 2 && col == 2;
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: isRequired
                            ? theme.colorScheme.primary
                            : isFree
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ),
      ),
    );
  }
}
