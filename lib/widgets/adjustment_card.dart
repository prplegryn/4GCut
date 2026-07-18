import 'dart:ui';

import 'package:flutter/material.dart';

class AdjustmentCard extends StatelessWidget {
  const AdjustmentCard({
    super.key,
    required this.zoom,
    required this.offsetX,
    required this.offsetY,
    required this.enabled,
    required this.animateValues,
    required this.onZoomChanged,
    required this.onOffsetXChanged,
    required this.onOffsetYChanged,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });

  final double zoom;
  final double offsetX;
  final double offsetY;
  final bool enabled;
  final bool animateValues;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<double> onOffsetXChanged;
  final ValueChanged<double> onOffsetYChanged;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.46,
      duration: const Duration(milliseconds: 180),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.fromLTRB(18, 15, 15, 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE8ECF2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D15345E),
              blurRadius: 18,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          children: [
            _AdjustmentRow(
              label: '缩放',
              value: zoom,
              min: 100,
              max: 250,
              valueLabel: '${zoom.round()}%',
              enabled: enabled,
              animate: animateValues,
              onChanged: onZoomChanged,
              onInteractionStart: onInteractionStart,
              onInteractionEnd: onInteractionEnd,
            ),
            const SizedBox(height: 7),
            _AdjustmentRow(
              label: 'X 轴',
              value: offsetX,
              min: -100,
              max: 100,
              valueLabel: _signedValue(offsetX),
              enabled: enabled,
              animate: animateValues,
              onChanged: onOffsetXChanged,
              onInteractionStart: onInteractionStart,
              onInteractionEnd: onInteractionEnd,
            ),
            const SizedBox(height: 7),
            _AdjustmentRow(
              label: 'Y 轴',
              value: offsetY,
              min: -100,
              max: 100,
              valueLabel: _signedValue(offsetY),
              enabled: enabled,
              animate: animateValues,
              onChanged: onOffsetYChanged,
              onInteractionStart: onInteractionStart,
              onInteractionEnd: onInteractionEnd,
            ),
          ],
        ),
      ),
    );
  }

  static String _signedValue(double value) {
    final rounded = value.round();
    return rounded > 0 ? '+$rounded' : '$rounded';
  }
}

class _AdjustmentRow extends StatelessWidget {
  const _AdjustmentRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.enabled,
    required this.animate,
    required this.onChanged,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String valueLabel;
  final bool enabled;
  final bool animate;
  final ValueChanged<double> onChanged;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF344054),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: value),
            duration: animate ? const Duration(milliseconds: 180) : Duration.zero,
            curve: Curves.easeOutCubic,
            builder: (context, animatedValue, child) {
              return SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: const Color(0xFF3478F6),
                  inactiveTrackColor: const Color(0xFFDCE4EF),
                  thumbColor: const Color(0xFF3478F6),
                  overlayColor: const Color(0x173478F6),
                  thumbShape: const _CapsuleThumbShape(),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                ),
                child: Slider(
                  value: animatedValue.clamp(min, max).toDouble(),
                  min: min,
                  max: max,
                  onChangeStart: enabled ? (_) => onInteractionStart() : null,
                  onChangeEnd: enabled ? (_) => onInteractionEnd() : null,
                  onChanged: enabled ? onChanged : null,
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: 43,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 130),
            child: Text(
              valueLabel,
              key: ValueKey(valueLabel),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CapsuleThumbShape extends SliderComponentShape {
  const _CapsuleThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(24, 11);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final paint = Paint()..color = sliderTheme.thumbColor ?? const Color(0xFF3478F6);
    final rect = Rect.fromCenter(center: center, width: 24, height: 10);
    context.canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5)), paint);
  }
}
