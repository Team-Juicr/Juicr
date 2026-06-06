import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'ad_policy.dart';
import 'app_state.dart';
import 'catalog_empty_state.dart';
import 'catalog_item.dart';
import 'details_page.dart';
import 'diagnostic_log.dart';
import 'motion.dart';
import 'stream_api.dart';
import 'visual_style.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

enum _CatalogScopeKind { all, company, collection }

class _CatalogOriginOption {
  const _CatalogOriginOption({required this.label, required this.code});

  const _CatalogOriginOption.all() : this(label: 'All countries', code: '');

  final String label;
  final String code;

  bool get isAll => code.isEmpty;
  String get shortLabel => isAll ? 'All' : code;

  @override
  bool operator ==(Object other) {
    return other is _CatalogOriginOption &&
        other.label == label &&
        other.code == code;
  }

  @override
  int get hashCode => Object.hash(label, code);
}

class _CatalogScopeOption {
  const _CatalogScopeOption._({
    required this.kind,
    required this.label,
    this.query,
  });

  const _CatalogScopeOption.all()
    : this._(kind: _CatalogScopeKind.all, label: 'All');

  const _CatalogScopeOption.company(String company)
    : this._(kind: _CatalogScopeKind.company, label: company, query: company);

  const _CatalogScopeOption.collection(String collection)
    : this._(
        kind: _CatalogScopeKind.collection,
        label: collection,
        query: collection,
      );

  final _CatalogScopeKind kind;
  final String label;
  final String? query;

  String? get company => kind == _CatalogScopeKind.company ? query : null;
  String? get collection => kind == _CatalogScopeKind.collection ? query : null;
  bool get isAll => kind == _CatalogScopeKind.all;
  String get displayLabel => switch (kind) {
    _CatalogScopeKind.all => label,
    _CatalogScopeKind.company => 'Studio: $label',
    _CatalogScopeKind.collection => 'Collection: $label',
  };
  String get shortLabel => switch (kind) {
    _CatalogScopeKind.all => label,
    _CatalogScopeKind.company => label,
    _CatalogScopeKind.collection => label.replaceAll(' Collection', ''),
  };
  bool get hasMatureContentSignal {
    final text = '$label ${query ?? ''}'.toLowerCase();
    return RegExp(
      r'\b(adult|nsfw|xxx|porn|pornography|erotic|explicit|softcore|sexploitation|sexuality|nudity|striptease|hentai|vivamax|viva\s*max)\b',
    ).hasMatch(text);
  }

  @override
  bool operator ==(Object other) {
    return other is _CatalogScopeOption &&
        other.kind == kind &&
        other.label == label &&
        other.query == query;
  }

  @override
  int get hashCode => Object.hash(kind, label, query);
}

class _CatalogPageState extends State<CatalogPage>
    with AutomaticKeepAliveClientMixin<CatalogPage> {
  static const String _discoveryWarmSnapshotKey = 'discovery_warm_snapshot_v1';
  static const String _allYearsLabel = 'All';
  static const List<String> _betaLiveTvCountryOptions = [
    'All countries',
    'Argentina',
    'Australia',
    'Brazil',
    'Canada',
    'China',
    'France',
    'Germany',
    'India',
    'Indonesia',
    'Italy',
    'Japan',
    'Mexico',
    'Philippines',
    'South Korea',
    'Spain',
    'Thailand',
    'United Kingdom',
    'United States',
  ];
  static const List<String> _gammaLiveTvGenreOptions = [
    'All genres',
    'Documentary',
    'Entertainment',
    'Kids',
    'Lifestyle',
    'Local',
    'Movies',
    'Music',
    'News',
    'Sports',
  ];
  static const List<String> _alphaLiveTvGenreOptions = [
    'All genres',
    'Auto',
    'Business',
    'Comedy',
    'Culture',
    'Documentary',
    'Education',
    'Entertainment',
    'Family',
    'General',
    'Kids',
    'Lifestyle',
    'Local',
    'Movies',
    'Music',
    'News',
    'Religious',
    'Shop',
    'Sports',
    'Weather',
  ];
  static const List<_CatalogScopeOption> _scopeOptions = [
    _CatalogScopeOption.all(),
    _CatalogScopeOption.collection('Captain Marvel Collection'),
    _CatalogScopeOption.collection('Harry Potter Collection'),
    _CatalogScopeOption.collection('Marvel Rising Collection'),
    _CatalogScopeOption.collection('Spider-Man (MCU) Collection'),
    _CatalogScopeOption.collection('Star Wars Collection'),
    _CatalogScopeOption.collection('The Avengers Collection'),
    _CatalogScopeOption.collection('The Fast and the Furious Collection'),
    _CatalogScopeOption.collection('The Lord of the Rings Collection'),
    _CatalogScopeOption.company('20th Century Studios'),
    _CatalogScopeOption.company('A24'),
    _CatalogScopeOption.company('DC Studios'),
    _CatalogScopeOption.company('Lionsgate'),
    _CatalogScopeOption.company('Lucasfilm'),
    _CatalogScopeOption.company('MAPPA'),
    _CatalogScopeOption.company('Marvel Studios'),
    _CatalogScopeOption.company('Netflix'),
    _CatalogScopeOption.company('Paramount Pictures'),
    _CatalogScopeOption.company('Pixar'),
    _CatalogScopeOption.company('Sony Pictures'),
    _CatalogScopeOption.company('Studio Ghibli'),
    _CatalogScopeOption.company('Toei Animation'),
    _CatalogScopeOption.company('Universal Pictures'),
    _CatalogScopeOption.company('Viva Films'),
    _CatalogScopeOption.company('Vivamax'),
    _CatalogScopeOption.company('Walt Disney Pictures'),
    _CatalogScopeOption.company('Warner Bros. Pictures'),
  ];
  static const List<_CatalogOriginOption> _originOptions = [
    _CatalogOriginOption.all(),
    _CatalogOriginOption(label: 'Afghanistan', code: 'AF'),
    _CatalogOriginOption(label: 'Aland Islands', code: 'AX'),
    _CatalogOriginOption(label: 'Albania', code: 'AL'),
    _CatalogOriginOption(label: 'Algeria', code: 'DZ'),
    _CatalogOriginOption(label: 'American Samoa', code: 'AS'),
    _CatalogOriginOption(label: 'Andorra', code: 'AD'),
    _CatalogOriginOption(label: 'Angola', code: 'AO'),
    _CatalogOriginOption(label: 'Anguilla', code: 'AI'),
    _CatalogOriginOption(label: 'Antarctica', code: 'AQ'),
    _CatalogOriginOption(label: 'Antigua and Barbuda', code: 'AG'),
    _CatalogOriginOption(label: 'Argentina', code: 'AR'),
    _CatalogOriginOption(label: 'Armenia', code: 'AM'),
    _CatalogOriginOption(label: 'Aruba', code: 'AW'),
    _CatalogOriginOption(label: 'Australia', code: 'AU'),
    _CatalogOriginOption(label: 'Austria', code: 'AT'),
    _CatalogOriginOption(label: 'Azerbaijan', code: 'AZ'),
    _CatalogOriginOption(label: 'Bahamas', code: 'BS'),
    _CatalogOriginOption(label: 'Bahrain', code: 'BH'),
    _CatalogOriginOption(label: 'Bangladesh', code: 'BD'),
    _CatalogOriginOption(label: 'Barbados', code: 'BB'),
    _CatalogOriginOption(label: 'Belarus', code: 'BY'),
    _CatalogOriginOption(label: 'Belgium', code: 'BE'),
    _CatalogOriginOption(label: 'Belize', code: 'BZ'),
    _CatalogOriginOption(label: 'Benin', code: 'BJ'),
    _CatalogOriginOption(label: 'Bermuda', code: 'BM'),
    _CatalogOriginOption(label: 'Bhutan', code: 'BT'),
    _CatalogOriginOption(label: 'Bolivia', code: 'BO'),
    _CatalogOriginOption(label: 'Bonaire', code: 'BQ'),
    _CatalogOriginOption(label: 'Bosnia and Herzegovina', code: 'BA'),
    _CatalogOriginOption(label: 'Botswana', code: 'BW'),
    _CatalogOriginOption(label: 'Bouvet Island', code: 'BV'),
    _CatalogOriginOption(label: 'Brazil', code: 'BR'),
    _CatalogOriginOption(label: 'British Indian Ocean Territory', code: 'IO'),
    _CatalogOriginOption(label: 'Brunei', code: 'BN'),
    _CatalogOriginOption(label: 'Bulgaria', code: 'BG'),
    _CatalogOriginOption(label: 'Burkina Faso', code: 'BF'),
    _CatalogOriginOption(label: 'Burundi', code: 'BI'),
    _CatalogOriginOption(label: 'Cambodia', code: 'KH'),
    _CatalogOriginOption(label: 'Cameroon', code: 'CM'),
    _CatalogOriginOption(label: 'Canada', code: 'CA'),
    _CatalogOriginOption(label: 'Cape Verde', code: 'CV'),
    _CatalogOriginOption(label: 'Cayman Islands', code: 'KY'),
    _CatalogOriginOption(label: 'Central African Republic', code: 'CF'),
    _CatalogOriginOption(label: 'Chad', code: 'TD'),
    _CatalogOriginOption(label: 'Chile', code: 'CL'),
    _CatalogOriginOption(label: 'China', code: 'CN'),
    _CatalogOriginOption(label: 'Christmas Island', code: 'CX'),
    _CatalogOriginOption(label: 'Cocos Islands', code: 'CC'),
    _CatalogOriginOption(label: 'Colombia', code: 'CO'),
    _CatalogOriginOption(label: 'Comoros', code: 'KM'),
    _CatalogOriginOption(label: 'Congo', code: 'CG'),
    _CatalogOriginOption(label: 'Cook Islands', code: 'CK'),
    _CatalogOriginOption(label: 'Costa Rica', code: 'CR'),
    _CatalogOriginOption(label: "Cote d'Ivoire", code: 'CI'),
    _CatalogOriginOption(label: 'Croatia', code: 'HR'),
    _CatalogOriginOption(label: 'Cuba', code: 'CU'),
    _CatalogOriginOption(label: 'Curacao', code: 'CW'),
    _CatalogOriginOption(label: 'Cyprus', code: 'CY'),
    _CatalogOriginOption(label: 'Czechia', code: 'CZ'),
    _CatalogOriginOption(label: 'Democratic Republic of the Congo', code: 'CD'),
    _CatalogOriginOption(label: 'Denmark', code: 'DK'),
    _CatalogOriginOption(label: 'Djibouti', code: 'DJ'),
    _CatalogOriginOption(label: 'Dominica', code: 'DM'),
    _CatalogOriginOption(label: 'Dominican Republic', code: 'DO'),
    _CatalogOriginOption(label: 'Ecuador', code: 'EC'),
    _CatalogOriginOption(label: 'Egypt', code: 'EG'),
    _CatalogOriginOption(label: 'El Salvador', code: 'SV'),
    _CatalogOriginOption(label: 'Equatorial Guinea', code: 'GQ'),
    _CatalogOriginOption(label: 'Eritrea', code: 'ER'),
    _CatalogOriginOption(label: 'Estonia', code: 'EE'),
    _CatalogOriginOption(label: 'Eswatini', code: 'SZ'),
    _CatalogOriginOption(label: 'Ethiopia', code: 'ET'),
    _CatalogOriginOption(label: 'Falkland Islands', code: 'FK'),
    _CatalogOriginOption(label: 'Faroe Islands', code: 'FO'),
    _CatalogOriginOption(label: 'Fiji', code: 'FJ'),
    _CatalogOriginOption(label: 'Finland', code: 'FI'),
    _CatalogOriginOption(label: 'France', code: 'FR'),
    _CatalogOriginOption(label: 'French Guiana', code: 'GF'),
    _CatalogOriginOption(label: 'French Polynesia', code: 'PF'),
    _CatalogOriginOption(label: 'French Southern Territories', code: 'TF'),
    _CatalogOriginOption(label: 'Gabon', code: 'GA'),
    _CatalogOriginOption(label: 'Gambia', code: 'GM'),
    _CatalogOriginOption(label: 'Georgia', code: 'GE'),
    _CatalogOriginOption(label: 'Germany', code: 'DE'),
    _CatalogOriginOption(label: 'Ghana', code: 'GH'),
    _CatalogOriginOption(label: 'Gibraltar', code: 'GI'),
    _CatalogOriginOption(label: 'Greece', code: 'GR'),
    _CatalogOriginOption(label: 'Greenland', code: 'GL'),
    _CatalogOriginOption(label: 'Grenada', code: 'GD'),
    _CatalogOriginOption(label: 'Guadeloupe', code: 'GP'),
    _CatalogOriginOption(label: 'Guam', code: 'GU'),
    _CatalogOriginOption(label: 'Guatemala', code: 'GT'),
    _CatalogOriginOption(label: 'Guernsey', code: 'GG'),
    _CatalogOriginOption(label: 'Guinea', code: 'GN'),
    _CatalogOriginOption(label: 'Guinea-Bissau', code: 'GW'),
    _CatalogOriginOption(label: 'Guyana', code: 'GY'),
    _CatalogOriginOption(label: 'Haiti', code: 'HT'),
    _CatalogOriginOption(
      label: 'Heard Island and McDonald Islands',
      code: 'HM',
    ),
    _CatalogOriginOption(label: 'Honduras', code: 'HN'),
    _CatalogOriginOption(label: 'Hong Kong', code: 'HK'),
    _CatalogOriginOption(label: 'Hungary', code: 'HU'),
    _CatalogOriginOption(label: 'Iceland', code: 'IS'),
    _CatalogOriginOption(label: 'India', code: 'IN'),
    _CatalogOriginOption(label: 'Indonesia', code: 'ID'),
    _CatalogOriginOption(label: 'Iran', code: 'IR'),
    _CatalogOriginOption(label: 'Iraq', code: 'IQ'),
    _CatalogOriginOption(label: 'Ireland', code: 'IE'),
    _CatalogOriginOption(label: 'Isle of Man', code: 'IM'),
    _CatalogOriginOption(label: 'Israel', code: 'IL'),
    _CatalogOriginOption(label: 'Italy', code: 'IT'),
    _CatalogOriginOption(label: 'Jamaica', code: 'JM'),
    _CatalogOriginOption(label: 'Japan', code: 'JP'),
    _CatalogOriginOption(label: 'Jersey', code: 'JE'),
    _CatalogOriginOption(label: 'Jordan', code: 'JO'),
    _CatalogOriginOption(label: 'Kazakhstan', code: 'KZ'),
    _CatalogOriginOption(label: 'Kenya', code: 'KE'),
    _CatalogOriginOption(label: 'Kiribati', code: 'KI'),
    _CatalogOriginOption(label: 'Kuwait', code: 'KW'),
    _CatalogOriginOption(label: 'Kyrgyzstan', code: 'KG'),
    _CatalogOriginOption(label: 'Laos', code: 'LA'),
    _CatalogOriginOption(label: 'Latvia', code: 'LV'),
    _CatalogOriginOption(label: 'Lebanon', code: 'LB'),
    _CatalogOriginOption(label: 'Lesotho', code: 'LS'),
    _CatalogOriginOption(label: 'Liberia', code: 'LR'),
    _CatalogOriginOption(label: 'Libya', code: 'LY'),
    _CatalogOriginOption(label: 'Liechtenstein', code: 'LI'),
    _CatalogOriginOption(label: 'Lithuania', code: 'LT'),
    _CatalogOriginOption(label: 'Luxembourg', code: 'LU'),
    _CatalogOriginOption(label: 'Macao', code: 'MO'),
    _CatalogOriginOption(label: 'Madagascar', code: 'MG'),
    _CatalogOriginOption(label: 'Malawi', code: 'MW'),
    _CatalogOriginOption(label: 'Malaysia', code: 'MY'),
    _CatalogOriginOption(label: 'Maldives', code: 'MV'),
    _CatalogOriginOption(label: 'Mali', code: 'ML'),
    _CatalogOriginOption(label: 'Malta', code: 'MT'),
    _CatalogOriginOption(label: 'Marshall Islands', code: 'MH'),
    _CatalogOriginOption(label: 'Martinique', code: 'MQ'),
    _CatalogOriginOption(label: 'Mauritania', code: 'MR'),
    _CatalogOriginOption(label: 'Mauritius', code: 'MU'),
    _CatalogOriginOption(label: 'Mayotte', code: 'YT'),
    _CatalogOriginOption(label: 'Mexico', code: 'MX'),
    _CatalogOriginOption(label: 'Micronesia', code: 'FM'),
    _CatalogOriginOption(label: 'Moldova', code: 'MD'),
    _CatalogOriginOption(label: 'Monaco', code: 'MC'),
    _CatalogOriginOption(label: 'Mongolia', code: 'MN'),
    _CatalogOriginOption(label: 'Montenegro', code: 'ME'),
    _CatalogOriginOption(label: 'Montserrat', code: 'MS'),
    _CatalogOriginOption(label: 'Morocco', code: 'MA'),
    _CatalogOriginOption(label: 'Mozambique', code: 'MZ'),
    _CatalogOriginOption(label: 'Myanmar', code: 'MM'),
    _CatalogOriginOption(label: 'Namibia', code: 'NA'),
    _CatalogOriginOption(label: 'Nauru', code: 'NR'),
    _CatalogOriginOption(label: 'Nepal', code: 'NP'),
    _CatalogOriginOption(label: 'Netherlands', code: 'NL'),
    _CatalogOriginOption(label: 'New Zealand', code: 'NZ'),
    _CatalogOriginOption(label: 'Nicaragua', code: 'NI'),
    _CatalogOriginOption(label: 'Niger', code: 'NE'),
    _CatalogOriginOption(label: 'Nigeria', code: 'NG'),
    _CatalogOriginOption(label: 'Niue', code: 'NU'),
    _CatalogOriginOption(label: 'Norfolk Island', code: 'NF'),
    _CatalogOriginOption(label: 'North Korea', code: 'KP'),
    _CatalogOriginOption(label: 'North Macedonia', code: 'MK'),
    _CatalogOriginOption(label: 'Northern Mariana Islands', code: 'MP'),
    _CatalogOriginOption(label: 'Norway', code: 'NO'),
    _CatalogOriginOption(label: 'Oman', code: 'OM'),
    _CatalogOriginOption(label: 'Pakistan', code: 'PK'),
    _CatalogOriginOption(label: 'Palau', code: 'PW'),
    _CatalogOriginOption(label: 'Palestine', code: 'PS'),
    _CatalogOriginOption(label: 'Panama', code: 'PA'),
    _CatalogOriginOption(label: 'Papua New Guinea', code: 'PG'),
    _CatalogOriginOption(label: 'Paraguay', code: 'PY'),
    _CatalogOriginOption(label: 'Peru', code: 'PE'),
    _CatalogOriginOption(label: 'Philippines', code: 'PH'),
    _CatalogOriginOption(label: 'Pitcairn', code: 'PN'),
    _CatalogOriginOption(label: 'Poland', code: 'PL'),
    _CatalogOriginOption(label: 'Portugal', code: 'PT'),
    _CatalogOriginOption(label: 'Puerto Rico', code: 'PR'),
    _CatalogOriginOption(label: 'Qatar', code: 'QA'),
    _CatalogOriginOption(label: 'Reunion', code: 'RE'),
    _CatalogOriginOption(label: 'Romania', code: 'RO'),
    _CatalogOriginOption(label: 'Russia', code: 'RU'),
    _CatalogOriginOption(label: 'Rwanda', code: 'RW'),
    _CatalogOriginOption(label: 'Saint Barthelemy', code: 'BL'),
    _CatalogOriginOption(label: 'Saint Helena', code: 'SH'),
    _CatalogOriginOption(label: 'Saint Kitts and Nevis', code: 'KN'),
    _CatalogOriginOption(label: 'Saint Lucia', code: 'LC'),
    _CatalogOriginOption(label: 'Saint Martin', code: 'MF'),
    _CatalogOriginOption(label: 'Saint Pierre and Miquelon', code: 'PM'),
    _CatalogOriginOption(label: 'Saint Vincent and the Grenadines', code: 'VC'),
    _CatalogOriginOption(label: 'Samoa', code: 'WS'),
    _CatalogOriginOption(label: 'San Marino', code: 'SM'),
    _CatalogOriginOption(label: 'Sao Tome and Principe', code: 'ST'),
    _CatalogOriginOption(label: 'Saudi Arabia', code: 'SA'),
    _CatalogOriginOption(label: 'Senegal', code: 'SN'),
    _CatalogOriginOption(label: 'Serbia', code: 'RS'),
    _CatalogOriginOption(label: 'Seychelles', code: 'SC'),
    _CatalogOriginOption(label: 'Sierra Leone', code: 'SL'),
    _CatalogOriginOption(label: 'Singapore', code: 'SG'),
    _CatalogOriginOption(label: 'Sint Maarten', code: 'SX'),
    _CatalogOriginOption(label: 'Slovakia', code: 'SK'),
    _CatalogOriginOption(label: 'Slovenia', code: 'SI'),
    _CatalogOriginOption(label: 'Solomon Islands', code: 'SB'),
    _CatalogOriginOption(label: 'Somalia', code: 'SO'),
    _CatalogOriginOption(label: 'South Africa', code: 'ZA'),
    _CatalogOriginOption(
      label: 'South Georgia and the South Sandwich Islands',
      code: 'GS',
    ),
    _CatalogOriginOption(label: 'South Korea', code: 'KR'),
    _CatalogOriginOption(label: 'South Sudan', code: 'SS'),
    _CatalogOriginOption(label: 'Spain', code: 'ES'),
    _CatalogOriginOption(label: 'Sri Lanka', code: 'LK'),
    _CatalogOriginOption(label: 'Sudan', code: 'SD'),
    _CatalogOriginOption(label: 'Suriname', code: 'SR'),
    _CatalogOriginOption(label: 'Svalbard and Jan Mayen', code: 'SJ'),
    _CatalogOriginOption(label: 'Sweden', code: 'SE'),
    _CatalogOriginOption(label: 'Switzerland', code: 'CH'),
    _CatalogOriginOption(label: 'Syria', code: 'SY'),
    _CatalogOriginOption(label: 'Taiwan', code: 'TW'),
    _CatalogOriginOption(label: 'Tajikistan', code: 'TJ'),
    _CatalogOriginOption(label: 'Tanzania', code: 'TZ'),
    _CatalogOriginOption(label: 'Thailand', code: 'TH'),
    _CatalogOriginOption(label: 'Timor-Leste', code: 'TL'),
    _CatalogOriginOption(label: 'Togo', code: 'TG'),
    _CatalogOriginOption(label: 'Tokelau', code: 'TK'),
    _CatalogOriginOption(label: 'Tonga', code: 'TO'),
    _CatalogOriginOption(label: 'Trinidad and Tobago', code: 'TT'),
    _CatalogOriginOption(label: 'Tunisia', code: 'TN'),
    _CatalogOriginOption(label: 'Turkey', code: 'TR'),
    _CatalogOriginOption(label: 'Turkmenistan', code: 'TM'),
    _CatalogOriginOption(label: 'Turks and Caicos Islands', code: 'TC'),
    _CatalogOriginOption(label: 'Tuvalu', code: 'TV'),
    _CatalogOriginOption(label: 'Uganda', code: 'UG'),
    _CatalogOriginOption(label: 'Ukraine', code: 'UA'),
    _CatalogOriginOption(label: 'United Arab Emirates', code: 'AE'),
    _CatalogOriginOption(label: 'United Kingdom', code: 'GB'),
    _CatalogOriginOption(label: 'United States', code: 'US'),
    _CatalogOriginOption(
      label: 'United States Minor Outlying Islands',
      code: 'UM',
    ),
    _CatalogOriginOption(label: 'Uruguay', code: 'UY'),
    _CatalogOriginOption(label: 'Uzbekistan', code: 'UZ'),
    _CatalogOriginOption(label: 'Vanuatu', code: 'VU'),
    _CatalogOriginOption(label: 'Vatican City', code: 'VA'),
    _CatalogOriginOption(label: 'Venezuela', code: 'VE'),
    _CatalogOriginOption(label: 'Vietnam', code: 'VN'),
    _CatalogOriginOption(label: 'Virgin Islands, British', code: 'VG'),
    _CatalogOriginOption(label: 'Virgin Islands, U.S.', code: 'VI'),
    _CatalogOriginOption(label: 'Wallis and Futuna', code: 'WF'),
    _CatalogOriginOption(label: 'Western Sahara', code: 'EH'),
    _CatalogOriginOption(label: 'Yemen', code: 'YE'),
    _CatalogOriginOption(label: 'Zambia', code: 'ZM'),
    _CatalogOriginOption(label: 'Zimbabwe', code: 'ZW'),
  ];
  static const List<String> _movieGenres = [
    'All genres',
    'Action',
    'Adventure',
    'Animation',
    'Comedy',
    'Crime',
    'Documentary',
    'Drama',
    'Family',
    'Fantasy',
    'History',
    'Horror',
    'Music',
    'Mystery',
    'Romance',
    'Science Fiction',
    'Thriller',
    'TV Movie',
    'War',
    'Western',
  ];

  static const List<String> _seriesOnlyGenres = [
    'Action & Adventure',
    'Kids',
    'News',
    'Reality',
    'Sci-Fi & Fantasy',
    'Soap',
    'Talk',
    'War & Politics',
  ];

  static const List<String> _animationGenres = [
    'All genres',
    'Action',
    'Adventure',
    'Animation',
    'Comedy',
    'Drama',
    'Family',
    'Fantasy',
    'Kids',
    'Romance',
    'Sci-Fi & Fantasy',
    'Thriller',
  ];

  static final List<String> _years = [
    for (var year = DateTime.now().year; year >= 1900; year--) '$year',
  ];

  final StreamApi _api = StreamApi();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late Future<StreamConfig?> _configFuture;
  StreamConfig? _latestConfig;
  late final String _homeGreeting;
  late String _homePrompt;
  String _decisionPrompt = 'Decision fatigue?';
  Set<String> _verifiedAddonCatalogTypes = <String>{};
  final Map<MediaType, List<String>> _detectedDefaultYears =
      <MediaType, List<String>>{};
  final Set<MediaType> _detectingDefaultYears = <MediaType>{};

  MediaType _type = MediaType.movie;
  CatalogSort _sort = CatalogSort.top;
  String _year = _allYearsLabel;
  String _genre = 'All genres';
  _CatalogOriginOption _origin = const _CatalogOriginOption.all();
  _CatalogScopeOption _scope = const _CatalogScopeOption.all();
  String _search = '';
  Timer? _searchDebounce;
  Timer? _searchIdleTimer;
  Timer? _searchCloseTimer;
  Timer? _refreshMessageTimer;
  Timer? _contextCycleTimer;
  Timer? _catalogPrefetchTimer;
  Timer? _configLoadTimer;
  int _requestToken = 0;
  int _configLoadGeneration = 0;
  DateTime? _discoveryVisibleSince;
  double _lastScrollOffset = 0;
  final Map<String, List<_CatalogOriginOption>> _scopedOriginOptionsCache =
      <String, List<_CatalogOriginOption>>{};
  final Map<String, Future<List<_CatalogOriginOption>>>
  _scopedOriginOptionsInFlight = <String, Future<List<_CatalogOriginOption>>>{};

  List<CatalogItem> _items = [];
  List<CatalogItem> _visibleItems = [];
  Map<MediaType, List<CatalogItem>> _searchResultGroups =
      <MediaType, List<CatalogItem>>{};
  int _skip = 0;
  bool _loading = true;
  bool _reloadPriming = false;
  bool _hasMore = true;
  String? _error;
  bool _controlsVisible = true;
  bool _showScrollTop = false;
  bool _pendingEndLoadLog = false;
  bool _nearEndArmed = true;
  double _nextAutoLoadPixels = 0;
  bool _searchExpanded = false;
  bool _searchFieldActive = false;
  bool _searchShellExpanded = false;
  bool _searchSuggestionsVisible = false;
  bool _refreshMessageVisible = false;
  bool _greetingVisible = true;
  bool _greetingContextVisible = true;
  bool _animateGreeting = true;
  bool _showDecisionPrompt = true;
  bool _randomPickLoading = false;
  bool _startupSettled = false;
  bool _configLoadStarted = false;
  bool _pendingVisibleRefresh = false;
  bool _matureContentChoiceScheduled = false;
  DateTime? _lastAppliedDiscoveryIntentAt;

  bool get _searchActive => _search.trim().isNotEmpty;

  String _effectiveGenre([StreamConfig? config]) {
    final options = _filterOptionsFor(config);
    if (_type == MediaType.animation) {
      return _genre == 'All genres' || options.contains(_genre)
          ? _genre
          : 'All genres';
    }
    return options.contains(_genre) ? _genre : options.first;
  }

  List<_CatalogScopeOption> _scopeOptionsFor(MediaType type) {
    if (type == MediaType.liveTv ||
        type == MediaType.music ||
        type == MediaType.nsfw) {
      return const [_CatalogScopeOption.all()];
    }
    if (type == MediaType.movie) return _scopeOptions;
    return _scopeOptions
        .where((scope) => scope.kind != _CatalogScopeKind.collection)
        .toList(growable: false);
  }

  _CatalogScopeOption _effectiveScopeFor(MediaType type) {
    return const _CatalogScopeOption.all();
  }

  bool _supportsOriginFilter(MediaType type) {
    return type == MediaType.movie ||
        type == MediaType.series ||
        type == MediaType.animation;
  }

  bool _supportsYearFilter(MediaType type, {CatalogSort? sort}) {
    final targetSort = sort ?? _sort;
    return type != MediaType.liveTv &&
        type != MediaType.music &&
        type != MediaType.nsfw &&
        targetSort != CatalogSort.nowPlaying &&
        targetSort != CatalogSort.upcoming;
  }

  String _activeOriginCode() {
    final code = _origin.code.trim().toUpperCase();
    return RegExp(r'^[A-Z]{2}$').hasMatch(code) ? code : '';
  }

  _CatalogOriginOption _globalOriginOptionForCode(String code) {
    final cleanCode = code.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(cleanCode)) {
      return const _CatalogOriginOption.all();
    }
    for (final option in _originOptions) {
      if (option.code == cleanCode) return option;
    }
    return const _CatalogOriginOption.all();
  }

  _CatalogOriginOption _originOptionForCode(MediaType type, String code) {
    final globalOption = _globalOriginOptionForCode(code);
    if (globalOption.isAll) {
      return globalOption;
    }
    if (!_supportsOriginFilter(type)) return const _CatalogOriginOption.all();
    return globalOption;
  }

  String _rememberedOriginCodeFor(MediaType type) {
    if (!_supportsOriginFilter(type)) return '';
    final globalOption = _globalOriginOptionForCode(_activeOriginCode());
    return globalOption.isAll ? '' : globalOption.code;
  }

  _CatalogOriginOption _effectiveOriginFor(MediaType type) {
    if (!_supportsOriginFilter(type)) return const _CatalogOriginOption.all();
    return _originOptionForCode(type, _activeOriginCode());
  }

  List<_CatalogOriginOption> _originOptionsFor(MediaType type) {
    if (!_supportsOriginFilter(type)) return const [_CatalogOriginOption.all()];
    final key = _originOptionsCacheKey(type: type);
    final scopedOptions = _scopedOriginOptionsCache[key];
    if (scopedOptions == null || scopedOptions.isEmpty) {
      return _originOptionsWithActiveSelection(const [
        _CatalogOriginOption.all(),
      ]);
    }
    return _originOptionsWithActiveSelection(scopedOptions);
  }

  List<_CatalogOriginOption> _originOptionsWithActiveSelection(
    List<_CatalogOriginOption> scopedOptions,
  ) {
    final activeOrigin = _globalOriginOptionForCode(_activeOriginCode());
    if (activeOrigin.isAll || scopedOptions.contains(activeOrigin)) {
      return scopedOptions;
    }
    return <_CatalogOriginOption>[
      const _CatalogOriginOption.all(),
      activeOrigin,
      ...scopedOptions.where((option) => !option.isAll),
    ];
  }

  String _originOptionsCacheKey({
    required MediaType type,
    CatalogSort? sort,
    String? year,
    String? genre,
  }) {
    final effectiveSort = _sortOptionsFor(type).contains(sort ?? _sort)
        ? (sort ?? _sort)
        : _sortOptionsFor(type).first;
    final effectiveYear = _normalizedOriginYearFor(
      type,
      sort: effectiveSort,
      year: year,
    );
    final effectiveGenre = _normalizedOriginGenreFor(
      type,
      sort: effectiveSort,
      genre: genre,
    );
    return [
      type.compatTypeValue,
      effectiveSort.id,
      effectiveYear,
      effectiveGenre,
    ].join('::');
  }

  String _normalizedOriginYearFor(
    MediaType type, {
    required CatalogSort sort,
    String? year,
  }) {
    if (!_supportsYearFilter(type, sort: sort)) return '';
    final candidate = (year ?? _year).trim();
    return RegExp(r'^\d{4}$').hasMatch(candidate) ? candidate : '';
  }

  String _normalizedOriginGenreFor(
    MediaType type, {
    required CatalogSort sort,
    String? genre,
  }) {
    final candidate = (genre ?? _genre).trim();
    final options = _filterOptionsFor(_latestConfig, type: type, sort: sort);
    final normalized = candidate.isEmpty
        ? options.first
        : (options.contains(candidate) ? candidate : options.first);
    return normalized == 'All genres' ? '' : normalized;
  }

  Future<List<_CatalogOriginOption>> _loadScopedOriginOptions(
    MediaType type, {
    CatalogSort? sort,
    String? year,
    String? genre,
    bool forceRefresh = false,
  }) async {
    if (!_supportsOriginFilter(type)) {
      return const [_CatalogOriginOption.all()];
    }
    final effectiveSort = _sortOptionsFor(type).contains(sort ?? _sort)
        ? (sort ?? _sort)
        : _sortOptionsFor(type).first;
    final normalizedYear = _normalizedOriginYearFor(
      type,
      sort: effectiveSort,
      year: year,
    );
    final normalizedGenre = _normalizedOriginGenreFor(
      type,
      sort: effectiveSort,
      genre: genre,
    );
    final cacheKey = _originOptionsCacheKey(
      type: type,
      sort: effectiveSort,
      year: normalizedYear,
      genre: normalizedGenre,
    );
    if (!forceRefresh) {
      final cached = _scopedOriginOptionsCache[cacheKey];
      if (cached != null && cached.isNotEmpty) return cached;
      final inFlight = _scopedOriginOptionsInFlight[cacheKey];
      if (inFlight != null) return inFlight;
    }
    final future = _api
        .catalogOriginCountries(
          type: type,
          sort: effectiveSort,
          year: normalizedYear,
          genre: normalizedGenre,
        )
        .then((codes) {
          final allowed = codes.toSet();
          final options = <_CatalogOriginOption>[
            const _CatalogOriginOption.all(),
            ..._originOptions.where(
              (option) =>
                  option.code.isNotEmpty && allowed.contains(option.code),
            ),
          ];
          if (!mounted) return options;
          setState(() {
            _scopedOriginOptionsCache[cacheKey] = options;
          });
          return options;
        })
        .catchError(
          (_) => const <_CatalogOriginOption>[_CatalogOriginOption.all()],
        );
    _scopedOriginOptionsInFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _scopedOriginOptionsInFlight.remove(cacheKey);
    }
  }

  List<String> _movieGenreOptions(StreamConfig? config) {
    return _mergedCatalogGenres(_movieGenres, config?.movieGenres);
  }

  List<String> _seriesGenreOptions(StreamConfig? config) {
    final genres = config?.seriesGenres;
    if (genres == null || genres.isEmpty)
      return [..._movieGenres, ..._seriesOnlyGenres];
    return _mergedCatalogGenres([
      ..._movieGenres,
      ..._seriesOnlyGenres,
    ], genres);
  }

  List<String> _animationGenreOptions(StreamConfig? config) {
    return _mergedCatalogGenres(_animationGenres, config?.animationGenres);
  }

  List<String> _liveTvGenreOptions(StreamConfig? config, {CatalogSort? sort}) {
    if ((sort ?? _sort) == CatalogSort.newest) {
      final countries =
          config?.liveTvCountries ??
          _latestConfig?.liveTvCountries ??
          StreamApi.cachedConfig?.liveTvCountries;
      if (countries == null || countries.isEmpty) {
        return _betaLiveTvCountryOptions;
      }
      return _withAllCountries(countries);
    }
    if ((sort ?? _sort) == CatalogSort.imdbRating) {
      return _gammaLiveTvGenreOptions;
    }
    final genres =
        config?.liveTvGenres ??
        _latestConfig?.liveTvGenres ??
        StreamApi.cachedConfig?.liveTvGenres;
    if (genres == null || genres.isEmpty) return _alphaLiveTvGenreOptions;
    return _withAllGenres(genres);
  }

  List<String> _musicGenreOptions(StreamConfig? config) {
    final genres = config?.musicGenres;
    if (genres == null || genres.isEmpty) return const ['All genres'];
    return _withAllGenres(genres);
  }

  List<String> _nsfwGenreOptions(StreamConfig? config) {
    final genres = config?.nsfwGenres;
    if (genres == null || genres.isEmpty) return const ['All genres'];
    return _withAllGenres(genres);
  }

  List<String> _yearOptions(StreamConfig? config, {CatalogSort? sort}) {
    final currentYear = DateTime.now().year;
    final targetSort = sort ?? _sort;
    if (targetSort == CatalogSort.nowPlaying) {
      return const [_allYearsLabel];
    }
    final minYear = targetSort == CatalogSort.upcoming ? currentYear : 1900;
    final maxYear = targetSort == CatalogSort.upcoming
        ? currentYear + 2
        : currentYear;
    final detected =
        <int>{
            ...?_detectedDefaultYears[_type]
                ?.map((year) => int.tryParse(year.trim()))
                .whereType<int>(),
            ...?config
                ?.addonYearsFor(_type)
                ?.map((year) => int.tryParse(year.trim()))
                .whereType<int>(),
            for (var year = maxYear; year >= minYear; year--) year,
          }.where((year) => year >= minYear && year <= maxYear).toList()
          ..sort((a, b) => b.compareTo(a));
    final years = detected.isEmpty
        ? [currentYear.toString()]
        : [for (final year in detected) '$year'];
    return [_allYearsLabel, ...years];
  }

  bool _yearSelectionAvailable(StreamConfig? config, {CatalogSort? sort}) {
    if (AppState.defaultCatalogEnabled.value &&
        _detectingDefaultYears.contains(_type)) {
      return true;
    }
    final years = _yearOptions(config, sort: sort);
    return years.length > 1 || (years.isNotEmpty && years.first != 'Unknown');
  }

  String get _fallbackYear => _years.first;

  String? get _activeYearFilter {
    if (_type == MediaType.liveTv ||
        _type == MediaType.music ||
        _type == MediaType.nsfw ||
        _sort == CatalogSort.nowPlaying) {
      return null;
    }
    final value = _year.trim();
    if (value.isEmpty || value == 'Unknown' || value == _allYearsLabel) {
      return null;
    }
    return RegExp(r'^\d{4}$').hasMatch(value) ? value : null;
  }

  bool _isYearFilterSettling(StreamConfig? config) {
    if (_activeYearFilter == null) return false;
    if (_type == MediaType.liveTv ||
        _type == MediaType.music ||
        _type == MediaType.nsfw) {
      return false;
    }
    if (_year == 'Unknown') return true;
    return AppState.defaultCatalogEnabled.value &&
        _detectingDefaultYears.contains(_type) &&
        _visibleItems.isEmpty;
  }

  void _ensureDefaultYearOptions() {
    if (!AppState.defaultCatalogEnabled.value) return;
    if (AppState.isInInteractionQuietWindow) return;
    if (_type == MediaType.liveTv ||
        _type == MediaType.music ||
        _type == MediaType.nsfw) {
      return;
    }
    if (_detectedDefaultYears.containsKey(_type) ||
        _detectingDefaultYears.contains(_type)) {
      return;
    }
    final targetType = _type;
    _detectingDefaultYears.add(targetType);
    unawaited(
      _api
          .builtInYearOptions(targetType)
          .then((years) {
            if (!mounted) return;
            var shouldReload = false;
            setState(() {
              _detectingDefaultYears.remove(targetType);
              _detectedDefaultYears[targetType] = years;
              if (_type == targetType &&
                  _activeYearFilter != null &&
                  years.isNotEmpty) {
                if (!years.contains(_year)) {
                  _year = _yearOptions(null).first;
                  shouldReload = true;
                }
              }
            });
            if (shouldReload) _reload(preserveVisibleItems: false);
          })
          .catchError((Object error) {
            if (!mounted) return;
            setState(() {
              _detectingDefaultYears.remove(targetType);
              _detectedDefaultYears[targetType] = const <String>[];
            });
            DiagnosticLog.add(
              'catalog built-in year options unavailable type=${targetType.compatTypeValue} error=$error',
            );
          }),
    );
  }

  List<String> get _filterOptions {
    return _filterOptionsFor(null);
  }

  List<String> _filterOptionsFor(
    StreamConfig? config, {
    MediaType? type,
    CatalogSort? sort,
  }) {
    final targetType = type ?? _type;
    if (targetType == MediaType.liveTv) {
      return _liveTvGenreOptions(config, sort: sort);
    }
    if (targetType == MediaType.music) return _musicGenreOptions(config);
    if (targetType == MediaType.nsfw) return _nsfwGenreOptions(config);
    if (targetType == MediaType.animation) {
      return _animationGenreOptions(config);
    }
    if (targetType == MediaType.series) {
      return _seriesGenreOptions(config);
    }
    return _movieGenreOptions(config);
  }

  List<MediaType> _typeOptionsFor(StreamConfig? config) {
    if (config != null && config.addonCatalogTypes.isNotEmpty) {
      _verifiedAddonCatalogTypes = config.addonCatalogTypes
          .map((type) => type.trim().toLowerCase())
          .where((type) => type.isNotEmpty)
          .toSet();
    } else if (!AppState.userAddons.value.any((addon) => addon.active)) {
      _verifiedAddonCatalogTypes = <String>{};
    }
    final values = <MediaType>[MediaType.movie, MediaType.series];
    if (AppState.defaultCatalogEnabled.value ||
        _supportsAnimationCatalog(config)) {
      values.add(MediaType.animation);
    }
    final hideLiveTvForOrigin = _activeOriginCode().isNotEmpty;
    if (!hideLiveTvForOrigin &&
        ((AppState.tvSourcesEnabled.value &&
                AppState.publicIptvEnabled.value) ||
            _supportsAddonCatalogType(config, MediaType.liveTv))) {
      values.add(MediaType.liveTv);
    }
    if (_supportsAddonCatalogType(config, MediaType.music))
      values.add(MediaType.music);
    if (_supportsNsfwCatalog(config)) values.add(MediaType.nsfw);
    return values;
  }

  bool _supportsAddonCatalogType(StreamConfig? config, MediaType type) {
    return config?.supportsAddonCatalogType(type) == true ||
        _verifiedAddonCatalogTypes.any(type.matchesCompatType);
  }

  bool _supportsAnimationCatalog(StreamConfig? config) {
    return _supportsAddonCatalogType(config, MediaType.animation) ||
        _hasAnimationGenreSignal(config?.animationGenres) ||
        _hasAnimationGenreSignal(config?.seriesGenres);
  }

  bool _supportsNsfwCatalog(StreamConfig? config) {
    if (!AppState.showMatureContent.value) return false;
    return _supportsAddonCatalogType(config, MediaType.nsfw) ||
        (config?.nsfwGenres.isNotEmpty ?? false);
  }

  void _maybeShowMatureContentChoice() {
    if (!mounted ||
        !_isDiscoveryTabSelected ||
        !_hasDiscoverableContent ||
        _matureContentChoiceScheduled ||
        AppState.matureContentChoiceSeen.value) {
      return;
    }
    if (!AppState.tryBeginMatureContentChoice()) return;
    _matureContentChoiceScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_isDiscoveryTabSelected ||
          !_hasDiscoverableContent ||
          AppState.matureContentChoiceSeen.value) {
        _matureContentChoiceScheduled = false;
        AppState.finishMatureContentChoice();
        return;
      }
      unawaited(_showMatureContentChoice());
    });
  }

  Future<void> _showMatureContentChoice() async {
    try {
      DiagnosticLog.screen(context, 'Discovery mature content choice');
      final showMatureContent = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Show 18+ titles?'),
              content: const Text(
                'Juicr can keep mature titles hidden, or include them in Home and Discovery.\n\n'
                'You can change this anytime in Settings General.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Keep hidden'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Show 18+'),
                ),
              ],
            ),
          );
        },
      );
      if (showMatureContent == null) {
        DiagnosticLog.add(
          'discovery mature content choice closed without choice',
        );
        return;
      }
      AppState.setShowMatureContent(showMatureContent);
      DiagnosticLog.add(
        'discovery mature content choice ${showMatureContent ? 'show' : 'hide'}',
      );
    } finally {
      _matureContentChoiceScheduled = false;
      AppState.finishMatureContentChoice();
    }
  }

  bool _hasAnimationGenreSignal(List<String>? genres) {
    if (genres == null || genres.isEmpty) return false;
    return genres.any((genre) {
      final normalized = genre.trim().toLowerCase();
      return normalized == 'animation';
    });
  }

  bool get _hasDiscoverableContent {
    return AppState.preferencesReady.value && AppState.hasCatalogSource;
  }

  List<CatalogItem> _localCatalogItemsForBrowse() {
    return const <CatalogItem>[];
  }

  String _greetingForNow() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String _randomPrompt([String? current]) {
    final prompts = [
      'What sounds good tonight?',
      'Where are we going first?',
      'Want something easy, weird, or loud?',
      'Tell me the mood. I will look.',
      'Let us find the thing.',
    ];
    final seed = DateTime.now().millisecondsSinceEpoch;
    var next = prompts[seed % prompts.length];
    if (current != null && prompts.length > 1 && next == current) {
      next = prompts[(prompts.indexOf(next) + 1) % prompts.length];
    }
    return next;
  }

  String _randomDecisionPrompt([String? current]) {
    final prompts = [
      'Decision fatigue?',
      'Want a little nudge?',
      'I can throw a dart.',
      'No shame. Picking is work.',
      'Let Juicr pick first.',
      'Need the first spark?',
    ];
    final seed = DateTime.now().microsecondsSinceEpoch;
    var next = prompts[seed % prompts.length];
    if (current != null && prompts.length > 1 && next == current) {
      next = prompts[(prompts.indexOf(next) + 1) % prompts.length];
    }
    return next;
  }

  void _handleCatalogSourcesChanged() {
    StreamApi.clearAddonManifestCache();
    _latestConfig = StreamApi.cachedConfig;
    _cancelPendingConfigLoad();
    if (!AppState.userAddons.value.any((addon) => addon.active)) {
      _verifiedAddonCatalogTypes = <String>{};
    }
    DiagnosticLog.add(
      'catalog sources changed '
      'defaultCatalog=${AppState.defaultCatalogEnabled.value} '
      'tvSources=${AppState.tvSourcesEnabled.value} '
      'publicIptv=${AppState.publicIptvEnabled.value} '
      'personalServers=${AppState.personalServerConnections.value.where((connection) => connection.active).length} '
      'activeAddons=${AppState.userAddons.value.where((addon) => addon.active).length}',
    );
    _configLoadStarted = false;
    if (!mounted) return;
    if (!_hasDiscoverableContent) {
      _catalogPrefetchTimer?.cancel();
      setState(() {
        _items = [];
        _visibleItems = [];
        _skip = 0;
        _loading = false;
        _reloadPriming = false;
        _hasMore = false;
        _error = null;
        _pendingEndLoadLog = false;
      });
      return;
    }
    if (!_isDiscoveryTabSelected) {
      _pendingVisibleRefresh = true;
      return;
    }
    _restoreDiscoveryWarmSnapshot();
    _configLoadStarted = false;
    _configFuture = Future<StreamConfig?>.value(_latestConfig);
    _startVisibleCatalogWork(forceReload: true);
    _maybeShowMatureContentChoice();
  }

  void _handleMatureChoicePromptSignal() {
    _maybeShowMatureContentChoice();
  }

  bool get _isDiscoveryTabSelected => AppState.shellTab.value == 1;

  void _handleShellTabChanged() {
    if (!mounted) return;
    if (!_isDiscoveryTabSelected) {
      _discoveryVisibleSince = null;
      _cancelPendingConfigLoad();
      return;
    }
    _discoveryVisibleSince = DateTime.now();
    final handledIntent = _applyDiscoveryIntent();
    if (!handledIntent) {
      _startVisibleCatalogWork(forceReload: _pendingVisibleRefresh);
    }
    _maybeShowMatureContentChoice();
  }

  void _cancelPendingConfigLoad() {
    _configLoadTimer?.cancel();
    _configLoadTimer = null;
    _configLoadGeneration += 1;
  }

  void _startConfigLoadIfNeeded() {
    if (_configLoadStarted) return;
    if (!_isDiscoveryTabSelected) return;
    final quietRemaining = _discoveryConfigQuietRemaining();
    if (quietRemaining > Duration.zero) {
      _configLoadTimer?.cancel();
      final generation = _configLoadGeneration;
      _configLoadTimer = Timer(quietRemaining, () {
        if (!mounted ||
            generation != _configLoadGeneration ||
            !_isDiscoveryTabSelected) {
          return;
        }
        _startConfigLoadIfNeeded();
      });
      return;
    }
    _configLoadStarted = true;
    _configLoadTimer?.cancel();
    _configLoadTimer = null;
    final generation = _configLoadGeneration;
    _configFuture = Future<StreamConfig?>.delayed(
      const Duration(milliseconds: 1400),
      () async {
        if (!mounted ||
            generation != _configLoadGeneration ||
            !_isDiscoveryTabSelected) {
          _configLoadStarted = false;
          return _latestConfig;
        }
        final quietRemaining = _discoveryConfigQuietRemaining();
        if (quietRemaining > Duration.zero) {
          _configLoadStarted = false;
          DiagnosticLog.add(
            'catalog config load deferred reason=interaction_quiet remainingMs=${quietRemaining.inMilliseconds}',
          );
          _configLoadTimer?.cancel();
          _configLoadTimer = Timer(quietRemaining, () {
            if (!mounted || !_isDiscoveryTabSelected) return;
            _startConfigLoadIfNeeded();
          });
          return _latestConfig;
        }
        final config = await _api.config().catchError((_) => null);
        if (config != null) {
          _latestConfig = config;
          DiagnosticLog.add(
            'catalog config loaded liveTvGenres=${config.liveTvGenres.length} addonTypes=${config.addonCatalogTypes.length}',
          );
          _maybeShowMatureContentChoice();
        }
        return config ?? _latestConfig;
      },
    );
    setState(() {});
  }

  Duration _discoveryConfigQuietRemaining() {
    final visibleSince = _discoveryVisibleSince;
    final visibleRemaining = visibleSince == null
        ? AppState.interactionQuietWindow
        : AppState.interactionQuietWindow -
              DateTime.now().difference(visibleSince);
    final interactionRemaining = AppState.interactionQuietRemaining();
    final remaining = visibleRemaining > interactionRemaining
        ? visibleRemaining
        : interactionRemaining;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void _startVisibleCatalogWork({bool forceReload = false}) {
    _startConfigLoadIfNeeded();
    _primeOriginOptions();
    if (!_hasDiscoverableContent) return;
    if (_visibleItems.isEmpty || forceReload || _pendingVisibleRefresh) {
      _pendingVisibleRefresh = false;
      _reload();
    }
  }

  void _primeOriginOptions() {
    if (!_supportsOriginFilter(_type)) return;
    unawaited(_loadScopedOriginOptions(_type));
  }

  bool _restoreDiscoveryWarmSnapshot() {
    if (!mounted || !_hasDiscoverableContent || _searchActive) return false;
    final prefs = AppState.prefs;
    if (prefs == null) return false;
    final raw = prefs.getString(_discoveryWarmSnapshotKey);
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      if (decoded['type'] != _type.compatTypeValue ||
          decoded['sort'] != _sort.id ||
          decoded['year'] != _year ||
          decoded['genre'] != _effectiveGenre(_latestConfig) ||
          decoded['origin'] != _effectiveOriginFor(_type).code ||
          decoded['scope'] != _effectiveScopeFor(_type).displayLabel) {
        return false;
      }
      final rawItems = decoded['items'];
      if (rawItems is! List) return false;
      final items = <CatalogItem>[];
      for (final rawItem in rawItems) {
        if (rawItem is! Map<String, dynamic>) continue;
        final item = CatalogItem.fromJson(rawItem);
        if (item.isLocalCatalogItem ||
            item.personalServerItemId != null ||
            item.personalServerSeriesItemId != null) {
          continue;
        }
        items.add(item);
      }
      final restored = _catalogItemsForRequestedType(
        _dedupeCatalogItems(items),
        _type,
      );
      if (restored.isEmpty) return false;
      setState(() {
        _items = restored;
        _visibleItems = restored;
        _skip =
            int.tryParse((decoded['skip'] ?? '').toString()) ?? restored.length;
        _hasMore = decoded['hasMore'] == true;
        _loading = false;
        _reloadPriming = true;
        _error = null;
        _pendingVisibleRefresh = true;
      });
      DiagnosticLog.add(
        'catalog warm snapshot restored source=local_snapshot type=${_type.compatTypeValue} count=${restored.length}',
      );
      DiagnosticLog.viewTiming(
        surface: 'catalog',
        state: 'interaction_ready',
        cacheStateBucket: 'local_snapshot',
        mediaKind: _type.compatTypeValue,
        itemCount: restored.length,
      );
      return true;
    } catch (error) {
      DiagnosticLog.add(
        'catalog warm snapshot skipped reason=decode_failed error=${error.runtimeType}',
      );
      return false;
    }
  }

  void _saveDiscoveryWarmSnapshot() {
    final prefs = AppState.prefs;
    if (prefs == null ||
        !_hasDiscoverableContent ||
        _searchActive ||
        _visibleItems.isEmpty) {
      return;
    }
    final safeItems = [
      for (final item in _visibleItems.take(40))
        if (!item.isLocalCatalogItem &&
            item.personalServerItemId == null &&
            item.personalServerSeriesItemId == null)
          item.toJson(),
    ];
    if (safeItems.isEmpty) return;
    final payload = <String, dynamic>{
      'version': 1,
      'savedAt': DateTime.now().toIso8601String(),
      'type': _type.compatTypeValue,
      'sort': _sort.id,
      'year': _year,
      'genre': _effectiveGenre(_latestConfig),
      'origin': _effectiveOriginFor(_type).code,
      'scope': _effectiveScopeFor(_type).displayLabel,
      'skip': _skip,
      'hasMore': _hasMore,
      'items': safeItems,
    };
    unawaited(prefs.setString(_discoveryWarmSnapshotKey, jsonEncode(payload)));
  }

  void _restoreBrowseFilterPreference() {
    final preference = AppState.browseFilterPreference.value;
    final preferredType = preference.type;
    final preferredSort = preference.sortFor(preferredType);
    _type = preferredType;
    _sort = _sortOptionsFor(preferredType).contains(preferredSort)
        ? preferredSort
        : CatalogSort.top;
    if (_sort == CatalogSort.year) _sort = CatalogSort.top;
    final preferredYear = preference.yearFor(preferredType);
    final years = _yearOptions(null);
    _year = years.contains(preferredYear) ? preferredYear : years.first;
    final preferredGenre = preference.genreFor(preferredType);
    final options = _filterOptionsFor(null);
    _genre = options.contains(preferredGenre) ? preferredGenre : options.first;
    final preferredOrigin = preference.originFor(preferredType);
    _origin = _originOptionForCode(preferredType, preferredOrigin);
    DiagnosticLog.add(
      'browse filter restored type=${_type.compatTypeValue} sort=${_sort.id} genre=$_genre origin=${_origin.code}',
    );
  }

  void _rememberBrowseFilterPreference() {
    AppState.rememberBrowseFilter(
      type: _type,
      sort: _sort,
      year: _year,
      genre: _effectiveGenre(_latestConfig),
      origin: _rememberedOriginCodeFor(_type),
    );
  }

  void _openBrowseSheet(BuildContext context) {
    final config = _latestConfig;
    final typeOptions = _typeOptionsFor(config);
    final filterOptions = _filterOptionsFor(config);
    final scopeOptions = _scopeOptionsFor(_type);
    final genreOptionsByType = <MediaType, List<String>>{
      MediaType.movie: _movieGenreOptions(config),
      MediaType.series: _seriesGenreOptions(config),
      MediaType.animation: _animationGenreOptions(config),
      MediaType.liveTv: _liveTvGenreOptions(config, sort: _sort),
      MediaType.music: _musicGenreOptions(config),
      MediaType.nsfw: _nsfwGenreOptions(config),
    };
    _BrowseControlCard(
      type: _type,
      types: typeOptions,
      sort: _sort,
      year: _year,
      genre: _effectiveGenre(config),
      origin: _effectiveOriginFor(_type),
      scope: _effectiveScopeFor(_type),
      genres: filterOptions,
      genreOptionsByType: genreOptionsByType,
      originOptions: _originOptionsFor(_type),
      scopeOptions: scopeOptions,
      years: _yearOptions(config),
      yearSelectionAvailable: _yearSelectionAvailable(config),
      yearsForSort: (sort) => _yearOptions(config, sort: sort),
      yearSelectionAvailableForSort: (sort) =>
          _yearSelectionAvailable(config, sort: sort),
      onOpenBrowseSheet: () => _openBrowseSheet(context),
      onTypeChanged: _setType,
      onSortChanged: _setSort,
      onYearChanged: _setYear,
      onGenreChanged: _setGenre,
      onOriginChanged: _setOrigin,
      onScopeChanged: _setScope,
    )._showBrowseSheet(context);
  }

  @override
  void initState() {
    super.initState();
    _homeGreeting = _greetingForNow();
    _homePrompt = _randomPrompt();
    _restoreBrowseFilterPreference();
    _latestConfig = StreamApi.cachedConfig;
    _configFuture = Future<StreamConfig?>.value(_latestConfig);
    AppState.userAddons.addListener(_handleCatalogSourcesChanged);
    AppState.personalServerConnections.addListener(
      _handleCatalogSourcesChanged,
    );
    AppState.preferencesReady.addListener(_handleCatalogSourcesChanged);
    AppState.defaultCatalogEnabled.addListener(_handleCatalogSourcesChanged);
    AppState.showMatureContent.addListener(_handleCatalogSourcesChanged);
    AppState.matureContentChoiceSeen.addListener(
      _handleMatureChoicePromptSignal,
    );
    AppState.tvSourcesEnabled.addListener(_handleCatalogSourcesChanged);
    AppState.publicIptvEnabled.addListener(_handleCatalogSourcesChanged);
    AppState.searchHistory.addListener(_handleSearchHistoryChanged);
    AppState.discoveryIntent.addListener(_handleDiscoveryIntentChanged);
    AppState.shellTab.addListener(_handleShellTabChanged);
    AppState.artworkMotion.addListener(_handleVisualPreferenceChanged);
    AppState.homeDensity.addListener(_handleVisualPreferenceChanged);
    AppState.batteryDataSettings.addListener(_handleVisualPreferenceChanged);
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    _scrollController.addListener(_handleScroll);
    DiagnosticLog.add('catalog init');
    _restoreDiscoveryWarmSnapshot();
    _scheduleContextCycle(delay: const Duration(seconds: 4));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isDiscoveryTabSelected) {
        _discoveryVisibleSince ??= DateTime.now();
      }
      final handledIntent = _applyDiscoveryIntent();
      if (_isDiscoveryTabSelected && !handledIntent) {
        _startVisibleCatalogWork();
      }
      Timer(const Duration(milliseconds: 2600), () {
        if (!mounted) return;
        _startupSettled = true;
        if (_isDiscoveryTabSelected && AppState.preferencesReady.value) {
          _ensureDefaultYearOptions();
        }
      });
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchIdleTimer?.cancel();
    _searchCloseTimer?.cancel();
    _refreshMessageTimer?.cancel();
    _contextCycleTimer?.cancel();
    _catalogPrefetchTimer?.cancel();
    _configLoadTimer?.cancel();
    _configLoadGeneration += 1;
    AppState.userAddons.removeListener(_handleCatalogSourcesChanged);
    AppState.personalServerConnections.removeListener(
      _handleCatalogSourcesChanged,
    );
    AppState.preferencesReady.removeListener(_handleCatalogSourcesChanged);
    AppState.defaultCatalogEnabled.removeListener(_handleCatalogSourcesChanged);
    AppState.showMatureContent.removeListener(_handleCatalogSourcesChanged);
    AppState.matureContentChoiceSeen.removeListener(
      _handleMatureChoicePromptSignal,
    );
    AppState.tvSourcesEnabled.removeListener(_handleCatalogSourcesChanged);
    AppState.publicIptvEnabled.removeListener(_handleCatalogSourcesChanged);
    AppState.searchHistory.removeListener(_handleSearchHistoryChanged);
    AppState.discoveryIntent.removeListener(_handleDiscoveryIntentChanged);
    AppState.shellTab.removeListener(_handleShellTabChanged);
    AppState.artworkMotion.removeListener(_handleVisualPreferenceChanged);
    AppState.homeDensity.removeListener(_handleVisualPreferenceChanged);
    AppState.batteryDataSettings.removeListener(_handleVisualPreferenceChanged);
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _api.close();
    super.dispose();
  }

  void _handleSearchFocusChanged() {
    if (_searchFocusNode.hasFocus) {
      _expandSearch();
    } else if (_searchController.text.trim().isEmpty) {
      _scheduleSearchRetract();
    }
  }

  void _handleSearchHistoryChanged() {
    if (mounted) setState(() {});
  }

  void _clearSearch({required bool keepSearchOpen}) {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _search = '';
      _searchResultGroups = <MediaType, List<CatalogItem>>{};
      _searchExpanded = keepSearchOpen;
      _searchFieldActive = keepSearchOpen;
      _searchShellExpanded = keepSearchOpen;
      _searchSuggestionsVisible = keepSearchOpen;
      _animateGreeting = true;
      _greetingVisible = !keepSearchOpen;
      _showDecisionPrompt = !keepSearchOpen;
      _controlsVisible = true;
    });
    _reload(preserveVisibleItems: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
      if (keepSearchOpen) {
        _searchFocusNode.requestFocus();
      } else {
        _searchFocusNode.unfocus();
      }
    });
  }

  void _handleDiscoveryIntentChanged() {
    _applyDiscoveryIntent();
  }

  bool _applyDiscoveryIntent() {
    final intent = AppState.discoveryIntent.value;
    if (intent == null || !mounted) return false;
    if (_lastAppliedDiscoveryIntentAt == intent.createdAt) return false;
    final nextGenre = _normalizeDiscoveryGenre(intent.genre);
    if (_type == intent.type &&
        _sort == intent.sort &&
        _genre == nextGenre &&
        _search.isEmpty) {
      _lastAppliedDiscoveryIntentAt = intent.createdAt;
      return false;
    }
    _lastAppliedDiscoveryIntentAt = intent.createdAt;
    DiagnosticLog.add(
      'catalog discovery intent type=${intent.type.compatTypeValue} sort=${intent.sort.id} genre=$nextGenre',
    );
    _searchDebounce?.cancel();
    _searchIdleTimer?.cancel();
    _searchFocusNode.unfocus();
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
      _searchDebounce?.cancel();
    }
    setState(() {
      _type = intent.type;
      _sort = intent.sort;
      _genre = nextGenre;
      _search = '';
      _searchExpanded = false;
      _searchFieldActive = false;
      _searchShellExpanded = false;
      _searchSuggestionsVisible = false;
      _showDecisionPrompt = false;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (_isDiscoveryTabSelected) {
      _pendingVisibleRefresh = false;
      _startConfigLoadIfNeeded();
      _primeOriginOptions();
      if (_hasDiscoverableContent) {
        _reload(preserveVisibleItems: false);
      }
    } else {
      _pendingVisibleRefresh = true;
    }
    return true;
  }

  String _normalizeDiscoveryGenre(String rawGenre) {
    final cleaned = rawGenre.trim();
    if (cleaned.isEmpty) return 'All genres';
    final lower = cleaned.toLowerCase();
    if (lower == 'sci-fi' || lower == 'sci fi' || lower == 'science fiction') {
      return 'Science Fiction';
    }
    if (lower == 'film-noir') return 'Film Noir';
    if (lower == 'sports') return 'Sport';
    if (lower == 'tv-movie' || lower == 'tv movie') return 'TV Movie';
    if (lower == 'reality-tv') return 'Reality-TV';
    if (lower == 'talk-show') return 'Talk-Show';
    if (lower == 'game-show') return 'Game-Show';
    return lower
        .split(RegExp(r'[\s_-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  void _handleVisualPreferenceChanged() {
    if (mounted) setState(() {});
  }

  void _restoreGreetingAnimationSoon() {
    Timer(const Duration(milliseconds: 280), () {
      if (mounted && !_animateGreeting) {
        setState(() => _animateGreeting = true);
      }
    });
  }

  void _scheduleContextCycle({Duration delay = const Duration(seconds: 3)}) {
    _contextCycleTimer?.cancel();
    _contextCycleTimer = Timer(delay, () {
      if (!mounted || _searchExpanded || !_greetingVisible) return;
      setState(() {
        _showDecisionPrompt = true;
        _decisionPrompt = _randomDecisionPrompt(_decisionPrompt);
      });
      _scheduleContextCycle(delay: const Duration(seconds: 5));
    });
  }

  void _closeSearchAfterSuggestions({required bool showDecisionPrompt}) {
    if (!_searchExpanded && !_searchFieldActive && !_searchShellExpanded)
      return;
    _searchIdleTimer?.cancel();
    _searchCloseTimer?.cancel();
    _contextCycleTimer?.cancel();
    _searchFocusNode.unfocus();
    final shouldDelay =
        _searchSuggestionsVisible && AppState.searchHistory.value.isNotEmpty;
    if (_searchSuggestionsVisible) {
      setState(() => _searchSuggestionsVisible = false);
    }
    _searchCloseTimer = Timer(
      shouldDelay ? const Duration(milliseconds: 520) : Duration.zero,
      () {
        if (!mounted) return;
        setState(() {
          _searchExpanded = false;
          _searchFieldActive = false;
          _searchShellExpanded = false;
          _searchSuggestionsVisible = false;
          _animateGreeting = false;
          _showDecisionPrompt = true;
          _decisionPrompt = _randomDecisionPrompt(_decisionPrompt);
          _greetingVisible = false;
          _greetingContextVisible = false;
        });
        Timer(const Duration(milliseconds: 460), () {
          if (!mounted || _searchExpanded) return;
          setState(() => _greetingVisible = true);
          Timer(const Duration(milliseconds: 120), () {
            if (mounted && !_searchExpanded) {
              setState(() => _greetingContextVisible = true);
            }
          });
          _restoreGreetingAnimationSoon();
          _scheduleContextCycle();
        });
      },
    );
  }

  void _dismissSearchOverlay() {
    final shouldShowDecisionPrompt = _searchController.text.trim().isEmpty;
    _closeSearchAfterSuggestions(showDecisionPrompt: shouldShowDecisionPrompt);
  }

  void _expandSearch() {
    _searchIdleTimer?.cancel();
    _searchCloseTimer?.cancel();
    _contextCycleTimer?.cancel();
    if (!_searchExpanded || _showDecisionPrompt) {
      setState(() {
        _animateGreeting = true;
        _searchExpanded = true;
        _searchFieldActive = false;
        _searchShellExpanded = false;
        _searchSuggestionsVisible = false;
        _greetingVisible = false;
        _greetingContextVisible = false;
        _showDecisionPrompt = false;
      });
    }
    Timer(const Duration(milliseconds: 120), () {
      if (mounted && _searchExpanded) {
        setState(() => _searchShellExpanded = true);
      }
    });
    Timer(const Duration(milliseconds: 460), () {
      if (mounted && _searchExpanded) {
        setState(() {
          _searchFieldActive = true;
          _searchSuggestionsVisible = true;
        });
        _searchFocusNode.requestFocus();
      }
    });
    _scheduleSearchRetract();
  }

  void _scheduleSearchRetract() {
    _searchIdleTimer?.cancel();
    _searchIdleTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted ||
          !_searchExpanded ||
          _searchController.text.trim().isNotEmpty) {
        return;
      }
      _closeSearchAfterSuggestions(showDecisionPrompt: true);
    });
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final pixels = position.pixels;
    final delta = pixels - _lastScrollOffset;
    if (delta.abs() > 2 && _searchExpanded) {
      _dismissSearchOverlay();
    }
    var nextControlsVisible = _controlsVisible;
    var nextShowScrollTop = _showScrollTop;

    if (pixels <= 18) {
      nextControlsVisible = true;
      nextShowScrollTop = false;
    } else {
      if (delta > 18 && pixels > 128) nextControlsVisible = false;
      if (delta < -12) nextControlsVisible = true;
      nextShowScrollTop = pixels > 520;
    }

    _lastScrollOffset = pixels;
    if (nextControlsVisible != _controlsVisible ||
        nextShowScrollTop != _showScrollTop) {
      setState(() {
        _controlsVisible = nextControlsVisible;
        _showScrollTop = nextShowScrollTop;
      });
    }

    final prefetchThreshold = max(720.0, position.viewportDimension * 1.15);
    final nearEnd = pixels >= position.maxScrollExtent - prefetchThreshold;
    final rearmBoundary = position.maxScrollExtent - (prefetchThreshold * 1.35);
    if (!nearEnd && pixels < rearmBoundary) {
      _nearEndArmed = true;
    }

    if (pixels < _nextAutoLoadPixels) return;
    if (_searchActive) return;
    if (_loading || !_hasMore || !_nearEndArmed) return;
    if (nearEnd) {
      _nearEndArmed = false;
      _nextAutoLoadPixels =
          pixels + max(320.0, position.viewportDimension * 0.55);
      if (!_pendingEndLoadLog) {
        _pendingEndLoadLog = true;
        DiagnosticLog.add(
          'catalog near end trigger type=${_type.compatTypeValue} sort=${_sort.id} skip=$_skip visible=${_visibleItems.length} maxScroll=${position.maxScrollExtent.toStringAsFixed(1)} pixels=${pixels.toStringAsFixed(1)} threshold=${prefetchThreshold.toStringAsFixed(1)} nextGate=${_nextAutoLoadPixels.toStringAsFixed(1)}',
        );
      }
      _loadMore();
    }
  }

  void _loadMoreIfStillNearEnd({required String reason}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_searchActive || _loading || !_hasMore) return;
      final position = _scrollController.position;
      final threshold = max(720.0, position.viewportDimension * 1.15);
      final nearEnd = position.pixels >= position.maxScrollExtent - threshold;
      if (!nearEnd) return;
      _nearEndArmed = true;
      _nextAutoLoadPixels = 0;
      DiagnosticLog.add(
        'catalog near end post-load trigger reason=$reason type=${_type.compatTypeValue} sort=${_sort.id} skip=$_skip visible=${_visibleItems.length} maxScroll=${position.maxScrollExtent.toStringAsFixed(1)} pixels=${position.pixels.toStringAsFixed(1)} threshold=${threshold.toStringAsFixed(1)}',
      );
      _loadMore();
    });
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    setState(() {
      _controlsVisible = true;
      _showScrollTop = false;
    });
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    final currentText = _searchController.text.trim();
    if (_searchExpanded && currentText.isEmpty) {
      _scheduleSearchRetract();
    } else {
      _searchIdleTimer?.cancel();
    }
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      final next = currentText;
      if (next == _search) return;
      DiagnosticLog.add(
        'search typed length=${next.length} type=${_type.compatTypeValue} sort=${_sort.id} genre=$_genre',
      );
      setState(() => _search = next);
      _reload(deepSearch: false, preserveVisibleItems: false);
    });
  }

  void _submitSearch(String value) {
    final next = value.trim();
    if (next.isEmpty) return;
    DiagnosticLog.add(
      'search submitted length=${next.length} type=${_type.compatTypeValue} sort=${_sort.id} genre=$_genre',
    );
    _searchDebounce?.cancel();
    AppState.addSearchHistory(next, recordTaste: AppState.hasCatalogSource);
    if (next != _search) {
      setState(() => _search = next);
    }
    _closeSearchAfterSuggestions(showDecisionPrompt: false);
    _reload(deepSearch: true, preserveVisibleItems: false);
  }

  void _selectSearchSuggestion(String value) {
    final next = value.trim();
    if (next.isEmpty) return;
    DiagnosticLog.add(
      'search suggestion selected length=${next.length} type=${_type.compatTypeValue} sort=${_sort.id} genre=$_genre previousLength=${_search.length}',
    );
    _searchDebounce?.cancel();
    _searchIdleTimer?.cancel();
    _searchController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _searchDebounce?.cancel();
    AppState.addSearchHistory(next, recordTaste: AppState.hasCatalogSource);
    setState(() {
      _search = next;
      _showDecisionPrompt = false;
    });
    _closeSearchAfterSuggestions(showDecisionPrompt: false);
    _reload(deepSearch: true, preserveVisibleItems: false);
  }

  Future<void> _openRandomCatalogItem() async {
    if (_randomPickLoading) return;
    setState(() => _randomPickLoading = true);
    final random = Random();
    CatalogItem? item = _randomLocalCatalogItem(random);

    try {
      if (item == null) {
        final types = [MediaType.movie, MediaType.series, MediaType.animation]
          ..shuffle(random);
        final sorts = [
          CatalogSort.top,
          CatalogSort.year,
          CatalogSort.imdbRating,
        ]..shuffle(random);

        for (var attempt = 0; attempt < 8 && item == null; attempt += 1) {
          final type = types[attempt % types.length];
          final sort = sorts[attempt % sorts.length];
          final skip = random.nextInt(32) * StreamApi.pageSize;
          try {
            DiagnosticLog.add(
              'random pick catalog attempt type=${type.compatTypeValue} sort=${sort.id} skip=$skip',
            );
            final result = await _api.catalog(
              type: type,
              sort: sort,
              skip: skip,
              genre: 'All genres',
            );
            final candidates = result.items
                .where(
                  (item) =>
                      !item.type.isLive &&
                      _catalogItemAllowedByMatureGate(item),
                )
                .toList();
            if (candidates.isNotEmpty) {
              item = candidates[random.nextInt(candidates.length)];
            }
          } catch (error) {
            DiagnosticLog.add('random pick catalog failed error=$error');
          }
        }
      }

      if (!mounted) return;
      if (item == null) {
        setState(() => _randomPickLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No picks yet. Try again soon.')),
        );
        return;
      }
      final selected = item;
      DiagnosticLog.add(
        'random pick opened id=${selected.id} type=${selected.type.compatTypeValue}',
      );
      setState(() => _randomPickLoading = false);
      Navigator.of(
        context,
      ).push(AppPageRoute<void>(builder: (_) => DetailsPage(item: selected)));
    } catch (_) {
      if (mounted) setState(() => _randomPickLoading = false);
      rethrow;
    }
  }

  CatalogItem? _randomLocalCatalogItem(Random random) {
    final visibleCandidates = _visibleItems
        .where((item) => !item.type.isLive)
        .toList();
    if (visibleCandidates.isNotEmpty) {
      return visibleCandidates[random.nextInt(visibleCandidates.length)];
    }
    final localCandidates = _items.where((item) => !item.type.isLive).toList();
    if (localCandidates.isNotEmpty) {
      return localCandidates[random.nextInt(localCandidates.length)];
    }
    return null;
  }

  Future<void> _reload({
    bool deepSearch = false,
    bool preserveVisibleItems = true,
  }) async {
    final localItems = _localCatalogItemsForBrowse();
    final preserveWarmSnapshot =
        preserveVisibleItems &&
        _reloadPriming &&
        _visibleItems.isNotEmpty &&
        localItems.isEmpty;
    _requestToken += 1;
    final activeOrigin = _effectiveOriginFor(_type);
    DiagnosticLog.add(
      'catalog reload type=${_type.compatTypeValue} sort=${_sort.id} genre=${_effectiveGenre(_latestConfig)} origin=${activeOrigin.code} scope=${_effectiveScopeFor(_type).displayLabel} search="$_search"',
    );
    setState(() {
      if (!preserveWarmSnapshot) {
        _items = localItems;
        _visibleItems = localItems;
      }
      _searchResultGroups = <MediaType, List<CatalogItem>>{};
      _skip = 0;
      _loading = false;
      _reloadPriming = AppState.hasCatalogSource;
      _hasMore = AppState.hasCatalogSource;
      _error = null;
      _nearEndArmed = true;
      _nextAutoLoadPixels = 0;
    });
    if (preserveWarmSnapshot) {
      DiagnosticLog.add(
        'catalog warm snapshot refresh allowed type=${_type.compatTypeValue}',
      );
    }
    _catalogPrefetchTimer?.cancel();
    if (!AppState.hasCatalogSource) {
      if (mounted) {
        setState(() {
          _hasMore = false;
          _loading = false;
          _reloadPriming = false;
        });
      }
      return;
    }
    DiagnosticLog.add(
      'discovery client fallback skipped reason=server_source_only',
    );
    if (_searchActive) {
      await _loadGroupedSearch(deepSearch: deepSearch);
      return;
    }
    await _loadMore(deepSearch: deepSearch);
  }

  Future<void> _handlePullRefresh() async {
    final refreshStopwatch = Stopwatch()..start();
    _refreshMessageTimer?.cancel();
    setState(() => _refreshMessageVisible = true);
    DiagnosticLog.add('catalog pull refresh started');
    await _reload();
    if (!mounted) return;
    DiagnosticLog.add('catalog pull refresh completed');
    DiagnosticLog.viewTiming(
      surface: 'catalog',
      state: 'interaction_ready',
      elapsed: refreshStopwatch.elapsed,
      mediaKind: _type.compatTypeValue,
      cacheStateBucket: 'network_or_unknown',
      refreshActionBucket: 'pull_to_refresh',
      itemCount: _visibleItems.length,
    );
    _refreshMessageTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _refreshMessageVisible = false);
    });
  }

  Future<void> _loadGroupedSearch({bool deepSearch = false}) async {
    if (!AppState.hasCatalogSource || !_searchActive) return;
    final requestToken = _requestToken;
    final query = _search;
    final types = _typeOptionsFor(_latestConfig);
    final timerKey = 'catalog:grouped-search:$requestToken';
    DiagnosticLog.start(
      timerKey,
      'catalog grouped search start length=${query.length} types=${types.map((type) => type.compatTypeValue).join("|")}',
    );
    setState(() {
      _loading = true;
      _error = null;
      _hasMore = false;
    });

    try {
      final results = await Future.wait<_CatalogSearchGroupResult>([
        for (final type in types)
          _loadSearchGroup(type, query: query, deepSearch: deepSearch),
      ]);
      if (!mounted || requestToken != _requestToken || query != _search) return;
      final groups = <MediaType, List<CatalogItem>>{};
      for (final result in results) {
        if (result.items.isEmpty) continue;
        groups[result.type] = result.items;
      }
      final promotedAnimationCount = _promoteAnimationTaggedSearchResults(
        groups,
      );
      final allItems = [for (final groupItems in groups.values) ...groupItems];
      setState(() {
        _searchResultGroups = groups;
        _items = _dedupeCatalogItems(allItems);
        _visibleItems = _items;
        _skip = 0;
        _hasMore = false;
        _reloadPriming = false;
        _pendingEndLoadLog = false;
      });
      _schedulePosterPrefetch(_visibleItems);
      DiagnosticLog.end(
        timerKey,
        'catalog grouped search ok groups=${groups.entries.map((entry) => "${entry.key.compatTypeValue}:${entry.value.length}").join("|")} total=${_visibleItems.length} animationPromoted=$promotedAnimationCount',
      );
    } catch (error) {
      if (!mounted || requestToken != _requestToken) return;
      DiagnosticLog.end(timerKey, 'catalog grouped search failed error=$error');
      setState(() {
        _error = error.toString();
        _reloadPriming = false;
        _pendingEndLoadLog = false;
      });
    } finally {
      if (mounted && requestToken == _requestToken) {
        setState(() {
          _loading = false;
          _reloadPriming = false;
        });
      }
    }
  }

  Future<_CatalogSearchGroupResult> _loadSearchGroup(
    MediaType type, {
    required String query,
    required bool deepSearch,
  }) async {
    try {
      final result = await _api.catalog(
        type: type,
        sort: CatalogSort.top,
        skip: 0,
        genre: 'All genres',
        search: query,
        deepSearch: deepSearch,
      );
      return _CatalogSearchGroupResult(
        type: type,
        items: _dedupeCatalogItems(result.items),
      );
    } catch (error) {
      DiagnosticLog.add(
        'catalog grouped search type failed type=${type.compatTypeValue} error=$error',
      );
      return _CatalogSearchGroupResult(type: type, items: const []);
    }
  }

  Future<void> _loadMore({bool deepSearch = false}) async {
    if (!AppState.hasCatalogSource) return;
    if (_searchActive) return;
    if (_loading || !_hasMore) return;
    final requestToken = _requestToken;
    final currentSkip = _skip;
    final activeYear = _activeYearFilter;
    final activeGenre = _effectiveGenre(_latestConfig);
    final activeOrigin = _effectiveOriginFor(_type);
    final activeScope = _effectiveScopeFor(_type);
    final timerKey = 'catalog:${requestToken}:$currentSkip';
    DiagnosticLog.start(
      timerKey,
      'catalog loadMore type=${_type.compatTypeValue} sort=${_sort.id} year=${activeYear ?? ""} genre=$activeGenre origin=${activeOrigin.code} scope=${activeScope.displayLabel} search="$_search" skip=$currentSkip',
    );
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _api.catalog(
        type: _type,
        sort: _search.isNotEmpty ? CatalogSort.top : _sort,
        skip: currentSkip,
        genre: activeGenre,
        year: activeYear,
        originCountry: activeOrigin.code,
        company: activeScope.company,
        collection: activeScope.collection,
        search: _search,
        deepSearch: deepSearch,
        preferDefaultCatalog:
            activeYear != null || !activeOrigin.isAll || !activeScope.isAll,
      );
      if (!mounted || requestToken != _requestToken) return;
      final resultItems = _catalogItemsForRequestedType(result.items, _type);
      DiagnosticLog.end(
        timerKey,
        'catalog loadMore ok count=${resultItems.length} first=${_diagnosticCatalogSample(resultItems)}',
      );
      final resultHasMore = resultItems.isNotEmpty
          ? (result.hasMore ?? true)
          : false;
      setState(() {
        _items = _catalogItemsForDisplayOrder(
          _appendCatalogItems(_items, resultItems),
          _sort,
        );
        _visibleItems = _items;
        _skip = currentSkip + (result.skipDelta ?? StreamApi.pageSize);
        _hasMore = resultHasMore;
        _nearEndArmed = true;
        _nextAutoLoadPixels = 0;
        _reloadPriming = false;
        _pendingEndLoadLog = false;
      });
      _schedulePosterPrefetch(resultItems);
      _scheduleCatalogPrefetch(
        sort: _search.isNotEmpty ? CatalogSort.top : _sort,
        year: activeYear,
        originCountry: activeOrigin.code,
        scope: activeScope,
        nextSkip: _skip,
        stride: result.skipDelta ?? StreamApi.pageSize,
        deepSearch: deepSearch,
      );
      DiagnosticLog.add(
        'catalog list updated total=${_visibleItems.length} nextSkip=$_skip hasMore=$_hasMore received=${resultItems.length}',
      );
      if (currentSkip == 0 && _search.isEmpty && _visibleItems.isNotEmpty) {
        _saveDiscoveryWarmSnapshot();
        DiagnosticLog.add(
          'discovery client fallback save skipped reason=server_source_only',
        );
      }
      if (_hasMore) {
        _loadMoreIfStillNearEnd(reason: 'page_appended');
      }
    } catch (error) {
      if (!mounted || requestToken != _requestToken) return;
      DiagnosticLog.end(timerKey, 'catalog loadMore failed error=$error');
      setState(() {
        _error = error.toString();
        if (currentSkip == 0) {
          _items = const <CatalogItem>[];
          _visibleItems = const <CatalogItem>[];
          _skip = 0;
          _hasMore = false;
        }
        _reloadPriming = false;
        _pendingEndLoadLog = false;
      });
    } finally {
      if (mounted && requestToken == _requestToken) {
        setState(() {
          _loading = false;
          _reloadPriming = false;
        });
      }
    }
  }

  String _diagnosticCatalogSample(List<CatalogItem> items) {
    if (items.isEmpty) return 'none';
    return items
        .take(5)
        .map((item) {
          final title = item.name.replaceAll('"', "'");
          return '${item.type.compatTypeValue}:${item.id}:$title';
        })
        .join(' | ');
  }

  void _schedulePosterPrefetch(List<CatalogItem> items) {
    if (items.isEmpty || !mounted) return;
    if (AppState.batteryDataSettings.value.batterySaverPlayback) {
      DiagnosticLog.add('catalog poster prefetch skipped reason=battery_saver');
      return;
    }
    Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (AppState.isInInteractionQuietWindow) return;
      final posters = items
          .map((item) => item.poster)
          .whereType<String>()
          .where((poster) => poster.isNotEmpty)
          .take(6)
          .toList(growable: false);
      if (posters.isEmpty) return;
      DiagnosticLog.add(
        'catalog poster prefetch count=${posters.length} type=${_type.compatTypeValue} skip=${_skip}',
      );
      for (final poster in posters) {
        unawaited(
          precacheImage(
            ResizeImage.resizeIfNeeded(320, null, NetworkImage(poster)),
            context,
            onError: (error, stackTrace) {
              DiagnosticLog.add(
                'catalog poster prefetch skipped type=${_type.compatTypeValue} error=${error.runtimeType}',
              );
            },
          ),
        );
      }
    });
  }

  void _scheduleCatalogPrefetch({
    required CatalogSort sort,
    String? year,
    required String originCountry,
    required _CatalogScopeOption scope,
    required int nextSkip,
    required int stride,
    required bool deepSearch,
  }) {
    _catalogPrefetchTimer?.cancel();
    if (!_hasMore || !mounted) return;
    if (AppState.batteryDataSettings.value.batterySaverPlayback) {
      DiagnosticLog.add('catalog prefetch skipped reason=battery_saver');
      return;
    }
    final requestType = _type;
    final requestSearch = _search;
    final requestGenre = _effectiveGenre(_latestConfig);
    _catalogPrefetchTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted || _loading || !_hasMore) return;
      if (AppState.isInInteractionQuietWindow) return;
      unawaited(() async {
        final prefetched = await _api.prefetchCatalogPage(
          type: requestType,
          sort: sort,
          skip: nextSkip,
          genre: requestGenre,
          year: year,
          originCountry: originCountry,
          company: scope.company,
          collection: scope.collection,
          search: requestSearch,
          deepSearch: deepSearch,
          preferDefaultCatalog:
              (year != null && year.trim().isNotEmpty) ||
              originCountry.isNotEmpty ||
              !scope.isAll,
        );
        if (!mounted || prefetched == null) return;
        final canLookFurther =
            prefetched.hasMore == true &&
            prefetched.items.length >= max(1, stride ~/ 2);
        if (!canLookFurther) return;
        final secondSkip = nextSkip + stride;
        DiagnosticLog.add(
          'catalog prefetch second-page scheduled type=${requestType.compatTypeValue} sort=${sort.id} skip=$secondSkip baseSkip=$nextSkip',
        );
        await _api.prefetchCatalogPage(
          type: requestType,
          sort: sort,
          skip: secondSkip,
          genre: requestGenre,
          year: year,
          originCountry: originCountry,
          company: scope.company,
          collection: scope.collection,
          search: requestSearch,
          deepSearch: deepSearch,
          preferDefaultCatalog:
              (year != null && year.trim().isNotEmpty) ||
              originCountry.isNotEmpty ||
              !scope.isAll,
        );
      }());
    });
  }

  void _setType(MediaType type) {
    if (_type == type) return;
    if (type == MediaType.liveTv && _activeOriginCode().isNotEmpty) {
      DiagnosticLog.add('filter type locked liveTv reason=origin_active');
      return;
    }
    DiagnosticLog.add(
      'filter type changed ${_type.compatTypeValue} -> ${type.compatTypeValue}',
    );
    _searchDebounce?.cancel();
    final carriedOrigin = _activeOriginCode();
    setState(() {
      final preference = AppState.browseFilterPreference.value;
      _type = type;
      final preferredSort = preference.sortFor(type);
      _sort = _sortOptionsFor(type).contains(preferredSort)
          ? preferredSort
          : CatalogSort.top;
      final allowedGenres = _filterOptionsFor(
        _latestConfig,
        type: type,
        sort: _sort,
      );
      final preferredGenre = preference.genreFor(type);
      _genre = allowedGenres.contains(preferredGenre)
          ? preferredGenre
          : allowedGenres.first;
      final preferredYear = preference.yearFor(type);
      _scope = const _CatalogScopeOption.all();
      final years = _yearOptions(null);
      _year = years.contains(preferredYear) ? preferredYear : years.first;
      final preferredOrigin = carriedOrigin.isNotEmpty
          ? carriedOrigin
          : preference.originFor(type);
      _origin = _originOptionForCode(type, preferredOrigin);
    });
    _primeOriginOptions();
    _rememberBrowseFilterPreference();
    _reload(preserveVisibleItems: false);
  }

  void _setSort(CatalogSort sort, {List<String>? years}) {
    if (!_sortOptionsFor(_type).contains(sort)) {
      DiagnosticLog.add(
        'filter sort locked ${sort.id} reason=unsupported type=${_type.compatTypeValue}',
      );
      return;
    }
    if (_sort == sort) return;
    DiagnosticLog.add('filter sort changed ${_sort.id} -> ${sort.id}');
    final carriedOrigin = _activeOriginCode();
    setState(() {
      _sort = sort;
      final allowedYears = years ?? _yearOptions(_latestConfig, sort: sort);
      if (!allowedYears.contains(_year)) _year = allowedYears.first;
      final allowedGenres = _filterOptionsFor(_latestConfig, sort: sort);
      if (!allowedGenres.contains(_genre)) _genre = allowedGenres.first;
      _origin = _originOptionForCode(_type, carriedOrigin);
    });
    _primeOriginOptions();
    _rememberBrowseFilterPreference();
    _reload(preserveVisibleItems: false);
  }

  void _setYear(String year) {
    if (_year == year) return;
    DiagnosticLog.add('filter year changed $_year -> $year');
    final carriedOrigin = _activeOriginCode();
    setState(() {
      _year = year;
      _origin = _originOptionForCode(_type, carriedOrigin);
    });
    _primeOriginOptions();
    _rememberBrowseFilterPreference();
    _reload(preserveVisibleItems: false);
  }

  void _setGenre(String genre) {
    if (_genre == genre) return;
    DiagnosticLog.add('filter genre changed $_genre -> $genre');
    final carriedOrigin = _activeOriginCode();
    setState(() {
      _genre = genre;
      _origin = _originOptionForCode(_type, carriedOrigin);
    });
    _primeOriginOptions();
    _rememberBrowseFilterPreference();
    _reload(preserveVisibleItems: false);
  }

  void _setOrigin(_CatalogOriginOption origin) {
    if (_origin == origin) return;
    DiagnosticLog.add(
      'filter origin changed ${_origin.code} -> ${origin.code}',
    );
    setState(() => _origin = origin);
    _rememberBrowseFilterPreference();
    _reload(preserveVisibleItems: false);
  }

  void _setScope(_CatalogScopeOption scope) {
    if (_scope == scope) return;
    DiagnosticLog.add(
      'filter scope changed ${_scope.displayLabel} -> ${scope.displayLabel}',
    );
    setState(() {
      _scope = scope;
      if (scope.kind == _CatalogScopeKind.collection) {
        _type = MediaType.movie;
        _genre = 'All genres';
      }
    });
    _reload(preserveVisibleItems: false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!AppState.preferencesReady.value) {
      return Scaffold(
        body: SafeArea(
          left: !JuicrVisual.compactLandscape(context),
          child: CustomScrollView(
            physics: const NeverScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 160)),
              _PosterGridSkeleton(type: _type),
            ],
          ),
        ),
      );
    }
    return FutureBuilder<StreamConfig?>(
      future: _configFuture,
      builder: (context, configSnapshot) {
        final config = configSnapshot.data ?? _latestConfig;
        final configLoading =
            configSnapshot.connectionState != ConnectionState.done;
        final typeOptions = _typeOptionsFor(config);
        if (!configLoading && !typeOptions.contains(_type)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || typeOptions.contains(_type)) return;
            setState(() {
              _type = typeOptions.first;
              _genre = 'All genres';
            });
            _reload(preserveVisibleItems: false);
          });
        }
        if (!configLoading &&
            _startupSettled &&
            _isDiscoveryTabSelected &&
            !AppState.isInInteractionQuietWindow) {
          _ensureDefaultYearOptions();
        }
        final filterOptions = _filterOptionsFor(config);
        final scopeOptions = _scopeOptionsFor(_type);
        final activeScope = _effectiveScopeFor(_type);
        final genreOptionsByType = <MediaType, List<String>>{
          MediaType.movie: _movieGenreOptions(config),
          MediaType.series: _seriesGenreOptions(config),
          MediaType.animation: _animationGenreOptions(config),
          MediaType.liveTv: _liveTvGenreOptions(config, sort: _sort),
          MediaType.music: _musicGenreOptions(config),
          MediaType.nsfw: _nsfwGenreOptions(config),
        };
        final activeGenre = _effectiveGenre(config);
        final yearOptions = _yearOptions(config);
        final yearSelectionAvailable = _yearSelectionAvailable(config);
        final catalogSettling = configLoading || _isYearFilterSettling(config);
        final visibleItems = _visibleItems;
        final suggestions = AppState.searchHistory.value
            .take(AppState.searchHistoryLimit)
            .toList();
        final showSearchContext =
            _search.isNotEmpty && !_searchExpanded && _controlsVisible;
        final showRefreshContext =
            _refreshMessageVisible && !_searchExpanded && _controlsVisible;
        final showHeaderContext = showSearchContext || showRefreshContext;
        final browseCardVisible = _controlsVisible && !_searchActive;
        final textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1.0, 1.3);
        final compactLandscape = JuicrVisual.compactLandscape(context);
        final browseCardHeight =
            (compactLandscape ? 68.0 : 78.0) +
            ((textScale - 1.0) * 72.0).clamp(
              0.0,
              compactLandscape ? 8.0 : 12.0,
            );
        final suggestionsVisible =
            _searchExpanded &&
            _searchFieldActive &&
            _searchSuggestionsVisible &&
            suggestions.isNotEmpty;
        final headerContextHeight = showSearchContext
            ? 50.0
            : showRefreshContext
            ? 32.0
            : 0.0;
        final headerContextSlotHeight = showSearchContext ? 44.0 : 22.0;
        final baseHeaderHeight =
            (compactLandscape ? 66.0 : 76.0) +
            (browseCardVisible
                ? browseCardHeight + (compactLandscape ? 4.0 : 6.0)
                : 0.0) +
            headerContextHeight;
        final suggestionsHeight = suggestionsVisible
            ? 88.0 + (suggestions.length * 40.0).clamp(0.0, 240.0)
            : 0.0;
        final headerHeight = max(baseHeaderHeight, suggestionsHeight);
        final artworkMotion =
            AppState.artworkMotion.value &&
            !AppState.batteryDataSettings.value.batterySaverPlayback;
        final headerAnimationDuration = !artworkMotion
            ? Duration.zero
            : showRefreshContext
            ? const Duration(milliseconds: 220)
            : Duration(milliseconds: _controlsVisible ? 520 : 380);
        final headerAnimationCurve = _controlsVisible
            ? Curves.easeOutCubic
            : Curves.easeInOutCubicEmphasized;

        final colorScheme = Theme.of(context).colorScheme;
        if (!_hasDiscoverableContent) {
          return Scaffold(
            body: SafeArea(
              left: !JuicrVisual.compactLandscape(context),
              child: const CatalogEmptyState(title: 'Discovery'),
            ),
          );
        }

        return Scaffold(
          floatingActionButton: AnimatedScale(
            scale: _showScrollTop ? 1 : 0.82,
            duration: artworkMotion
                ? const Duration(milliseconds: 180)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: _showScrollTop ? 1 : 0,
              duration: artworkMotion
                  ? const Duration(milliseconds: 180)
                  : Duration.zero,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: Semantics(
                  button: true,
                  enabled: _showScrollTop,
                  label: 'Back to top',
                  child: ExcludeSemantics(
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _showScrollTop ? _scrollToTop : null,
                      child: Tooltip(
                        message: 'Back to top',
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: JuicrVisual.elevatedCircleDecoration(
                            colorScheme,
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.9),
                            shadowAlpha: 0.14,
                            glowAlpha: 0.03,
                          ),
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            size: 22,
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.92,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          body: SafeArea(
            left: !JuicrVisual.compactLandscape(context),
            child: Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _handlePullRefresh,
                  edgeOffset: headerHeight,
                  displacement: 24,
                  child: CustomScrollView(
                    controller: _scrollController,
                    cacheExtent: _type == MediaType.liveTv ? 420 : 900,
                    slivers: [
                      SliverToBoxAdapter(
                        child: AnimatedContainer(
                          duration: headerAnimationDuration,
                          curve: headerAnimationCurve,
                          height: headerHeight,
                        ),
                      ),
                      if (_error != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                            child: AppReveal(
                              child: _ErrorBanner(
                                message: _error!,
                                onRetry: _loadMore,
                              ),
                            ),
                          ),
                        ),
                      if (_items.isEmpty &&
                          (_loading || _reloadPriming || catalogSettling))
                        _PosterGridSkeleton(type: _type)
                      else if (visibleItems.isEmpty)
                        SliverFillRemaining(
                          child: AppReveal(
                            child: CatalogEmptyState(
                              searching: _search.isNotEmpty,
                              filtered: AppState.hasCatalogSource,
                            ),
                          ),
                        )
                      else if (_searchActive) ...[
                        ValueListenableBuilder<String>(
                          valueListenable: AppState.homeDensity,
                          builder: (context, density, _) {
                            return ValueListenableBuilder<
                              Map<String, ContinueWatchingEntry>
                            >(
                              valueListenable: AppState.continueWatching,
                              builder: (context, progress, __) {
                                final progressByItemId =
                                    _continueWatchingByItemId(progress);
                                return SliverMainAxisGroup(
                                  slivers: [
                                    for (final entry
                                        in _searchResultGroups.entries)
                                      _CatalogSearchResultSection(
                                        api: _api,
                                        type: entry.key,
                                        items: entry.value,
                                        density: density,
                                        progressByItemId: progressByItemId,
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                            child: Center(
                              child: _loading
                                  ? const SizedBox.square(
                                      dimension: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                      ),
                                    )
                                  : Text(
                                      'End of search results.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.54),
                                          ),
                                    ),
                            ),
                          ),
                        ),
                      ] else ...[
                        ValueListenableBuilder<String>(
                          valueListenable: AppState.homeDensity,
                          builder: (context, density, _) {
                            return ValueListenableBuilder<
                              Map<String, ContinueWatchingEntry>
                            >(
                              valueListenable: AppState.continueWatching,
                              builder: (context, progress, __) {
                                final progressByItemId =
                                    _continueWatchingByItemId(progress);
                                final spacing = _catalogGridSpacing(density);
                                return SliverPadding(
                                  padding: EdgeInsets.fromLTRB(
                                    compactLandscape ? 14 : 18,
                                    0,
                                    compactLandscape ? 14 : 18,
                                    compactLandscape ? 12 : 18,
                                  ),
                                  sliver: SliverGrid(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: _catalogGridColumns(
                                            _type,
                                            density,
                                            compactLandscape: compactLandscape,
                                          ),
                                          crossAxisSpacing: spacing,
                                          mainAxisSpacing: spacing,
                                          childAspectRatio:
                                              _type == MediaType.liveTv
                                              ? 1.45
                                              : 2 / 3,
                                        ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final item = visibleItems[index];
                                        final entry = progressByItemId[item.id];
                                        return _PosterTile(
                                          api: _api,
                                          item: item,
                                          index: index,
                                          entry: entry,
                                          showReleaseDateBadge:
                                              _sort == CatalogSort.upcoming,
                                        );
                                      },
                                      childCount: visibleItems.length,
                                      addAutomaticKeepAlives: false,
                                      addRepaintBoundaries: true,
                                      addSemanticIndexes: false,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                            child: Center(
                              child: _loading
                                  ? const SizedBox.square(
                                      dimension: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                      ),
                                    )
                                  : !_hasMore
                                  ? Text(
                                      'You\'ve reached the end.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.54),
                                          ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_searchExpanded)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _dismissSearchOverlay,
                    ),
                  ),
                _CatalogHeaderPanel(
                  height: headerHeight,
                  browseVisible: browseCardVisible,
                  greeting: _homeGreeting,
                  prompt: _homePrompt,
                  decisionPrompt: _decisionPrompt,
                  decisionPromptVisible: _showDecisionPrompt,
                  randomPickLoading: _randomPickLoading,
                  searchExpanded: _searchExpanded,
                  searchFieldActive: _searchFieldActive,
                  searchShellExpanded: _searchShellExpanded,
                  searchSuggestionsVisible: _searchSuggestionsVisible,
                  greetingVisible: _greetingVisible,
                  greetingContextVisible: _greetingContextVisible,
                  animateGreeting: _animateGreeting,
                  searchQuery: _search,
                  showSearchContext: showSearchContext,
                  showRefreshContext: showRefreshContext,
                  headerContextSlotHeight: headerContextSlotHeight,
                  suggestions: suggestions,
                  searchController: _searchController,
                  searchFocusNode: _searchFocusNode,
                  onSubmitted: _submitSearch,
                  onClearSearch: () => _clearSearch(keepSearchOpen: true),
                  onClearSearchContext: () =>
                      _clearSearch(keepSearchOpen: false),
                  onSearchTap: _expandSearch,
                  onRandomPick: _openRandomCatalogItem,
                  onSuggestionSelected: _selectSearchSuggestion,
                  browseCard: SizedBox(
                    height: browseCardHeight,
                    child: _BrowseControlCard(
                      type: _type,
                      types: typeOptions,
                      sort: _sort,
                      year: _year,
                      genre: activeGenre,
                      origin: _effectiveOriginFor(_type),
                      scope: activeScope,
                      genres: filterOptions,
                      genreOptionsByType: genreOptionsByType,
                      originOptions: _originOptionsFor(_type),
                      scopeOptions: scopeOptions,
                      years: yearOptions,
                      yearSelectionAvailable: yearSelectionAvailable,
                      yearsForSort: (sort) => _yearOptions(config, sort: sort),
                      yearSelectionAvailableForSort: (sort) =>
                          _yearSelectionAvailable(config, sort: sort),
                      onOpenBrowseSheet: () => _openBrowseSheet(context),
                      onTypeChanged: _setType,
                      onSortChanged: _setSort,
                      onYearChanged: _setYear,
                      onGenreChanged: _setGenre,
                      onOriginChanged: _setOrigin,
                      onScopeChanged: _setScope,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}

List<String> _withAllGenres(List<String> genres) {
  final cleaned = _dedupeCatalogGenres(genres);
  if (cleaned.any((genre) => genre.toLowerCase() == 'all genres')) {
    return cleaned;
  }
  return ['All genres', ...cleaned];
}

List<String> _withAllCountries(List<String> countries) {
  final cleaned = _dedupeCatalogGenres(countries);
  if (cleaned.any((country) => country.toLowerCase() == 'all countries')) {
    return cleaned;
  }
  return ['All countries', ...cleaned];
}

List<String> _mergedCatalogGenres(
  List<String> baseGenres,
  List<String>? remoteGenres,
) {
  return _withAllGenres([
    ...baseGenres.where((genre) => genre.toLowerCase() != 'all genres'),
    ...?remoteGenres,
  ]);
}

List<String> _dedupeCatalogGenres(Iterable<String> genres) {
  final seen = <String>{};
  final values = <String>[];
  for (final raw in genres) {
    final display = _catalogGenreDisplay(raw);
    final key = display.toLowerCase();
    if (display.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    values.add(display);
  }
  return values;
}

String _catalogGenreDisplay(String raw) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return '';
  final lower = cleaned.toLowerCase();
  if (lower == 'all genres') return 'All genres';
  if (lower == 'sci-fi' || lower == 'sci fi' || lower == 'science fiction') {
    return 'Science Fiction';
  }
  if (lower == 'film-noir') return 'Film Noir';
  if (lower == 'sports') return 'Sport';
  if (lower == 'tv-movie' || lower == 'tv movie') return 'TV Movie';
  if (lower == 'reality-tv') return 'Reality-TV';
  if (lower == 'talk-show') return 'Talk-Show';
  if (lower == 'game-show') return 'Game-Show';
  return lower
      .split(RegExp(r'[\s_-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

List<CatalogSort> _sortOptionsFor(MediaType type) {
  if (type == MediaType.liveTv) {
    return const [CatalogSort.top, CatalogSort.newest, CatalogSort.imdbRating];
  }
  if (type == MediaType.music || type == MediaType.nsfw) {
    return const [CatalogSort.top];
  }
  if (type == MediaType.movie) {
    return const [
      CatalogSort.top,
      CatalogSort.nowPlaying,
      CatalogSort.topRated,
      CatalogSort.upcoming,
    ];
  }
  if (type == MediaType.series) {
    return const [
      CatalogSort.top,
      CatalogSort.airingToday,
      CatalogSort.onTv,
      CatalogSort.topRated,
    ];
  }
  if (type == MediaType.animation) {
    return const [CatalogSort.top, CatalogSort.onTv];
  }
  return const [CatalogSort.top];
}

int _promoteAnimationTaggedSearchResults(
  Map<MediaType, List<CatalogItem>> groups,
) {
  final seriesItems = groups[MediaType.series];
  if (seriesItems == null || seriesItems.isEmpty) return 0;
  final animationItems = groups[MediaType.animation] ?? const <CatalogItem>[];
  final animationKeys = {
    for (final item in animationItems) _catalogSearchIdentityKey(item),
  };
  final promoted = <CatalogItem>[];
  final remainingSeries = <CatalogItem>[];
  for (final item in seriesItems) {
    if (_isAnimationTaggedCatalogItem(item)) {
      final animationItem = item.withType(MediaType.animation);
      if (animationKeys.add(_catalogSearchIdentityKey(animationItem))) {
        promoted.add(animationItem);
      }
    } else {
      remainingSeries.add(item);
    }
  }
  if (promoted.isEmpty) return 0;
  groups[MediaType.series] = remainingSeries;
  groups[MediaType.animation] = _dedupeCatalogItems([
    ...animationItems,
    ...promoted,
  ]);
  if (remainingSeries.isEmpty) {
    groups.remove(MediaType.series);
  }
  return promoted.length;
}

bool _isAnimationTaggedCatalogItem(CatalogItem item) {
  return item.genres.any((genre) {
    final normalized = genre.trim().toLowerCase();
    return normalized == 'animation';
  });
}

String _catalogSearchIdentityKey(CatalogItem item) {
  final normalizedName = item.name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  return [
    normalizedName,
    item.year ?? '',
    item.tmdbId == null ? '' : 'tmdb:${item.tmdbId}',
    item.id,
  ].join('|');
}

List<CatalogItem> _dedupeCatalogItems(List<CatalogItem> items) {
  final seen = <String>{};
  final posterIndexes = <String, int>{};
  final deduped = <CatalogItem>[];
  for (final item in items) {
    if (!_catalogItemAllowedByMatureGate(item)) continue;
    final normalizedName = item.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    if (item.type == MediaType.liveTv) {
      final channelKey = '${item.type.compatTypeValue}|${item.id}';
      if (seen.add(channelKey) && normalizedName.isNotEmpty) {
        deduped.add(item);
      }
      continue;
    }
    final titleKey = [
      item.type.compatTypeValue,
      normalizedName,
      item.year ?? '',
    ].join('|');
    final tmdbKey = item.tmdbId == null
        ? null
        : [item.type.compatTypeValue, 'tmdb:${item.tmdbId}'].join('|');
    final posterKey = _normalizedPosterKey(item);
    if (seen.contains(titleKey) ||
        (tmdbKey != null && seen.contains(tmdbKey))) {
      continue;
    }

    final posterIndex = posterKey == null ? null : posterIndexes[posterKey];
    final similarPosterIndex =
        posterIndex ??
        deduped.indexWhere((existing) => _looksLikeSamePoster(item, existing));
    if (similarPosterIndex >= 0) {
      final existing = deduped[similarPosterIndex];
      if (_preferCatalogItem(item, existing)) {
        deduped[similarPosterIndex] = item;
      }
      seen.add(titleKey);
      if (tmdbKey != null) {
        seen.add(tmdbKey);
      }
      continue;
    }

    seen.add(titleKey);
    if (tmdbKey != null) {
      seen.add(tmdbKey);
    }
    if (posterKey != null) {
      posterIndexes[posterKey] = deduped.length;
    }
    if (normalizedName.isNotEmpty) {
      deduped.add(item);
    }
  }
  return deduped;
}

List<CatalogItem> _catalogItemsForRequestedType(
  List<CatalogItem> items,
  MediaType type,
) {
  return [
    for (final item in items)
      if (_catalogItemMatchesRequestedType(item, type)) item,
  ];
}

bool _catalogItemMatchesRequestedType(CatalogItem item, MediaType type) {
  if (type == MediaType.liveTv) return item.type == MediaType.liveTv;
  if (type == MediaType.music) return item.type == MediaType.music;
  if (type == MediaType.nsfw) return item.type == MediaType.nsfw;
  if (item.type.isLive) return false;
  return item.type == type;
}

List<CatalogItem> _appendCatalogItems(
  List<CatalogItem> existing,
  List<CatalogItem> incoming,
) {
  if (existing.isEmpty) return _dedupeCatalogItems(incoming);
  if (incoming.isEmpty) return existing;

  final deduped = [
    for (final item in existing)
      if (_catalogItemAllowedByMatureGate(item)) item,
  ];
  final seen = <String>{};
  final posterIndexes = <String, int>{};

  void indexItem(CatalogItem item, int index) {
    final normalizedName = item.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    if (item.type == MediaType.liveTv) {
      seen.add('${item.type.compatTypeValue}|${item.id}');
      return;
    }
    final titleKey = [
      item.type.compatTypeValue,
      normalizedName,
      item.year ?? '',
    ].join('|');
    seen.add(titleKey);
    if (item.tmdbId != null) {
      seen.add('${item.type.compatTypeValue}|tmdb:${item.tmdbId}');
    }
    final posterKey = _normalizedPosterKey(item);
    if (posterKey != null) {
      posterIndexes[posterKey] = index;
    }
  }

  for (var index = 0; index < deduped.length; index += 1) {
    indexItem(deduped[index], index);
  }

  for (final item in incoming) {
    if (!_catalogItemAllowedByMatureGate(item)) continue;
    final normalizedName = item.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    if (normalizedName.isEmpty) continue;

    if (item.type == MediaType.liveTv) {
      final channelKey = '${item.type.compatTypeValue}|${item.id}';
      if (seen.add(channelKey)) {
        deduped.add(item);
      }
      continue;
    }

    final titleKey = [
      item.type.compatTypeValue,
      normalizedName,
      item.year ?? '',
    ].join('|');
    final tmdbKey = item.tmdbId == null
        ? null
        : '${item.type.compatTypeValue}|tmdb:${item.tmdbId}';
    if (seen.contains(titleKey) ||
        (tmdbKey != null && seen.contains(tmdbKey))) {
      continue;
    }

    final posterKey = _normalizedPosterKey(item);
    final posterIndex = posterKey == null ? null : posterIndexes[posterKey];
    final similarPosterIndex =
        posterIndex ??
        deduped.indexWhere(
          (existingItem) => _looksLikeSamePoster(item, existingItem),
        );
    if (similarPosterIndex >= 0) {
      final existingItem = deduped[similarPosterIndex];
      if (_preferCatalogItem(item, existingItem)) {
        deduped[similarPosterIndex] = item;
        if (posterKey != null) {
          posterIndexes[posterKey] = similarPosterIndex;
        }
      }
      seen.add(titleKey);
      if (tmdbKey != null) {
        seen.add(tmdbKey);
      }
      continue;
    }

    seen.add(titleKey);
    if (tmdbKey != null) {
      seen.add(tmdbKey);
    }
    if (posterKey != null) {
      posterIndexes[posterKey] = deduped.length;
    }
    deduped.add(item);
  }

  return deduped;
}

List<CatalogItem> _catalogItemsForDisplayOrder(
  List<CatalogItem> items,
  CatalogSort sort,
) {
  return items;
}

int _compareCatalogUpcomingReleaseDate(CatalogItem left, CatalogItem right) {
  final leftDate = _catalogUpcomingReleaseSortDate(left);
  final rightDate = _catalogUpcomingReleaseSortDate(right);
  if (leftDate == null && rightDate == null) {
    return _catalogQualityScore(right).compareTo(_catalogQualityScore(left));
  }
  if (leftDate == null) return 1;
  if (rightDate == null) return -1;
  final dateCompare = leftDate.compareTo(rightDate);
  if (dateCompare != 0) return dateCompare;
  return _catalogQualityScore(right).compareTo(_catalogQualityScore(left));
}

DateTime? _catalogUpcomingReleaseSortDate(CatalogItem item) {
  final rawDate = item.releaseDate?.trim();
  if (rawDate == null || rawDate.isEmpty) return null;
  final date = DateTime.tryParse(rawDate);
  if (date == null) return null;
  return DateTime(date.year, date.month, date.day);
}

bool _catalogItemAllowedByMatureGate(CatalogItem item) {
  return AppState.showMatureContent.value || !item.hasMatureContentSignal;
}

Map<String, ContinueWatchingEntry> _continueWatchingByItemId(
  Map<String, ContinueWatchingEntry> progress,
) {
  final indexed = <String, ContinueWatchingEntry>{};
  for (final entry in progress.values) {
    if (!AppState.isDisplayableContinueEntry(entry)) continue;
    indexed[entry.item.id] = entry;
  }
  return indexed;
}

String? _normalizedPosterKey(CatalogItem item) {
  final poster = item.poster?.trim();
  if (poster == null || poster.isEmpty) return null;
  final decodedPoster = Uri.decodeFull(poster).toLowerCase();
  final parsed = Uri.tryParse(decodedPoster);
  if (parsed == null) {
    return '${item.type.compatTypeValue}|${_posterSignature(decodedPoster)}';
  }
  final path = parsed.path
      .replaceAll(RegExp(r'/w\d+/', caseSensitive: false), '/')
      .replaceAll(RegExp(r'/h\d+/', caseSensitive: false), '/')
      .replaceAll(RegExp(r'/original/', caseSensitive: false), '/')
      .replaceAll(RegExp(r'/resize/[^/]+/', caseSensitive: false), '/')
      .replaceAll(RegExp(r'/\d+x\d+/'), '/');
  final signature = _posterSignature(path);
  if (signature.isEmpty) return null;
  return '${item.type.compatTypeValue}|$signature';
}

bool _preferCatalogItem(CatalogItem candidate, CatalogItem existing) {
  return _catalogQualityScore(candidate) > _catalogQualityScore(existing);
}

int _catalogQualityScore(CatalogItem item) {
  return [
    if (item.tmdbId != null) 8,
    if (item.background != null && item.background!.isNotEmpty) 5,
    if (item.imdbRating != null && item.imdbRating!.isNotEmpty) 4,
    if (item.description != null && item.description!.isNotEmpty) 3,
    item.genres.length.clamp(0, 4),
    item.name.length.clamp(0, 48),
  ].fold<int>(0, (total, value) => total + value);
}

String _posterSignature(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'\.(jpg|jpeg|png|webp).*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  if (cleaned.isEmpty) return '';
  final parts = cleaned
      .split(RegExp(r'\s+'))
      .where((part) => part.length > 2)
      .toList();
  if (parts.isEmpty) return cleaned;
  return parts.length <= 4
      ? parts.join(' ')
      : parts.sublist(parts.length - 4).join(' ');
}

bool _looksLikeSamePoster(CatalogItem a, CatalogItem b) {
  final aTokens = _posterTokens(a.poster);
  final bTokens = _posterTokens(b.poster);
  if (aTokens.isEmpty || bTokens.isEmpty) return false;
  final overlap = aTokens.intersection(bTokens).length;
  if (overlap >= 5) return true;
  final smaller = aTokens.length < bTokens.length
      ? aTokens.length
      : bTokens.length;
  return smaller >= 4 && overlap / smaller >= 0.72;
}

int _catalogGridColumns(
  MediaType type,
  String density, {
  bool compactLandscape = false,
}) {
  if (type == MediaType.liveTv) {
    if (compactLandscape) return density == 'large' ? 2 : 3;
    return density == 'large' ? 1 : 2;
  }
  if (compactLandscape) {
    return switch (density) {
      'compact' => 6,
      'large' => 4,
      _ => 5,
    };
  }
  return switch (density) {
    'large' => 2,
    _ => 3,
  };
}

double _catalogGridSpacing(String density) {
  return switch (density) {
    'compact' => 9,
    'large' => 14,
    _ => 12,
  };
}

class _CatalogSearchGroupResult {
  const _CatalogSearchGroupResult({required this.type, required this.items});

  final MediaType type;
  final List<CatalogItem> items;
}

Set<String> _posterTokens(String? poster) {
  if (poster == null || poster.trim().isEmpty) return const {};
  final decoded = Uri.decodeFull(poster).toLowerCase();
  final parsed = Uri.tryParse(decoded);
  final raw = [
    parsed?.host ?? '',
    parsed?.path ?? decoded,
    parsed?.query ?? '',
  ].join(' ');
  final common = {
    'http',
    'https',
    'www',
    'com',
    'org',
    'net',
    'jpg',
    'jpeg',
    'png',
    'webp',
    'poster',
    'posters',
    'image',
    'images',
    'medium',
    'small',
    'large',
    'original',
    'resize',
    'cache',
    'cdn',
    'tmdb',
    'themoviedb',
    'media',
    'metahub',
    'space',
    'cloudfront',
    'amazonaws',
  };
  return raw
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((token) => token.length > 2 && !common.contains(token))
      .toSet();
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onClear,
    required this.expanded,
    required this.hasSuggestions,
    required this.fieldActive,
    required this.shellExpanded,
    required this.onTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final bool expanded;
  final bool hasSuggestions;
  final bool fieldActive;
  final bool shellExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - 36;
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 430),
          curve: Curves.easeOutCubic,
          tween: Tween<double>(end: expanded ? width : 46),
          builder: (context, animatedWidth, child) {
            return Container(
              width: animatedWidth,
              height: 46,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: expanded && hasSuggestions
                    ? const BorderRadius.vertical(top: Radius.circular(23))
                    : BorderRadius.circular(999),
                boxShadow: JuicrVisual.softShadow(
                  colorScheme,
                  alpha: 0.1,
                  blur: 14,
                  y: 5,
                ),
              ),
              child: expanded
                  ? fieldActive
                        ? TextField(
                            controller: controller,
                            focusNode: focusNode,
                            textAlignVertical: TextAlignVertical.center,
                            textInputAction: TextInputAction.search,
                            onSubmitted: onSubmitted,
                            decoration: InputDecoration(
                              filled: false,
                              fillColor: Colors.transparent,
                              isDense: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              hintText: 'Search anything...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: value.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear',
                                      onPressed: onClear,
                                      icon: const Icon(Icons.close),
                                    ),
                            ),
                          )
                        : shellExpanded
                        ? Row(
                            children: [
                              const SizedBox(width: 14),
                              Icon(
                                Icons.search_rounded,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.74,
                                ),
                                size: 20,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Search anything...',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.54,
                                        ),
                                      ),
                                ),
                              ),
                            ],
                          )
                        : const Center(
                            child: Icon(Icons.search_rounded, size: 20),
                          )
                  : IconButton(
                      tooltip: 'Search',
                      onPressed: onTap,
                      icon: const Icon(Icons.search_rounded),
                    ),
            );
          },
        );
      },
    );
  }
}

class _SearchResultContextPill extends StatelessWidget {
  const _SearchResultContextPill({required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Showing results for "$query"',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.68),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          label: 'Clear search',
          child: ExcludeSemantics(
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onClear,
              child: SizedBox(
                height: 36,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.86,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: Text(
                        'Clear',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.86,
                              ),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchSuggestions extends StatelessWidget {
  const _SearchSuggestions({
    required this.suggestions,
    required this.onSelected,
  });

  final List<String> suggestions;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final visible = suggestions.take(AppState.searchHistoryLimit).toList();
    return Material(
      color: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.24),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(23)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(23),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.52),
            ),
            const SizedBox(height: 6),
            for (final suggestion in visible)
              SizedBox(
                height: 40,
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  minVerticalPadding: 0,
                  leading: Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: colorScheme.onSurface.withValues(alpha: 0.92),
                  ),
                  title: Text(
                    suggestion,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onTap: () => onSelected(suggestion),
                ),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _CatalogHeaderPanel extends StatelessWidget {
  const _CatalogHeaderPanel({
    required this.height,
    required this.browseVisible,
    required this.greeting,
    required this.prompt,
    required this.decisionPrompt,
    required this.decisionPromptVisible,
    required this.randomPickLoading,
    required this.searchExpanded,
    required this.searchFieldActive,
    required this.searchShellExpanded,
    required this.searchSuggestionsVisible,
    required this.greetingVisible,
    required this.greetingContextVisible,
    required this.animateGreeting,
    required this.searchQuery,
    required this.showSearchContext,
    required this.showRefreshContext,
    required this.headerContextSlotHeight,
    required this.suggestions,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSubmitted,
    required this.onClearSearch,
    required this.onClearSearchContext,
    required this.onSearchTap,
    required this.onRandomPick,
    required this.onSuggestionSelected,
    required this.browseCard,
  });

  final double height;
  final bool browseVisible;
  final String greeting;
  final String prompt;
  final String decisionPrompt;
  final bool decisionPromptVisible;
  final bool randomPickLoading;
  final bool searchExpanded;
  final bool searchFieldActive;
  final bool searchShellExpanded;
  final bool searchSuggestionsVisible;
  final bool greetingVisible;
  final bool greetingContextVisible;
  final bool animateGreeting;
  final String searchQuery;
  final bool showSearchContext;
  final bool showRefreshContext;
  final double headerContextSlotHeight;
  final List<String> suggestions;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClearSearch;
  final VoidCallback onClearSearchContext;
  final VoidCallback onSearchTap;
  final VoidCallback onRandomPick;
  final ValueChanged<String> onSuggestionSelected;
  final Widget browseCard;

  @override
  Widget build(BuildContext context) {
    final compactLandscape = JuicrVisual.compactLandscape(context);
    final showSuggestions =
        searchExpanded &&
        searchFieldActive &&
        searchSuggestionsVisible &&
        suggestions.isNotEmpty;
    final headerMotionDuration = showRefreshContext && !showSearchContext
        ? Duration.zero
        : Duration(milliseconds: browseVisible ? 520 : 380);
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.24),
      child: AnimatedContainer(
        duration: headerMotionDuration,
        curve: browseVisible
            ? Curves.easeOutCubic
            : Curves.easeInOutCubicEmphasized,
        height: height,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compactLandscape ? 14 : 18,
            compactLandscape ? 7 : 12,
            compactLandscape ? 14 : 18,
            compactLandscape ? 6 : 8,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: compactLandscape ? 50 : 56,
                      child: Stack(
                        alignment: Alignment.centerRight,
                        children: [
                          AnimatedSlide(
                            offset: greetingVisible || !animateGreeting
                                ? Offset.zero
                                : const Offset(-0.08, 0),
                            duration: animateGreeting
                                ? const Duration(milliseconds: 260)
                                : Duration.zero,
                            curve: Curves.easeOutCubic,
                            child: AnimatedOpacity(
                              opacity: greetingVisible ? 1 : 0,
                              duration: animateGreeting
                                  ? const Duration(milliseconds: 220)
                                  : Duration.zero,
                              curve: Curves.easeOutCubic,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _GreetingText(
                                  greeting: greeting,
                                  prompt: prompt,
                                  decisionPrompt: decisionPrompt,
                                  decisionPromptVisible: decisionPromptVisible,
                                  randomPickLoading: randomPickLoading,
                                  contextVisible: greetingContextVisible,
                                  onRandomPick: onRandomPick,
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: _TopBar(
                              controller: searchController,
                              focusNode: searchFocusNode,
                              onSubmitted: onSubmitted,
                              onClear: onClearSearch,
                              expanded: searchExpanded,
                              hasSuggestions: showSuggestions,
                              fieldActive: searchFieldActive,
                              shellExpanded: searchShellExpanded,
                              onTap: onSearchTap,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: headerMotionDuration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInOutCubicEmphasized,
                      transitionBuilder: (child, animation) {
                        final curved = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                          reverseCurve: Curves.easeInOutCubicEmphasized,
                        );
                        return SizeTransition(
                          sizeFactor: curved,
                          axisAlignment: -1,
                          child: FadeTransition(
                            opacity: curved,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, -0.18),
                                end: Offset.zero,
                              ).animate(curved),
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: browseVisible
                          ? Padding(
                              key: const ValueKey<String>('browse-card'),
                              padding: const EdgeInsets.only(top: 6),
                              child: browseCard,
                            )
                          : const SizedBox(
                              key: ValueKey<String>('browse-card-hidden'),
                              width: double.infinity,
                            ),
                    ),
                    if (showSearchContext || showRefreshContext)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: SizedBox(
                          width: double.infinity,
                          height: headerContextSlotHeight,
                          child: showSearchContext
                              ? _SearchResultContextPill(
                                  query: searchQuery,
                                  onClear: onClearSearchContext,
                                )
                              : Center(
                                  child: Text(
                                    'Updated just now',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.68),
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 51,
                child: IgnorePointer(
                  ignoring: !showSuggestions,
                  child: AnimatedSlide(
                    offset: showSuggestions
                        ? Offset.zero
                        : const Offset(0, -0.08),
                    duration: const Duration(milliseconds: 440),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: showSuggestions ? 1 : 0,
                      duration: const Duration(milliseconds: 340),
                      curve: Curves.easeOutQuart,
                      child: _SearchSuggestions(
                        suggestions: suggestions,
                        onSelected: onSuggestionSelected,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GreetingText extends StatelessWidget {
  const _GreetingText({
    required this.greeting,
    required this.prompt,
    required this.decisionPrompt,
    required this.decisionPromptVisible,
    required this.randomPickLoading,
    required this.contextVisible,
    required this.onRandomPick,
  });

  final String greeting;
  final String prompt;
  final String decisionPrompt;
  final bool decisionPromptVisible;
  final bool randomPickLoading;
  final bool contextVisible;
  final VoidCallback onRandomPick;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        AnimatedSlide(
          offset: contextVisible ? Offset.zero : const Offset(-0.08, 0),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: contextVisible ? 1 : 0,
            duration: const Duration(milliseconds: 210),
            curve: Curves.easeOutCubic,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.centerLeft,
                  clipBehavior: Clip.none,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              transitionBuilder: (child, animation) {
                final offset =
                    Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: offset, child: child),
                );
              },
              child: randomPickLoading
                  ? Row(
                      key: const ValueKey<String>('random-pick-loading'),
                      children: [
                        SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Finding a pick...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.62,
                                  ),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    )
                  : decisionPromptVisible
                  ? Row(
                      key: ValueKey<String>('decide-$decisionPrompt'),
                      children: [
                        Flexible(
                          child: Text(
                            decisionPrompt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.62,
                                  ),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Semantics(
                          button: true,
                          label: 'Pick something random',
                          child: ExcludeSemantics(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: onRandomPick,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 1,
                                ),
                                child: Text(
                                  'Tap here',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      prompt,
                      key: ValueKey<String>('prompt-$prompt'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BrowseControlCard extends StatelessWidget {
  const _BrowseControlCard({
    required this.type,
    required this.types,
    required this.sort,
    required this.year,
    required this.genre,
    required this.origin,
    required this.scope,
    required this.genres,
    required this.genreOptionsByType,
    required this.originOptions,
    required this.scopeOptions,
    required this.years,
    required this.yearSelectionAvailable,
    required this.yearsForSort,
    required this.yearSelectionAvailableForSort,
    required this.onOpenBrowseSheet,
    required this.onTypeChanged,
    required this.onSortChanged,
    required this.onYearChanged,
    required this.onGenreChanged,
    required this.onOriginChanged,
    required this.onScopeChanged,
  });

  final MediaType type;
  final List<MediaType> types;
  final CatalogSort sort;
  final String year;
  final String genre;
  final _CatalogOriginOption origin;
  final _CatalogScopeOption scope;
  final List<String> genres;
  final Map<MediaType, List<String>> genreOptionsByType;
  final List<_CatalogOriginOption> originOptions;
  final List<_CatalogScopeOption> scopeOptions;
  final List<String> years;
  final bool yearSelectionAvailable;
  final List<String> Function(CatalogSort sort) yearsForSort;
  final bool Function(CatalogSort sort) yearSelectionAvailableForSort;
  final VoidCallback onOpenBrowseSheet;
  final ValueChanged<MediaType> onTypeChanged;
  final ValueChanged<CatalogSort> onSortChanged;
  final ValueChanged<String> onYearChanged;
  final ValueChanged<String> onGenreChanged;
  final ValueChanged<_CatalogOriginOption> onOriginChanged;
  final ValueChanged<_CatalogScopeOption> onScopeChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final compactLandscape = JuicrVisual.compactLandscape(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(
        alpha: colorScheme.brightness == Brightness.dark ? 0.5 : 0.16,
      ),
      shape: JuicrVisual.cardShape(colorScheme, alpha: 0.3),
      child: Semantics(
        button: true,
        label: 'Browse ${type.pluralLabel}',
        value: _browseSubtitle,
        hint: 'Choose browse filters',
        child: ExcludeSemantics(
          child: InkWell(
            borderRadius: BorderRadius.circular(JuicrVisual.cardRadius),
            onTap: onOpenBrowseSheet,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compactLandscape ? 12 : 14,
                vertical: compactLandscape ? 9 : 13,
              ),
              child: Row(
                children: [
                  Container(
                    width: compactLandscape ? 34 : 42,
                    height: compactLandscape ? 34 : 42,
                    decoration: JuicrVisual.elevatedIconDecoration(
                      colorScheme,
                      radius: 12,
                      shadowAlpha: 0.08,
                      glowAlpha: 0.04,
                    ),
                    child: Icon(
                      _typeIcon(type),
                      color: colorScheme.primary,
                      size: compactLandscape ? 19 : 22,
                    ),
                  ),
                  SizedBox(width: compactLandscape ? 10 : 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _browseTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (compactLandscape
                                      ? Theme.of(context).textTheme.titleSmall
                                      : Theme.of(context).textTheme.titleMedium)
                                  ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: compactLandscape ? 2 : 3),
                        Text(
                          _browseSubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.62,
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: compactLandscape ? 8 : 10),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.primary,
                    size: compactLandscape ? 22 : 24,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _browseSubtitle {
    final filterContext = _browseFilterContext;
    final primary = _browseSortLabel(type, sort);
    if (filterContext.isEmpty) return primary;
    return '$primary - $filterContext';
  }

  String get _browseTitle {
    return type.label;
  }

  String get _browseFilterContext {
    if (type == MediaType.liveTv && sort == CatalogSort.newest) {
      return genre == 'All countries' ? 'All countries' : genre;
    }
    if (!_supportsYearFilter(type)) {
      final filter = genre == 'All genres' ? 'all genres' : genre;
      return _sentenceCaseFilterLabel(filter);
    }
    if (!yearSelectionAvailable || year == 'Unknown') {
      return 'Finding current picks';
    }
    final hasGenre = genre != 'All genres';
    final hasYear =
        year != 'Unknown' && year != _CatalogPageState._allYearsLabel;
    final hasOrigin = !origin.isAll;
    final hasScope = !scope.isAll;
    final parts = <String>[];
    if (hasGenre && hasYear && hasOrigin) {
      parts.add('${_sentenceCaseFilterLabel(genre)} in $year');
    } else {
      if (hasGenre) parts.add(_sentenceCaseFilterLabel(genre));
      if (hasYear) parts.add(year);
    }
    if (hasOrigin) parts.add(origin.shortLabel);
    if (hasScope) parts.add(scope.shortLabel);
    return parts.join(' - ');
  }

  String _sentenceCaseFilterLabel(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return cleaned;
    return '${cleaned[0].toUpperCase()}${cleaned.substring(1)}';
  }

  String _browseSortLabel(MediaType type, CatalogSort sort) {
    if (type == MediaType.liveTv) {
      return switch (sort) {
        CatalogSort.newest => 'Beta',
        CatalogSort.imdbRating => 'Gamma',
        _ => 'Alpha',
      };
    }
    if (type == MediaType.animation) {
      return switch (sort) {
        CatalogSort.onTv => 'Series',
        _ => 'Movie',
      };
    }
    return sort.label;
  }

  List<String> _genresForPlaylist(MediaType type, CatalogSort sort) {
    final values = genreOptionsByType[type] ?? genres;
    if (type == MediaType.liveTv && sort == CatalogSort.newest) {
      return _CatalogPageState._betaLiveTvCountryOptions;
    }
    if (type == MediaType.liveTv && sort == CatalogSort.imdbRating) {
      return _CatalogPageState._gammaLiveTvGenreOptions;
    }
    return values;
  }

  String _liveTvFilterTitle(MediaType type, CatalogSort sort) {
    return type == MediaType.liveTv && sort == CatalogSort.newest
        ? 'Country'
        : 'Genre';
  }

  bool _supportsYearFilter(MediaType type, {CatalogSort? sort}) {
    final targetSort = sort ?? this.sort;
    return type != MediaType.liveTv &&
        type != MediaType.music &&
        type != MediaType.nsfw &&
        targetSort != CatalogSort.nowPlaying &&
        targetSort != CatalogSort.upcoming;
  }

  bool _supportsOriginFilter(MediaType type) {
    return type == MediaType.movie ||
        type == MediaType.series ||
        type == MediaType.animation;
  }

  IconData _typeIcon(MediaType type) {
    return switch (type) {
      MediaType.movie => Icons.movie_creation_outlined,
      MediaType.series => Icons.tv_outlined,
      MediaType.animation => Icons.auto_awesome_outlined,
      MediaType.liveTv => Icons.live_tv_rounded,
      MediaType.music => Icons.library_music_outlined,
      MediaType.nsfw => Icons.visibility_off_outlined,
    };
  }

  Future<void> _showBrowseSheet(
    BuildContext context, {
    MediaType? currentType,
    CatalogSort? currentSort,
    String? currentYear,
    String? currentGenre,
    _CatalogOriginOption? currentOrigin,
    _CatalogScopeOption? currentScope,
  }) async {
    final displayType = currentType ?? type;
    final displaySortOptions = _sortOptionsFor(displayType);
    final requestedSort = currentSort ?? sort;
    final displaySort = displaySortOptions.contains(requestedSort)
        ? requestedSort
        : CatalogSort.top;
    final displayYearControls = _supportsYearFilter(
      displayType,
      sort: displaySort,
    );
    final displayYears = yearsForSort(displaySort);
    final displayYearSelectionAvailable =
        displayYearControls && yearSelectionAvailableForSort(displaySort);
    final displayGenres = _genresForPlaylist(displayType, displaySort);
    final displayYear =
        currentYear != null && displayYears.contains(currentYear)
        ? currentYear
        : displayYears.contains(year)
        ? year
        : displayYears.first;
    final displayGenre =
        currentGenre ??
        (displayGenres.contains(genre) ? genre : displayGenres.first);
    final displayOriginOptions = _supportsOriginFilter(displayType)
        ? originOptions
        : const [_CatalogOriginOption.all()];
    final displayOrigin =
        currentOrigin ??
        (displayOriginOptions.contains(origin)
            ? origin
            : const _CatalogOriginOption.all());
    final allScopeOptions = displayType == MediaType.movie
        ? scopeOptions
        : scopeOptions
              .where((scope) => scope.kind != _CatalogScopeKind.collection)
              .toList(growable: false);
    final displayScopeOptions = AppState.showMatureContent.value
        ? allScopeOptions
        : allScopeOptions
              .where((scope) => !scope.hasMatureContentSignal)
              .toList(growable: false);
    final displayScope =
        currentScope ??
        (displayScopeOptions.contains(scope)
            ? scope
            : displayScopeOptions.first);
    final floatingSheet = JuicrVisual.bottomSheetUsesFloatingLayout(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: !floatingSheet,
      isScrollControlled: true,
      backgroundColor: floatingSheet
          ? Colors.transparent
          : Theme.of(context).scaffoldBackgroundColor,
      shape: floatingSheet ? null : JuicrVisual.bottomSheetShape,
      builder: (sheetContext) {
        final sheetFloating = JuicrVisual.bottomSheetUsesFloatingLayout(
          sheetContext,
        );
        return SafeArea(
          top: false,
          child: JuicrVisual.bottomSheetFrame(
            sheetContext,
            includeHandle: sheetFloating,
            padding: sheetFloating
                ? const EdgeInsets.fromLTRB(16, 10, 16, 16)
                : EdgeInsets.zero,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  18,
                  0,
                  18,
                  JuicrVisual.bottomSheetBottomBreathingRoom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BrowseSummaryTile(
                      icon: _typeIcon(displayType),
                      title: 'Type',
                      value: displayType.label,
                      onTap: () {
                        _openNestedBrowsePicker<MediaType>(
                          context,
                          sheetContext: sheetContext,
                          title: 'Type',
                          value: displayType,
                          values: types,
                          labelFor: (type) => type.label,
                          iconFor: _typeIcon,
                          onSelected: onTypeChanged,
                          onBack: (_) => onOpenBrowseSheet(),
                        );
                      },
                    ),
                    _BrowseSummaryTile(
                      icon: _browseSortIcon(displayType, displaySort),
                      title: displayType == MediaType.liveTv
                          ? 'Playlist'
                          : 'Sort',
                      value: _browseSortLabel(displayType, displaySort),
                      onTap: () {
                        _openNestedBrowsePicker<CatalogSort>(
                          context,
                          sheetContext: sheetContext,
                          title: displayType == MediaType.liveTv
                              ? 'Playlist'
                              : 'Sort',
                          value: displaySort,
                          values: displaySortOptions,
                          labelFor: (sort) =>
                              _browseSortLabel(displayType, sort),
                          iconFor: (sort) => _browseSortIcon(displayType, sort),
                          onSelected: onSortChanged,
                          onBack: (_) => onOpenBrowseSheet(),
                        );
                      },
                    ),
                    if (displayYearControls)
                      _BrowseSummaryTile(
                        icon: Icons.calendar_month_outlined,
                        title: 'Year',
                        value: !displayYearSelectionAvailable
                            ? 'Unknown'
                            : displayYear,
                        locked: !displayYearSelectionAvailable,
                        onTap: () {
                          if (!displayYearSelectionAvailable) return;
                          _openNestedBrowsePicker<String>(
                            context,
                            sheetContext: sheetContext,
                            title: 'Year',
                            value: displayYear,
                            values: displayYears,
                            labelFor: (year) => year,
                            iconFor: (_) => Icons.calendar_month_outlined,
                            onSelected: onYearChanged,
                            onBack: (_) => onOpenBrowseSheet(),
                          );
                        },
                      ),
                    _BrowseSummaryTile(
                      icon:
                          displayType == MediaType.liveTv &&
                              displaySort == CatalogSort.newest
                          ? Icons.public_rounded
                          : Icons.category_outlined,
                      title: _liveTvFilterTitle(displayType, displaySort),
                      value: displayGenre,
                      onTap: () {
                        _openNestedBrowsePicker<String>(
                          context,
                          sheetContext: sheetContext,
                          title: _liveTvFilterTitle(displayType, displaySort),
                          value: displayGenre,
                          values: displayGenres,
                          labelFor: (genre) => genre,
                          iconFor: (_) =>
                              displayType == MediaType.liveTv &&
                                  displaySort == CatalogSort.newest
                              ? Icons.public_rounded
                              : Icons.category_outlined,
                          onSelected: onGenreChanged,
                          onBack: (_) => onOpenBrowseSheet(),
                        );
                      },
                    ),
                    if (_supportsOriginFilter(displayType))
                      _BrowseSummaryTile(
                        icon: Icons.public_rounded,
                        title: 'Origin',
                        value: displayOrigin.label,
                        onTap: () {
                          final resolvedOrigin =
                              displayOriginOptions.contains(displayOrigin)
                              ? displayOrigin
                              : const _CatalogOriginOption.all();
                          _openNestedBrowsePicker<_CatalogOriginOption>(
                            context,
                            sheetContext: sheetContext,
                            title: 'Origin',
                            value: resolvedOrigin,
                            values: displayOriginOptions,
                            labelFor: (origin) => origin.label,
                            iconFor: (_) => Icons.public_rounded,
                            onSelected: onOriginChanged,
                            onBack: (_) => onOpenBrowseSheet(),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openNestedBrowsePicker<T>(
    BuildContext context, {
    required BuildContext sheetContext,
    required String title,
    required T value,
    required List<T> values,
    required String Function(T value) labelFor,
    required IconData Function(T value) iconFor,
    bool Function(T value)? enabledFor,
    required ValueChanged<T> onSelected,
    required ValueChanged<T> onBack,
  }) {
    Navigator.of(sheetContext).pop();
    unawaited(
      _showSingleBrowsePicker<T>(
        context,
        title: title,
        value: value,
        values: values,
        labelFor: labelFor,
        iconFor: iconFor,
        enabledFor: enabledFor,
        onSelected: onSelected,
        onBack: onBack,
      ),
    );
  }

  Future<void> _showSingleBrowsePicker<T>(
    BuildContext context, {
    required String title,
    required T value,
    required List<T> values,
    required String Function(T value) labelFor,
    required IconData Function(T value) iconFor,
    bool Function(T value)? enabledFor,
    required ValueChanged<T> onSelected,
    required ValueChanged<T> onBack,
  }) async {
    final manyItems = values.length > 6;
    final floatingSheet = JuicrVisual.bottomSheetUsesFloatingLayout(context);
    var selectedValue = value;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: !floatingSheet,
      isScrollControlled: true,
      backgroundColor: floatingSheet
          ? Colors.transparent
          : Theme.of(context).scaffoldBackgroundColor,
      shape: floatingSheet ? null : JuicrVisual.bottomSheetShape,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final sheetFloating = JuicrVisual.bottomSheetUsesFloatingLayout(
              sheetContext,
            );
            final targetHeight = sheetFloating
                ? JuicrVisual.bottomSheetMaxHeight(sheetContext)
                : MediaQuery.sizeOf(sheetContext).height *
                      (manyItems ? 0.48 : 0.36);
            final options = _BrowseSheetSection<T>(
              title: '',
              value: selectedValue,
              values: values,
              spacious: !manyItems,
              labelFor: labelFor,
              iconFor: iconFor,
              enabledFor: enabledFor,
              onSelected: (nextValue) {
                if (nextValue == selectedValue) return;
                setSheetState(() => selectedValue = nextValue);
                onSelected(nextValue);
              },
            );
            return SafeArea(
              top: false,
              child: JuicrVisual.bottomSheetFrame(
                sheetContext,
                includeHandle: sheetFloating,
                padding: sheetFloating
                    ? const EdgeInsets.fromLTRB(16, 10, 16, 16)
                    : EdgeInsets.zero,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: targetHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                    child: Column(
                      mainAxisSize: manyItems || sheetFloating
                          ? MainAxisSize.max
                          : MainAxisSize.min,
                      children: [
                        ListTile(
                          minLeadingWidth: 20,
                          horizontalTitleGap: 8,
                          contentPadding: EdgeInsets.zero,
                          leading: IconButton(
                            tooltip: 'Back',
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              onBack(selectedValue);
                            },
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          title: Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (manyItems)
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.only(
                                bottom:
                                    JuicrVisual.bottomSheetBottomBreathingRoom,
                              ),
                              itemCount: values.length,
                              itemBuilder: (context, index) {
                                final item = values[index];
                                final enabled = enabledFor?.call(item) ?? true;
                                return JuicrSheetOptionTile(
                                  enabled: enabled,
                                  icon: iconFor(item),
                                  label: labelFor(item),
                                  selected: item == selectedValue,
                                  padding: const EdgeInsets.only(bottom: 8),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 11,
                                  ),
                                  onTap: enabled
                                      ? () {
                                          if (item == selectedValue) return;
                                          setSheetState(() {
                                            selectedValue = item;
                                          });
                                          onSelected(item);
                                        }
                                      : null,
                                );
                              },
                            ),
                          )
                        else if (sheetFloating)
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(
                                bottom:
                                    JuicrVisual.bottomSheetBottomBreathingRoom,
                              ),
                              child: options,
                            ),
                          )
                        else ...[
                          options,
                          const SizedBox(
                            height: JuicrVisual.bottomSheetBottomBreathingRoom,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  IconData _sortIcon(CatalogSort sort) {
    return switch (sort) {
      CatalogSort.top => Icons.local_fire_department_outlined,
      CatalogSort.topRated => Icons.star_border_rounded,
      CatalogSort.newest => Icons.new_releases_outlined,
      CatalogSort.oldest => Icons.history_rounded,
      CatalogSort.alphaAsc => Icons.sort_by_alpha_rounded,
      CatalogSort.alphaDesc => Icons.sort_by_alpha_rounded,
      CatalogSort.nowPlaying => Icons.play_circle_outline_rounded,
      CatalogSort.airingToday => Icons.today_outlined,
      CatalogSort.onTv => Icons.live_tv_outlined,
      CatalogSort.year => Icons.calendar_month_outlined,
      CatalogSort.upcoming => Icons.event_available_outlined,
      CatalogSort.imdbRating => Icons.star_border_rounded,
      CatalogSort.hiddenGems => Icons.auto_awesome_outlined,
    };
  }

  IconData _browseSortIcon(MediaType type, CatalogSort sort) {
    if (type == MediaType.liveTv) return Icons.playlist_play_rounded;
    return _sortIcon(sort);
  }

  IconData _scopeIcon(_CatalogScopeOption scope) {
    return switch (scope.kind) {
      _CatalogScopeKind.all => Icons.public_rounded,
      _CatalogScopeKind.company => Icons.business_rounded,
      _CatalogScopeKind.collection => Icons.collections_bookmark_outlined,
    };
  }
}

class _BrowseSummaryTile extends StatelessWidget {
  const _BrowseSummaryTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.locked = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mutedColor = colorScheme.onSurface.withValues(alpha: 0.42);
    return JuicrSheetOptionTile(
      enabled: !locked,
      icon: icon,
      label: title,
      subtitle: value,
      trailing: Icon(
        locked ? Icons.lock_rounded : Icons.chevron_right_rounded,
        color: locked
            ? mutedColor
            : colorScheme.onSurface.withValues(alpha: 0.62),
      ),
      onTap: locked ? null : onTap,
    );
  }
}

class _BrowseSheetSection<T> extends StatelessWidget {
  const _BrowseSheetSection({
    required this.title,
    required this.value,
    required this.values,
    required this.labelFor,
    required this.iconFor,
    this.spacious = false,
    this.enabledFor,
    required this.onSelected,
  });

  final String title;
  final T value;
  final List<T> values;
  final String Function(T value) labelFor;
  final IconData Function(T value) iconFor;
  final bool spacious;
  final bool Function(T value)? enabledFor;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.64),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        Column(
          children: [
            for (var index = 0; index < values.length; index++) ...[
              Builder(
                builder: (context) {
                  final item = values[index];
                  final enabled = enabledFor?.call(item) ?? true;
                  return JuicrSheetOptionTile(
                    enabled: enabled,
                    icon: iconFor(item),
                    label: labelFor(item),
                    selected: item == value,
                    padding: EdgeInsets.only(bottom: spacious ? 10 : 8),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: spacious ? 16 : 11,
                    ),
                    onTap: enabled ? () => onSelected(item) : null,
                  );
                },
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _PopupFilter<T> extends StatelessWidget {
  const _PopupFilter({
    required this.value,
    required this.values,
    required this.labelFor,
    required this.onChanged,
  });

  final T value;
  final List<T> values;
  final String Function(T value) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = labelFor(value);
    return Semantics(
      button: true,
      label: 'Filter by $label',
      hint: 'Choose filter option',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _showOptions(context),
          child: Ink(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.72,
              ),
              borderRadius: BorderRadius.circular(999),
              boxShadow: JuicrVisual.softShadow(
                colorScheme,
                alpha: 0.06,
                blur: 10,
                y: 3,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const _FilterTriangleIcon(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showOptions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (sheetContext) {
        final visibleValues = values.toList();
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.5,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                12,
                18,
                JuicrVisual.bottomSheetBottomBreathingRoom +
                    MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (
                          var index = 0;
                          index < visibleValues.length;
                          index++
                        ) ...[
                          JuicrSheetOptionTile(
                            label: labelFor(visibleValues[index]),
                            selected: visibleValues[index] == value,
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              onChanged(visibleValues[index]);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FilterTriangleIcon extends StatelessWidget {
  const _FilterTriangleIcon();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: const Size(10, 8),
      painter: _FilterTrianglePainter(colorScheme.primary),
    );
  }
}

class _FilterTrianglePainter extends CustomPainter {
  const _FilterTrianglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FilterTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _CatalogSearchResultSection extends StatelessWidget {
  const _CatalogSearchResultSection({
    required this.api,
    required this.type,
    required this.items,
    required this.density,
    required this.progressByItemId,
  });

  final StreamApi api;
  final MediaType type;
  final List<CatalogItem> items;
  final String density;
  final Map<String, ContinueWatchingEntry> progressByItemId;

  @override
  Widget build(BuildContext context) {
    final spacing = _catalogGridSpacing(density);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
            child: _CatalogSearchSectionDivider(label: type.pluralLabel),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _catalogGridColumns(type, density),
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: type == MediaType.liveTv ? 1.45 : 2 / 3,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                return _PosterTile(
                  api: api,
                  item: item,
                  index: index,
                  entry: progressByItemId[item.id],
                  showReleaseDateBadge: false,
                );
              },
              childCount: items.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              addSemanticIndexes: false,
            ),
          ),
        ),
      ],
    );
  }
}

class _CatalogSearchSectionDivider extends StatelessWidget {
  const _CatalogSearchSectionDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lineColor = colorScheme.onSurface.withValues(alpha: 0.16);
    return Row(
      children: [
        Expanded(child: Divider(height: 1, thickness: 1, color: lineColor)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: colorScheme.primary,
            ),
          ),
        ),
        Expanded(child: Divider(height: 1, thickness: 1, color: lineColor)),
      ],
    );
  }
}

class _PosterTile extends StatefulWidget {
  const _PosterTile({
    required this.api,
    required this.item,
    required this.index,
    required this.entry,
    required this.showReleaseDateBadge,
  });

  final StreamApi api;
  final CatalogItem item;
  final int index;
  final ContinueWatchingEntry? entry;
  final bool showReleaseDateBadge;

  @override
  State<_PosterTile> createState() => _PosterTileState();
}

class _PosterTileState extends State<_PosterTile> {
  CatalogItem? _hydratedItem;
  bool _hydratingPoster = false;
  bool _posterLoadFailed = false;

  CatalogItem get _displayItem => _hydratedItem ?? widget.item;

  @override
  void initState() {
    super.initState();
    _maybeHydratePoster();
  }

  @override
  void didUpdateWidget(covariant _PosterTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.poster != widget.item.poster) {
      _hydratedItem = null;
      _hydratingPoster = false;
      _posterLoadFailed = false;
      _maybeHydratePoster();
    }
  }

  void _maybeHydratePoster() {
    if (_hydratingPoster) return;
    if ((widget.item.poster?.trim().isNotEmpty ?? false) &&
        !_posterLoadFailed) {
      return;
    }
    if (widget.item.tmdbId == null) return;
    _hydratingPoster = true;
    unawaited(() async {
      try {
        final details = await widget.api.meta(widget.item);
        final hydrated = widget.item.merge(details.item);
        if (!mounted) return;
        final hydratedPoster = hydrated.poster?.trim();
        if (hydratedPoster != null &&
            hydratedPoster.isNotEmpty &&
            hydratedPoster != widget.item.poster?.trim()) {
          setState(() {
            _hydratedItem = hydrated;
            _hydratingPoster = false;
            _posterLoadFailed = false;
          });
          DiagnosticLog.add(
            'catalog poster hydrated type=${widget.item.type.compatTypeValue} id=${widget.item.id}',
          );
          return;
        }
      } catch (error) {
        DiagnosticLog.add(
          'catalog poster hydrate skipped type=${widget.item.type.compatTypeValue} id=${widget.item.id} error=${error.runtimeType}',
        );
      }
      if (mounted) {
        setState(() => _hydratingPoster = false);
      } else {
        _hydratingPoster = false;
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final item = _displayItem;
    final colorScheme = Theme.of(context).colorScheme;
    final posterProvider = item.poster == null
        ? null
        : ResizeImage.resizeIfNeeded(320, null, NetworkImage(item.poster!));
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: 'Open ${item.name}',
        hint: 'Show details',
        child: ExcludeSemantics(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openDetails(context),
            child: item.type == MediaType.liveTv
                ? _LiveChannelCard(item: item)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: ColoredBox(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.72),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  item.poster == null
                                      ? const _CatalogArtworkFallback()
                                      : ValueListenableBuilder<String>(
                                          valueListenable:
                                              AppState.posterImageIntensity,
                                          builder: (context, intensity, _) {
                                            return JuicrVisual.posterTone(
                                              intensity,
                                              child: Image(
                                                image: posterProvider!,
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                                height: double.infinity,
                                                filterQuality:
                                                    FilterQuality.low,
                                                gaplessPlayback: true,
                                                loadingBuilder:
                                                    (
                                                      context,
                                                      child,
                                                      loadingProgress,
                                                    ) {
                                                      if (loadingProgress ==
                                                          null) {
                                                        return child;
                                                      }
                                                      return const AppSkeletonCard(
                                                        radius: 10,
                                                      );
                                                    },
                                                errorBuilder: (_, __, ___) {
                                                  if (!_posterLoadFailed) {
                                                    _posterLoadFailed = true;
                                                    _maybeHydratePoster();
                                                  }
                                                  return const _CatalogArtworkFallback();
                                                },
                                              ),
                                            );
                                          },
                                        ),
                                  if (item.isLocalCatalogItem)
                                    const Positioned(
                                      left: 8,
                                      top: 8,
                                      child: _LocalPrivateBadge(),
                                    ),
                                  if (widget.entry case final badgeEntry?)
                                    _ContinueBadge(entry: badgeEntry),
                                  if (widget.showReleaseDateBadge &&
                                      item.releaseDate?.trim().isNotEmpty ==
                                          true)
                                    Positioned(
                                      left: 8,
                                      top: 8,
                                      child: _UpcomingReleaseDateBadge(
                                        item: item,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  void _openDetails(BuildContext context) {
    final item = _displayItem;
    DiagnosticLog.screen(context, 'Catalog poster tap');
    DiagnosticLog.add(
      'catalog poster tap index=${widget.index} id=${item.id} type=${item.type.compatTypeValue}',
    );
    unawaited(
      JuicrAdPolicy.maybeShowInterstitial(reason: 'discovery_title_open'),
    );
    Navigator.of(
      context,
    ).push(AppPageRoute<void>(builder: (_) => DetailsPage(item: item)));
  }
}

class _UpcomingReleaseDateBadge extends StatelessWidget {
  const _UpcomingReleaseDateBadge({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final label = _catalogUpcomingDateLabel(item);
    if (label == null) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 10,
            height: 1,
          ),
        ),
      ),
    );
  }
}

String? _catalogUpcomingDateLabel(CatalogItem item) {
  final rawDate = item.releaseDate?.trim();
  if (rawDate == null || rawDate.isEmpty) return null;
  final date = DateTime.tryParse(rawDate);
  if (date == null || date.month < 1 || date.month > 12) return null;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}

class _CatalogArtworkFallback extends StatelessWidget {
  const _CatalogArtworkFallback();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final muted = colorScheme.onSurface.withValues(alpha: 0.42);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.86),
            colorScheme.surface.withValues(alpha: 0.92),
          ],
        ),
      ),
      child: Center(
        child: Icon(Icons.image_not_supported_rounded, color: muted, size: 28),
      ),
    );
  }
}

class _LocalPrivateBadge extends StatelessWidget {
  const _LocalPrivateBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'LOCAL',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onPrimary,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _LiveChannelCard extends StatelessWidget {
  const _LiveChannelCard({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final imageUrl = item.logo ?? item.poster;
    final cacheWidth = _catalogImageCacheWidth(context, 160);
    final imageProvider = imageUrl == null
        ? null
        : ResizeImage.resizeIfNeeded(cacheWidth, null, NetworkImage(imageUrl));
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: JuicrVisual.elevatedCardDecoration(
        colorScheme,
        color: colorScheme.surfaceContainer,
        radius: 10,
        borderAlpha: 0.26,
        shadowAlpha: 0.12,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: imageUrl == null
                    ? Icon(
                        Icons.live_tv_rounded,
                        color: colorScheme.onSurface.withValues(alpha: 0.46),
                        size: 34,
                      )
                    : Image(
                        image: imageProvider!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        filterQuality: FilterQuality.low,
                        gaplessPlayback: true,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const AppSkeletonCard(radius: 10);
                        },
                        errorBuilder: (_, __, ___) {
                          return Icon(
                            Icons.live_tv_rounded,
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.46,
                            ),
                            size: 34,
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

int _catalogImageCacheWidth(BuildContext context, double logicalWidth) {
  final width = logicalWidth * MediaQuery.devicePixelRatioOf(context);
  return width.clamp(120, 900).round();
}

class _ContinueBadge extends StatelessWidget {
  const _ContinueBadge({required this.entry});

  final ContinueWatchingEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0x66000000), Colors.transparent, Color(0x99000000)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 7,
              right: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Continue watching',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 8,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 7,
              right: 7,
              bottom: 7,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  value: entry.progress,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterGridSkeleton extends StatelessWidget {
  const _PosterGridSkeleton({required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context) {
    final liveTv = type == MediaType.liveTv;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: liveTv ? 2 : 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: liveTv ? 1.45 : 2 / 3,
        ),
        itemCount: liveTv ? 10 : 15,
        itemBuilder: (context, index) {
          return AppReveal(
            delay: Duration(milliseconds: 18 * (index % 9)),
            duration: const Duration(milliseconds: 420),
            child: liveTv
                ? const AppLiveTileSkeleton()
                : const _PosterTileSkeleton(),
          );
        },
      ),
    );
  }
}

class _PosterTileSkeleton extends StatelessWidget {
  const _PosterTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const [
        Positioned.fill(child: AppSkeletonCard(radius: 10)),
        Positioned(
          left: 10,
          right: 10,
          bottom: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeletonLine(height: 8),
              SizedBox(height: 7),
              AppSkeletonLine(height: 8, widthFactor: 0.62),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final serviceDisabled = message.toLowerCase().contains(
      'service is currently unavailable',
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: serviceDisabled
            ? colorScheme.surfaceContainerHighest
            : colorScheme.errorContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        boxShadow: JuicrVisual.softShadow(
          colorScheme,
          alpha: serviceDisabled ? 0.08 : 0.12,
          blur: 14,
          y: 5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            serviceDisabled
                ? Icons.power_settings_new_rounded
                : Icons.error_outline,
            color: serviceDisabled ? colorScheme.primary : colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              serviceDisabled
                  ? 'Service unavailable. Please try again later.'
                  : message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: serviceDisabled
                    ? colorScheme.onSurface.withValues(alpha: 0.7)
                    : null,
                fontWeight: serviceDisabled ? FontWeight.w700 : null,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
