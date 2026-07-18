import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'models/video_slot_data.dart';
import 'services/alignment_service.dart';
import 'services/export_service.dart';
import 'widgets/action_controls.dart';
import 'widgets/adjustment_card.dart';
import 'widgets/export_progress_dialog.dart';
import 'widgets/guide_preview.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFF7F8FA),
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFF7F8FA),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const FourGCutApp());
}

class FourGCutApp extends StatelessWidget {
  const FourGCutApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF3478F6);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '4GCut',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        splashFactory: InkSparkle.splashFactory,
      ),
      home: const EditorPage(),
    );
  }
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  static const _mediaChannel = MethodChannel('com.prplegryn.fourgcut/media');

  final _alignmentService = AlignmentService();
  final _exportService = ExportService();
  late final List<VideoSlotData> _slots;

  int _selectedIndex = 0;
  int _audioIndex = 0;
  int _aspectIndex = 0;
  bool _aligning = false;
  bool _exporting = false;
  bool _sliderDragging = false;
  bool _isPlaying = false;
  String _alignmentMessage = '';
  AlignmentResult? _alignment;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _slots = List.generate(4, (index) => VideoSlotData(number: index + 1));
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    for (final slot in _slots) {
      unawaited(slot.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableHeight = media.size.height - media.padding.vertical;
    final deviceRatio = media.size.width / availableHeight;
    final aspectOptions = <_AspectOption>[
      _AspectOption(_fractionLabel(deviceRatio), deviceRatio),
      const _AspectOption('9:16', 9 / 16),
      const _AspectOption('4:5', 4 / 5),
      const _AspectOption('3:4', 3 / 4),
      const _AspectOption('1:1', 1),
    ];
    if (_aspectIndex >= aspectOptions.length) _aspectIndex = 0;
    final aspect = aspectOptions[_aspectIndex];
    final selected = _slots[_selectedIndex];
    final busy = _aligning || _exporting;
    final allImported = _slots.every((slot) => slot.isImported);
    final adjustmentEnabled = selected.isImported && !busy;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 9),
            const SizedBox(
              height: 43,
              child: Center(
                child: Text(
                  '4GCut',
                  style: TextStyle(
                    color: Color(0xFF162033),
                    fontSize: 22,
                    letterSpacing: -0.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: GuidePreview(
                      slots: _slots,
                      selectedIndex: _selectedIndex,
                      aspectRatio: aspect.ratio,
                      enabled: !busy,
                      onSelect: (index) {
                        _stopPlayback();
                        setState(() {
                          _selectedIndex = index;
                          _sliderDragging = false;
                        });
                      },
                      onImport: _importVideo,
                    ),
                  ),
                  SizedBox(
                    height: 28,
                    child: Center(child: _buildStatus()),
                  ),
                  const SizedBox(height: 4),
                  AdjustmentCard(
                    zoom: selected.zoom,
                    offsetX: selected.offsetX,
                    offsetY: selected.offsetY,
                    enabled: adjustmentEnabled,
                    animateValues: !_sliderDragging,
                    onZoomChanged: (value) => setState(() => selected.zoom = value),
                    onOffsetXChanged: (value) => setState(() => selected.offsetX = value),
                    onOffsetYChanged: (value) => setState(() => selected.offsetY = value),
                    onInteractionStart: () => setState(() => _sliderDragging = true),
                    onInteractionEnd: () => setState(() => _sliderDragging = false),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            ActionControls(
              audioLabel: '音频 ${_audioIndex + 1}',
              ratioLabel: aspect.label,
              audioEnabled: _slots.any((slot) => slot.isImported) && !busy,
              ratioEnabled: !busy,
              alignEnabled: allImported && !busy,
              previewEnabled: _alignment != null && !busy,
              exportEnabled: _alignment != null && !busy,
              aligning: _aligning,
              onAudio: _cycleAudio,
              onRatio: () {
                setState(() => _aspectIndex = (_aspectIndex + 1) % aspectOptions.length);
              },
              onAlign: _runAlignment,
              onPreview: _startPreview,
              onExport: () => _startExport(aspect),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus() {
    if (_aligning) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Text(
          _alignmentMessage,
          key: ValueKey(_alignmentMessage),
          style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
        ),
      );
    }
    if (_alignment != null) {
      return AnimatedScale(
        scale: 1,
        duration: const Duration(milliseconds: 220),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF3478F6)),
              SizedBox(width: 4),
              Text(
                '已对齐',
                style: TextStyle(
                  color: Color(0xFF3478F6),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _importVideo(int index) async {
    if (_aligning || _exporting) return;
    _stopPlayback();
    setState(() => _selectedIndex = index);
    final result = await FilePicker.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;

    final next = VideoPlayerController.file(File(path));
    try {
      await next.initialize();
      await next.setLooping(false);
      await next.setVolume(0);
      final previous = _slots[index].controller;
      setState(() {
        _slots[index]
          ..path = path
          ..controller = next;
        _alignment = null;
        if (!_slots[_audioIndex].isImported) {
          _audioIndex = index;
        }
      });
      await previous?.dispose();
    } catch (_) {
      await next.dispose();
      if (mounted) _showMessage('视频 ${index + 1} 无法读取，请选择常见的视频格式');
    }
  }

  Future<void> _runAlignment() async {
    if (_aligning || _exporting || !_slots.every((slot) => slot.isImported)) return;
    _stopPlayback();
    setState(() {
      _aligning = true;
      _alignmentMessage = '准备分析音频';
    });
    try {
      final result = await _alignmentService.align(
        paths: _slots.map((slot) => slot.path!).toList(growable: false),
        durations: _slots
            .map((slot) => slot.controller!.value.duration)
            .toList(growable: false),
        onProgress: (progress, message) {
          if (mounted) setState(() => _alignmentMessage = message);
        },
      );
      if (!mounted) return;
      setState(() => _alignment = result);
      _showMessage('对齐完成，共同片段 ${_durationLabel(result.duration)}');
    } on AlignmentException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('音频分析失败，请确认四段视频都包含可播放的音轨');
    } finally {
      if (mounted) {
        setState(() {
          _aligning = false;
          _alignmentMessage = '';
        });
      }
    }
  }

  Future<void> _startPreview() async {
    final alignment = _alignment;
    if (alignment == null || _aligning || _exporting) return;
    _stopPlayback();
    try {
      for (var index = 0; index < _slots.length; index++) {
        final controller = _slots[index].controller!;
        await controller.pause();
        await controller.setVolume(index == _audioIndex ? 1 : 0);
        await controller.seekTo(
          Duration(milliseconds: (alignment.trimStartFor(index) * 1000).round()),
        );
      }
      await Future.wait(_slots.map((slot) => slot.controller!.play()));
      if (!mounted) return;
      setState(() => _isPlaying = true);
      _syncTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        final referencePosition = _slots.first.controller!.value.position;
        final elapsed = referencePosition.inMilliseconds / 1000 - alignment.trimStartFor(0);
        if (elapsed >= alignment.duration) {
          _stopPlayback();
        }
      });
    } catch (_) {
      _stopPlayback();
      if (mounted) _showMessage('同步预览启动失败，请重新对齐后再试');
    }
  }

  void _stopPlayback() {
    _syncTimer?.cancel();
    _syncTimer = null;
    for (final slot in _slots) {
      if (slot.controller != null) unawaited(slot.controller!.pause());
    }
    if (_isPlaying && mounted) setState(() => _isPlaying = false);
  }

  void _cycleAudio() {
    for (var step = 1; step <= 4; step++) {
      final candidate = (_audioIndex + step) % 4;
      if (_slots[candidate].isImported) {
        setState(() => _audioIndex = candidate);
        if (_isPlaying) {
          for (var index = 0; index < 4; index++) {
            unawaited(_slots[index].controller!.setVolume(index == candidate ? 1 : 0));
          }
        }
        return;
      }
    }
  }

  Future<void> _startExport(_AspectOption aspect) async {
    final alignment = _alignment;
    if (alignment == null || _exporting || _aligning) return;
    _stopPlayback();
    final progress = ValueNotifier<ExportProgress>(
      const ExportProgress(progress: 0, remaining: null),
    );
    setState(() => _exporting = true);
    var dialogShown = false;
    unawaited(
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: const Color(0x520F1A2A),
        transitionDuration: const Duration(milliseconds: 220),
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
          );
        },
        pageBuilder: (context, animation, secondaryAnimation) {
          dialogShown = true;
          return ExportProgressDialog(
            progress: progress,
            ratioLabel: aspect.label,
            audioNumber: _audioIndex + 1,
            onCancel: () => unawaited(_exportService.cancel()),
          );
        },
      ),
    );

    File? output;
    try {
      output = await _exportService.export(
        slots: _slots
            .map(
              (slot) => SlotExportSettings(
                path: slot.path!,
                zoom: slot.zoom,
                offsetX: slot.offsetX,
                offsetY: slot.offsetY,
              ),
            )
            .toList(growable: false),
        alignment: alignment,
        audioIndex: _audioIndex,
        aspectRatio: aspect.ratio,
        onProgress: (value) => progress.value = value,
      );
      final fileName = '4GCut_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await _mediaChannel.invokeMethod<String>(
        'saveVideo',
        <String, String>{'path': output.path, 'name': fileName},
      );
      if (mounted) _showMessage('导出完成，已保存到“影片/4GCut”');
    } on ExportCanceledException catch (error) {
      if (mounted) _showMessage(error.message);
    } on ExportException catch (error) {
      if (mounted) _showMessage(error.message);
    } on PlatformException catch (error) {
      if (mounted) _showMessage('视频已生成，但保存失败：${error.message ?? '存储不可用'}');
    } catch (_) {
      if (mounted) _showMessage('导出失败，请检查设备存储空间');
    } finally {
      if (output != null && await output.exists()) await output.delete();
      if (mounted && dialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) setState(() => _exporting = false);
      progress.dispose();
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF263244),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
  }

  static String _durationLabel(double seconds) {
    final rounded = seconds.round();
    final minutes = rounded ~/ 60;
    final remainder = rounded % 60;
    return minutes > 0 ? '$minutes 分 $remainder 秒' : '$remainder 秒';
  }

  static String _fractionLabel(double ratio) {
    var bestNumerator = 1;
    var bestDenominator = 1;
    var bestError = double.infinity;
    for (var denominator = 1; denominator <= 24; denominator++) {
      final numerator = math.max(1, (ratio * denominator).round());
      final error = (numerator / denominator - ratio).abs();
      if (error < bestError) {
        bestError = error;
        bestNumerator = numerator;
        bestDenominator = denominator;
      }
    }
    final divisor = _greatestCommonDivisor(bestNumerator, bestDenominator);
    return '${bestNumerator ~/ divisor}:${bestDenominator ~/ divisor}';
  }

  static int _greatestCommonDivisor(int left, int right) {
    while (right != 0) {
      final remainder = left % right;
      left = right;
      right = remainder;
    }
    return left;
  }
}

class _AspectOption {
  const _AspectOption(this.label, this.ratio);

  final String label;
  final double ratio;
}
