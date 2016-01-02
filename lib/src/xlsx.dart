part of spreadsheet;

/// Convert a character based column
int lettersToNumeric(String letters) {
  var sum = 0;
  var mul = 1;
  var n;
  for (var index = letters.length - 1; index >= 0; index--) {
    var c = letters[index].codeUnitAt(0);
    n = 1;
    if (65 <= c && c <= 90) {
      n += c - 65;
    } else if (97 <= c && c <= 122) {
      n += c - 97;
    }
    sum += n * mul;
    mul = mul * 26;
  }
  return sum;
}

int _letterOnly(int rune) {
  if (65 <= rune && rune <= 90) {
    return rune;
  } else if (97 <= rune && rune <= 122) {
    return rune - 32;
  }
  return 0;
}

int _intOnly(int rune) {
  if (rune >= 48 && rune < 58) {
    return rune;
  }
  return 0;
}

/// Returns the coordinates from a cell name.
/// "A1" returns [1, 1] and the "B3" return [2, 3].
List cellCoordsFromCellId(String cellId) {
  var letters = cellId.runes.map(_letterOnly);
  var lettersPart = UTF8.decode(letters.where((rune) => rune > 0).toList(growable: false));
  var numericsPart = cellId.substring(lettersPart.length);
  var x = lettersToNumeric(lettersPart);
  var y = int.parse(numericsPart);
  return [x, y];
}

/// Read and parse XSLX spreadsheet
class XlsxDecoder extends SpreadsheetDecoder {
  List<String> _sharedStrings = new List<String>();

  XlsxDecoder(Archive archive) {
    this._archive = archive;
    _tables = new Map<String, SpreadsheetTable>();
    _parseSharedStrings();
    _parseContent();
  }

  _parseSharedStrings() {
    var sharedStrings = _archive.findFile('xl/sharedStrings.xml');
    if (sharedStrings != null) {
      sharedStrings.decompress();
      var document = parse(UTF8.decode(sharedStrings.content));
      document.findAllElements('si').forEach((node) {
        _parseSharedString(node);
      });
    }
  }

  _parseSharedString(XmlElement node) {
    var list = new List();
    node.findAllElements('t').forEach((child) {
      list.add(_parseValue(child));
    });
    _sharedStrings.add(list.join(''));
  }

  _parseContent() {
    var workbook = _archive.findFile('xl/workbook.xml');
    workbook.decompress();
    var document = parse(UTF8.decode(workbook.content));
    document.findAllElements('sheet').forEach((node) {
      _parseTable(node);
    });
  }

  _parseTable(XmlElement node) {
    var name = node.getAttribute('name');
    var id = node.getAttribute('sheetId');
    tables[name] = new SpreadsheetTable();
    var table = tables[name];

    var sheet = _archive.findFile('xl/worksheets/sheet$id.xml');
    sheet.decompress();

    var document = parse(UTF8.decode(sheet.content));
    document.findAllElements('row').forEach((child) {
      _parseRow(child, table);
    });

    _normalizeTable(table);
  }

  _parseRow(XmlElement node, SpreadsheetTable table) {
    var row = new List();

    node.findElements('c').forEach((child) {
      _parseCell(child, table, row);
    });

    var rowNumber = int.parse(node.getAttribute('r'));
    if (_isNotEmptyRow(row) && rowNumber > table._rows.length + 1) {
      var repeat = rowNumber - table._rows.length - 1;
      for (var index = 0; index < repeat; index++) {
        table._rows.add(_emptyRow);
      }
    }

    if (_isNotEmptyRow(row)) {
      table._rows.add(row);
    } else {
      table._rows.add(_emptyRow);
    }

    _countFilledRow(table, row);
  }

  _parseCell(XmlElement node, SpreadsheetTable table, List row) {
    var list = new List<String>();

    var coords = cellCoordsFromCellId(node.getAttribute('r'));
    var colNumber = coords[0] - 1;
    if (colNumber > row.length) {
      var repeat = colNumber - table._rows.length + 1;
      for (var index = 0; index < repeat; index++) {
        row.add(null);
      }
    }

    node.findElements('v').forEach((child) {
      var type = node.getAttribute('t');
      if (type == 's') {
        list.add(_sharedStrings[int.parse(_parseValue(child))]);
      } else {
        list.add(_parseValue(child));
      }
    });

    var text = (list.isNotEmpty) ? list.join('').trim() : null;
    row.add(text);

    _countFilledColumn(table, row, text);
  }

  _parseValue(XmlElement node) {
    var buffer = new StringBuffer();

    node.children.forEach((child) {
      if (child is XmlElement) {
        buffer.write(_unescape(_parseValue(child)));
      } else if (child is XmlText) {
        buffer.write(_unescape(child.text));
      }
    });

    return buffer.toString();
  }
}
