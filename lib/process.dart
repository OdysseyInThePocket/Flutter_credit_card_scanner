import 'package:credit_card_validator/credit_card_validator.dart';
import 'package:credit_card_validator/validation_results.dart';

import 'credit_card.dart';
import 'iban.dart';

String removeNonDigits(String text) {
  final buffer = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    final char = text[i];
    if (char.contains(RegExp(r'[0-9]'))) {
      buffer.write(char);
    }
  }
  return buffer.toString();
}

/// A class that processes strings to extract credit card information.
class ProccessCreditCard {
  /// The extracted credit card number.
  String cardNumber = '';

  /// The extracted cardholder name.
  String cardName = '';

  /// The extracted card expiration month.
  String cardExpirationMonth = '';

  /// The extracted card expiration year.
  String cardExpirationYear = '';

  /// Whether to check for a credit card number.
  bool checkCreditCardNumber;

  /// Whether to check for a cardholder name.
  bool checkCreditCardName;

  /// Whether to check for a credit card expiry date.
  bool checkCreditCardExpiryDate;

  /// The extracted credit card information.
  CreditCardModel? creditCardModel;

  /// A list of 4-digit number strings, used to assemble the card number.
  final numberTextList = <String>[];

  /// use Luhn algorithm to check if the number is valid
  final bool useLuhnValidation;

  /// The extracted credit card information.
  final _ccValidator = CreditCardValidator();

  /// The validation results for the card number.
  CCNumValidationResults? _v;

  /// Creates a new instance of [ProccessCreditCard].
  ///
  /// The [checkCreditCardNumber], [checkCreditCardName], and [checkCreditCardExpiryDate] parameters
  /// determine whether the processor should attempt to extract those pieces of information.
  ProccessCreditCard({
    this.cardNumber = "",
    this.cardName = "",
    this.cardExpirationMonth = "",
    this.cardExpirationYear = "",
    this.useLuhnValidation = true,
    required this.checkCreditCardNumber,
    required this.checkCreditCardName,
    required this.checkCreditCardExpiryDate,
  });

  /// Returns the full expiry date in MM/YYYY format.
  String get fullExpiryDate => '$cardExpirationMonth/$cardExpirationYear';

  /// Returns a [CreditCardModel] if all required information has been extracted.
  ///
  /// Whether a piece of information is required is determined by the
  /// [checkCreditCardNumber], [checkCreditCardName], and [checkCreditCardExpiryDate] parameters.
  CreditCardModel? getCreditCardModel() {
    final t = CreditCardModel(
      number: checkCreditCardNumber ? cardNumber : "",
      holderName: checkCreditCardName ? cardName : "",
      expirationMonth: checkCreditCardExpiryDate ? cardExpirationMonth : "",
      expirationYear: checkCreditCardExpiryDate ? cardExpirationYear : "",
    );

    if (t.number.isEmpty && checkCreditCardNumber) {
      return null;
    }

    if (t.expiryDate.isEmpty && checkCreditCardExpiryDate) {
      return null;
    }

    if (t.holderName.isEmpty && checkCreditCardName) {
      return null;
    }

    t.creditCardNumberValidationResults = _v;

    creditCardModel = t;

    return creditCardModel;
  }

  /// Attempts to extract the expiry date from the given text.
  ///
  /// Returns the extracted expiry date in MM/YY format, or null if no date is found.
  /// Uses simple XX/XX pattern matching to handle cases where extra digits
  /// appear after the expiry date (e.g., "08/30 040").
  String? processDate(String text) {
    if (!checkCreditCardExpiryDate) return null;

    // Fix common OCR errors: O misread as 0, I/l misread as 1
    text = text.replaceAll('O', '0').replaceAll('I', '1').replaceAll('l', '1');

    // Match XX/XX pattern where X is a digit
    final match = RegExp(r'(\d{2})/(\d{2})').firstMatch(text);
    if (match != null) {
      final month = match.group(1)!;
      final year = match.group(2)!;

      // Validate month is 01-12
      final monthInt = int.tryParse(month);
      if (monthInt != null && monthInt >= 1 && monthInt <= 12) {
        cardExpirationMonth = month;
        cardExpirationYear = year;
        return fullExpiryDate;
      }
    }

    return fullExpiryDate.length > 4 ? fullExpiryDate : null;
  }

  /// Attempts to extract the cardholder name from the given text.
  ///
  /// Returns the extracted cardholder name, or null if no name is found.
  String? processName(String text) {
    if (!checkCreditCardName) {
      return null;
    }

    if (text.contains(RegExp(r'[a-zA-Z\.]'))) {
      final hasSpace = text.contains(' ');
      final hasNumber = text.contains(RegExp(r'[0-9]'));
      if (hasSpace) {
        final lines = text.split('\n');
        final validLines =
            lines.where((line) => line.trim().isNotEmpty && line.contains(' '));

        if (validLines.isNotEmpty) {
          if (hasNumber) {
            cardName = validLines.firstWhere(
              (line) => !line.contains(RegExp(r'[0-9]')),
              orElse: () => '',
            );
          } else {
            cardName = validLines.first;
          }
        }
      }
    }
    return cardName.isEmpty ? null : cardName;
  }

  /// Attempts to extract the credit card number from the given text.
  ///
  /// Returns the extracted credit card number, or null if no number is found.
  /// Supports both single-line full card numbers and multi-line card numbers
  /// where each line contains digit groups (typically 4 digits, but can be 1-4
  /// for cards with non-standard lengths like 17-digit Maestro cards).
  String? processNumber(String text) {
    if (!checkCreditCardNumber) {
      return null;
    }

    // Fix common OCR error: L misread as 1
    text = text.replaceAll("L", "1");

    // Strip trailing OCR artifacts that start with a letter (e.g., "5127 8810 3138 2740 N1" → "5127 8810 3138 2740")
    // The regex matches: space(s) + letter + any alphanumeric chars at end of string
    final cleanedText = text.replaceAll(RegExp(r'\s+[a-zA-Z][a-zA-Z0-9]*$'), '').trim();

    // Try direct validation first (single line with full number)
    final v = _ccValidator.validateCCNum(cleanedText, ignoreLuhnValidation: !useLuhnValidation);

    if (v.isValid) {
      cardNumber = cleanedText;
      _v = v;
      numberTextList.clear();
      return cardNumber;
    }

    // Check for digit groups (multi-line card number support)
    // Support groups of 1-4 digits for cards with varying lengths (e.g., 17-digit cards)
    final digitsOnly = removeNonDigits(text);

    // Skip if text contains letters (likely OCR artifact like "N1", not a card number group)
    if (text.contains(RegExp(r'[a-zA-Z]'))) {
      return null;
    }

    if (digitsOnly.isNotEmpty && digitsOnly.length <= 4) {
      numberTextList.add(digitsOnly);

      // Try to form a card number with current groups (supports 4-5 groups for 16-19 digit cards)
      if (numberTextList.length >= 4 && numberTextList.length <= 5) {
        final combined = numberTextList.join();
        final validation = _ccValidator.validateCCNum(combined, ignoreLuhnValidation: !useLuhnValidation);

        if (validation.isValid) {
          cardNumber = combined;
          _v = validation;
          numberTextList.clear();
          return cardNumber;
        } else if (numberTextList.length == 5) {
          // If 5 groups didn't work, remove oldest and keep trying on the next
          // frame. Static scans use extractCardFromLines, which reasons over all
          // lines at once, so this path is camera-only.
          numberTextList.removeAt(0);
        }
      }
    } else if (digitsOnly.length > 4) {
      // Reset accumulator if we see a line with more than 4 digits
      numberTextList.clear();
    }

    return null;
  }

  /// Processes the given text to extract credit card information.
  ///
  /// Returns a [CreditCardModel] containing the extracted information, or null if
  /// not all required information is found.
  CreditCardModel? processString(String text) {
    // Check for expiration date
    processDate(text);

    // Check for card number
    processNumber(text);

    // Check for cardholder's name
    processName(text);

    return getCreditCardModel();
  }
}

/// Extracts a credit card from a complete set of OCR lines in a single pass.
///
/// This is the extraction path for static image scans, where the entire OCR
/// result is available up front. Unlike [ProccessCreditCard.processNumber] —
/// which is built for the live camera stream, accumulates digit groups
/// statefully, and relies on later frames to re-trigger validation — this
/// reasons over all [lines] at once, so it deterministically handles
/// label-prefixed PAN lines ("CARD 1234 ..."), IBAN-before-card ordering, and
/// PANs split across multiple lines.
///
/// Returns a [CreditCardModel] honouring the detect flags, or null when a
/// requested field could not be found. The live [CameraScannerWidget] is not
/// affected — it keeps using [ProccessCreditCard.processNumber].
CreditCardModel? extractCardFromLines(
  List<String> lines, {
  bool detectCardNumber = true,
  bool detectCardHolder = true,
  bool detectCardExpiryDate = true,
  bool useLuhnValidation = true,
}) {
  final proc = ProccessCreditCard(
    useLuhnValidation: useLuhnValidation,
    checkCreditCardNumber: detectCardNumber,
    checkCreditCardName: detectCardHolder,
    checkCreditCardExpiryDate: detectCardExpiryDate,
  );

  if (detectCardNumber) {
    final candidate =
        _findCardNumber(lines, useLuhnValidation: useLuhnValidation);
    if (candidate != null) {
      proc.cardNumber = candidate.number;
      proc._v = candidate.results;
    }
  }

  // Cardholder name and expiry reuse the existing per-line logic; both methods
  // no-op when their detect flag is disabled.
  for (final line in lines) {
    proc.processName(line);
    proc.processDate(line);
  }

  return proc.getCreditCardModel();
}

/// A validated card-number candidate found while scanning OCR lines.
class _CardCandidate {
  const _CardCandidate(
    this.number,
    this.results,
    this.lineIndex,
    this.singleLine,
  );

  /// Digits-only card number (no spaces).
  final String number;

  /// Validation results, carried onto the [CreditCardModel].
  final CCNumValidationResults results;

  /// Index of the (first) source line — used as a tie-breaker.
  final int lineIndex;

  /// Whether the number came from one line (true) or assembled groups (false).
  final bool singleLine;

  int get length => number.length;
}

/// Scans [lines] for the best valid card number, considering the full set at
/// once rather than line-by-line accumulation.
_CardCandidate? _findCardNumber(
  List<String> lines, {
  required bool useLuhnValidation,
}) {
  final validator = CreditCardValidator();

  // Per-line digit strings. Lines that are themselves an IBAN are blanked so
  // their all-digit groups can never feed a PAN candidate — this is the exact
  // contamination behind the multi-line accumulation bug. A lenient (no
  // checksum) IBAN match is used so even a checksum-broken OCR'd IBAN is
  // excluded; card-number lines never match the IBAN grammar.
  final perLineDigits = <String>[];
  for (final line in lines) {
    if (extractIbans(line, validateChecksum: false).isNotEmpty) {
      perLineDigits.add('');
    } else {
      perLineDigits.add(_digitsForCardScan(line));
    }
  }

  final candidates = <_CardCandidate>[];

  // 1) A single line carrying a full PAN (handles label prefixes like "CARD").
  for (var i = 0; i < perLineDigits.length; i++) {
    final digits = perLineDigits[i];
    if (digits.length >= 13 && digits.length <= 19) {
      final res =
          validator.validateCCNum(digits, ignoreLuhnValidation: !useLuhnValidation);
      if (res.isValid) candidates.add(_CardCandidate(digits, res, i, true));
    }
  }

  // 2) A PAN split across consecutive group-like lines (1-4 digits each).
  for (var i = 0; i < perLineDigits.length; i++) {
    if (perLineDigits[i].isEmpty || perLineDigits[i].length > 4) continue;
    final buffer = StringBuffer();
    for (var j = i; j < perLineDigits.length; j++) {
      final digits = perLineDigits[j];
      if (digits.isEmpty || digits.length > 4) break;
      buffer.write(digits);
      final combined = buffer.toString();
      if (combined.length > 19) break;
      if (combined.length >= 13) {
        final res = validator.validateCCNum(combined,
            ignoreLuhnValidation: !useLuhnValidation);
        if (res.isValid) candidates.add(_CardCandidate(combined, res, i, false));
      }
    }
  }

  if (candidates.isEmpty) return null;

  // Prefer the longest valid number (most complete), then a single-line match
  // over an assembled one, then the earliest in reading order.
  candidates.sort((a, b) {
    if (a.length != b.length) return b.length.compareTo(a.length);
    if (a.singleLine != b.singleLine) return a.singleLine ? -1 : 1;
    return a.lineIndex.compareTo(b.lineIndex);
  });

  return candidates.first;
}

/// Pulls the digits from a line for card-number matching.
///
/// Repairs the OCR confusables this codebase already handles (O→0, I/l/L→1)
/// per whitespace-separated token, then keeps a token only if nothing but
/// digits remains. This means:
///   - a standalone confusable like "O" survives as the digit it represents
///     (e.g. "… 4702 O" → "…47020"), and
///   - a label ("CARD") or a letter-glued artifact ("N3", "N1") is dropped
///     whole, so it can never inject a stray digit into the PAN.
String _digitsForCardScan(String line) {
  final buffer = StringBuffer();
  for (final token in line.split(RegExp(r'\s+'))) {
    final repaired = token
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('l', '1')
        .replaceAll('L', '1');
    // A residual non-confusable letter marks a label or artifact, not PAN digits.
    if (repaired.contains(RegExp(r'[a-zA-Z]'))) continue;
    buffer.write(removeNonDigits(repaired));
  }
  return buffer.toString();
}
