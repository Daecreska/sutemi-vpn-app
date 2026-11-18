class CountryRule {
  final String code;
  final String flag;
  final RegExp codePattern;
  final RegExp wordPattern;

  CountryRule(this.code, this.flag, String codeRegex, String wordRegex)
      : codePattern = RegExp(codeRegex),
        wordPattern = RegExp(wordRegex, caseSensitive: false);
}

class CountryDetector {
  static const Set<String> blockedAiCountries = {
    'RU', 'BY', 'CN', 'HK', 'MO', 'IR', 'KP', 'SY', 'CU', 'AF', 'VE', 'MM',
  };

  static const Set<String> _sanctioned = {'RU', 'BY', 'CN', 'IR', 'KP', 'SY', 'CU'};

  static final Map<String, Set<String>> serviceBlockedCountries = {
    'gemini': _sanctioned,
    'aistudio': {..._sanctioned, 'HK', 'MO', 'MM'},
    'chatgpt': {..._sanctioned, 'HK', 'MO', 'VE'},
    'claude': {..._sanctioned, 'HK', 'MO', 'AF', 'VE', 'MM'},
  };

  static const Set<String> euTier1 = {
    'PL', 'LT', 'LV', 'EE', 'FI', 'SE', 'DE', 'NL', 'CZ', 'AT', 'NO', 'DK',
  };

  static const Set<String> euTier2 = {
    'GB', 'FR', 'CH', 'BE', 'IE', 'ES', 'IT', 'RO', 'HU', 'SK', 'BG', 'MD', 'PT', 'GR',
  };

  static const Set<String> aiTier3 = {
    'US', 'CA', 'JP', 'SG', 'KR', 'AU', 'TW', 'NZ',
  };

  static final List<CountryRule> _rules = [
    CountryRule('DE', '🇩🇪', r'(?:^|[^A-Za-z])(?:DE|GER)(?=$|[^A-Za-z])', r'german|герман|frankfurt|франкфурт|berlin|munich|falkenstein|nuremberg|dusseldorf|hetzner'),
    CountryRule('NL', '🇳🇱', r'(?:^|[^A-Za-z])(?:NL|NLD)(?=$|[^A-Za-z])', r'nether|holland|нидерланд|голланд|amster|амстердам|haarlem|rotterdam'),
    CountryRule('PL', '🇵🇱', r'(?:^|[^A-Za-z])(?:PL|POL)(?=$|[^A-Za-z])', r'poland|польш|warsaw|варшав|gdansk|krakow|wroclaw'),
    CountryRule('FI', '🇫🇮', r'(?:^|[^A-Za-z])(?:FI|FIN)(?=$|[^A-Za-z])', r'finland|финлянд|helsinki|хельсинки|espoo|tampere'),
    CountryRule('LT', '🇱🇹', r'(?:^|[^A-Za-z])(?:LT|LTU)(?=$|[^A-Za-z])', r'lithuania|литв|vilnius|вильнюс|kaunas'),
    CountryRule('LV', '🇱🇻', r'(?:^|[^A-Za-z])(?:LV|LVA)(?=$|[^A-Za-z])', r'latvia|латв|riga|рига'),
    CountryRule('EE', '🇪🇪', r'(?:^|[^A-Za-z])(?:EE|EST)(?=$|[^A-Za-z])', r'estonia|эстон|tallinn|таллин'),
    CountryRule('SE', '🇸🇪', r'(?:^|[^A-Za-z])(?:SE|SWE)(?=$|[^A-Za-z])', r'sweden|швец|stockholm|стокгольм|malmo'),
    CountryRule('GB', '🇬🇧', r'(?:^|[^A-Za-z])(?:GB|UK|GBR)(?=$|[^A-Za-z])', r'united.?kingdom|britain|england|великобрит|британ|англи|london|лондон|manchester'),
    CountryRule('FR', '🇫🇷', r'(?:^|[^A-Za-z])(?:FR|FRA)(?=$|[^A-Za-z])', r'france|франц|paris|париж|marseille|strasbourg|roubaix|gravelines'),
    CountryRule('CH', '🇨🇭', r'(?:^|[^A-Za-z])(?:CH|CHE)(?=$|[^A-Za-z])', r'switz|швейцар|zurich|цюрих|geneva|basel'),
    CountryRule('US', '🇺🇸', r'(?:^|[^A-Za-z])(?:US|USA)(?=$|[^A-Za-z])', r'united.?states|america|сша|америк|new.?york|ashburn|dallas|los.?angeles|miami|seattle|chicago|atlanta|silicon.?valley|virginia|phoenix'),
    CountryRule('CA', '🇨🇦', r'(?:^|[^A-Za-z])(?:CA|CAN)(?=$|[^A-Za-z])', r'canada|канад|toronto|торонто|montreal|vancouver'),
    CountryRule('CZ', '🇨🇿', r'(?:^|[^A-Za-z])(?:CZ|CZE)(?=$|[^A-Za-z])', r'czech|чехи|prague|прага|praha'),
    CountryRule('AT', '🇦🇹', r'(?:^|[\[\(【|•·_\-])(?:AT|AUT)(?:[\]\)】|•·_\-\d]|$)', r'austria|австр|vienna|вена|wien'),
    CountryRule('NO', '🇳🇴', r'(?:^|[\[\(【|•·_\-])(?:NO|NOR)(?:[\]\)】|•·_\-\d]|$)', r'norway|норвег|oslo|осло'),
    CountryRule('DK', '🇩🇰', r'(?:^|[^A-Za-z])(?:DK|DNK)(?=$|[^A-Za-z])', r'denmark|дани|copenhagen|копенгаген'),
    CountryRule('BE', '🇧🇪', r'(?:^|[^A-Za-z])(?:BE|BEL)(?=$|[^A-Za-z])', r'belgium|бельг|brussels|брюссель'),
    CountryRule('IE', '🇮🇪', r'(?:^|[^A-Za-z])(?:IE|IRL)(?=$|[^A-Za-z])', r'ireland|ирланд|dublin|дублин'),
    CountryRule('ES', '🇪🇸', r'(?:^|[^A-Za-z])(?:ES|ESP)(?=$|[^A-Za-z])', r'spain|испан|madrid|мадрид|barcelona'),
    CountryRule('IT', '🇮🇹', r'(?:^|[\[\(【|•·_\-])(?:IT|ITA)(?:[\]\)】|•·_\-\d]|$)', r'italy|итал|milan|милан|rome|рим|turin'),
    CountryRule('PT', '🇵🇹', r'(?:^|[^A-Za-z])(?:PT|PRT)(?=$|[^A-Za-z])', r'portugal|португал|lisbon|лиссабон'),
    CountryRule('GR', '🇬🇷', r'(?:^|[^A-Za-z])(?:GR|GRC)(?=$|[^A-Za-z])', r'greece|грец|athens|афины'),
    CountryRule('RO', '🇷🇴', r'(?:^|[^A-Za-z])(?:RO|ROU)(?=$|[^A-Za-z])', r'romania|румын|bucharest|бухарест'),
    CountryRule('HU', '🇭🇺', r'(?:^|[^A-Za-z])(?:HU|HUN)(?=$|[^A-Za-z])', r'hungary|венгр|budapest|будапешт'),
    CountryRule('SK', '🇸🇰', r'(?:^|[^A-Za-z])(?:SK|SVK)(?=$|[^A-Za-z])', r'slovakia|словак|bratislava|братислав'),
    CountryRule('BG', '🇧🇬', r'(?:^|[^A-Za-z])(?:BG|BGR)(?=$|[^A-Za-z])', r'bulgaria|болгар|sofia|софия'),
    CountryRule('MD', '🇲🇩', r'(?:^|[^A-Za-z])(?:MD|MDA)(?=$|[^A-Za-z])', r'moldova|молдов|молдав|chisinau|кишин'),
    CountryRule('LU', '🇱🇺', r'(?:^|[^A-Za-z])(?:LU|LUX)(?=$|[^A-Za-z])', r'luxembourg|люксембург'),
    CountryRule('IS', '🇮🇸', r'(?:^|[\[\(【|•·_\-])(?:IS|ISL)(?:[\]\)】|•·_\-\d]|$)', r'iceland|исланд|reykjavik'),
    CountryRule('CY', '🇨🇾', r'(?:^|[^A-Za-z])(?:CY|CYP)(?=$|[^A-Za-z])', r'cyprus|кипр|limassol|nicosia'),
    CountryRule('RS', '🇷🇸', r'(?:^|[^A-Za-z])(?:RS|SRB)(?=$|[^A-Za-z])', r'serbia|серб|belgrade|белград'),
    CountryRule('HR', '🇭🇷', r'(?:^|[^A-Za-z])(?:HR|HRV)(?=$|[^A-Za-z])', r'croatia|хорват|zagreb'),
    CountryRule('SI', '🇸🇮', r'(?:^|[^A-Za-z])(?:SI|SVN)(?=$|[^A-Za-z])', r'slovenia|словен|ljubljana'),
    CountryRule('SG', '🇸🇬', r'(?:^|[^A-Za-z])(?:SG|SGP)(?=$|[^A-Za-z])', r'singapore|сингапур'),
    CountryRule('JP', '🇯🇵', r'(?:^|[^A-Za-z])(?:JP|JPN)(?=$|[^A-Za-z])', r'japan|япон|tokyo|токио|osaka'),
    CountryRule('KR', '🇰🇷', r'(?:^|[^A-Za-z])(?:KR|KOR)(?=$|[^A-Za-z])', r'korea|коре|seoul|сеул'),
    CountryRule('TW', '🇹🇼', r'(?:^|[^A-Za-z])(?:TW|TWN)(?=$|[^A-Za-z])', r'taiwan|тайван|taipei|тайбэ'),
    CountryRule('AU', '🇦🇺', r'(?:^|[^A-Za-z])(?:AU|AUS)(?=$|[^A-Za-z])', r'australia|австрал|sydney|сидней|melbourne'),
    CountryRule('NZ', '🇳🇿', r'(?:^|[^A-Za-z])(?:NZ|NZL)(?=$|[^A-Za-z])', r'new.?zealand|зеланд|auckland'),
    CountryRule('UA', '🇺🇦', r'(?:^|[^A-Za-z])(?:UA|UKR)(?=$|[^A-Za-z])', r'ukraine|украин|kyiv|kiev|киев|kharkiv|lviv|odessa'),
    CountryRule('TR', '🇹🇷', r'(?:^|[^A-Za-z])(?:TR|TUR)(?=$|[^A-Za-z])', r'turkey|turkiye|турц|istanbul|стамбул|ankara|izmir'),
    CountryRule('AE', '🇦🇪', r'(?:^|[^A-Za-z])(?:AE|UAE)(?=$|[^A-Za-z])', r'dubai|emirates|дуба|оаэ'),
    CountryRule('IL', '🇮🇱', r'(?:^|[^A-Za-z])(?:IL|ISR)(?=$|[^A-Za-z])', r'israel|израил|tel.?aviv'),
    CountryRule('BR', '🇧🇷', r'(?:^|[^A-Za-z])(?:BR|BRA)(?=$|[^A-Za-z])', r'brazil|бразил|sao.?paulo'),
    CountryRule('KZ', '🇰🇿', r'(?:^|[^A-Za-z])(?:KZ|KAZ)(?=$|[^A-Za-z])', r'kazakh|казахст|almaty|astana|алмат|астан'),
    CountryRule('AM', '🇦🇲', r'(?:^|[\[\(【|•·_\-])(?:AM|ARM)(?:[\]\)】|•·_\-\d]|$)', r'armenia|армен|ереван|yerevan'),
    CountryRule('GE', '🇬🇪', r'(?:^|[^A-Za-z])(?:GE|GEO)(?=$|[^A-Za-z])', r'georgia|груз|тбилис|tbilisi'),
    CountryRule('AZ', '🇦🇿', r'(?:^|[^A-Za-z])(?:AZ|AZE)(?=$|[^A-Za-z])', r'azerbaijan|азербайдж|baku|баку'),
    CountryRule('UZ', '🇺🇿', r'(?:^|[^A-Za-z])(?:UZ|UZB)(?=$|[^A-Za-z])', r'uzbek|узбек|tashkent|ташкент'),
    CountryRule('IN', '🇮🇳', r'(?:^|[\[\(【|•·_\-])(?:IN|IND)(?:[\]\)】|•·_\-\d]|$)', r'india|инди|mumbai|bangalore|delhi'),
    CountryRule('RU', '🇷🇺', r'(?:^|[\[\(【|•·_\-])(?:RU|RUS)(?:[\]\)】|•·_\-\d]|$)', r'russia|росси|moscow|moskva|москв|saint.?petersburg|petersburg|петербург|питер|\bspb\b|novosibirsk|ekaterinburg|yekaterinburg|kazan|samara|vladivostok|krasnodar|sochi|rostov'),
    CountryRule('BY', '🇧🇾', r'(?:^|[\[\(【|•·_\-])(?:BY|BLR)(?:[\]\)】|•·_\-\d]|$)', r'belarus|беларус|белорус|minsk|минск|brest|gomel|grodno'),
    CountryRule('CN', '🇨🇳', r'(?:^|[^A-Za-z])(?:CN|CHN)(?=$|[^A-Za-z])', r'china|кита|beijing|shanghai|shenzhen|guangzhou|hangzhou|chengdu'),
    CountryRule('HK', '🇭🇰', r'(?:^|[^A-Za-z])(?:HK|HKG)(?=$|[^A-Za-z])', r'hong.?kong|hongkong|гонконг'),
    CountryRule('MO', '🇲🇴', r'(?:^|[^A-Za-z])(?:MO|MAC)(?=$|[^A-Za-z])', r'macau|macao|макао'),
    CountryRule('IR', '🇮🇷', r'(?:^|[^A-Za-z])(?:IR|IRN)(?=$|[^A-Za-z])', r'iran|иран|tehran|isfahan|shiraz'),
  ];

  static final RegExp _ruAudienceOnly = RegExp(
    r'(?:black[_\-\s]*(?:vless|ss\+?all)[_\-\s]*rus|for[_\-\s]*ru(?:s|ssia)?|bypass[_\-\s]*ru(?:s|ssia)?|ru[_\-\s]*bypass|(?:^|[\[\(\|#_\-\s])rus(?:[\]\)\s_\-\d]|$))',
    caseSensitive: false,
  );

  static final RegExp _ruPhysical = RegExp(
    r'🇷🇺|russia|росси|moscow|moskva|москв|saint.?petersburg|petersburg|петербург|питер|\bspb\b|novosibirsk|ekaterinburg|yekaterinburg|kazan|samara|vladivostok|krasnodar|sochi|rostov',
    caseSensitive: false,
  );

  static final RegExp _tldRegex = RegExp(
    r'\.(de|nl|pl|fi|ee|lv|lt|se|fr|ch|cz|at|no|dk|be|ie|es|it|pt|gr|ro|hu|sk|bg|md|lu|is|cy|rs|hr|si|sg|jp|kr|tw|au|nz|ua|tr|ae|il|br|kz|am|ge|az|uz|in|ru|by|cn|hk|ir)$',
  );

  static String detect(String name, [String address = '']) {
    for (final rule in _rules) {
      if (rule.code == 'RU') continue;
      if (name.contains(rule.flag)) return rule.code;
    }

    final cleaned = name.replaceAll(RegExp(r'https?:\/\/\S+|t\.me\/\S+|@\S+', caseSensitive: false), ' ').trim();
    for (final rule in _rules) {
      if (rule.code == 'RU') continue;
      if (rule.wordPattern.hasMatch(cleaned)) return rule.code;
    }
    for (final rule in _rules) {
      if (rule.code == 'RU') continue;
      if (rule.codePattern.hasMatch(cleaned)) return rule.code;
    }

    final host = address.trim().toLowerCase();
    final tld = _tldRegex.firstMatch(host);
    if (tld != null) return tld.group(1)!.toUpperCase();

    if (_ruPhysical.hasMatch(cleaned) && !_ruAudienceOnly.hasMatch(cleaned)) return 'RU';
    if (RegExp(r'(?:^|[\[\(【|•·_\-])RU(?:[\]\)】|•·_\-\d]|$)').hasMatch(cleaned) &&
        !_ruAudienceOnly.hasMatch(cleaned)) {
      return 'RU';
    }
    return 'WW';
  }

  static String flagEmoji(String code) {
    final clean = code.trim().toUpperCase();
    for (final rule in _rules) {
      if (rule.code == clean) return rule.flag;
    }
    return '🌐';
  }
}
