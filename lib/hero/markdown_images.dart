import 'dart:typed_data';
import 'dart:isolate';

enum MarkdownImageKind { destination, reference, html }

class MarkdownImageLink {
  final int start, end;
  final String source, prefix, title;
  final MarkdownImageKind kind;
  final bool auxiliary;
  const MarkdownImageLink(
    this.start,
    this.end,
    this.source,
    this.kind, {
    this.prefix = '',
    this.title = '',
    this.auxiliary = false,
  });
  Uri? get uri {
    var value = _entities(source).replaceAllMapped(
      RegExp(r'\\([!"#$%&\x27()*+,\-./:;<=>?@\[\]\\^_`{|}~])'),
      (m) => m[1]!,
    );
    if (value.startsWith('//')) value = 'https:$value';
    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        !['http', 'https'].contains(parsed.scheme) ||
        parsed.host.isEmpty) {
      return null;
    }
    return parsed;
  }

  String replacement(String url) {
    final encoded = Uri.parse(
      url,
    ).toString().replaceAll('(', '%28').replaceAll(')', '%29');
    if (kind == MarkdownImageKind.html) {
      return encoded
          .replaceAll('&', '&amp;')
          .replaceAll('"', '&quot;')
          .replaceAll("'", '&#39;');
    }
    if (kind == MarkdownImageKind.reference) {
      return '$prefix(<$encoded>${title.isEmpty ? '' : ' $title'})';
    }
    return encoded;
  }
}

class MarkdownImageDocument {
  final String text;
  final List<MarkdownImageLink> links;
  const MarkdownImageDocument(this.text, this.links);
  static Future<MarkdownImageDocument> parseAsync(String text) =>
      Isolate.run(() => MarkdownImageDocument.parse(text));
  Iterable<MarkdownImageLink> get images => links.where((e) => !e.auxiliary);
  List<Uri> get remoteUris {
    final unique = <String, Uri>{};
    for (final link in images) {
      final uri = link.uri;
      if (uri != null) unique[uri.toString()] = uri;
    }
    return unique.values.toList();
  }

  String replace(Map<String, String> uploaded) {
    final result = StringBuffer();
    var cursor = 0;
    for (final link in links) {
      final uri = link.uri;
      final next = uri == null ? null : uploaded[uri.toString()];
      if (next == null) continue;
      result.write(text.substring(cursor, link.start));
      result.write(link.replacement(next));
      cursor = link.end;
    }
    result.write(text.substring(cursor));
    return result.toString();
  }

  factory MarkdownImageDocument.parse(String text) {
    final masked = Uint8List(text.length);
    void mask(int start, int end) => masked.fillRange(start, end, 1);
    bool escaped(int index) {
      var count = 0;
      for (var i = index - 1; i >= 0 && text[i] == r'\'; i--) {
        count++;
      }
      return count.isOdd;
    }

    final lines = RegExp(r'^.*(?:\r?\n|$)', multiLine: true).allMatches(text);
    String? fence;
    var fenceLength = 0, fenceStart = 0, fenceQuotes = 0, fenceIndent = 0;
    final lists = <(int, int)>[];
    for (final line in lines) {
      var logical = line[0]!;
      var quotes = 0;
      while (true) {
        final prefix = RegExp(r'^ {0,3}>[ \t]?').firstMatch(logical);
        if (prefix == null) break;
        quotes++;
        logical = logical.substring(prefix.end);
      }
      final indent = RegExp(r'^ *').firstMatch(logical)!.end;
      if (fence != null) {
        if (quotes < fenceQuotes ||
            (logical.trim().isNotEmpty && indent < fenceIndent)) {
          mask(fenceStart, line.start);
          fence = null;
        } else {
          final body = logical.substring(fenceIndent.clamp(0, logical.length));
          final closing = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(body);
          if (closing != null &&
              closing[1]![0] == fence &&
              closing[1]!.length >= fenceLength &&
              body.substring(closing.end).trim().isEmpty) {
            mask(fenceStart, line.end);
            fence = null;
          }
          continue;
        }
      }
      final bullet = RegExp(
        r'^( *)(?:[-+*]|\d+[.)])[ \t]+',
      ).firstMatch(logical);
      if (bullet != null) {
        final listIndent = bullet[1]!.length;
        while (lists.isNotEmpty && lists.last.$1 >= listIndent) {
          lists.removeLast();
        }
        lists.add((listIndent, bullet.end));
        logical = logical.substring(bullet.end);
      } else {
        if (logical.trim().isNotEmpty) {
          while (lists.isNotEmpty && indent < lists.last.$2) {
            lists.removeLast();
          }
        }
        if (lists.isNotEmpty && indent >= lists.last.$2) {
          logical = logical.substring(lists.last.$2);
        }
      }
      final opening = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(logical);
      if (opening != null) {
        fence = opening[1]![0];
        fenceLength = opening[1]!.length;
        fenceStart = line.start;
        fenceQuotes = quotes;
        fenceIndent = lists.isEmpty ? 0 : lists.last.$2;
      } else if (RegExp(r'^(?: {4}|\t)').hasMatch(logical)) {
        mask(line.start, line.end);
      }
    }
    if (fence != null) mask(fenceStart, text.length);
    for (final comment in RegExp(r'<!--[\s\S]*?(?:-->|$)').allMatches(text)) {
      mask(comment.start, comment.end);
    }
    for (var i = 0; i < text.length; i++) {
      if (masked[i] != 0 || text[i] != '`' || escaped(i)) continue;
      var end = i;
      while (end < text.length && text[end] == '`') {
        end++;
      }
      final run = text.substring(i, end);
      var closing = text.indexOf(run, end);
      while (closing >= 0 &&
          ((closing > 0 && text[closing - 1] == '`') ||
              (closing + run.length < text.length &&
                  text[closing + run.length] == '`'))) {
        closing = text.indexOf(run, closing + run.length);
      }
      if (closing >= 0) {
        mask(i, closing + run.length);
        i = closing + run.length - 1;
      } else {
        i = end - 1;
      }
    }
    String referenceKey(String raw) =>
        _entities(raw).replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    final references = <String, (String, String)>{};
    final definition = RegExp(
      r'''^ {0,3}\[([^\]\r\n]+)\]:[ \t]*(?:<([^>\r\n]+)>|(\S+))(?:[ \t]+("[^"\r\n]*"|'[^'\r\n]*'|\([^\)\r\n]*\)))?[ \t]*\r?$''',
      multiLine: true,
    );
    for (final match in definition.allMatches(text)) {
      if (masked[match.start] == 0) {
        references.putIfAbsent(
          referenceKey(match[1]!),
          () => (match[2] ?? match[3]!, match[4] ?? ''),
        );
      }
    }
    (int, int, int)? destination(int open) {
      var cursor = open + 1;
      while (cursor < text.length && RegExp(r'\s').hasMatch(text[cursor])) {
        cursor++;
      }
      if (cursor >= text.length) return null;
      late int start, end;
      if (text[cursor] == '<') {
        start = ++cursor;
        while (cursor < text.length &&
            (text[cursor] != '>' || escaped(cursor))) {
          cursor++;
        }
        if (cursor >= text.length) return null;
        end = cursor++;
      } else {
        start = cursor;
        var nested = 0;
        while (cursor < text.length) {
          final char = text[cursor];
          if (!escaped(cursor)) {
            if (RegExp(r'\s').hasMatch(char) || (char == ')' && nested == 0)) {
              break;
            }
            if (char == '(') nested++;
            if (char == ')') nested--;
          }
          cursor++;
        }
        end = cursor;
      }
      if (end == start) return null;
      while (cursor < text.length && RegExp(r'\s').hasMatch(text[cursor])) {
        cursor++;
      }
      if (cursor < text.length && ['"', "'", '('].contains(text[cursor])) {
        final quote = text[cursor] == '(' ? ')' : text[cursor];
        cursor++;
        while (cursor < text.length &&
            (text[cursor] != quote || escaped(cursor))) {
          cursor++;
        }
        if (cursor >= text.length) return null;
        cursor++;
        while (cursor < text.length && RegExp(r'\s').hasMatch(text[cursor])) {
          cursor++;
        }
      }
      return cursor < text.length && text[cursor] == ')'
          ? (start, end, cursor + 1)
          : null;
    }

    final result = <MarkdownImageLink>[];
    for (var i = 0; i < text.length - 1; i++) {
      if (masked[i] != 0 ||
          text[i] != '!' ||
          text[i + 1] != '[' ||
          escaped(i)) {
        continue;
      }
      var close = i + 2, nesting = 1;
      while (close < text.length && nesting > 0) {
        if (!escaped(close)) {
          if (text[close] == '[') nesting++;
          if (text[close] == ']') nesting--;
        }
        if (nesting > 0) close++;
      }
      if (close >= text.length) continue;
      var after = close + 1;
      MarkdownImageLink? image;
      var imageEnd = after;
      if (after < text.length && text[after] == '(') {
        final parsed = destination(after);
        if (parsed != null) {
          image = MarkdownImageLink(
            parsed.$1,
            parsed.$2,
            text.substring(parsed.$1, parsed.$2),
            MarkdownImageKind.destination,
          );
          imageEnd = parsed.$3;
        }
      } else {
        final alt = text.substring(i + 2, close);
        while (after < text.length &&
            (text[after] == ' ' || text[after] == '\t')) {
          after++;
        }
        var key = alt;
        imageEnd = close + 1;
        if (after < text.length && text[after] == '[') {
          final referenceEnd = text.indexOf(']', after + 1);
          if (referenceEnd < 0) continue;
          final label = text.substring(after + 1, referenceEnd);
          key = label.isEmpty ? alt : label;
          imageEnd = referenceEnd + 1;
        }
        final reference = references[referenceKey(key)];
        if (reference != null) {
          image = MarkdownImageLink(
            i,
            imageEnd,
            reference.$1,
            MarkdownImageKind.reference,
            prefix: text.substring(i, close + 1),
            title: reference.$2,
          );
        }
      }
      if (image == null) continue;
      result.add(image);
      // Keep a link wrapping this exact image working, while leaving ordinary hyperlinks alone.
      if (i > 0 &&
          text[i - 1] == '[' &&
          !escaped(i - 1) &&
          imageEnd + 1 < text.length &&
          text.substring(imageEnd, imageEnd + 2) == '](') {
        final outer = destination(imageEnd + 1);
        if (outer != null) {
          final link = MarkdownImageLink(
            outer.$1,
            outer.$2,
            text.substring(outer.$1, outer.$2),
            MarkdownImageKind.destination,
            auxiliary: true,
          );
          if (image.uri != null && image.uri == link.uri) result.add(link);
        }
      }
      i = imageEnd - 1;
    }
    final tags = RegExp(
      r'''<img\b(?:"[^"]*"|'[^']*'|[^'">])*?>''',
      caseSensitive: false,
    );
    final src = RegExp(
      r'''\ssrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
      caseSensitive: false,
    );
    for (final tag in tags.allMatches(text)) {
      if (masked[tag.start] != 0) continue;
      final match = src.firstMatch(tag[0]!);
      if (match == null) continue;
      final group = match[1] != null
          ? 1
          : match[2] != null
          ? 2
          : 3;
      final value = match[group]!;
      // Attribute content occurs after the '='; include quotes only in the prefix search.
      final equals = match[0]!.indexOf('=');
      var offset = match.start + equals + 1;
      while (offset < tag[0]!.length &&
          RegExp(r'\s').hasMatch(tag[0]![offset])) {
        offset++;
      }
      if (group != 3) offset++;
      final start = tag.start + offset;
      result.add(
        MarkdownImageLink(
          start,
          start + value.length,
          value,
          MarkdownImageKind.html,
        ),
      );
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    // Never apply overlapping edits to malformed Markdown/HTML.
    final nonOverlapping = <MarkdownImageLink>[];
    for (final link in result) {
      if (nonOverlapping.isEmpty || link.start >= nonOverlapping.last.end) {
        nonOverlapping.add(link);
      }
    }
    return MarkdownImageDocument(text, nonOverlapping);
  }
}

String _entities(String text) => text.replaceAllMapped(
  RegExp(r'&(?:amp|quot|apos|lt|gt|#\d+|#x[0-9a-fA-F]+);'),
  (match) {
    final entity = match[0]!;
    final named = {
      '&amp;': '&',
      '&quot;': '"',
      '&apos;': "'",
      '&lt;': '<',
      '&gt;': '>',
    };
    if (named.containsKey(entity)) return named[entity]!;
    final hex = entity.startsWith('&#x');
    final code = int.tryParse(
      entity.substring(hex ? 3 : 2, entity.length - 1),
      radix: hex ? 16 : 10,
    );
    return code == null || code < 0 || code > 0x10ffff
        ? entity
        : String.fromCharCode(code);
  },
);
