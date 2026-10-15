// Design tokens MORI — satu-satunya sumber kebenaran untuk warna & ukuran.
// Sesuai panduan neo-brutalist & spesifikasi MORI Home.

import 'package:flutter/material.dart';

abstract class MoriColors {
  /// background krem netral: #F5F3EC
  static const background = Color(0xFFF5F3EC);

  /// surface (input, tile platform): #EDEBE4
  static const surface    = Color(0xFFEDEBE4);

  /// ink (teks utama, tombol ANALYZE, border, ikon): #121212 (hampir hitam murni)
  static const ink        = Color(0xFF121212);

  /// border input saat fokus/aktif: #121212
  static const activeBorder = Color(0xFF121212);

  /// hint / placeholder: #9E9E9E
  static const hint       = Color(0xFF9E9E9E);

  /// label abu (SUPPORTED PLATFORMS, item nav tidak aktif): #6B6B6B
  static const label      = Color(0xFF6B6B6B);

  /// fill background tombol FAB: #EDEBE4
  static const fabFill    = Color(0xFFEDEBE4);

  /// border abu tombol FAB: #BDBDBD
  static const fabBorder  = Color(0xFFBDBDBD);
}

abstract class MoriRadius {
  static const double field  = 10;
  static const double button = 10;
  static const double tile   = 0; // sudut siku (radius 0) intentional neo-brutalist
}

abstract class MoriSpacing {
  static const double pagePad    = 20;
  static const double titleTop   = 40;
  static const double afterTitle = 56;
  static const double afterField = 16;
  static const double afterBtn   = 48;
  static const double afterLabel = 24;
  static const double gridGap    = 12;
  static const double tileHeight = 41;
}

abstract class MoriText {
  static const double titleSize   = 42;
  static const double labelSize   = 12;
  static const double fieldSize   = 17;
  static const double btnSize     = 16;
  static const double tileSize    = 15;

  static const double titleLetterSpacing = 2;
  static const double labelLetterSpacing = 2.5;
  static const double btnLetterSpacing   = 3;
  static const double tileLetterSpacing  = 1.5;
  static const double navLetterSpacing   = 1.2;

  static const double navLabelSize = 11;
}

abstract class MoriBorder {
  static const double field = 1.5;
  static const double tile  = 1.5;
  static const double fab   = 2.0;
  static const double nav   = 1.0;
}