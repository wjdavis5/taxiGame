import 'package:flutter/material.dart';

import '../systems/run_environment.dart';

/// The palette a road profile's district paints with (issue #280).
///
/// One lookup shared by the street renderer ([RoadSegment]) and the
/// skyline renderer ([Background]) so the two can never disagree about
/// what a district looks like. Every colour derives from the profile the
/// environment already rolls — no draw is spent, and the pinned
/// environment output is untouched.
///
/// [standard] is deliberately the pre-#280 palette byte for byte, so a
/// run on the standard street and every pinned golden renders exactly as
/// before; the other districts depart from it.
class DistrictPalette {
  const DistrictPalette({
    required this.surface,
    required this.sidewalk,
    required this.marking,
    required this.intersection,
    required this.building,
    required this.landmark,
  });

  /// Dry asphalt.
  final Color surface;

  /// The kerb-side walk, at the dry colour.
  final Color sidewalk;

  /// Lane dashes and edge lines.
  final Color marking;

  /// The cross street's asphalt.
  final Color intersection;

  /// A skyline body at noon.
  final Color building;

  /// The landmark silhouette at noon.
  final Color landmark;

  static const DistrictPalette _standard = DistrictPalette(
    surface: Color(0xFF404040),
    sidewalk: Color(0xFFBDBDBD),
    marking: Colors.white,
    intersection: Color(0xFF4A4A4A),
    building: Color(0xFF616161),
    landmark: Color(0xFF4E5259),
  );

  static const DistrictPalette _narrow = DistrictPalette(
    surface: Color(0xFF4A3E34),
    sidewalk: Color(0xFFC4AE8E),
    marking: Color(0xFFE8D9A8),
    intersection: Color(0xFF544639),
    building: Color(0xFF8A5A44),
    landmark: Color(0xFFB9A38C),
  );

  static const DistrictPalette _avenue = DistrictPalette(
    surface: Color(0xFF3C4650),
    sidewalk: Color(0xFFC6CBD3),
    marking: Color(0xFFF4F7FF),
    intersection: Color(0xFF46505A),
    building: Color(0xFF8E97A3),
    landmark: Color(0xFF6E7683),
  );

  /// The palette of [profile]'s district.
  static DistrictPalette of(RoadProfile profile) => switch (profile) {
        RoadProfile.standard => _standard,
        RoadProfile.narrow => _narrow,
        RoadProfile.avenue => _avenue,
      };

  /// The colour a wet [sidewalk] dries toward — the same rain tint every
  /// district shares, because rain is weather, not place.
  static const Color wetSidewalk = Color(0xFF6E7A86);
}
