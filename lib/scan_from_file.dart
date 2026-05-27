import 'dart:developer';
import 'dart:io';

import 'package:apple_vision_recognize_text/apple_vision_recognize_text.dart'
    as apple;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'credit_card.dart';
import 'iban.dart';
import 'process.dart';

const _androidChannel = MethodChannel('flutter_credit_card_scanner');

/// The result of a [scanFromFile] call.
class ScanResult {
  const ScanResult({
    required this.card,
    required this.ibans,
    required this.rawText,
  });

  /// Extracted credit card data, or null if no valid card was detected.
  final CreditCardModel? card;

  /// Extracted IBANs, normalized to uppercase with no spaces, deduplicated.
  final List<String> ibans;

  /// Full OCR text produced by the recognition engine — useful for debugging.
  final String rawText;
}

/// Scans a static image file for credit card data and IBANs on-device.
///
/// Accepts any image file format supported by the platform OCR engine
/// (JPEG, PNG, etc.). No data leaves the device.
///
/// Returns a [ScanResult] with the detected entities; fields are empty / null
/// when the corresponding detector is disabled or nothing was found.
Future<ScanResult> scanFromFile(
  String filePath, {
  bool detectCardNumber = true,
  bool detectCardHolder = true,
  bool detectCardExpiryDate = true,
  bool detectIbans = true,
  bool useLuhnValidation = true,
  bool validateIbanChecksum = true,
  bool debug = kDebugMode,
}) async {
  final lines = <String>[];
  var rawText = '';

  if (Platform.isAndroid) {
    // The native plugin uses InputImage.fromFilePath which reads EXIF orientation
    // automatically, then runs the same ML Kit TextRecognizer as the camera path.
    final result = await _androidChannel.invokeMethod<List<dynamic>>(
      'recognizeTextFromFile',
      {'path': filePath},
    );
    if (result != null) {
      lines.addAll(result.cast<String>());
      rawText = lines.join('\n');
    }
  } else if (Platform.isIOS) {
    final fileBytes = await File(filePath).readAsBytes();
    final controller = apple.AppleVisionRecognizeTextController();
    final result = await controller.processImage(
      apple.RecognizeTextData(
        image: fileBytes,
        // The native plugin routes to VNImageRequestHandler(data:) when
        // data.count != width * height * 4. Passing Size(1,1) ensures the
        // encoded-image path is always taken for file inputs.
        imageSize: const Size(1, 1),
        recognitionLevel: apple.RecognitionLevel.accurate,
        automaticallyDetectsLanguage: false,
        languages: const [Locale('en', 'US')],
        dispatch: apple.Dispatch.background,
      ),
    );
    for (final r in result ?? const <apple.RecognizedText>[]) {
      lines.addAll(r.listText);
    }
    rawText = lines.join('\n');
  }

  if (debug) {
    log('[scanFromFile] OCR lines (${lines.length} total):');
    for (final line in lines) {
      log('[scanFromFile] OCR line: "$line"');
    }
  }

  // Static scans have the full OCR line set up front, so reason over all lines
  // at once instead of the live camera's stateful per-line accumulator.
  final card = extractCardFromLines(
    lines,
    detectCardNumber: detectCardNumber,
    detectCardHolder: detectCardHolder,
    detectCardExpiryDate: detectCardExpiryDate,
    useLuhnValidation: useLuhnValidation,
  );
  final ibans = detectIbans
      ? extractIbans(rawText, validateChecksum: validateIbanChecksum)
      : const <String>[];
  if (debug) log('[scanFromFile] result — card: $card, ibans: $ibans');

  return ScanResult(
    card: card,
    ibans: ibans,
    rawText: rawText,
  );
}
