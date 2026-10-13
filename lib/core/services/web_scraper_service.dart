import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Service responsible for fetching website hero metadata, og:image/hero image,
/// and scraping readable article/page content.
class WebScraperService {
  WebScraperService._();
  static final WebScraperService instance = WebScraperService._();

  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true);

  /// Scrapes a web URL: extracts title, clean content summary, and downloads/saves the hero thumbnail.
  /// Returns a map with:
  /// - `title`: String
  /// - `content`: String (clean text snippet/summary)
  /// - `thumbnailPath`: String? (local file path to downloaded hero image)
  /// - `heroImageUrl`: String?
  /// - `host`: String
  Future<Map<String, dynamic>> scrapeUrl(String rawUrl) async {
    String cleanUrl = rawUrl.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }

    Uri? uri;
    try {
      uri = Uri.parse(cleanUrl);
    } catch (e) {
      debugPrint('[WebScraperService] Invalid URI: $rawUrl');
      return {
        'title': 'Saved Link',
        'content': rawUrl,
        'thumbnailPath': null,
        'heroImageUrl': null,
        'host': rawUrl,
      };
    }

    final host = uri.host.isNotEmpty ? uri.host : 'Website';
    String title = 'Bookmark: $host';
    String content = 'Website link: $cleanUrl';
    String? heroImageUrl;
    String? localThumbnailPath;

    try {
      final request = await _httpClient.getUrl(uri);
      request.headers.set('User-Agent', 'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36');
      request.headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8');

      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode >= 200 && response.statusCode < 400) {
        // Read response body with safe encoding handling
        final bytes = await response.fold<List<int>>([], (prev, element) => prev..addAll(element));
        String html = '';
        try {
          html = utf8.decode(bytes, allowMalformed: true);
        } catch (_) {
          html = latin1.decode(bytes);
        }

        if (html.isNotEmpty) {
          // 1. Extract Title
          final ogTitleMatch = RegExp(r'<meta[^>]+property=["' "'" r']og:title["' "'" r'][^>]+content=["' "'" r']([^"' "'" r']+)["' "'" r']', caseSensitive: false).firstMatch(html) ??
              RegExp(r'<meta[^>]+content=["' "'" r']([^"' "'" r']+)["' "'" r'][^>]+property=["' "'" r']og:title["' "'" r']', caseSensitive: false).firstMatch(html);

          final titleMatch = RegExp(r'<title[^>]*>([^<]+)<\/title>', caseSensitive: false).firstMatch(html);

          if (ogTitleMatch != null && ogTitleMatch.group(1)?.trim().isNotEmpty == true) {
            title = _cleanHtmlEntities(ogTitleMatch.group(1)!.trim());
          } else if (titleMatch != null && titleMatch.group(1)?.trim().isNotEmpty == true) {
            title = _cleanHtmlEntities(titleMatch.group(1)!.trim());
          }

          // 2. Extract Hero Image (og:image / twitter:image / hero img)
          final ogImageMatch = RegExp(r'<meta[^>]+property=["' "'" r']og:image["' "'" r'][^>]+content=["' "'" r']([^"' "'" r']+)["' "'" r']', caseSensitive: false).firstMatch(html) ??
              RegExp(r'<meta[^>]+content=["' "'" r']([^"' "'" r']+)["' "'" r'][^>]+property=["' "'" r']og:image["' "'" r']', caseSensitive: false).firstMatch(html) ??
              RegExp(r'<meta[^>]+name=["' "'" r']twitter:image["' "'" r'][^>]+content=["' "'" r']([^"' "'" r']+)["' "'" r']', caseSensitive: false).firstMatch(html);

          if (ogImageMatch != null && ogImageMatch.group(1)?.trim().isNotEmpty == true) {
            heroImageUrl = ogImageMatch.group(1)!.trim();
          } else {
            // Find first major hero image or banner in article / header
            final imgMatch = RegExp(r'<img[^>]+src=["' "'" r']([^"' "'" r']+\.(?:png|jpg|jpeg|webp))["' "'" r']', caseSensitive: false).firstMatch(html);
            if (imgMatch != null) {
              heroImageUrl = imgMatch.group(1)?.trim();
            }
          }

          // Resolve relative image URLs
          if (heroImageUrl != null && !heroImageUrl.startsWith('http://') && !heroImageUrl.startsWith('https://')) {
            if (heroImageUrl.startsWith('//')) {
              heroImageUrl = '${uri.scheme}:$heroImageUrl';
            } else if (heroImageUrl.startsWith('/')) {
              heroImageUrl = '${uri.scheme}://${uri.host}$heroImageUrl';
            } else {
              heroImageUrl = '${uri.scheme}://${uri.host}/${heroImageUrl}';
            }
          }

          // 3. Extract Meta Description & Body Content
          final ogDescMatch = RegExp(r'<meta[^>]+property=["' "'" r']og:description["' "'" r'][^>]+content=["' "'" r']([^"' "'" r']+)["' "'" r']', caseSensitive: false).firstMatch(html) ??
              RegExp(r'<meta[^>]+name=["' "'" r']description["' "'" r'][^>]+content=["' "'" r']([^"' "'" r']+)["' "'" r']', caseSensitive: false).firstMatch(html);

          String description = '';
          if (ogDescMatch != null && ogDescMatch.group(1)?.trim().isNotEmpty == true) {
            description = _cleanHtmlEntities(ogDescMatch.group(1)!.trim());
          }

          // Clean main paragraphs
          final bodyText = _extractReadableText(html);
          if (description.isNotEmpty && bodyText.isNotEmpty) {
            content = '$description\n\n$bodyText';
          } else if (description.isNotEmpty) {
            content = description;
          } else if (bodyText.isNotEmpty) {
            content = bodyText;
          }

          // Limit content length for clean memory entry
          if (content.length > 2500) {
            content = '${content.substring(0, 2500)}...';
          }
        }
      }
    } catch (e) {
      debugPrint('[WebScraperService] HTML fetch error for $cleanUrl: $e');
    }

    // 4. Download and save hero image thumbnail locally if found
    if (heroImageUrl != null && heroImageUrl.isNotEmpty) {
      localThumbnailPath = await _downloadThumbnail(heroImageUrl);
    }

    return {
      'title': title,
      'content': content,
      'thumbnailPath': localThumbnailPath,
      'heroImageUrl': heroImageUrl,
      'host': host,
      'url': cleanUrl,
    };
  }

  /// Downloads the hero image to app documents directory and returns local path
  Future<String?> _downloadThumbnail(String imageUrl) async {
    try {
      final uri = Uri.parse(imageUrl);
      final request = await _httpClient.getUrl(uri);
      request.headers.set('User-Agent', 'Mozilla/5.0 GlanceBot/1.0');
      final response = await request.close().timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 400) {
        final bytes = await response.fold<List<int>>([], (prev, element) => prev..addAll(element));
        if (bytes.length > 500) {
          final dir = await getApplicationDocumentsDirectory();
          final thumbsDir = Directory('${dir.path}/web_thumbs');
          if (!thumbsDir.existsSync()) {
            thumbsDir.createSync(recursive: true);
          }
          final filename = 'thumb_${DateTime.now().millisecondsSinceEpoch}_${uri.pathSegments.isNotEmpty ? uri.pathSegments.last.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '') : 'web.jpg'}';
          final file = File('${thumbsDir.path}/$filename');
          await file.writeAsBytes(bytes);
          return file.path;
        }
      }
    } catch (e) {
      debugPrint('[WebScraperService] Hero image download failed: $e');
    }
    return null;
  }

  static String _extractReadableText(String html) {
    // Strip scripts, styles, svg, and tags
    String clean = html.replaceAll(RegExp(r'<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>', caseSensitive: false), ' ');
    clean = clean.replaceAll(RegExp(r'<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>', caseSensitive: false), ' ');
    clean = clean.replaceAll(RegExp(r'<svg\b[^<]*(?:(?!<\/svg>)<[^<]*)*<\/svg>', caseSensitive: false), ' ');
    clean = clean.replaceAll(RegExp(r'<nav\b[^<]*(?:(?!<\/nav>)<[^<]*)*<\/nav>', caseSensitive: false), ' ');
    clean = clean.replaceAll(RegExp(r'<header\b[^<]*(?:(?!<\/header>)<[^<]*)*<\/header>', caseSensitive: false), ' ');
    clean = clean.replaceAll(RegExp(r'<footer\b[^<]*(?:(?!<\/footer>)<[^<]*)*<\/footer>', caseSensitive: false), ' ');
    clean = clean.replaceAll(RegExp(r'<br\s*[\/]?>', caseSensitive: false), '\n');
    clean = clean.replaceAll(RegExp(r'<\/p>', caseSensitive: false), '\n\n');
    clean = clean.replaceAll(RegExp(r'<\/h[1-6]>', caseSensitive: false), '\n\n');
    clean = clean.replaceAll(RegExp(r'<[^>]+>'), ' ');
    clean = _cleanHtmlEntities(clean);
    clean = clean.replaceAll(RegExp(r'[ \t]+'), ' ');
    clean = clean.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return clean.trim();
  }

  static String _cleanHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#8217;', "'")
        .replaceAll('&#8220;', '"')
        .replaceAll('&#8221;', '"')
        .replaceAll('&#8212;', '—')
        .replaceAll('&#8211;', '–');
  }
}
