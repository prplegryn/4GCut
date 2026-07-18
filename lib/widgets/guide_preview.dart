import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/video_slot_data.dart';

class GuidePreview extends StatefulWidget {
  const GuidePreview({
    super.key,
    required this.slots,
    required this.selectedIndex,
    required this.aspectRatio,
    required this.enabled,
    required this.onSelect,
    required this.onImport,
  });

  final List<VideoSlotData> slots;
  final int selectedIndex;
  final double aspectRatio;
  final bool enabled;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onImport;

  @override
  State<GuidePreview> createState() => _GuidePreviewState();
}

class _GuidePreviewState extends State<GuidePreview> {
  double _horizontalGuide = 0;
  double _verticalGuide = 1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final areaWidth = constraints.maxWidth;
        final maximumPreviewWidth = areaWidth - 92;
        final maximumPreviewHeight = constraints.hasBoundedHeight
            ? math.max(150.0, math.min(330.0, constraints.maxHeight - 70))
            : 330.0;
        late final double previewWidth;
        late final double previewHeight;
        if (widget.aspectRatio > maximumPreviewWidth / maximumPreviewHeight) {
          previewWidth = maximumPreviewWidth;
          previewHeight = previewWidth / widget.aspectRatio;
        } else {
          previewHeight = maximumPreviewHeight;
          previewWidth = previewHeight * widget.aspectRatio;
        }

        final previewTop = math.min(58.0, math.max(32.0, maximumPreviewHeight * 0.18));
        final previewLeft = (areaWidth - previewWidth) / 2;
        final previewRight = previewLeft + previewWidth;
        final previewBottom = previewTop + previewHeight;
        final areaHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : previewBottom + 28;
        const horizontalMinimum = 12.0;
        final horizontalMaximum = math.max(horizontalMinimum + 1, previewBottom - 10);
        final horizontalY = horizontalMinimum +
            _horizontalGuide * (horizontalMaximum - horizontalMinimum);
        final verticalMinimum = previewLeft + 10;
        final verticalMaximum = math.max(verticalMinimum + 1, previewRight + 18);
        final verticalRange =
            (verticalMaximum - verticalMinimum).clamp(0.0, double.infinity).toDouble();
        final verticalX = verticalMinimum + _verticalGuide * verticalRange;
        final horizontalStart =
            (previewLeft - 18).clamp(18.0, areaWidth - 18).toDouble();

        return SizedBox(
          height: areaHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOutCubic,
                left: previewLeft,
                top: previewTop,
                width: previewWidth,
                height: previewHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9EDF3),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x140D2A52),
                        blurRadius: 18,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(child: _buildCell(0)),
                              const SizedBox(width: 1.5),
                              Expanded(child: _buildCell(1)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 1.5),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(child: _buildCell(2)),
                              const SizedBox(width: 1.5),
                              Expanded(child: _buildCell(3)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: horizontalStart,
                top: horizontalY,
                width: (previewRight - horizontalStart).clamp(1.0, areaWidth).toDouble(),
                height: 2,
                child: const IgnorePointer(
                  child: CustomPaint(painter: _DottedLinePainter()),
                ),
              ),
              Positioned(
                left: horizontalStart - 21,
                top: horizontalY - 21,
                width: 44,
                height: 44,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: widget.enabled
                      ? (details) {
                          setState(() {
                            _horizontalGuide = (_horizontalGuide +
                                    details.delta.dy /
                                        (horizontalMaximum - horizontalMinimum))
                                .clamp(0.0, 1.0)
                                .toDouble();
                          });
                        }
                      : null,
                  child: const Center(child: _GuideHandle()),
                ),
              ),
              Positioned(
                left: verticalX,
                top: previewTop,
                width: 2,
                height: previewHeight,
                child: const IgnorePointer(
                  child: CustomPaint(painter: _DottedLinePainter(vertical: true)),
                ),
              ),
              Positioned(
                left: verticalX - 21,
                top: previewBottom - 21,
                width: 44,
                height: 44,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: widget.enabled
                      ? (details) {
                          final range = (verticalMaximum - verticalMinimum)
                              .clamp(1.0, double.infinity)
                              .toDouble();
                          setState(() {
                            _verticalGuide = (_verticalGuide + details.delta.dx / range)
                                .clamp(0.0, 1.0)
                                .toDouble();
                          });
                        }
                      : null,
                  child: const Center(child: _GuideHandle()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCell(int index) {
    final slot = widget.slots[index];
    final selected = widget.selectedIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? () => widget.onSelect(index) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        foregroundDecoration: BoxDecoration(
          border: Border.all(
            color: selected ? const Color(0xFF3478F6) : Colors.transparent,
            width: selected ? 2 : 0,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (slot.isImported)
              _VideoSurface(slot: slot)
            else
              const ColoredBox(
                color: Color(0xFFF0F2F5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.video_file_outlined, color: Color(0xFF94A0B2), size: 27),
                    SizedBox(height: 5),
                    Text(
                      '暂无视频',
                      style: TextStyle(color: Color(0xFF7C8798), fontSize: 11),
                    ),
                    SizedBox(height: 24),
                  ],
                ),
              ),
            Positioned(
              left: 7,
              top: 7,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 21,
                height: 21,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF3478F6) : const Color(0xBFFFFFFF),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? const Color(0xFF3478F6) : const Color(0xFFD3D9E2),
                  ),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF667085),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Center(
                child: Material(
                  color: slot.isImported
                      ? const Color(0xCFE9F1FF)
                      : const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: widget.enabled ? () => widget.onImport(index) : null,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      child: Text(
                        '导入',
                        style: TextStyle(
                          color: Color(0xFF3478F6),
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({required this.slot});

  final VideoSlotData slot;

  @override
  Widget build(BuildContext context) {
    final controller = slot.controller!;
    final size = controller.value.size;
    return LayoutBuilder(
      builder: (context, constraints) {
        final sourceAspect = size.width / size.height;
        final cellAspect = constraints.maxWidth / constraints.maxHeight;
        final baseWidth = sourceAspect > cellAspect
            ? constraints.maxHeight * sourceAspect
            : constraints.maxWidth;
        final baseHeight = sourceAspect > cellAspect
            ? constraints.maxHeight
            : constraints.maxWidth / sourceAspect;
        final displayWidth = baseWidth * slot.zoom / 100;
        final displayHeight = baseHeight * slot.zoom / 100;
        final availablePanX = math.max(0.0, (displayWidth - constraints.maxWidth) / 2);
        final availablePanY = math.max(0.0, (displayHeight - constraints.maxHeight) / 2);
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform.translate(
              offset: Offset(
                slot.offsetX / 100 * availablePanX,
                slot.offsetY / 100 * availablePanY,
              ),
              child: SizedBox(
                width: displayWidth,
                height: displayHeight,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GuideHandle extends StatelessWidget {
  const _GuideHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 17,
      height: 17,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF79A8F8), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0x1A3478F6), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: const Center(
        child: SizedBox(
          width: 4,
          height: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Color(0xFF3478F6), shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  const _DottedLinePainter({this.vertical = false});

  final bool vertical;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF8DB7FA)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    const dash = 4.0;
    const gap = 4.0;
    final length = vertical ? size.height : size.width;
    for (var start = 0.0; start < length; start += dash + gap) {
      final end = (start + dash).clamp(0.0, length).toDouble();
      if (vertical) {
        canvas.drawLine(Offset(size.width / 2, start), Offset(size.width / 2, end), paint);
      } else {
        canvas.drawLine(Offset(start, size.height / 2), Offset(end, size.height / 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter oldDelegate) {
    return oldDelegate.vertical != vertical;
  }
}
