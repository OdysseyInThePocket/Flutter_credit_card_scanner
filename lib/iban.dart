// ISO 13616 IBAN country code → expected total length (including 2-char country + 2-char check digits).
const Map<String, int> _ibanLengths = {
  'AD': 24, 'AE': 23, 'AL': 28, 'AT': 20, 'AZ': 28,
  'BA': 20, 'BE': 16, 'BG': 22, 'BH': 22, 'BR': 29,
  'BY': 28, 'CH': 21, 'CR': 22, 'CY': 28, 'CZ': 24,
  'DE': 22, 'DJ': 27, 'DK': 18, 'DO': 28, 'EE': 20,
  'EG': 29, 'ES': 24, 'FI': 18, 'FK': 18, 'FO': 18,
  'FR': 27, 'GB': 22, 'GE': 22, 'GI': 23, 'GL': 18,
  'GR': 27, 'GT': 28, 'HR': 21, 'HU': 28, 'IE': 22,
  'IL': 23, 'IQ': 23, 'IR': 26, 'IS': 26, 'IT': 27,
  'JO': 30, 'KW': 30, 'KZ': 20, 'LB': 28, 'LC': 32,
  'LI': 21, 'LT': 20, 'LU': 20, 'LV': 21, 'LY': 25,
  'MC': 27, 'MD': 24, 'ME': 22, 'MK': 19, 'MN': 20,
  'MR': 27, 'MT': 31, 'MU': 30, 'NI': 28, 'NL': 18,
  'NO': 15, 'PK': 24, 'PL': 28, 'PS': 29, 'PT': 25,
  'QA': 29, 'RO': 24, 'RS': 22, 'RU': 33, 'SA': 24,
  'SC': 31, 'SD': 18, 'SE': 24, 'SI': 19, 'SK': 24,
  'SM': 27, 'SO': 23, 'ST': 25, 'SV': 28, 'TL': 23,
  'TN': 24, 'TR': 26, 'UA': 29, 'VA': 22, 'VG': 24,
  'XK': 20,
};

// Extracts and validates IBANs from raw OCR text.
//
// Returns a deduplicated list of normalized IBANs (uppercase, no spaces).
// When [validateChecksum] is true (default), rejects any match that fails
// the ISO 13616 mod-97 checksum.
List<String> extractIbans(String text, {bool validateChecksum = true}) {
  final upper = text.toUpperCase();
  final results = <String>{};

  // Two alternatives to avoid cross-word greedy consumption:
  //   1. Compact  — continuous alphanumeric BBAN, with an optional single space
  //                 after the check digits (handles "BE97 652822032949" where the
  //                 BBAN is one unbroken run, not split into print groups)
  //   2. Grouped  — BBAN split into 1-4 char groups separated by single spaces
  //                 (standard print format: "BE68 5390 0754 7034")
  final pattern = RegExp(
    r'[A-Z]{2}[0-9]{2} ?[A-Z0-9]{11,30}'
    r'|'
    // Optional space between check-digits and first BBAN group handles standard
    // print format "BE68 5390 0754 7034" as well as no-separator variants.
    r'[A-Z]{2}[0-9]{2} ?(?:[A-Z0-9]{1,4} ){1,8}[A-Z0-9]{1,4}',
  );

  for (final match in pattern.allMatches(upper)) {
    var candidate = match.group(0)!;

    // Strip spaces to normalize (OCR often introduces gaps inside IBANs).
    var normalized = candidate.replaceAll(' ', '');
    final country = normalized.substring(0, 2);

    final expectedLength = _ibanLengths[country];
    if (expectedLength == null) continue;

    // Repair OCR confusables inside the IBAN body before length/checksum checks.
    normalized = _repairOcrConfusables(normalized, country);

    if (normalized.length != expectedLength) continue;

    if (validateChecksum && !_validateMod97(normalized)) continue;

    results.add(normalized);
  }

  return results.toList();
}

// Applies OCR confusable substitutions inside the purely-numeric portions of the IBAN.
// Country code (chars 0-1) is kept as-is; check digits (chars 2-3) and the BBAN
// vary by country but we conservatively repair only digit-expected positions.
String _repairOcrConfusables(String iban, String country) {
  // Replace common OCR letter-for-digit confusables in the check-digit + BBAN region.
  // We only touch positions 2 onwards to preserve the known-alpha country code.
  final body = iban.substring(2);
  // Only O↔0 and I↔1 — both reliably map to digits in all-digit BBAN positions.
  // L and B are kept as-is: they appear in bank codes (e.g. NL's ABNA, GB's NWBK)
  // and replacing them would corrupt valid IBANs.
  final repaired = body.replaceAll('O', '0').replaceAll('I', '1');
  return '${iban.substring(0, 2)}$repaired';
}

// Validates the IBAN checksum using the ISO 13616 mod-97 algorithm.
bool _validateMod97(String iban) {
  // Move the first four characters to the end.
  final rearranged = iban.substring(4) + iban.substring(0, 4);

  // Convert letters to digits: A=10, B=11, … Z=35.
  final numeric = StringBuffer();
  for (final char in rearranged.split('')) {
    final code = char.codeUnitAt(0);
    if (code >= 65 && code <= 90) {
      // 'A'.codeUnitAt(0) == 65
      numeric.write(code - 55);
    } else {
      numeric.write(char);
    }
  }

  // Compute mod 97 in chunks to avoid BigInt overflow in Dart's int.
  var remainder = 0;
  for (final char in numeric.toString().split('')) {
    remainder = (remainder * 10 + int.parse(char)) % 97;
  }

  return remainder == 1;
}
