import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadHistoryEntry {
  const DownloadHistoryEntry({
    required this.id,
    required this.url,
    required this.title,
    required this.platform,
    required this.quality,
    required this.extension,
    required this.timestamp,
    this.thumbnail,
    this.savedPath,
  });

  final String id;
  final String url;
  final String title;
  final String platform;
  final String quality;
  final String extension;
  final DateTime timestamp;
  final String? thumbnail;
  final String? savedPath;

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'platform': platform,
        'quality': quality,
        'extension': extension,
        'timestamp': timestamp.toIso8601String(),
        if (thumbnail != null) 'thumbnail': thumbnail,
        if (savedPath != null) 'savedPath': savedPath,
      };

  factory DownloadHistoryEntry.fromJson(Map<String, dynamic> j) =>
      DownloadHistoryEntry(
        id: j['id'] as String,
        url: j['url'] as String,
        title: j['title'] as String,
        platform: j['platform'] as String,
        quality: j['quality'] as String,
        extension: j['extension'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        thumbnail: j['thumbnail'] as String?,
        savedPath: j['savedPath'] as String?,
      );

  /// Label ekstensi singkat untuk tampil di UI.
  String get kindLabel {
    switch (extension.toLowerCase()) {
      case 'mp3':
      case 'm4a':
        return 'AUDIO';
      case 'mp4':
      case 'mov':
        return 'VIDEO';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
        return 'PHOTO';
      default:
        return extension.toUpperCase();
    }
  }
}

class HistoryRepository {
  static const _key = 'mori_download_history_v1';
  static const _maxEntries = 200;

  static HistoryRepository? _instance;
  static HistoryRepository get instance =>
      _instance ??= HistoryRepository._();
  HistoryRepository._();

  Future<List<DownloadHistoryEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final entries = <DownloadHistoryEntry>[];
    for (final s in raw) {
      try {
        entries.add(
          DownloadHistoryEntry.fromJson(
            (jsonDecode(s) as Map).cast<String, dynamic>(),
          ),
        );
      } catch (_) {}
    }
    // Terbaru di atas
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  Future<void> add(DownloadHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.insert(0, jsonEncode(entry.toJson()));
    // Potong jika melebihi batas
    if (raw.length > _maxEntries) {
      raw.removeRange(_maxEntries, raw.length);
    }
    await prefs.setStringList(_key, raw);
  }

  Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.removeWhere((s) {
      try {
        return (jsonDecode(s) as Map)['id'] == id;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_key, raw);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
