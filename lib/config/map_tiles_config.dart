import 'package:flutter/material.dart';

/// Basemap tiles for the MMaT heatmap.
///
/// Tiles are CARTO raster basemaps built on OpenStreetMap data
/// (https://carto.com/basemaps). Free use requires:
///   1. A CARTO-issued API key (free; request one at
///      https://carto.com/basemaps/apikey/). Without a key CARTO serves
///      tiles with an "API key required" watermark.
///   2. Visible attribution to both OpenStreetMap and CARTO on every map.
///      The heatmap view renders this permanently in the corner of the map.
///
/// The free tier allows 1M tile requests/month for commercial use and 5M/month
/// for non-commercial use (CARTO Basemaps Terms, Sept 2026).
class MapTilesConfig {
  MapTilesConfig._();

  /// CARTO basemaps API key.
  ///
  /// Supply at build time:
  ///   flutter build ipa --dart-define=CARTO_API_KEY=your_key
  /// or paste the key into `defaultValue` below so Xcode archives pick it up.
  /// The key ships inside the app either way (it is a client-side key), so
  /// restrict it to this app in the CARTO dashboard if that option is offered.
  static const String cartoApiKey =
      String.fromEnvironment('CARTO_API_KEY',
          defaultValue: 'cb1_538n_1_43196b01db1dd5dfed4d4b37');

  static bool get hasCartoKey => cartoApiKey.isNotEmpty;

  /// Tile URL for [style]. `{r}` becomes `@2x` on high-density screens when
  /// the TileLayer's `retinaMode` is enabled.
  static String urlTemplate(BasemapStyle style, Brightness brightness) {
    final path = switch (style.resolve(brightness)) {
      BasemapStyle.dark => 'dark_all',
      BasemapStyle.streets => 'rastertiles/voyager',
      _ => 'light_all',
    };
    final keyParam =
        hasCartoKey ? '?key=${Uri.encodeQueryComponent(cartoApiKey)}' : '';
    return 'https://basemaps.cartocdn.com/$path/{z}/{x}/{y}{r}.png$keyParam';
  }

  static final Uri osmCopyrightUri =
      Uri.parse('https://www.openstreetmap.org/copyright');
  static final Uri cartoAttributionUri =
      Uri.parse('https://carto.com/attributions');
}

/// Basemap styles offered in the map's layer menu.
enum BasemapStyle {
  /// Light basemap in light mode, dark basemap in dark mode.
  auto('Match System', Icons.brightness_auto_outlined),
  light('Light', Icons.light_mode_outlined),
  dark('Dark', Icons.dark_mode_outlined),
  streets('Streets', Icons.map_outlined);

  const BasemapStyle(this.label, this.icon);

  final String label;
  final IconData icon;

  BasemapStyle resolve(Brightness brightness) {
    if (this != BasemapStyle.auto) return this;
    return brightness == Brightness.dark ? BasemapStyle.dark : BasemapStyle.light;
  }
}
