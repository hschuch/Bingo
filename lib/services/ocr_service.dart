import 'dart:io';
import 'dart:math' as math;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/bingo_card.dart';

class OcrResult {
  final List<BingoCard> cards;
  final int totalNumbersDetected;
  final int totalTextElements;

  OcrResult({
    required this.cards,
    required this.totalNumbersDetected,
    required this.totalTextElements,
  });
}

class OcrService {
  final _textRecognizer = TextRecognizer();

  /// Process an image file and extract bingo card(s).
  /// Handles sheets with 1-9 cards in any grid layout.
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
            ));
          }
        }
      }
    }

    if (elements.length < 5) {
      return OcrResult(
        cards: [],
        totalNumbersDetected: elements.length,
        totalTextElements: totalTextElements,
      );
    }
    return OcrResult(
      cards: _extractCards(elements),
      totalNumbersDetected: elements.length,
      totalTextElements: totalTextElements,
    );
  }

  List<BingoCard> _extractCards(List<_NumberElement> elements) {
    // Step 1: Cluster X and Y positions.
    // Numbers in the same grid column share similar X; same row share similar Y.
    final xClusters = _clusterValues(elements.map((e) => e.centerX).toList());
    final yClusters = _clusterValues(elements.map((e) => e.centerY).toList());

    // Step 2: Determine grid layout from cluster count.
    // Each bingo card has 5 columns and 5 rows, so:
    //   cluster_count / 5 = number of card columns (or rows)
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
    // If a region has too many numbers per column, it likely contains
    // multiple unseparated cards — split them further.
    final cards = <BingoCard>[];
    final sortedKeys = regions.keys.toList()..sort();
    for (final key in sortedKeys) {
      final regionElements = regions[key]!;
      if (regionElements.length >= 8) {
        cards.addAll(_buildCardsFromRegion(regionElements));
      }
    }

    // Fallback: if no cards were built, treat all elements as one region
    if (cards.isEmpty) {
      cards.addAll(_buildCardsFromRegion(elements));
    }

    return cards;
  }

  /// Group nearby coordinate values into clusters.
  /// Returns sorted list of cluster center values.
  List<double> _clusterValues(List<double> values) {
    if (values.isEmpty) return [];
    values.sort();

    final range = values.last - values.first;
    if (range < 1) return [values.first];

    // Values within 2% of total range are considered the same cluster
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

  /// Compute boundary positions between card regions using cluster positions.
  /// Divides clusters evenly into numCards groups and places boundaries
  /// at the midpoint between adjacent groups.
  List<double> _boundariesFromClusters(List<double> clusters, int numCards) {
    if (numCards <= 1 || clusters.length < 5) return [];

    final clustersPerCard = clusters.length / numCards;
    final boundaries = <double>[];

    for (int i = 1; i < numCards; i++) {
      final splitIdx = (i * clustersPerCard).round();
      if (splitIdx > 0 && splitIdx < clusters.length) {
        boundaries.add(
            (clusters[splitIdx - 1] + clusters[splitIdx]) / 2);
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

  /// Build one or more BingoCards from a region of elements.
  /// If a region appears to contain multiple cards (>6 numbers in any
  /// bingo column range), split by Y position and build separately.
  List<BingoCard> _buildCardsFromRegion(List<_NumberElement> elements) {
    // Group by bingo column range
    final columns = <int, List<_NumberElement>>{
      for (int i = 0; i < 5; i++) i: [],
    };
    for (final elem in elements) {
      final col = _columnForNumber(elem.number);
      if (col != null) {
        columns[col]!.add(elem);
      }
    }

    // Check if this region likely has multiple cards
    final maxPerCol = columns.values
        .map((l) => l.length)
        .fold(0, (int a, int b) => math.max(a, b));

    if (maxPerCol <= 6) {
      // Single card
      final card = _buildSingleCard(columns);
      return card != null ? [card] : [];
    }

    // Multiple cards stacked vertically — split by Y clusters
    final estimatedCards = (maxPerCol / 5).round().clamp(2, 3);
    final yClusters =
        _clusterValues(elements.map((e) => e.centerY).toList());
    final yBoundaries =
        _boundariesFromClusters(yClusters, estimatedCards);

    if (yBoundaries.isEmpty) {
      final card = _buildSingleCard(columns);
      return card != null ? [card] : [];
    }

    // Split elements into sub-regions by Y boundary
    final cards = <BingoCard>[];
    for (int i = 0; i <= yBoundaries.length; i++) {
      final low = i == 0 ? double.negativeInfinity : yBoundaries[i - 1];
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

  /// Build a single BingoCard from pre-grouped column lists.
  BingoCard? _buildSingleCard(Map<int, List<_NumberElement>> columns) {
    final grid = List.generate(5, (_) => List<int?>.filled(5, null));

    for (int col = 0; col < 5; col++) {
      final colElements = columns[col]!;
      colElements.sort((a, b) => a.centerY.compareTo(b.centerY));
      for (int row = 0; row < colElements.length && row < 5; row++) {
        grid[row][col] = colElements[row].number;
      }
    }

    grid[2][2] = null; // Free space

    int filled = 0;
    for (final row in grid) {
      for (final cell in row) {
        if (cell != null) filled++;
      }
    }
    if (filled < 8) return null;

    return BingoCard(numbers: grid);
  }

  /// Build a BingoCard from a flat list of elements.
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
    if (number >= 1 && number <= 15) return 0; // B
    if (number >= 16 && number <= 30) return 1; // I
    if (number >= 31 && number <= 45) return 2; // N
    if (number >= 46 && number <= 60) return 3; // G
    if (number >= 61 && number <= 75) return 4; // O
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
