import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

typedef AlignmentProgress = void Function(double progress, String message);

class AlignmentResult {
  const AlignmentResult({
    required this.offsets,
    required this.commonStart,
    required this.commonEnd,
    required this.confidence,
  });

  final List<double> offsets;
  final double commonStart;
  final double commonEnd;
  final double confidence;

  double get duration => commonEnd - commonStart;
  double trimStartFor(int index) => commonStart + offsets[index];
}

class AlignmentException implements Exception {
  const AlignmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AlignmentService {
  static const _sampleRate = 8000;
  static const _hopSize = 800;
  static const _secondsPerFrame = _hopSize / _sampleRate;

  Future<AlignmentResult> align({
    required List<String> paths,
    required List<Duration> durations,
    required AlignmentProgress onProgress,
  }) async {
    if (paths.length != 4 || durations.length != 4) {
      throw const AlignmentException('需要先导入四段视频');
    }

    final temporaryDirectory = await getTemporaryDirectory();
    final fingerprints = <List<List<double>>>[];

    for (var index = 0; index < paths.length; index++) {
      onProgress(index * 0.12, '正在读取视频 ${index + 1} 的音频');
      final pcmFile = File(
        '${temporaryDirectory.path}/4gcut_audio_${index}_${DateTime.now().microsecondsSinceEpoch}.pcm',
      );
      try {
        final command = '-nostdin -hide_banner -loglevel error -y '
            '-i ${_quote(paths[index])} -map 0:a:0 -vn -ac 1 '
            '-ar $_sampleRate -f s16le ${_quote(pcmFile.path)}';
        final session = await FFmpegKit.execute(command);
        final returnCode = await session.getReturnCode();
        if (!ReturnCode.isSuccess(returnCode) || !await pcmFile.exists()) {
          throw AlignmentException('视频 ${index + 1} 未检测到可用音频');
        }
        final bytes = await pcmFile.readAsBytes();
        if (bytes.length < _sampleRate * 2 * 3) {
          throw AlignmentException('视频 ${index + 1} 的有效音频不足 3 秒');
        }
        onProgress(index * 0.12 + 0.06, '正在提取视频 ${index + 1} 的音频特征');
        final fingerprint = await Isolate.run(() => _fingerprint(bytes));
        if (fingerprint.length < 30 || _featureActivity(fingerprint) < 0.08) {
          throw AlignmentException('视频 ${index + 1} 的音频过弱，无法可靠识别');
        }
        fingerprints.add(fingerprint);
      } finally {
        if (await pcmFile.exists()) {
          await pcmFile.delete();
        }
      }
    }

    final offsets = <double>[0];
    final scores = <double>[];
    for (var index = 1; index < 4; index++) {
      onProgress(0.48 + index * 0.12, '正在匹配视频 1 与视频 ${index + 1}');
      final match = await Isolate.run(
        () => _matchFingerprints(fingerprints.first, fingerprints[index]),
      );
      if (match.score < 0.13 || match.margin < 0.008) {
        throw AlignmentException('视频 ${index + 1} 未找到可靠的共同音频片段');
      }
      offsets.add(match.lag * _secondsPerFrame);
      scores.add(match.score);
    }

    // A single reference match can land on a repeated chorus or a strong
    // transient. Verify every pair before accepting the result so a plausible
    // but wrong offset never becomes a green “已对齐” state.
    for (var left = 1; left < 4; left++) {
      for (var right = left + 1; right < 4; right++) {
        onProgress(0.84, '正在交叉校验视频 ${left + 1} 与视频 ${right + 1}');
        final pair = await Isolate.run(
          () => _matchFingerprints(fingerprints[left], fingerprints[right]),
        );
        final expectedLag =
            ((offsets[right] - offsets[left]) / _secondsPerFrame).round();
        if (pair.score < 0.13 || pair.margin < 0.008 ||
            (pair.lag - expectedLag).abs() > 5) {
          throw AlignmentException(
            '视频 ${left + 1} 与视频 ${right + 1} 的共同音乐不一致，无法安全对齐',
          );
        }
        scores.add(pair.score);
      }
    }

    var commonStart = 0.0;
    var commonEnd = durations.first.inMilliseconds / 1000.0;
    for (var index = 0; index < 4; index++) {
      final sourceDuration = durations[index].inMilliseconds / 1000.0;
      commonStart = math.max(commonStart, -offsets[index]);
      commonEnd = math.min(commonEnd, sourceDuration - offsets[index]);
    }

    if (commonEnd - commonStart < 2) {
      throw const AlignmentException('四段视频没有足够长的共同有效区间');
    }

    onProgress(1, '已找到共同音乐区间');
    return AlignmentResult(
      offsets: offsets,
      commonStart: commonStart,
      commonEnd: commonEnd,
      confidence: scores.reduce((a, b) => a + b) / scores.length,
    );
  }

  static List<List<double>> _fingerprint(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    final frames = sampleCount ~/ _hopSize;
    if (frames == 0) return const [];

    const cutoffs = [220.0, 600.0, 1500.0, 3200.0];
    final coefficients = cutoffs
        .map((frequency) => math.exp(-2 * math.pi * frequency / _sampleRate))
        .toList(growable: false);
    final lowPass = List<double>.filled(cutoffs.length, 0);
    final energies = List.generate(frames, (_) => List<double>.filled(5, 0));
    final data = ByteData.sublistView(bytes);

    for (var sampleIndex = 0; sampleIndex < frames * _hopSize; sampleIndex++) {
      final sample = data.getInt16(sampleIndex * 2, Endian.little) / 32768.0;
      var previousBandEdge = 0.0;
      final frame = sampleIndex ~/ _hopSize;
      for (var band = 0; band < lowPass.length; band++) {
        lowPass[band] =
            coefficients[band] * lowPass[band] + (1 - coefficients[band]) * sample;
        final bandValue = lowPass[band] - previousBandEdge;
        energies[frame][band] += bandValue * bandValue;
        previousBandEdge = lowPass[band];
      }
      final highBand = sample - lowPass.last;
      energies[frame][4] += highBand * highBand;
    }

    for (final frame in energies) {
      for (var band = 0; band < frame.length; band++) {
        frame[band] = math.log(frame[band] / _hopSize + 1e-10);
      }
    }

    final features = <List<double>>[];
    for (var frame = 1; frame < energies.length; frame++) {
      features.add(List.generate(5, (band) {
        return (energies[frame][band] - energies[frame - 1][band])
            .clamp(-4.0, 4.0)
            .toDouble();
      }));
    }

    for (var band = 0; band < 5; band++) {
      var mean = 0.0;
      for (final feature in features) {
        mean += feature[band];
      }
      mean /= math.max(1, features.length);
      var variance = 0.0;
      for (final feature in features) {
        final difference = feature[band] - mean;
        variance += difference * difference;
      }
      final deviation = math.sqrt(variance / math.max(1, features.length)) + 1e-6;
      for (final feature in features) {
        feature[band] =
            ((feature[band] - mean) / deviation).clamp(-4.0, 4.0).toDouble();
      }
    }
    return features;
  }

  static double _featureActivity(List<List<double>> features) {
    var total = 0.0;
    for (final frame in features) {
      for (final value in frame) {
        total += value.abs();
      }
    }
    return total / math.max(1, features.length * 5);
  }

  static _FingerprintMatch _matchFingerprints(
    List<List<double>> reference,
    List<List<double>> target,
  ) {
    const coarseFactor = 4;
    final coarseReference = <List<double>>[];
    final coarseTarget = <List<double>>[];
    for (var index = 0; index < reference.length; index += coarseFactor) {
      coarseReference.add(reference[index]);
    }
    for (var index = 0; index < target.length; index += coarseFactor) {
      coarseTarget.add(target[index]);
    }

    final minimumCoarseOverlap = math.min(
      75,
      math.max(8, (math.min(coarseReference.length, coarseTarget.length) * 0.12).round()),
    );
    var bestCoarseLag = 0;
    var bestCoarseScore = -1.0;
    final candidates = <(int, double)>[];
    final minimumLag = -coarseReference.length + minimumCoarseOverlap;
    final maximumLag = coarseTarget.length - minimumCoarseOverlap;
    for (var lag = minimumLag; lag <= maximumLag; lag++) {
      final score = _correlation(coarseReference, coarseTarget, lag);
      candidates.add((lag, score));
      if (score > bestCoarseScore) {
        bestCoarseScore = score;
        bestCoarseLag = lag;
      }
    }

    var secondBest = -1.0;
    for (final candidate in candidates) {
      if ((candidate.$1 - bestCoarseLag).abs() > 3) {
        secondBest = math.max(secondBest, candidate.$2);
      }
    }

    final expectedLag = bestCoarseLag * coarseFactor;
    var bestLag = expectedLag;
    var bestScore = -1.0;
    for (var lag = expectedLag - 7; lag <= expectedLag + 7; lag++) {
      final score = _correlation(reference, target, lag);
      if (score > bestScore) {
        bestScore = score;
        bestLag = lag;
      }
    }
    return _FingerprintMatch(
      lag: bestLag,
      score: bestScore,
      margin: bestCoarseScore - secondBest,
    );
  }

  static double _correlation(
    List<List<double>> reference,
    List<List<double>> target,
    int lag,
  ) {
    final referenceStart = math.max(0, -lag);
    final referenceEnd = math.min(reference.length, target.length - lag);
    if (referenceEnd <= referenceStart) return -1;

    var dot = 0.0;
    var referencePower = 0.0;
    var targetPower = 0.0;
    for (var index = referenceStart; index < referenceEnd; index++) {
      final targetIndex = index + lag;
      for (var band = 0; band < 5; band++) {
        final left = reference[index][band];
        final right = target[targetIndex][band];
        dot += left * right;
        referencePower += left * left;
        targetPower += right * right;
      }
    }
    if (referencePower < 1e-8 || targetPower < 1e-8) return -1;
    final raw = dot / math.sqrt(referencePower * targetPower);
    final overlap = referenceEnd - referenceStart;
    final coverage = overlap / math.min(reference.length, target.length);
    return raw * (0.82 + 0.18 * math.min(1, coverage * 2));
  }

  static String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}

class _FingerprintMatch {
  const _FingerprintMatch({
    required this.lag,
    required this.score,
    required this.margin,
  });

  final int lag;
  final double score;
  final double margin;
}
