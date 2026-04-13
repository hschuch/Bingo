import 'dart:io';
import 'dart:math' as math;
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

    // Extract numbers from individual text elements
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

    // Try merging adjacent single digits into two-digit numbers
    // (OCR sometimes splits "35" into "3" and "5")
    _mergeAdjacentDigits(elements);
    final afterMerge = elements.length;

    // Filter out small text (card IDs, serial numbers)
    _filterByTextSize(elements);
    final afterFilter = elements.length;

    if (elements.length < 5) {
      return OcrResult(
        cards: [],
        totalNumbersDetected: totalDetected,
        numbersAfterFilter: afterFilter,
        totalTextElements: totalTextElements,
        debugInfo: 'Only $afterFilter numbers after filtering '
            '($totalDetected raw, $afterMerge after merge)',
      );
    }

    final result = _extractCards(elements);
    return OcrResult(
      cards: result.cards,
      totalNumbersDetected: totalDetected,
      numbersAfterFilter: afterFilter,
      totalTextElements: totalTextElements,
      debugInfo: 'Raw: $totalDetected, merged: $afterMerge, '
          'filtered: $afterFilter\n${result.debug}',
    );
  }

  /// Merge adjacent single-digit elements that are likely parts of one
  /// two-digit number split by OCR (e.g. "3" + "5" → "35").
  void _mergeAdjacentDigits(List<_NumberElement> elements) {
    // Sort by Y then X so adjacent elements in the same row are next to each other
    elements.sort((a, b) {
      final dy = a.centerY - b.centerY;
      if (dy.abs() > a.height * 0.3) return dy > 0 ? 1 : -1;
      return a.centerX.compareTo(b.centerX);
    });

    final toRemove = <int>{};
    final toAdd = <_NumberElement>[];

    for (int i = 0; i < elements.length - 1; i++) {
      if (toRemove.contains(i)) continue;
      final left = elements[i];
      if (left.number > 9) continue; // Only merge single digits

      final right = elements[i + 1];
      if (toRemove.contains(i + 1)) continue;
      if (right.number > 9) continue;

      // Must be on same row (similar Y)
      if ((left.centerY - right.centerY).abs() > left.height * 0.5) continue;

      // Must be very close horizontally — nearly touching
      final xGap = right.centerX - left.centerX;
      if (xGap <= 0 || xGap > math.max(left.width, right.width) * 1.5) continue;

      // Try merging left+right
      final merged = left.number * 10 + right.number;
      if (merged >= 1 && merged <= 75) {
        toRemove.add(i);
        toRemove.add(i + 1);
        toAdd.add(_NumberElement(
          number: merged,
          centerX: (left.centerX + right.centerX) / 2,
          centerY: (left.centerY + right.centerY) / 2,
          height: math.max(left.height, right.height),
          width: (right.centerX - left.centerX) + right.width,
        ));
      }
    }

    // Remove merged originals (in reverse order to keep indices valid)
    final sortedRemove = toRemove.toList()..sort((a, b) => b.compareTo(a));
    for (final idx in sortedRemove) {
      elements.removeAt(idx);
    }
    elements.addAll(toAdd);
  }

  /// Remove elements whose text height is significantly smaller than
  /// the typical bingo number. Uses 75th percentile as reference to be
  /// robust against noise pulling the median down.
  void _filterByTextSize(List<_NumberElement> elements) {
    if (elements.length < 10) return;
    final heights = elements.map((e) => e.height).toList()..sort();
    final refHeight = heights[(heights.length * 0.75).toInt()];
    // Keep only elements at least 50% of the reference height
    elements.removeWhere((e) => e.height < refHeight * 0.5);
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
        'threshold: ${threshold.toStringAsFixed(1)}');

    // --- X CARD COLUMN DETECTION ---
    // Use the bingo column with the most elements for X clustering.
    // Elements from the same bingo column on different cards are
    // separated by a full card width (much larger than within-card gaps).
    int bestCol = 0;
    int bestCount = 0;
    for (int i = 0; i < 5; i++) {
      if (byCol[i]!.length > bestCount) {
        bestCount = byCol[i]!.length;
        bestCol = i;
      }
    }
    final refXElems = byCol[bestCol]!;
    final refXClusters =
        _cluster(refXElems.map((e) => e.centerX).toList(), threshold);
    final numCardCols = refXClusters.length.clamp(1, 3);
    debug.writeln('X ref col=$bestCol (${refXElems.length} elems), '
        '${refXClusters.length} X-clusters → $numCardCols card col(s)');

    // For X boundaries, use B (leftmost) and O (rightmost) columns.
    // Boundary = midpoint between O of card i and B of card i+1.
    final bXClusters =
        _cluster(byCol[0]!.map((e) => e.centerX).toList(), threshold);
    final oXClusters =
        _cluster(byCol[4]!.map((e) => e.centerX).toList(), threshold);

    final xBoundaries = <double>[];
    if (numCardCols > 1 &&
        oXClusters.length >= numCardCols &&
        bXClusters.length >= numCardCols) {
      for (int i = 0; i < numCardCols - 1; i++) {
        xBoundaries.add((oXClusters[i] + bXClusters[i + 1]) / 2);
      }
    } else if (numCardCols > 1 && refXClusters.length >= numCardCols) {
      // Fallback: evenly split reference column clusters
      final cpc = refXClusters.length / numCardCols;
      for (int i = 1; i < numCardCols; i++) {
        final idx = (i * cpc).round();
        if (idx > 0 && idx < refXClusters.length) {
          xBoundaries
              .add((refXClusters[idx - 1] + refXClusters[idx]) / 2);
        }
      }
    }
    debug.writeln('X boundaries: ${xBoundaries.map((b) => b.toStringAsFixed(0)).toList()}');

    // --- Y CARD ROW DETECTION ---
    // Use ALL elements for Y clustering (much more data than B-only).
    // Each row cluster has elements from all card columns at that row.
    final allYClusters =
        _cluster(elements.map((e) => e.centerY).toList(), threshold);
    final numCardRows = _bestDivisor(allYClusters.length, 5);
    debug.writeln('${allYClusters.length} Y-clusters → $numCardRows card row(s)');

    // Compute Y boundaries between card rows
    final yBoundaries = <double>[];
    if (numCardRows > 1 && allYClusters.length >= numCardRows * 3) {
      final cpr = allYClusters.length / numCardRows;
      for (int i = 1; i < numCardRows; i++) {
        final idx = (i * cpr).round();
        if (idx > 0 && idx < allYClusters.length) {
          yBoundaries
              .add((allYClusters[idx - 1] + allYClusters[idx]) / 2);
        }
      }
    }
    debug.writeln('Y boundaries: ${yBoundaries.map((b) => b.toStringAsFixed(0)).toList()}');
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
    _mergeAdjacentDigits(elements);
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
