import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'alignment_service.dart';
import 'export_service.dart';

class PreviewService {
  Future<File> create({
    required List<SlotExportSettings> slots,
    required AlignmentResult alignment,
    required int audioIndex,
    required double aspectRatio,
  }) async {
    const outputWidth = 360;
    final outputHeight = math.max(2, (outputWidth / aspectRatio / 2).round() * 2);
    final cellWidth = outputWidth ~/ 2;
    final cellHeight = outputHeight ~/ 2;
    final duration = alignment.duration;
    final directory = await getTemporaryDirectory();
    final output = File(
      '${directory.path}/4gcut_preview_${DateTime.now().millisecondsSinceEpoch}.mp4',
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
        "x='max(0,min(iw-$cellWidth,(iw-$cellWidth)/2*(1-$x)))':"
        "y='max(0,min(ih-$cellHeight,(ih-$cellHeight)/2*(1-$y)))',"
        'setsar=1[v$index]',
      );
    }
    filters
      ..add('[v0][v1]hstack=inputs=2[top]')
      ..add('[v2][v3]hstack=inputs=2[bottom]')
      ..add('[top][bottom]vstack=inputs=2[vout]')
      ..add(
        '[$audioIndex:a]atrim=start=${alignment.trimStartFor(audioIndex).toStringAsFixed(3)}:'
        'duration=${duration.toStringAsFixed(3)},'
        'asetpts=PTS-STARTPTS,aresample=async=1:first_pts=0[aout]',
      );

    final command = '-nostdin -hide_banner -loglevel error -y ${inputs.toString()}'
        '-filter_complex "${filters.join(';')}" '
        '-map "[vout]" -map "[aout]" '
        '-c:v libx264 -preset ultrafast -tune zerolatency -crf 30 '
        '-pix_fmt yuv420p -r 24 -c:a aac -b:a 96k -movflags +faststart -shortest '
        '${_quote(output.path)}';

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode) || !await output.exists()) {
      final details = (await session.getOutput())?.trim();
      throw Exception(
        details == null || details.isEmpty ? '同步预览生成失败' : '同步预览生成失败：${_lastLine(details)}',
      );
    }
    return output;
  }

  static String _lastLine(String output) => output.split('\n').last.trim();

  static String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}
