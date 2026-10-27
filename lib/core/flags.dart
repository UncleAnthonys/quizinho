/// Country flags for nationality codes (FIFA/ISO-3 style, as in the data).
/// Flags are emoji, so they need no image assets. Countries that no longer
/// exist (USSR, Yugoslavia…) and Northern Ireland have no emoji flag — they
/// fall back to the code.
library;

const _iso2 = <String, String>{
  'ABW': 'AW', 'AFG': 'AF', 'ALB': 'AL', 'ALG': 'DZ', 'AND': 'AD', 'ANG': 'AO', 'ARG': 'AR', 'ARM': 'AM',
  'ATG': 'AG', 'AUS': 'AU', 'AUT': 'AT', 'AZE': 'AZ', 'BDI': 'BI', 'BEL': 'BE', 'BEN': 'BJ', 'BFA': 'BF',
  'BGD': 'BD', 'BHR': 'BH', 'BIH': 'BA', 'BLR': 'BY', 'BLZ': 'BZ', 'BMU': 'BM', 'BOL': 'BO', 'BRA': 'BR',
  'BRB': 'BB', 'BTN': 'BT', 'BUL': 'BG', 'BWA': 'BW', 'CAF': 'CF', 'CAN': 'CA', 'CHI': 'CL', 'CHN': 'CN',
  'CIV': 'CI', 'CMR': 'CM', 'COD': 'CD', 'COG': 'CG', 'COL': 'CO', 'COM': 'KM', 'CPV': 'CV', 'CRC': 'CR',
  'CRO': 'HR', 'CUB': 'CU', 'CUW': 'CW', 'CYP': 'CY', 'CZE': 'CZ', 'DEN': 'DK', 'DJI': 'DJ', 'DOM': 'DO',
  'ECU': 'EC', 'EGY': 'EG', 'ESP': 'ES', 'EST': 'EE', 'ETH': 'ET', 'FIN': 'FI', 'FRA': 'FR', 'FRO': 'FO',
  'GAB': 'GA', 'GAM': 'GM', 'GBR': 'GB', 'GEO': 'GE', 'GER': 'DE', 'GHA': 'GH', 'GIB': 'GI', 'GIN': 'GN',
  'GLP': 'GP', 'GNB': 'GW', 'GNQ': 'GQ', 'GRE': 'GR', 'GUA': 'GT', 'GUF': 'GF', 'GUM': 'GU', 'GUY': 'GY',
  'HAI': 'HT', 'HKG': 'HK', 'HON': 'HN', 'HUN': 'HU', 'IDN': 'ID', 'IND': 'IN', 'IRL': 'IE', 'IRN': 'IR',
  'IRQ': 'IQ', 'ISL': 'IS', 'ISR': 'IL', 'ITA': 'IT', 'JAM': 'JM', 'JEY': 'JE', 'JOR': 'JO', 'JPN': 'JP',
  'KAZ': 'KZ', 'KEN': 'KE', 'KGZ': 'KG', 'KOR': 'KR', 'KSA': 'SA', 'KWT': 'KW', 'LAO': 'LA', 'LBN': 'LB',
  'LBR': 'LR', 'LBY': 'LY', 'LIE': 'LI', 'LTU': 'LT', 'LUX': 'LU', 'LVA': 'LV', 'MAD': 'MG', 'MAR': 'MA',
  'MAS': 'MY', 'MDA': 'MD', 'MEX': 'MX', 'MKD': 'MK', 'MLI': 'ML', 'MLT': 'MT', 'MNE': 'ME', 'MOZ': 'MZ',
  'MRT': 'MR', 'MSR': 'MS', 'MTQ': 'MQ', 'MUS': 'MU', 'NAM': 'NA', 'NCL': 'NC', 'NED': 'NL', 'NER': 'NE',
  'NGA': 'NG', 'NOR': 'NO', 'NZL': 'NZ', 'OMN': 'OM', 'PAK': 'PK', 'PAN': 'PA', 'PAR': 'PY', 'PER': 'PE',
  'PHI': 'PH', 'POL': 'PL', 'POR': 'PT', 'PRI': 'PR', 'PRK': 'KP', 'PSE': 'PS', 'QAT': 'QA', 'ROU': 'RO',
  'RSA': 'ZA', 'RUS': 'RU', 'RWA': 'RW', 'SDN': 'SD', 'SEN': 'SN', 'SKN': 'KN', 'SLE': 'SL', 'SLV': 'SV',
  'SMR': 'SM', 'SRB': 'RS', 'SSD': 'SS', 'SUI': 'CH', 'SUR': 'SR', 'SVK': 'SK', 'SVN': 'SI', 'SWE': 'SE',
  'SYR': 'SY', 'TCA': 'TC', 'TCD': 'TD', 'THA': 'TH', 'TJK': 'TJ', 'TKM': 'TM', 'TOG': 'TG', 'TRI': 'TT',
  'TUN': 'TN', 'TUR': 'TR', 'TUV': 'TV', 'TZA': 'TZ', 'UAE': 'AE', 'UGA': 'UG', 'UKR': 'UA', 'URU': 'UY',
  'USA': 'US', 'UZB': 'UZ', 'VEN': 'VE', 'VNM': 'VN', 'XKS': 'XK', 'ZAM': 'ZM', 'ZIM': 'ZW',
};

/// England, Scotland and Wales use the subdivision-flag emoji.
const _homeNations = <String, String>{
  'ENG': '\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}',
  'SCO': '\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}',
  'WAL': '\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}',
};

/// The flag emoji for a nationality code, or null if there isn't one.
String? flagFor(String? code) {
  if (code == null) return null;
  final home = _homeNations[code];
  if (home != null) return home;
  final iso = _iso2[code];
  if (iso == null) return null;
  return String.fromCharCodes([for (final c in iso.codeUnits) 0x1F1E6 + c - 0x41]);
}

/// Flag if there is one, else the code ("SUN" for the USSR).
String? nationalityLabel(String? code) => flagFor(code) ?? code;
