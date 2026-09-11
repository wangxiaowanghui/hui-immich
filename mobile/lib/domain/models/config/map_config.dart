import 'package:flutter/material.dart';
import 'package:immich_mobile/utils/option.dart';

class MapConfig {
  final int relativeDays;
  final bool favoritesOnly;
  final bool includeArchived;
  final ThemeMode themeMode;
  final bool withPartners;
  final int amapPrivacyConsentVersion;
  final DateTime? customFrom;
  final DateTime? customTo;

  const MapConfig({
    this.relativeDays = 0,
    this.favoritesOnly = false,
    this.includeArchived = false,
    this.themeMode = .system,
    this.withPartners = false,
    this.amapPrivacyConsentVersion = 0,
    this.customFrom,
    this.customTo,
  });

  MapConfig copyWith({
    int? relativeDays,
    bool? favoritesOnly,
    bool? includeArchived,
    ThemeMode? themeMode,
    bool? withPartners,
    int? amapPrivacyConsentVersion,
    Option<DateTime>? customFrom,
    Option<DateTime>? customTo,
  }) => MapConfig(
    relativeDays: relativeDays ?? this.relativeDays,
    favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    includeArchived: includeArchived ?? this.includeArchived,
    themeMode: themeMode ?? this.themeMode,
    withPartners: withPartners ?? this.withPartners,
    amapPrivacyConsentVersion: amapPrivacyConsentVersion ?? this.amapPrivacyConsentVersion,
    customFrom: customFrom.patch(this.customFrom),
    customTo: customTo.patch(this.customTo),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MapConfig &&
          other.relativeDays == relativeDays &&
          other.favoritesOnly == favoritesOnly &&
          other.includeArchived == includeArchived &&
          other.themeMode == themeMode &&
          other.withPartners == withPartners &&
          other.amapPrivacyConsentVersion == amapPrivacyConsentVersion &&
          other.customFrom == customFrom &&
          other.customTo == customTo);

  @override
  int get hashCode => Object.hash(
    relativeDays,
    favoritesOnly,
    includeArchived,
    themeMode,
    withPartners,
    amapPrivacyConsentVersion,
    customFrom,
    customTo,
  );

  @override
  String toString() =>
      'MapConfig(relativeDays: $relativeDays, favoritesOnly: $favoritesOnly, includeArchived: $includeArchived, themeMode: $themeMode, withPartners: $withPartners, amapPrivacyConsentVersion: $amapPrivacyConsentVersion, customFrom: $customFrom, customTo: $customTo)';
}
