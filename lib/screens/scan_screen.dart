import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/bingo_card.dart';
import '../models/game_state.dart';
import '../services/ocr_service.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _picker = ImagePicker();
  final _ocrService = OcrService();
  bool _processing = false;
  List<BingoCard>? _detectedCards;
  String? _error;
  String? _detectionInfo;

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  Future<void> _scanSingleCard(ImageSource source) async {
    try {
      final image = await _picker.pickImage(source: source);
      if (image == null) return;

      setState(() {
        _processing = true;
        _error = null;
        _detectedCards = null;
        _detectionInfo = null;
      });

      final result =
          await _ocrService.processSingleCard(File(image.path));

      setState(() {
        _processing = false;
        _detectionInfo = result.debugInfo;
        if (result.cards.isEmpty) {
          _error =
              'Could not read card.\n'
              '${result.debugInfo}\n\n'
              'Make sure the card fills most of the photo '
              'and all numbers are clearly visible.';
        } else {
          _detectedCards = result.cards;
        }
      });
    } catch (e) {
      setState(() {
        _processing = false;
        _error = 'Failed to process image: $e';
      });
    }
  }

  Future<void> _scanCardSheet(ImageSource source) async {
    try {
      final image = await _picker.pickImage(source: source);
      if (image == null) return;

      setState(() {
        _processing = true;
        _error = null;
        _detectedCards = null;
        _detectionInfo = null;
      });

      final result = await _ocrService.processImage(File(image.path));

      setState(() {
        _processing = false;
        _detectionInfo = result.debugInfo;
        if (result.cards.isEmpty) {
          _error =
              'Could not read cards.\n'
              '${result.debugInfo}\n\n'
              'Try scanning one card at a time instead.';
        } else {
          _detectedCards = result.cards;
        }
      });
    } catch (e) {
      setState(() {
        _processing = false;
        _error = 'Failed to process image: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Bingo Card'),
      ),
      body: _processing
          ? _buildProcessing()
          : _detectedCards != null
              ? _buildReview()
              : _buildCapture(),
    );
  }

  Widget _buildCapture() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.document_scanner,
                size: 80,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withOpacity(0.4)),
            const SizedBox(height: 24),
            Text(
              'Scan Your Bingo Card',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),

            // Single card scanning (recommended)
            Text('Single Card',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
            const SizedBox(height: 4),
            Text(
              'Point your camera at one card. Best results.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _scanSingleCard(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan Single Card'),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),

            // Multi-card sheet scanning
            Text('Card Sheet',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
            const SizedBox(height: 4),
            Text(
              'Photograph a full sheet with multiple cards.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _scanCardSheet(ImageSource.camera),
              icon: const Icon(Icons.grid_view),
              label: const Text('Scan Card Sheet'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _scanCardSheet(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('Pick Sheet from Gallery'),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),

            // Manual options
            OutlinedButton.icon(
              onPressed: _addManualCard,
              icon: const Icon(Icons.edit),
              label: const Text('Enter Card Manually'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addRandomCard,
              icon: const Icon(Icons.casino),
              label: const Text('Generate Test Card'),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!,
                    style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.onErrorContainer)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProcessing() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text('Reading bingo card...'),
        ],
      ),
    );
  }

  Widget _buildReview() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Found ${_detectedCards!.length} card(s). '
                'Tap any cell to edit the number.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (_detectionInfo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: GestureDetector(
                    onTap: () => _showDebugInfo(),
                    child: Text(
                      'Tap for scan details',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _detectedCards!.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _EditableCardWidget(
                  card: _detectedCards![index],
                  label: 'Card ${index + 1}',
                  onCardChanged: (updated) {
                    setState(() {
                      _detectedCards![index] = updated;
                    });
                  },
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _detectedCards = null;
                      _error = null;
                    });
                  },
                  child: const Text('Rescan'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _acceptCards,
                  child: const Text('Accept Cards'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDebugInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scan Details'),
        content: SingleChildScrollView(
          child: Text(
            _detectionInfo ?? 'No details available',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _acceptCards() {
    final gameState = context.read<GameState>();
    for (final card in _detectedCards!) {
      gameState.addCard(card);
    }
    final count = _detectedCards!.length;
    final totalCards = gameState.cards.length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Added $count card(s)'),
        content: Text(
            'You now have $totalCards card(s) total. '
            'Scan another card or go back to start playing.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _detectedCards = null;
                _error = null;
                _detectionInfo = null;
              });
            },
            child: const Text('Scan Another'),
          ),
        ],
      ),
    );
  }

  void _addManualCard() {
    final card = BingoCard.empty();
    setState(() {
      _detectedCards = [card];
    });
  }

  void _addRandomCard() {
    final card = BingoCard.random();
    final gameState = context.read<GameState>();
    gameState.addCard(card);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added a random test card')),
    );
  }
}

class _EditableCardWidget extends StatelessWidget {
  final BingoCard card;
  final String label;
  final ValueChanged<BingoCard> onCardChanged;

  const _EditableCardWidget({
    required this.card,
    required this.label,
    required this.onCardChanged,
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
            Text(label,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            // BINGO header
            Row(
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
                      child: Text(letter,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 2),
            ...List.generate(5, (row) {
              return Row(
                children: List.generate(5, (col) {
                  final isFree = row == 2 && col == 2;
                  final number = card.numbers[row][col];
                  return Expanded(
                    child: GestureDetector(
                      onTap: isFree
                          ? null
                          : () => _editCell(context, row, col),
                      child: Container(
                        height: 48,
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: isFree
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: theme.colorScheme.outline
                                .withOpacity(0.3),
                          ),
                        ),
                        child: Center(
                          child: isFree
                              ? Text('FREE',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary))
                              : Text(
                                  number?.toString() ?? '?',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: number == null
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  );
                }),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _editCell(BuildContext context, int row, int col) {
    final colLetter = BingoCard.columnLetters[col];
    final minVal = col * 15 + 1;
    final maxVal = col * 15 + 15;

    // Collect numbers already used in this column (excluding current cell)
    final usedInCol = <int>{};
    for (int r = 0; r < 5; r++) {
      if (r == row) continue;
      final n = card.numbers[r][col];
      if (n != null) usedInCol.add(n);
    }

    // Available numbers for this column
    final available = <int>[];
    for (int n = minVal; n <= maxVal; n++) {
      if (!usedInCol.contains(n)) available.add(n);
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$colLetter Column'),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: available.map((n) {
                  final isCurrentValue = n == card.numbers[row][col];
                  return SizedBox(
                    width: 48,
                    height: 40,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: isCurrentValue
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                      ),
                      onPressed: () {
                        final newNumbers = List.generate(
                            5, (r) => List<int?>.from(card.numbers[r]));
                        newNumbers[row][col] = n;
                        onCardChanged(
                            BingoCard(id: card.id, numbers: newNumbers));
                        Navigator.pop(ctx);
                      },
                      child: Text('$n',
                          style: const TextStyle(fontSize: 14)),
                    ),
                  );
                }).toList(),
              ),
              if (card.numbers[row][col] != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    final newNumbers = List.generate(
                        5, (r) => List<int?>.from(card.numbers[r]));
                    newNumbers[row][col] = null;
                    onCardChanged(
                        BingoCard(id: card.id, numbers: newNumbers));
                    Navigator.pop(ctx);
                  },
                  child: const Text('Clear'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
