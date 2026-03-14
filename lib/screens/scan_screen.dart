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

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  Future<void> _captureImage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );
      if (image == null) return;

      setState(() {
        _processing = true;
        _error = null;
        _detectedCards = null;
      });

      final cards = await _ocrService.processImage(File(image.path));

      setState(() {
        _processing = false;
        if (cards.isEmpty) {
          _error = 'No bingo numbers detected. Try taking a clearer photo.';
        } else {
          _detectedCards = cards;
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.document_scanner,
                size: 80,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.4)),
            const SizedBox(height: 24),
            Text(
              'Scan Your Bingo Card',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Take a clear photo of one bingo card at a time. '
              'Make sure all numbers are visible.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => _captureImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take Photo'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _captureImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('Pick from Gallery'),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addManualCard,
              icon: const Icon(Icons.edit),
              label: const Text('Enter Card Manually'),
            ),
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
          child: Text(
            'Found ${_detectedCards!.length} card(s). '
            'Tap any cell to edit the number.',
            style: Theme.of(context).textTheme.bodyMedium,
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

  void _acceptCards() {
    final gameState = context.read<GameState>();
    for (final card in _detectedCards!) {
      gameState.addCard(card);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Added ${_detectedCards!.length} card(s)')),
    );
    Navigator.of(context).pop();
  }

  void _addManualCard() {
    final card = BingoCard.empty();
    setState(() {
      _detectedCards = [card];
    });
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
                                .withValues(alpha: 0.3),
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
    final currentNumber = card.numbers[row][col];
    final controller =
        TextEditingController(text: currentNumber?.toString() ?? '');

    final colLetter = BingoCard.columnLetters[col];
    final minVal = col * 15 + 1;
    final maxVal = col * 15 + 15;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$colLetter Column ($minVal-$maxVal)'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter number ($minVal-$maxVal)',
            border: const OutlineInputBorder(),
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
              final newNumbers = List.generate(
                  5, (r) => List<int?>.from(card.numbers[r]));
              newNumbers[row][col] = number;
              onCardChanged(BingoCard(
                  id: card.id, numbers: newNumbers));
              Navigator.pop(ctx);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }
}
