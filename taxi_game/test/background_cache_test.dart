import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/components/background.dart';

/// The background's cached shading must be pixel-identical to a fresh
/// build at the same darkness (issue #251). The cache only skips work
/// when [Background.darkness] moves less than its rebuild epsilon; these
/// probes drive darkness across the whole range and compare raw RGBA, so
/// a stale paint or a botched rebuild shows up as differing bytes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Background> loaded() async {
    final bg = Background();
    await bg.onLoad();
    return bg;
  }

  Future<Uint8List> renderAt(Background bg, double darkness) async {
    bg.darkness = darkness;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    bg.render(canvas);
    final image = await recorder.endRecording().toImage(400, 800);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return bytes!.buffer.asUint8List();
  }

  int channel(Uint8List pixels, int x, int y, int c) =>
      pixels[(y * 400 + x) * 4 + c];

  test('crossing the range and returning repaints identical bytes', () async {
    final bg = await loaded();
    final fresh = await renderAt(bg, 0.37);

    // Force the cache through both extremes, then come back: the last
    // render is a rebuild after two invalidations.
    await renderAt(bg, 0);
    await renderAt(bg, 1);
    final rebuilt = await renderAt(bg, 0.37);

    expect(rebuilt, fresh,
        reason: 'a rebuilt cache must equal a freshly built one');
  });

  test('a darkness wiggle inside the epsilon reuses the cache', () async {
    final bg = await loaded();
    final a = await renderAt(bg, 0.37);
    final b = await renderAt(bg, 0.37 + 5e-4);

    expect(b, a,
        reason: 'half an epsilon of drift must not repaint different pixels');
  });

  test('the sky still spans midday to midnight', () async {
    final bg = await loaded();

    final day = await renderAt(bg, 0);
    expect(channel(day, 5, 0, 0), 0x87);
    expect(channel(day, 5, 0, 1), 0xCE);
    expect(channel(day, 5, 0, 2), 0xEB);

    final night = await renderAt(bg, 1);
    expect(channel(night, 5, 0, 0), 0x0A);
    expect(channel(night, 5, 0, 1), 0x10);
    expect(channel(night, 5, 0, 2), 0x30);

    // The building band dims with the sky (grey 700 → 0xFF14182A); the
    // probe sits inside the left ground-floor block, clear of windows.
    expect(channel(day, 40, 40, 0), 0x61);
    expect(channel(night, 40, 40, 0), 0x14);
  });
}
