import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/bingo_card.dart';

class OcrService {
  final _textRecognizer = TextRecognizer();

  /// Process an image file and attempt to extract bingo card(s).
  /// Returns a list of BingoCards found in the image.
  Future<List<BingoCard>> processImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognized = await _textRecognizer.processImage(inputImage);

    // Extract all numeric elements with their positions
    final numberElements = <_NumberElement>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final number = int.tryParse(element.text.trim());
          if (number != null && number >= 1 && number <= 75) {
            final box = element.boundingBox;
            numberElements.add(_NumberElement(
              number: number,
              centerX: box.center.dx,
              centerY: box.center.dy,
            ));
          }
        }
      }
    }

    if (numberElements.isEmpty) return [];

    // Try to cluster numbers into 5x5 grids
    return _clusterIntoCards(numberElements);
  }

  /// Cluster detected numbers into bingo card grids.
  List<BingoCard> _clusterIntoCards(List<_NumberElement> elements) {
    // Sort by Y first, then X
    elements.sort((a, b) {
      final yDiff = a.centerY - b.centerY;
      if (yDiff.abs() > 20) return yDiff.toInt();
      return (a.centerX - b.centerX).toInt();
    });

    // Group into rows by Y proximity
    final rows = <List<_NumberElement>>[];
    List<_NumberElement> currentRow = [elements.first];

    for (int i = 1; i < elements.length; i++) {
      final yGap = (elements[i].centerY - currentRow.last.centerY).abs();
      if (yGap < 25) {
        currentRow.add(elements[i]);
      } else {
        currentRow.sort((a, b) => a.centerX.compareTo(b.centerX));
        rows.add(currentRow);
        currentRow = [elements[i]];
      }
    }
    currentRow.sort((a, b) => a.centerX.compareTo(b.centerX));
    rows.add(currentRow);

    // If we have exactly 5 rows with ~5 elements each, it's one card
    if (rows.length >= 5) {
      return _extractCardsFromRows(rows);
    }

    // If fewer rows, just try to make the best card we can
    if (elements.length >= 20) {
      return _extractCardsFromRows(rows);
    }

    // Too few numbers — build a partial card
    return [_buildPartialCard(elements)];
  }

  List<BingoCard> _extractCardsFromRows(List<List<_NumberElement>> rows) {
    final cards = <BingoCard>[];

    // Try to split into groups of 5 rows (multiple cards stacked vertically)
    for (int startRow = 0; startRow + 4 < rows.length; startRow += 5) {
      final cardRows = rows.sublist(startRow, startRow + 5);
      final grid = List.generate(5, (_) => List<int?>.filled(5, null));

      for (int r = 0; r < 5; r++) {
        final row = cardRows[r];
        // Take up to 5 numbers from each row
        for (int c = 0; c < row.length && c < 5; c++) {
          grid[r][c] = row[c].number;
        }
      }

      // Set free space
      grid[2][2] = null;
      cards.add(BingoCard(numbers: grid));
    }

    // If rows don't divide evenly by 5, try to make one card from remaining
    if (cards.isEmpty) {
      final grid = List.generate(5, (_) => List<int?>.filled(5, null));
      for (int r = 0; r < rows.length && r < 5; r++) {
        for (int c = 0; c < rows[r].length && c < 5; c++) {
          grid[r][c] = rows[r][c].number;
        }
      }
      grid[2][2] = null;
      cards.add(BingoCard(numbers: grid));
    }

    return cards;
  }

  BingoCard _buildPartialCard(List<_NumberElement> elements) {
    final grid = List.generate(5, (_) => List<int?>.filled(5, null));

    // Try to place numbers in their correct columns based on range
    final columns = <int, List<int>>{0: [], 1: [], 2: [], 3: [], 4: []};
    for (final elem in elements) {
      final col = _columnForNumber(elem.number);
      if (col != null && columns[col]!.length < 5) {
        columns[col]!.add(elem.number);
      }
    }

    for (int c = 0; c < 5; c++) {
      for (int r = 0; r < columns[c]!.length && r < 5; r++) {
        grid[r][c] = columns[c]![r];
      }
    }

    grid[2][2] = null; // Free space
    return BingoCard(numbers: grid);
  }

  int? _columnForNumber(int number) {
    if (number >= 1 && number <= 15) return 0;
    if (number >= 16 && number <= 30) return 1;
    if (number >= 31 && number <= 45) return 2;
    if (number >= 46 && number <= 60) return 3;
    if (number >= 61 && number <= 75) return 4;
    return null;
  }

  void dispose() {
    _textRecognizer.close();
  }
}

class _NumberElement {
  final int number;
  final double centerX;
  final double centerY;

  _NumberElement({
    required this.number,
    required this.centerX,
    required this.centerY,
  });
}
