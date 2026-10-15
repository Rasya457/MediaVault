import 'dart:io';

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
    await ensureGalleryAccess();
    try {
      await Gal.putImage(file.path, album: album);
    } on GalException catch (e) {
      throw StorageException(e.type.message);
    }
  }

  Future<void> saveVideo(File file) async {
    await ensureGalleryAccess();
    try {
      await Gal.putVideo(file.path, album: album);
    } on GalException catch (e) {
      throw StorageException(e.type.message);
    }
  }

  /// Audio disimpan di folder aplikasi (bukan galeri sistem).
  /// Alasan: butuh MediaStore audio via channel native yang belum teruji
  /// di device. File tetap ada dan bisa diputar in-app nantinya.
  Future<File> saveAudio(File file) async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/$album/audio',
    );
    await dir.create(recursive: true);
    return file.copy('${dir.path}/${_basename(file.path)}');
  }

  static String _basename(String path) =>
      path.split(Platform.pathSeparator).last;
}
