import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/bingo_card.dart';

class OcrResult {
  final List<BingoCard> cards;
  final int totalNumbersDetected;
  final int numbersAfterFilter;
  final int totalTextElements;
  final String debugInfo;

  OcrResult({
    required this.cards,
    required this.totalNumbersDetected,
    required this.numbersAfterFilter,
    required this.totalTextElements,
    this.debugInfo = '',
  });
}

class OcrService {
  final _textRecognizer = TextRecognizer();

  /// Process an image that may contain 1-9 bingo cards.
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
              width: box.width,
            ));
          }
        }
      }
    }

    final totalDetected = elements.length;
    _filterByTextSize(elements);
    final afterFilter = elements.length;

    if (elements.length < 5) {
      return OcrResult(
        cards: [],
        totalNumbersDetected: totalDetected,
        numbersAfterFilter: afterFilter,
        totalTextElements: totalTextElements,
        debugInfo: 'Only $afterFilter numbers found after filtering',
      );
    }

    final result = _extractCards(elements);
    return OcrResult(
      cards: result.cards,
      totalNumbersDetected: totalDetected,
      numbersAfterFilter: afterFilter,
      totalTextElements: totalTextElements,
      debugInfo: result.debug,
    );
  }

  /// Remove elements whose text height is significantly smaller than
  /// the typical bingo number. Filters card IDs, serial numbers, etc.
  void _filterByTextSize(List<_NumberElement> elements) {
    if (elements.length < 10) return;
    final heights = elements.map((e) => e.height).toList()..sort();
    final medianHeight = heights[heights.length ~/ 2];
    // Keep only elements at least 60% of median height
    elements.removeWhere((e) => e.height < medianHeight * 0.6);
  }

  _ExtractionResult _extractCards(List<_NumberElement> elements) {
    final debug = StringBuffer();

    // Group elements by bingo column using number value
    final byCol = <int, List<_NumberElement>>{
      for (int i = 0; i < 5; i++) i: [],
    };
    for (final elem in elements) {
      final col = _columnForNumber(elem.number);
      if (col != null) byCol[col]!.add(elem);
    }

    debug.writeln(
        'By column: B=${byCol[0]!.length} I=${byCol[1]!.length} '
        'N=${byCol[2]!.length} G=${byCol[3]!.length} O=${byCol[4]!.length}');

    // Adaptive clustering threshold from element sizes
    final heights = elements.map((e) => e.height).toList()..sort();
    final medianH = heights[heights.length ~/ 2];
    final threshold = medianH * 0.8;
    debug.writeln('Median height: ${medianH.toStringAsFixed(1)}, '
        'cluster threshold: ${threshold.toStringAsFixed(1)}');

    // Use B column (leftmost) to find card columns via X clustering.
    // B numbers from the same card column share an X position.
    // B numbers from different card columns are separated by a full card width.
    final bElems = byCol[0]!;
    final oElems = byCol[4]!;

    if (bElems.length < 3) {
      debug.writeln('Too few B-column numbers, falling back to single card');
      final card = _buildCardFromElements(elements);
      return _ExtractionResult(
          card != null ? [card] : [], debug.toString());
    }

    final bXClusters =
        _cluster(bElems.map((e) => e.centerX).toList(), threshold);
    final oXClusters =
        _cluster(oElems.map((e) => e.centerX).toList(), threshold);
    final numCardCols = bXClusters.length.clamp(1, 3);
    debug.writeln(
        'B X-clusters: ${bXClusters.length}, O X-clusters: ${oXClusters.length} '
        '→ $numCardCols card column(s)');

    // Compute X boundaries between card columns using the midpoint
    // between the O column of card i and the B column of card i+1.
    final xBoundaries = <double>[];
    if (numCardCols > 1 &&
        oXClusters.length >= numCardCols &&
        bXClusters.length >= numCardCols) {
      for (int i = 0; i < numCardCols - 1; i++) {
        xBoundaries.add((oXClusters[i] + bXClusters[i + 1]) / 2);
      }
    } else if (numCardCols > 1) {
      // Fallback: evenly split B clusters
      final cpc = bXClusters.length / numCardCols;
      for (int i = 1; i < numCardCols; i++) {
        final idx = (i * cpc).round();
        if (idx > 0 && idx < bXClusters.length) {
          xBoundaries
              .add((bXClusters[idx - 1] + bXClusters[idx]) / 2);
        }
      }
    }
    debug.writeln('X boundaries: $xBoundaries');

    // Cluster B-column Y positions to find number rows.
    // Total Y clusters should be 5 * numCardRows.
    final bYClusters =
        _cluster(bElems.map((e) => e.centerY).toList(), threshold);
    final numCardRows = _bestDivisor(bYClusters.length, 5);
    debug.writeln(
        'B Y-clusters: ${bYClusters.length} → $numCardRows card row(s)');

    // Compute Y boundaries between card rows
    final yBoundaries = <double>[];
    if (numCardRows > 1) {
      final cpr = bYClusters.length / numCardRows;
      for (int i = 1; i < numCardRows; i++) {
        final idx = (i * cpr).round();
        if (idx > 0 && idx < bYClusters.length) {
          yBoundaries
              .add((bYClusters[idx - 1] + bYClusters[idx]) / 2);
        }
      }
    }
    debug.writeln('Y boundaries: $yBoundaries');
    debug.writeln('Layout: ${numCardCols}x$numCardRows '
        '= ${numCardCols * numCardRows} cards');

    // Assign elements to card regions
    final regions = <String, List<_NumberElement>>{};
    for (final elem in elements) {
      final cx = _regionIndex(elem.centerX, xBoundaries);
      final cy = _regionIndex(elem.centerY, yBoundaries);
      final key = '${cy}_$cx';
      regions.putIfAbsent(key, () => []).add(elem);
    }

    debug.writeln('Regions: ${regions.length}');
    for (final entry in regions.entries) {
      debug.writeln('  ${entry.key}: ${entry.value.length} elements');
    }

    // Build a card from each region
    final cards = <BingoCard>[];
    final sortedKeys = regions.keys.toList()..sort();
    for (final key in sortedKeys) {
      final regionElements = regions[key]!;
      if (regionElements.length >= 8) {
        final card = _buildCardFromElements(regionElements);
        if (card != null) cards.add(card);
      }
    }

    if (cards.isEmpty) {
      debug.writeln('No cards from regions, falling back to single card');
      final card = _buildCardFromElements(elements);
      if (card != null) cards.add(card);
    }

    debug.writeln('Built ${cards.length} card(s)');
    return _ExtractionResult(cards, debug.toString());
  }

  /// Cluster sorted values by proximity. Returns cluster center positions.
  List<double> _cluster(List<double> values, double threshold) {
    if (values.isEmpty) return [];
    values = List.from(values)..sort();

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

  /// Find n in [1..3] such that numClusters ≈ n * expected.
  int _bestDivisor(int numClusters, int expected) {
    int best = 1;
    double bestErr = (numClusters - expected).abs().toDouble();
    for (int n = 2; n <= 3; n++) {
      final err = (numClusters - n * expected).abs().toDouble();
      if (err < bestErr) {
        bestErr = err;
        best = n;
      }
    }
    return best;
  }

  int _regionIndex(double value, List<double> boundaries) {
    int idx = 0;
    for (final b in boundaries) {
      if (value > b) idx++;
    }
    return idx;
  }

  /// Build one BingoCard from elements using number values for column
  /// assignment and Y position for row ordering.
  BingoCard? _buildCardFromElements(List<_NumberElement> elements) {
    final columns = <int, List<_NumberElement>>{
      for (int i = 0; i < 5; i++) i: [],
    };
    for (final elem in elements) {
      final col = _columnForNumber(elem.number);
      if (col != null) columns[col]!.add(elem);
    }

    final grid = List.generate(5, (_) => List<int?>.filled(5, null));

    for (int col = 0; col < 5; col++) {
      final colElements = columns[col]!;
      colElements.sort((a, b) => a.centerY.compareTo(b.centerY));
      for (int row = 0;
          row < colElements.length && row < 5;
          row++) {
        grid[row][col] = colElements[row].number;
      }
    }

    grid[2][2] = null; // FREE space

    int filled = 0;
    for (final row in grid) {
      for (final cell in row) {
        if (cell != null) filled++;
      }
    }
    if (filled < 8) return null;

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

  /// Simpler method for single-card photos.
  Future<OcrResult> processSingleCard(File imageFile) async {
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
              width: box.width,
            ));
          }
        }
      }
    }

    final totalDetected = elements.length;
    _filterByTextSize(elements);

    BingoCard? card;
    if (elements.length >= 5) {
      card = _buildCardFromElements(elements);
    }

    return OcrResult(
      cards: card != null ? [card] : [],
      totalNumbersDetected: totalDetected,
      numbersAfterFilter: elements.length,
      totalTextElements: totalTextElements,
      debugInfo: 'Single-card mode: ${elements.length} numbers after filter',
    );
  }

  void dispose() {
    _textRecognizer.close();
  }
}

class _ExtractionResult {
  final List<BingoCard> cards;
  final String debug;
  _ExtractionResult(this.cards, this.debug);
}

class _NumberElement {
  final int number;
  final double centerX;
  final double centerY;
  final double height;
  final double width;

  _NumberElement({
    required this.number,
    required this.centerX,
    required this.centerY,
    required this.height,
    required this.width,
  });
}
