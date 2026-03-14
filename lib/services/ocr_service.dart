import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/bingo_card.dart';

class OcrService {
  final _textRecognizer = TextRecognizer();

  /// Process an image file and extract bingo card(s).
  /// Handles sheets with 1-9 cards in any grid layout.
  Future<List<BingoCard>> processImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognized = await _textRecognizer.processImage(inputImage);

    final elements = <_NumberElement>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
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

    if (elements.length < 10) return [];
    return _extractCards(elements);
  }

  List<BingoCard> _extractCards(List<_NumberElement> elements) {
    // Step 1: Cluster X and Y positions to find column/row groups.
    // Numbers in the same grid column have nearly identical X values;
    // numbers in the same grid row have nearly identical Y values.
    final xClusters = _clusterValues(elements.map((e) => e.centerX).toList());
    final yClusters = _clusterValues(elements.map((e) => e.centerY).toList());

    // Step 2: Find card boundaries — large gaps between clusters
    // that separate one card from the next.
    final xBoundaries = _findCardBoundaries(xClusters);
    final yBoundaries = _findCardBoundaries(yClusters);

    // Step 3: Assign each element to a card region
    final regions = <String, List<_NumberElement>>{};
    for (final elem in elements) {
      final cx = _regionIndex(elem.centerX, xBoundaries);
      final cy = _regionIndex(elem.centerY, yBoundaries);
      final key = '${cy}_$cx';
      regions.putIfAbsent(key, () => []).add(elem);
    }

    // Step 4: Build a BingoCard from each region
    final cards = <BingoCard>[];
    final sortedKeys = regions.keys.toList()..sort();
    for (final key in sortedKeys) {
      final regionElements = regions[key]!;
      if (regionElements.length >= 15) {
        final card = _buildCardFromRegion(regionElements);
        if (card != null) cards.add(card);
      }
    }

    // Fallback: if boundary detection failed, try all elements as one card
    if (cards.isEmpty) {
      final card = _buildCardFromRegion(elements);
      if (card != null) return [card];
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

    // Threshold: values within 2.5% of total range are in the same cluster.
    // This groups numbers in the same grid column/row together.
    final threshold = range * 0.025;

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

  /// Find card boundaries from cluster center positions.
  /// A card boundary is a gap between clusters that is significantly
  /// larger than the typical within-card gap.
  List<double> _findCardBoundaries(List<double> clusters) {
    if (clusters.length <= 5) return []; // 5 or fewer = one card

    // Calculate gaps between consecutive cluster centers
    final gaps = <_Gap>[];
    for (int i = 1; i < clusters.length; i++) {
      gaps.add(_Gap(
        midpoint: (clusters[i] + clusters[i - 1]) / 2,
        size: clusters[i] - clusters[i - 1],
      ));
    }

    // Sort gap sizes to find the median
    final sortedSizes = gaps.map((g) => g.size).toList()..sort();
    final medianGap = sortedSizes[sortedSizes.length ~/ 2];

    // Card boundaries are gaps >= 1.7x the median gap
    final boundaries = <double>[];
    for (final gap in gaps) {
      if (gap.size > medianGap * 1.7) {
        // Avoid adding boundaries too close to each other
        if (boundaries.isEmpty ||
            (gap.midpoint - boundaries.last).abs() > medianGap * 2) {
          boundaries.add(gap.midpoint);
        }
      }
    }

    boundaries.sort();
    return boundaries;
  }

  int _regionIndex(double value, List<double> boundaries) {
    int idx = 0;
    for (final b in boundaries) {
      if (value > b) idx++;
    }
    return idx;
  }

  /// Build a BingoCard from elements belonging to one card region.
  /// Uses the number value to determine the correct column (B/I/N/G/O),
  /// then sorts by Y position to determine row order within each column.
  BingoCard? _buildCardFromRegion(List<_NumberElement> elements) {
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

    // Build grid: sort each column by Y, take top 5
    final grid = List.generate(5, (_) => List<int?>.filled(5, null));

    for (int col = 0; col < 5; col++) {
      final colElements = columns[col]!;
      colElements.sort((a, b) => a.centerY.compareTo(b.centerY));
      for (int row = 0; row < colElements.length && row < 5; row++) {
        grid[row][col] = colElements[row].number;
      }
    }

    // Free space
    grid[2][2] = null;

    // Verify we got enough numbers to be a real card
    int filled = 0;
    for (final row in grid) {
      for (final cell in row) {
        if (cell != null) filled++;
      }
    }
    if (filled < 10) return null;

    return BingoCard(numbers: grid);
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

class _Gap {
  final double midpoint;
  final double size;

  _Gap({required this.midpoint, required this.size});
}
