import 'dart:io';
import 'dart:math' as math;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/bingo_card.dart';

class OcrResult {
  final List<BingoCard> cards;
  final int totalNumbersDetected;
  final int numbersAfterFilter;
  final int totalTextElements;

  OcrResult({
    required this.cards,
    required this.totalNumbersDetected,
    required this.numbersAfterFilter,
    required this.totalTextElements,
  });
}

class OcrService {
  final _textRecognizer = TextRecognizer();

  Future<OcrResult> processImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognized = await _textRecognizer.processImage(inputImage);

    int totalTextElements = 0;
    final elements = <_NumberElement>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          totalTextElements++;
          final number = int.tryParse(element.text.trim());
          if (number != null && number >= 1 && number <= 75) {
            final box = element.boundingBox;
            elements.add(_NumberElement(
              number: number,
              centerX: box.center.dx,
              centerY: box.center.dy,
              height: box.height,
            ));
          }
        }
      }
    }

    final totalDetected = elements.length;

    // Filter out small text — bingo numbers are the largest text on the
    // card. Card IDs, serial numbers, and other noise are printed smaller.
    _filterByTextSize(elements);

    if (elements.length < 5) {
      return OcrResult(
        cards: [],
        totalNumbersDetected: totalDetected,
        numbersAfterFilter: elements.length,
        totalTextElements: totalTextElements,
      );
    }
    return OcrResult(
      cards: _extractCards(elements),
      totalNumbersDetected: totalDetected,
      numbersAfterFilter: elements.length,
      totalTextElements: totalTextElements,
    );
  }

  /// Remove elements whose text height is significantly smaller than
  /// the typical bingo number. This filters out card IDs, serial numbers,
  /// and other small printed noise while keeping the bold bingo numbers.
  void _filterByTextSize(List<_NumberElement> elements) {
    if (elements.length < 10) return;

    final heights = elements.map((e) => e.height).toList()..sort();
    final medianHeight = heights[heights.length ~/ 2];

    // Keep only elements at least 50% of the median height
    elements.removeWhere((e) => e.height < medianHeight * 0.5);
  }

  List<BingoCard> _extractCards(List<_NumberElement> elements) {
    // Step 1: Cluster X and Y positions.
    final xClusters = _clusterValues(elements.map((e) => e.centerX).toList());
    final yClusters = _clusterValues(elements.map((e) => e.centerY).toList());

    // Step 2: Determine grid layout from cluster count.
    // Each bingo card has 5 columns and 5 rows.
    final numCardCols = (xClusters.length / 5).round().clamp(1, 3);
    final numCardRows = (yClusters.length / 5).round().clamp(1, 3);

    // Step 3: Compute boundaries between card regions
    final xBoundaries = _boundariesFromClusters(xClusters, numCardCols);
    final yBoundaries = _boundariesFromClusters(yClusters, numCardRows);

    // Step 4: Assign each element to a card region
    final regions = <String, List<_NumberElement>>{};
    for (final elem in elements) {
      final cx = _regionIndex(elem.centerX, xBoundaries);
      final cy = _regionIndex(elem.centerY, yBoundaries);
      final key = '${cy}_$cx';
      regions.putIfAbsent(key, () => []).add(elem);
    }

    // Step 5: Build cards from each region.
    final cards = <BingoCard>[];
    final sortedKeys = regions.keys.toList()..sort();
    for (final key in sortedKeys) {
      final regionElements = regions[key]!;
      if (regionElements.length >= 8) {
        cards.addAll(_buildCardsFromRegion(regionElements));
      }
    }

    // Fallback: treat all elements as one region
    if (cards.isEmpty) {
      cards.addAll(_buildCardsFromRegion(elements));
    }

    return cards;
  }

  List<double> _clusterValues(List<double> values) {
    if (values.isEmpty) return [];
    values.sort();

    final range = values.last - values.first;
    if (range < 1) return [values.first];

    final threshold = range * 0.02;

    final centers = <double>[];
    var sum = values.first;
    var count = 1;

    for (int i = 1; i < values.length; i++) {
      if (values[i] - values[i - 1] <= threshold) {
        sum += values[i];
        count++;
      } else {
        centers.add(sum / count);
        sum = values[i];
        count = 1;
      }
    }
    centers.add(sum / count);
    return centers;
  }

  List<double> _boundariesFromClusters(List<double> clusters, int numCards) {
    if (numCards <= 1 || clusters.length < 5) return [];

    final clustersPerCard = clusters.length / numCards;
    final boundaries = <double>[];

    for (int i = 1; i < numCards; i++) {
      final splitIdx = (i * clustersPerCard).round();
      if (splitIdx > 0 && splitIdx < clusters.length) {
        boundaries
            .add((clusters[splitIdx - 1] + clusters[splitIdx]) / 2);
      }
    }

    return boundaries;
  }

  int _regionIndex(double value, List<double> boundaries) {
    int idx = 0;
    for (final b in boundaries) {
      if (value > b) idx++;
    }
    return idx;
  }

  List<BingoCard> _buildCardsFromRegion(List<_NumberElement> elements) {
    final columns = <int, List<_NumberElement>>{
      for (int i = 0; i < 5; i++) i: [],
    };
    for (final elem in elements) {
      final col = _columnForNumber(elem.number);
      if (col != null) {
        columns[col]!.add(elem);
      }
    }

    final maxPerCol = columns.values
        .map((l) => l.length)
        .fold(0, (int a, int b) => math.max(a, b));

    if (maxPerCol <= 6) {
      final card = _buildSingleCard(columns);
      return card != null ? [card] : [];
    }

    // Multiple cards in region — split by Y
    final estimatedCards = (maxPerCol / 5).round().clamp(2, 3);
    final yClusters =
        _clusterValues(elements.map((e) => e.centerY).toList());
    final yBoundaries =
        _boundariesFromClusters(yClusters, estimatedCards);

    if (yBoundaries.isEmpty) {
      final card = _buildSingleCard(columns);
      return card != null ? [card] : [];
    }

    final cards = <BingoCard>[];
    for (int i = 0; i <= yBoundaries.length; i++) {
      final low =
          i == 0 ? double.negativeInfinity : yBoundaries[i - 1];
      final high =
          i == yBoundaries.length ? double.infinity : yBoundaries[i];
      final sub = elements
          .where((e) => e.centerY > low && e.centerY <= high)
          .toList();
      if (sub.length >= 8) {
        final card = _buildCardFromElements(sub);
        if (card != null) cards.add(card);
      }
    }
    return cards;
  }

  BingoCard? _buildSingleCard(Map<int, List<_NumberElement>> columns) {
    final grid = List.generate(5, (_) => List<int?>.filled(5, null));

    for (int col = 0; col < 5; col++) {
      final colElements = columns[col]!;
      colElements.sort((a, b) => a.centerY.compareTo(b.centerY));
      for (int row = 0; row < colElements.length && row < 5; row++) {
        grid[row][col] = colElements[row].number;
      }
    }

    grid[2][2] = null;

    int filled = 0;
    for (final row in grid) {
      for (final cell in row) {
        if (cell != null) filled++;
      }
    }
    if (filled < 8) return null;

    return BingoCard(numbers: grid);
  }

  BingoCard? _buildCardFromElements(List<_NumberElement> elements) {
    final columns = <int, List<_NumberElement>>{
      for (int i = 0; i < 5; i++) i: [],
    };
    for (final elem in elements) {
      final col = _columnForNumber(elem.number);
      if (col != null) {
        columns[col]!.add(elem);
      }
    }
    return _buildSingleCard(columns);
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
  final double height;

  _NumberElement({
    required this.number,
    required this.centerX,
    required this.centerY,
    required this.height,
  });
}
