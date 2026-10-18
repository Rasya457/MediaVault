import 'dart:io';

import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

class StorageException implements Exception {
  final String message;

  const StorageException(this.message);

  @override
  String toString() => 'StorageException: $message';
}

/// Jenis media untuk routing penyimpanan.
enum MediaKind { image, video, audio }

/// Petakan ekstensi ke jenis media. Null = tidak didukung.
MediaKind? mediaKindForExtension(String extension) {
  switch (extension.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'webp':
    case 'gif':
      return MediaKind.image;
    case 'mp4':
    case 'mov':
    case 'webm':
    case 'mkv':
      return MediaKind.video;
    case 'mp3':
    case 'm4a':
    case 'weba':
    case 'ogg':
    case 'wav':
      return MediaKind.audio;
    default:
      return null;
  }
}

/// Simpan file ke koleksi publik Android.
///
/// - Foto/video via gal (Pictures/Movies + album MediaVault).
/// - Audio ke folder aplikasi (MediaStore audio butuh channel native +
///   uji device; disengaja interim — lihat README).
class StorageService {
  static const album = 'MediaVault';

  Future<void> ensureGalleryAccess() async {
    if (await Gal.hasAccess(toAlbum: true)) return;
    if (!await Gal.requestAccess(toAlbum: true)) {
      throw const StorageException('Izin galeri ditolak');
    }
  }

  Future<void> saveImage(File file) async {
    await _ensureFile(file);
    await ensureGalleryAccess();
    try {
      await Gal.putImage(file.path, album: album);
    } on GalException catch (e) {
      throw StorageException(_galMessage(e, isVideo: false));
    } on PlatformException catch (e) {
      throw StorageException('Gagal menyimpan foto ke galeri: ${e.message}');
    } on MissingPluginException {
      throw const StorageException(
        'Plugin galeri belum terpasang. Restart aplikasi lalu coba lagi.',
      );
    }
  }

  Future<void> saveVideo(File file) async {
    await _ensureFile(file);
    await ensureGalleryAccess();
    try {
      await Gal.putVideo(file.path, album: album);
    } on GalException catch (e) {
      throw StorageException(_galMessage(e, isVideo: true));
    } on PlatformException catch (e) {
      throw StorageException('Gagal menyimpan video ke galeri: ${e.message}');
    } on MissingPluginException {
      throw const StorageException(
        'Plugin galeri belum terpasang. Restart aplikasi lalu coba lagi.',
      );
    }
  }

  /// Pastikan file temp benar-benar ada dan tidak kosong sebelum
  /// diserahkan ke plugin galeri (pesan gal yang asli berbahasa Inggris).
  Future<void> _ensureFile(File file) async {
    if (!await file.exists()) {
      throw const StorageException(
        'File unduhan tidak ditemukan. Coba unduh ulang.',
      );
    }
    if (await file.length() == 0) {
      throw const StorageException(
        'File unduhan kosong (0 byte). Periksa koneksi lalu coba lagi.',
      );
    }
  }

  /// Petakan error plugin galeri ke Bahasa Indonesia yang bisa ditindak.
  String _galMessage(GalException e, {required bool isVideo}) {
    switch (e.type) {
      case GalExceptionType.accessDenied:
        return 'Izin galeri ditolak. Aktifkan di Pengaturan > Aplikasi > '
            'MediaVault > Izin, lalu coba lagi.';
      case GalExceptionType.notEnoughSpace:
        return 'Penyimpanan penuh. Kosongkan ruang lalu coba lagi.';
      case GalExceptionType.notSupportedFormat:
        return isVideo
            ? 'Format video tidak didukung galeri. Pilih kualitas MP4 '
                '(bukan WEBM).'
            : 'Format gambar tidak didukung galeri. Coba file JPG/PNG.';
      case GalExceptionType.unexpected:
        return 'Gagal menyimpan ke galeri: ${e.type.message}';
    }
  }

  /// Audio disimpan di folder publik Music/Download (Android) atau Application Documents,
  /// sehingga dapat langsung dideteksi oleh pemutar musik dan file manager.
  Future<File> saveAudio(File file) async {
    Directory? targetDir;
    if (Platform.isAndroid) {
      for (final p in [
        '/storage/emulated/0/Music/$album',
        '/storage/emulated/0/Download/$album',
      ]) {
        try {
          final d = Directory(p);
          if (await d.exists() ||
              (await d
                  .create(recursive: true)
                  .then((_) => true)
                  .catchError((_) => false))) {
            targetDir = d;
            break;
          }
        } catch (_) {}
      }
      targetDir ??= await getExternalStorageDirectory();
    }
    targetDir ??= await getDownloadsDirectory();
    targetDir ??= await getApplicationDocumentsDirectory();

    final dir = Directory(targetDir.path.endsWith(album) || targetDir.path.contains(album)
        ? targetDir.path
        : '${targetDir.path}/$album/audio');
    await dir.create(recursive: true);
    return file.copy('${dir.path}/${_basename(file.path)}');
  }

  static String _basename(String path) =>
      path.split(Platform.pathSeparator).last;
}
