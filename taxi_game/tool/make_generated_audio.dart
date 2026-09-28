// Generates the three self-made audio files the game ships:
//
//   assets/audio/sfx/engine_loop.wav   idle-to-mid engine rumble (seamless loop)
//   assets/audio/sfx/brake.wav         short tyre squeal (one-shot)
//   assets/audio/music/shift_loop.wav  mellow backing track (seamless loop)
//
// Everything here is procedural synthesis — no sampled third-party audio — so
// the output carries no license obligation at all (see
// assets/licenses/LICENSES.txt, "Generated audio").
//
// Run from taxi_game/:
//
//   dart run tool/make_generated_audio.dart
//
// The RNG is seeded, so regenerating is idempotent: the same commit of this
// tool always produces byte-identical files.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show BytesBuilder;

void main() {
  writeEngineLoop();
  writeBrake();
  writeMusicLoop();
}

// --- shared helpers ---------------------------------------------------------

/// Writes a mono 16-bit PCM WAV file. [sampleRate] and [samples].length define
/// the loop length; callers keep everything periodic or wrap tails, so all
/// three outputs loop or end cleanly.
void writeWav(String path, int sampleRate, List<double> samples) {
  final bytes = BytesBuilder();

  const channels = 1;
  const bitsPerSample = 16;
  final dataLength = samples.length * 2;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;

  void ascii(String s) => bytes.add(s.codeUnits);
  void u32(int v) => bytes.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
  void u16(int v) => bytes.add([v & 255, (v >> 8) & 255]);

  ascii('RIFF');
  u32(36 + dataLength);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1); // PCM
  u16(channels);
  u32(sampleRate);
  u32(byteRate);
  u16(channels * bitsPerSample ~/ 8);
  u16(bitsPerSample);
  ascii('data');
  u32(dataLength);

  for (final s in samples) {
    final v = (s.clamp(-1.0, 1.0) * 32767).round();
    bytes.add([v & 255, (v >> 8) & 255]);
  }

  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytes(bytes.takeBytes(), flush: true);
  stdout.writeln('wrote $path (${samples.length} samples @ $sampleRate Hz)');
}

/// Sums full-length partials whose frequencies sit on exact integer multiples
/// of `1 / durationSeconds`, so the result is periodic with the buffer and
/// loops with zero seam. [partials] maps frequency (Hz) to (amplitude, phase).
List<double> periodicSum({
  required int sampleRate,
  required int count,
  required Map<double, (double, double)> partials,
}) {
  final out = List<double>.filled(count, 0);
  for (final entry in partials.entries) {
    final freq = entry.key;
    final (amp, phase) = entry.value;
    // The grid step is count / sampleRate; k * freq must be an integer there.
    final steps = freq * count / sampleRate;
    assert((steps - steps.roundToDouble()).abs() < 1e-9,
        'partial $freq Hz is off the loop grid');
    final w = 2 * pi * steps / count;
    for (var i = 0; i < count; i++) {
      out[i] += amp * sin(w * i + phase);
    }
  }
  return out;
}

void normalize(List<double> samples, double peak) {
  var maxAbs = 0.0;
  for (final s in samples) {
    final a = s.abs();
    if (a > maxAbs) maxAbs = a;
  }
  if (maxAbs == 0) return;
  final gain = peak / maxAbs;
  for (var i = 0; i < samples.length; i++) {
    samples[i] *= gain;
  }
}

/// One-pole lowpass in place.
void lowpass(List<double> samples, double cutoffHz, int sampleRate) {
  final rc = 1 / (2 * pi * cutoffHz);
  final dt = 1 / sampleRate;
  final alpha = dt / (rc + dt);
  var y = 0.0;
  for (var i = 0; i < samples.length; i++) {
    y += alpha * (samples[i] - y);
    samples[i] = y;
  }
}

// --- engine loop ------------------------------------------------------------

/// A four-stroke idle-to-mid-range hum. Timbre sits between idle and gentle
/// cruise; playback scales only its volume with speed, so the character is
/// baked. Every partial sits on the loop grid (0.75 s → 1⅓ Hz), the firing
/// roughness is 24 Hz (18 grid steps), and the "air" layer is dozens of
/// random-phase grid partials — noise that is still exactly periodic.
void writeEngineLoop() {
  const sampleRate = 44100;
  const seconds = 0.75;
  const count = sampleRate * seconds ~/ 1; // 33075
  final rng = Random(0xE3C1A1);

  final out = periodicSum(sampleRate: sampleRate, count: count, partials: {
    // Firing fundamental and its stack.
    48.0: (0.50, 0.0),
    96.0: (0.34, 0.8),
    144.0: (0.22, 2.1),
    192.0: (0.12, 4.0),
    288.0: (0.06, 1.3),
    384.0: (0.03, 5.2),
    // Slow amplitude wobble — a slightly uneven idle. (8/3 Hz = 2 grid steps.)
    8.0 / 3.0: (0.02, 0.4),
  });

  // Combustion roughness: 24 Hz AM, two taps deep.
  const amSteps = 24.0 * count / sampleRate; // integer on the grid
  const amW = 2 * pi * amSteps / count;
  for (var i = 0; i < count; i++) {
    out[i] *= 0.85 + 0.15 * sin(amW * i) + 0.08 * sin(2 * amW * i + 1.1);
  }

  // Mechanical air: random-phase partials in a mid band — loopable noise.
  final air = List<double>.filled(count, 0);
  for (var k = 0; k < 70; k++) {
    final gridStep = rng.nextInt(300) + 40; // 53..453 Hz on the 1.333 Hz grid
    final amp = 0.35 / (1 + k * 0.12);
    final w = 2 * pi * gridStep / count;
    final phase = rng.nextDouble() * 2 * pi;
    for (var i = 0; i < count; i++) {
      air[i] += amp * sin(w * i + phase);
    }
  }
  lowpass(air, 900, sampleRate);
  for (var i = 0; i < count; i++) {
    out[i] += 0.05 * air[i];
  }

  normalize(out, 0.85);
  writeWav('assets/audio/sfx/engine_loop.wav', sampleRate, out);
}

// --- brake squeal -----------------------------------------------------------

/// A short tyre squeal: three gliding partials around 900 Hz falling toward
/// 650 Hz over a breathing envelope, over a faint noise bed. One-shot — no
/// loop constraint — with a hard fade at both ends.
void writeBrake() {
  const sampleRate = 44100;
  const count = sampleRate * 0.5 ~/ 1; // 0.5 s
  final rng = Random(0xB24E);
  final out = List<double>.filled(count, 0);

  // Glide each partial from f0 to f1 with its own rate; phase integrates the
  // glide so the fall never aliases or clicks.
  const pairs = [
    (900.0, 650.0, 0.40),
    (930.0, 680.0, 0.28),
    (870.0, 640.0, 0.18),
  ];
  for (final (f0, f1, amp) in pairs) {
    var phase = rng.nextDouble() * 2 * pi;
    for (var i = 0; i < count; i++) {
      final t = i / count;
      final f = f0 + (f1 - f0) * t;
      phase += 2 * pi * f / sampleRate;
      // Tremolo keeps it reading as a tyre, not a test tone.
      final trem = 0.75 + 0.25 * sin(2 * pi * 13.0 * t);
      out[i] += amp * trem * sin(phase);
    }
  }

  // Faint broadband hiss under the squeal.
  for (var i = 0; i < count; i++) {
    out[i] += 0.02 * (rng.nextDouble() * 2 - 1);
  }

  // Attack in 8 ms, hold, then exponential decay; hard-zero the last 2 ms.
  const attack = sampleRate * 0.008 ~/ 1;
  const tail = sampleRate * 0.002 ~/ 1;
  for (var i = 0; i < count; i++) {
    var env = 1.0;
    if (i < attack) {
      env = i / attack;
    } else {
      env = exp(-(i - attack) / (sampleRate * 0.16));
    }
    out[i] *= env;
    if (i >= count - tail) {
      out[i] *= (count - i) / tail;
    }
  }

  normalize(out, 0.8);
  writeWav('assets/audio/sfx/brake.wav', sampleRate, out);
}

// --- music loop -------------------------------------------------------------

/// The shift's backing track: four laid-back bars at 84 BPM walking Am7 ·
/// Fmaj7 · Cmaj7 · G, a root bass on 1 and 3, soft pads, sparse pentatonic
/// plucks, and ghost ticks on the off-beats. Notes are written into a
/// circular buffer with wraparound, so release tails fold into the loop start
/// and the loop is seamless. Mono 22050 Hz — it sits under everything else.
void writeMusicLoop() {
  const sampleRate = 22050;
  const bpm = 84.0;
  const beatsPerBar = 4;
  const bars = 4;
  const beatSamples = sampleRate * 60 ~/ bpm; // 15750 (exact: 22050*60/84)
  const count = beatSamples * beatsPerBar * bars; // 252000
  final rng = Random(0x5A1F);

  final mix = List<double>.filled(count, 0);

  /// Adds one synthesized note, wrapping past the loop end back to the start.
  void addNote({
    required double freq,
    required double startBeat,
    required double lengthBeats,
    required double amp,
    required double attackSeconds,
    required double releaseSeconds,
    List<double> harmonics = const [1.0],
    double vibrato = 0,
  }) {
    final start = (startBeat * beatSamples).round() % count;
    final total = (lengthBeats * beatSamples).round();
    for (var i = 0; i < total; i++) {
      final t = i / sampleRate;
      var env = 1.0;
      final attack = attackSeconds * sampleRate;
      final release = releaseSeconds * sampleRate;
      if (i < attack) {
        env = i / attack;
      } else if (i > total - release) {
        env = (total - i) / release;
      }
      var sample = 0.0;
      for (var h = 0; h < harmonics.length; h++) {
        final w = 2 * pi * freq * (h + 1) * t;
        final vib = vibrato == 0 ? 0.0 : sin(2 * pi * 5 * t) * vibrato;
        sample += harmonics[h] * sin(w * (1 + vib) + h);
      }
      mix[(start + i) % count] += amp * env * sample;
    }
  }

  // A2, F2, C3, G2 — one root per bar.
  const roots = [110.0, 87.31, 130.81, 98.0];
  // Chord tones above each root (frequencies in Hz).
  const chords = [
    [220.0, 261.63, 329.63, 392.0], // Am7: A3 C4 E4 G4
    [174.61, 220.0, 261.63, 329.63], // Fmaj7: F3 A3 C4 E4
    [261.63, 329.63, 392.0], // Cmaj7: C4 E4 G4
    [196.0, 246.94, 293.66, 392.0], // G: G3 B3 D4 G4
  ];

  for (var bar = 0; bar < bars; bar++) {
    final baseBeat = bar * beatsPerBar.toDouble();

    // Bass: root on 1 and 3, sine plus a little 2nd harmonic.
    for (final b in [0.0, 2.0]) {
      addNote(
        freq: roots[bar],
        startBeat: baseBeat + b,
        lengthBeats: 1.9,
        amp: 0.30,
        attackSeconds: 0.012,
        releaseSeconds: 0.35,
        harmonics: const [1.0, 0.25],
      );
    }

    // Pad: the whole chord held across the bar, very soft, slow edges.
    for (final f in chords[bar]) {
      addNote(
        freq: f,
        startBeat: baseBeat,
        lengthBeats: beatsPerBar.toDouble(),
        amp: 0.055,
        attackSeconds: 0.45,
        releaseSeconds: 0.5,
        harmonics: const [1.0, 0.0, 0.22, 0.0, 0.08],
      );
    }

    // Pluck melody: two or three sparse pentatonic notes per bar.
    const pentatonic = [440.0, 523.25, 587.33, 659.26, 783.99];
    final pluckBeats = [rng.nextInt(4).toDouble(), 2.0 + rng.nextInt(4)];
    for (final b in pluckBeats) {
      addNote(
        freq: pentatonic[rng.nextInt(pentatonic.length)],
        startBeat: baseBeat + b,
        lengthBeats: 0.9,
        amp: 0.10,
        attackSeconds: 0.004,
        releaseSeconds: 0.30,
        vibrato: 0.004,
      );
    }

    // Ghost ticks on the off-beats: 8 ms noise taps, barely there.
    for (final b in [0.5, 1.5, 2.5, 3.5]) {
      final start = ((baseBeat + b) * beatSamples).round() % count;
      const tickLength = sampleRate * 0.008 ~/ 1;
      for (var i = 0; i < tickLength; i++) {
        final env = 1 - i / tickLength;
        mix[(start + i) % count] += 0.035 * env * (rng.nextDouble() * 2 - 1);
      }
    }
  }

  lowpass(mix, 3200, sampleRate);
  normalize(mix, 0.55);
  writeWav('assets/audio/music/shift_loop.wav', sampleRate, mix);
}
