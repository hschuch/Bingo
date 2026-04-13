import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
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

  /// Pre-process image for better OCR: grayscale, contrast boost,
  /// and binarization to create clean black text on white background.
  /// Runs in a background isolate to avoid blocking the UI.
  Future<File> _preprocessImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final resultBytes = await compute(_processImageBytes, bytes);
    final tempDir = await getTemporaryDirectory();
    final outFile = File('${tempDir.path}/bingo_preprocessed.png');
    await outFile.writeAsBytes(resultBytes);
    return outFile;
  }

  static List<int> _processImageBytes(List<int> bytes) {
    var image = img.decodeImage(Uint8List.fromList(bytes));
    if (image == null) return bytes;

    // Resize if very large (keeps OCR fast without losing detail)
    final maxDim = math.max(image.width, image.height);
    if (maxDim > 2500) {
      final scale = 2500 / maxDim;
      image = img.copyResize(image,
          width: (image.width * scale).round(),
          height: (image.height * scale).round());
    }

    // Convert to grayscale
    image = img.grayscale(image);

    // Boost contrast
    image = img.adjustColor(image, contrast: 2.0);

    // Sharpen to make number edges crisper
    image = img.convolution(image, filter: [
      0, -1, 0,
      -1, 5, -1,
      0, -1, 0,
    ], div: 1);

    // Otsu's method: find optimal global threshold automatically
    final histogram = List<int>.filled(256, 0);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        histogram[image.getPixel(x, y).r.toInt()]++;
      }
    }

    final total = image.width * image.height;
    double sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += i * histogram[i];
    }

    double sumB = 0, wB = 0, maxVar = 0;
    int thresh = 128;
    for (int i = 0; i < 256; i++) {
      wB += histogram[i];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += i * histogram[i];
      final mB = sumB / wB;
      final mF = (sum - sumB) / wF;
      final variance = wB * wF * (mB - mF) * (mB - mF);
      if (variance > maxVar) {
        maxVar = variance;
        thresh = i;
      }
    }

    // Apply threshold to create binary image
    final binary = img.Image(width: image.width, height: image.height);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y).r.toInt();
        if (pixel < thresh) {
          binary.setPixelRgb(x, y, 0, 0, 0);
        } else {
          binary.setPixelRgb(x, y, 255, 255, 255);
        }
      }
    }

    return img.encodePng(binary);
  }

  /// Process an image that may contain 1-9 bingo cards.
  Future<OcrResult> processImage(File imageFile) async {
    final preprocessed = await _preprocessImage(imageFile);
    final inputImage = InputImage.fromFile(preprocessed);
    final recognized = await _textRecognizer.processImage(inputImage);

    int totalTextElements = 0;
    final elements = <_NumberElement>[];

    // Extract numbers from individual text elements
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          totalTextElements++;
          final text = element.text.trim();
          final box = element.boundingBox;
          final number = int.tryParse(text);
          if (number != null && number >= 1 && number <= 75) {
            elements.add(_NumberElement(
              number: number,
              centerX: box.center.dx,
              centerY: box.center.dy,
              height: box.height,
              width: box.width,
            ));
          } else if (text.length >= 2 && text.length <= 6) {
            // Try regex to extract a number embedded in text
            // (handles "B17", "N33", "O72", etc.)
            final matches =
                RegExp(r'(\d{1,2})').allMatches(text).toList();
            if (matches.length == 1) {
              final n = int.tryParse(matches[0].group(1)!);
              if (n != null && n >= 1 && n <= 75) {
                elements.add(_NumberElement(
                  number: n,
                  centerX: box.center.dx,
                  centerY: box.center.dy,
                  height: box.height,
                  width: box.width,
                ));
              }
            }
          }
        }

        // Also extract numbers from the full line text that may have
        // been concatenated or missed at the element level.
        final lineBox = line.boundingBox;
        final lineText = line.text;
        final lineMatches =
            RegExp(r'\b(\d{1,2})\b').allMatches(lineText);
        for (final match in lineMatches) {
          final n = int.tryParse(match.group(1)!);
          if (n == null || n < 1 || n > 75) continue;

          // Estimate X position from character position within line
          final charMid =
              match.start + match.group(1)!.length / 2;
          final xFrac = lineText.length > 1
              ? charMid / lineText.length
              : 0.5;
          final estX = lineBox.left + lineBox.width * xFrac;

          // Skip if we already have this number near this position
          final isDupe = elements.any((e) =>
              e.number == n &&
              (e.centerY - lineBox.center.dy).abs() <
                  lineBox.height * 1.5 &&
              (e.centerX - estX).abs() < lineBox.width * 0.15);

          if (!isDupe) {
            elements.add(_NumberElement(
              number: n,
              centerX: estX,
              centerY: lineBox.center.dy,
              height: lineBox.height,
              width: lineBox.width / 5,
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

    // Adaptive clustering thresholds from element sizes.
    // X threshold is larger because card columns are separated by a full
    // card width — we need to tolerate imprecise positions from line-level
    // extraction. Y threshold is tighter to separate individual rows.
    final heights = elements.map((e) => e.height).toList()..sort();
    final medianH = heights[heights.length ~/ 2];
    final xThreshold = medianH * 2.0;
    final yThreshold = medianH * 0.8;
    debug.writeln('Median height: ${medianH.toStringAsFixed(1)}, '
        'xThresh: ${xThreshold.toStringAsFixed(1)}, '
        'yThresh: ${yThreshold.toStringAsFixed(1)}');

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
        _cluster(refXElems.map((e) => e.centerX).toList(), xThreshold);
    final numCardCols = refXClusters.length.clamp(1, 3);
    debug.writeln('X ref col=$bestCol (${refXElems.length} elems), '
        '${refXClusters.length} X-clusters → $numCardCols card col(s)');

    // For X boundaries, use B (leftmost) and O (rightmost) columns.
    // Boundary = midpoint between O of card i and B of card i+1.
    final bXClusters =
        _cluster(byCol[0]!.map((e) => e.centerX).toList(), xThreshold);
    final oXClusters =
        _cluster(byCol[4]!.map((e) => e.centerX).toList(), xThreshold);

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
        _cluster(elements.map((e) => e.centerY).toList(), yThreshold);
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
      if (regionElements.isNotEmpty) {
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
  /// assignment, spatial cross-validation, and Y position for row ordering.
  BingoCard? _buildCardFromElements(List<_NumberElement> elements) {
    if (elements.isEmpty) return null;

    // Cross-validate: cluster X positions to find spatial columns,
    // then verify each number's value matches its spatial column.
    // B(1-15) should be leftmost, I(16-30) next, etc.
    final heights = elements.map((e) => e.height).toList()..sort();
    final h = heights[heights.length ~/ 2];
    final xClusters =
        _cluster(elements.map((e) => e.centerX).toList(), h * 0.8);

    if (xClusters.length >= 4 && xClusters.length <= 6) {
      elements = elements.where((elem) {
        final col = _columnForNumber(elem.number);
        if (col == null) return false;

        // Find nearest spatial column (clusters are sorted left→right)
        int nearest = 0;
        double bestDist = (elem.centerX - xClusters[0]).abs();
        for (int i = 1; i < xClusters.length; i++) {
          final d = (elem.centerX - xClusters[i]).abs();
          if (d < bestDist) {
            bestDist = d;
            nearest = i;
          }
        }

        // Value-based column must match spatial column (±1 tolerance
        // when cluster count isn't exactly 5)
        final tolerance = xClusters.length == 5 ? 0 : 1;
        return (col - nearest).abs() <= tolerance;
      }).toList();
    }

    // Assign to columns by number value
    final columns = <int, List<_NumberElement>>{
      for (int i = 0; i < 5; i++) i: [],
    };
    for (final elem in elements) {
      final col = _columnForNumber(elem.number);
      if (col != null) columns[col]!.add(elem);
    }

    // Build 5x5 grid, sorted by Y within each column.
    // Skip duplicate numbers — each number appears at most once per card.
    final grid = List.generate(5, (_) => List<int?>.filled(5, null));
    for (int col = 0; col < 5; col++) {
      final colElements = columns[col]!;
      colElements.sort((a, b) => a.centerY.compareTo(b.centerY));
      final used = <int>{};
      int row = 0;
      for (final elem in colElements) {
        if (row >= 5) break;
        if (used.contains(elem.number)) continue;
        used.add(elem.number);
        grid[row][col] = elem.number;
        row++;
      }
    }

    grid[2][2] = null; // FREE space

    int filled = 0;
    for (final row in grid) {
      for (final cell in row) {
        if (cell != null) filled++;
      }
    }
    if (filled < 1) return null;

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
    final preprocessed = await _preprocessImage(imageFile);
    final inputImage = InputImage.fromFile(preprocessed);
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
