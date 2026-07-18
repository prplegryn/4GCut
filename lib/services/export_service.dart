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
  Future<File> export({
    required List<SlotExportSettings> slots,
    required AlignmentResult alignment,
    required int audioIndex,
    required double aspectRatio,
    required void Function(ExportProgress progress) onProgress,
  }) async {
    if (slots.length != 4) {
      throw const ExportException('导出需要四段视频');
    }

    const outputWidth = 1080;
    final rawHeight = outputWidth / aspectRatio;
    final outputHeight = math.max(2, (rawHeight / 2).round() * 2);
    final cellWidth = outputWidth ~/ 2;
    final cellHeight = outputHeight ~/ 2;
    final duration = alignment.duration;
    final temporaryDirectory = await getTemporaryDirectory();
    final output = File(
      '${temporaryDirectory.path}/4GCut_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );

    final inputs = StringBuffer();
    for (final slot in slots) {
      inputs.write('-i ${_quote(slot.path)} ');
    }

    final filters = <String>[];
    for (var index = 0; index < slots.length; index++) {
      final slot = slots[index];
      final start = alignment.trimStartFor(index).toStringAsFixed(3);
      final zoom = (slot.zoom / 100).toStringAsFixed(4);
      final x = (slot.offsetX / 100).toStringAsFixed(4);
      final y = (slot.offsetY / 100).toStringAsFixed(4);
      final cellAspect = (cellWidth / cellHeight).toStringAsFixed(8);
      filters.add(
        '[$index:v]trim=start=$start:duration=${duration.toStringAsFixed(3)},'
        'setpts=PTS-STARTPTS,'
        "scale=w='if(gt(a,$cellAspect),-2,$cellWidth*$zoom)':"
        "h='if(gt(a,$cellAspect),$cellHeight*$zoom,-2)',"
        "crop=$cellWidth:$cellHeight:"
        "x='max(0,min(iw-$cellWidth,(iw-$cellWidth)/2-$x*$cellWidth/2))':"
        "y='max(0,min(ih-$cellHeight,(ih-$cellHeight)/2-$y*$cellHeight/2))',"
        'setsar=1[v$index]',
      );
    }
    filters
      ..add('[v0][v1]hstack=inputs=2[top]')
      ..add('[v2][v3]hstack=inputs=2[bottom]')
      ..add('[top][bottom]vstack=inputs=2[vout]');

    final audioStart = alignment.trimStartFor(audioIndex).toStringAsFixed(3);
    filters.add(
      '[$audioIndex:a]atrim=start=$audioStart:duration=${duration.toStringAsFixed(3)},'
      'asetpts=PTS-STARTPTS,aresample=async=1:first_pts=0[aout]',
    );

    final command = '-nostdin -hide_banner -y ${inputs.toString()}'
        '-filter_complex "${filters.join(';')}" '
        '-map "[vout]" -map "[aout]" '
        '-c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -r 30 '
        '-c:a aac -b:a 192k -movflags +faststart -shortest '
        '${_quote(output.path)}';

    final completer = Completer<File>();
    final stopwatch = Stopwatch()..start();
    await FFmpegKit.executeAsync(
      command,
      (session) async {
        stopwatch.stop();
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode) && await output.exists()) {
          onProgress(const ExportProgress(progress: 1, remaining: Duration.zero));
          completer.complete(output);
          return;
        }
        if (ReturnCode.isCancel(returnCode)) {
          if (await output.exists()) await output.delete();
          completer.completeError(const ExportCanceledException());
          return;
        }
        final outputText = await session.getOutput();
        if (await output.exists()) await output.delete();
        final usefulMessage = _lastUsefulLine(outputText);
        completer.completeError(
          ExportException(
            usefulMessage == null ? '视频编码失败，请检查源视频格式' : '视频编码失败：$usefulMessage',
          ),
        );
      },
      null,
      (statistics) {
        final encodedMilliseconds = statistics.getTime();
        final progress =
            (encodedMilliseconds / (duration * 1000)).clamp(0.0, 0.99).toDouble();
        Duration? remaining;
        if (progress > 0.02) {
          final totalEstimate = stopwatch.elapsedMilliseconds / progress;
          remaining = Duration(
            milliseconds: math.max(0, totalEstimate.round() - stopwatch.elapsedMilliseconds),
          );
        }
        onProgress(ExportProgress(progress: progress, remaining: remaining));
      },
    );
    return completer.future;
  }

  Future<void> cancel() => FFmpegKit.cancel();

  static String? _lastUsefulLine(String? output) {
    if (output == null || output.trim().isEmpty) return null;
    final lines = output.trim().split('\n');
    return lines.last.trim();
  }

  static String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}
