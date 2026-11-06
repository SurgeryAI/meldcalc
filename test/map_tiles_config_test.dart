import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meldcalc/config/map_tiles_config.dart';

void main() {
  test('Basemap URLs use CARTO with a retina placeholder', () {
    for (final style in BasemapStyle.values) {
      for (final b in Brightness.values) {
        final url = MapTilesConfig.urlTemplate(style, b);
        expect(url, startsWith('https://basemaps.cartocdn.com/'));
        expect(url, contains('/{z}/{x}/{y}{r}.png'));
        expect(url, isNot(contains('google')));
      }
    }
  });

  test('Match System follows the platform brightness', () {
    expect(MapTilesConfig.urlTemplate(BasemapStyle.auto, Brightness.light),
        contains('/light_all/'));
    expect(MapTilesConfig.urlTemplate(BasemapStyle.auto, Brightness.dark),
        contains('/dark_all/'));
    expect(MapTilesConfig.urlTemplate(BasemapStyle.streets, Brightness.dark),
        contains('/rastertiles/voyager/'));
  });
}
