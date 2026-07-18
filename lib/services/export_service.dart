import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'alignment_service.dart';

class SlotExportSettings {
  const SlotExportSettings({
    required this.path,
    required this.zoom,
    required this.offsetX,
    required this.offsetY,
  });

  final String path;
  final double zoom;
  final double offsetX;
  final double offsetY;
}

class ExportProgress {
  const ExportProgress({
    required this.progress,
    required this.remaining,
  });

  final double progress;
  final Duration? remaining;
}

class ExportException implements Exception {
  const ExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ExportCanceledException extends ExportException {
  const ExportCanceledException() : super('已取消导出');
}

class ExportService {
  // Four original decoders at 1080p can exceed the native heap on phones.
  // Pre-render each cell separately, then compose four small cell streams.
  static const _outputWidth = 720;

  Future<File> export({
    required List<SlotExportSettings> slots,
    required AlignmentResult alignment,
    required int audioIndex,
    required double aspectRatio,
    required void Function(ExportProgress progress) onProgress,
  }) async {
    if (slots.length != 4) throw const ExportException('导出需要四段视频');

    final outputHeight = math.max(2, (_outputWidth / aspectRatio / 2).round() * 2);
    final cellWidth = _outputWidth ~/ 2;
    final cellHeight = outputHeight ~/ 2;
    final duration = alignment.duration;
    final temporaryDirectory = await getTemporaryDirectory();
    final jobDirectory = Directory(
      '${temporaryDirectory.path}/4gcut_export_${DateTime.now().microsecondsSinceEpoch}',
    );
    await jobDirectory.create(recursive: true);
    final output = File('${jobDirectory.path}/4GCut.mp4');
    final cellFiles = List.generate(
      4,
      (index) => File('${jobDirectory.path}/cell_$index.mp4'),
    );
    final audioFile = File('${jobDirectory.path}/audio.m4a');
    final stopwatch = Stopwatch()..start();

    try {
      for (var index = 0; index < slots.length; index++) {
        final slot = slots[index];
        final stageStart = index * 0.15;
        final filter = _cellFilter(
          slot: slot,
          cellWidth: cellWidth,
          cellHeight: cellHeight,
        );
        final command = '-nostdin -hide_banner -loglevel error -y '
            '-ss ${alignment.trimStartFor(index).toStringAsFixed(3)} '
            '-t ${duration.toStringAsFixed(3)} -i ${_quote(slot.path)} '
            '-an -vf ${_quote('$filter,fps=30')} '
            '-c:v libx264 -preset ultrafast -crf 21 -pix_fmt yuv420p '
            '-movflags +faststart ${_quote(cellFiles[index].path)}';
        await _executeStage(
          command: command,
          duration: duration,
          stageStart: stageStart,
          stageWeight: 0.15,
          stopwatch: stopwatch,
          onProgress: onProgress,
        );
      }

      final audioCommand = '-nostdin -hide_banner -loglevel error -y '
          '-ss ${alignment.trimStartFor(audioIndex).toStringAsFixed(3)} '
          '-t ${duration.toStringAsFixed(3)} -i ${_quote(slots[audioIndex].path)} '
          '-map 0:a:0 -vn -c:a aac -b:a 192k -ar 48000 -ac 2 '
          '${_quote(audioFile.path)}';
      await _executeStage(
        command: audioCommand,
        duration: duration,
        stageStart: 0.60,
        stageWeight: 0.10,
        stopwatch: stopwatch,
        onProgress: onProgress,
      );

      final inputs = StringBuffer();
      for (final file in cellFiles) {
        inputs.write('-i ${_quote(file.path)} ');
      }
      inputs.write('-i ${_quote(audioFile.path)} ');
      const graph = '[0:v][1:v]hstack=inputs=2[top];'
          '[2:v][3:v]hstack=inputs=2[bottom];'
          '[top][bottom]vstack=inputs=2[vout]';
      final composeCommand = '-nostdin -hide_banner -loglevel error -y ${inputs.toString()}'
          '-filter_complex ${_quote(graph)} -map "[vout]" -map 4:a:0 '
          '-c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p '
          '-c:a copy -movflags +faststart -shortest ${_quote(output.path)}';
      await _executeStage(
        command: composeCommand,
        duration: duration,
        stageStart: 0.70,
        stageWeight: 0.30,
        stopwatch: stopwatch,
        onProgress: onProgress,
      );
      onProgress(const ExportProgress(progress: 1, remaining: Duration.zero));
      return output;
    } finally {
      stopwatch.stop();
      // The caller copies the finished file before this directory is removed.
      // Keep the directory for the successful result; main deletes the returned
      // file after saving it and the next launch cleans old jobs.
    }
  }

  Future<void> _executeStage({
    required String command,
    required double duration,
    required double stageStart,
    required double stageWeight,
    required Stopwatch stopwatch,
    required void Function(ExportProgress progress) onProgress,
  }) async {
    final completer = Completer<void>();
    try {
      await FFmpegKit.executeAsync(
        command,
        (session) async {
          final returnCode = await session.getReturnCode();
          if (ReturnCode.isSuccess(returnCode)) {
            if (!completer.isCompleted) completer.complete();
          } else if (ReturnCode.isCancel(returnCode)) {
            if (!completer.isCompleted) {
              completer.completeError(const ExportCanceledException());
            }
          } else {
            final details = (await session.getOutput())?.trim();
            if (!completer.isCompleted) {
              completer.completeError(
                ExportException(
                  details == null || details.isEmpty
                      ? '视频编码失败，请检查源视频格式'
                      : '视频编码失败：${_lastUsefulLine(details)}',
                ),
              );
            }
          }
        },
        null,
        (statistics) {
          final encodedMilliseconds = statistics.getTime();
          final ratio = (encodedMilliseconds / (duration * 1000)).clamp(0.0, 1.0).toDouble();
          final overall = (stageStart + stageWeight * ratio).clamp(0.0, 0.99).toDouble();
          Duration? remaining;
          if (overall > 0.02) {
            final totalEstimate = stopwatch.elapsedMilliseconds / overall;
            remaining = Duration(
              milliseconds: math.max(
                0,
                totalEstimate.round() - stopwatch.elapsedMilliseconds,
              ),
            );
          }
          onProgress(ExportProgress(progress: overall, remaining: remaining));
        },
      );
    } catch (error) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    await completer.future;
  }

  Future<void> cancel() => FFmpegKit.cancel();

  static String _cellFilter({
    required SlotExportSettings slot,
    required int cellWidth,
    required int cellHeight,
  }) {
    final zoom = (slot.zoom / 100).toStringAsFixed(4);
    final x = (slot.offsetX / 100).toStringAsFixed(4);
    final y = (slot.offsetY / 100).toStringAsFixed(4);
    final cellAspect = (cellWidth / cellHeight).toStringAsFixed(8);
    return "scale=w='if(gt(a,$cellAspect),-2,$cellWidth*$zoom)':"
        "h='if(gt(a,$cellAspect),$cellHeight*$zoom,-2)',"
        "crop=$cellWidth:$cellHeight:"
        "x='max(0,min(iw-$cellWidth,(iw-$cellWidth)/2*(1-$x)))':"
        "y='max(0,min(ih-$cellHeight,(ih-$cellHeight)/2*(1-$y)))',"
        'setsar=1';
  }

  static String _lastUsefulLine(String output) => output.split('\n').last.trim();

  static String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}
