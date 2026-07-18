import 'package:flutter/material.dart';

import '../services/export_service.dart';

class ExportProgressDialog extends StatelessWidget {
  const ExportProgressDialog({
    super.key,
    required this.progress,
    required this.ratioLabel,
    required this.audioNumber,
    required this.onCancel,
  });

  final ValueListenable<ExportProgress> progress;
  final String ratioLabel;
  final int audioNumber;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 34),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: ValueListenableBuilder<ExportProgress>(
            valueListenable: progress,
            builder: (context, value, child) {
              final percentage = (value.progress * 100).round();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '正在导出',
                    style: TextStyle(
                      color: Color(0xFF182230),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 21),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$percentage%',
                        style: const TextStyle(
                          color: Color(0xFF3478F6),
                          fontSize: 34,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _remainingLabel(value.remaining),
                        style: const TextStyle(color: Color(0xFF7C8798), fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      minHeight: 7,
                      value: value.progress,
                      backgroundColor: const Color(0xFFE8EEF7),
                      color: const Color(0xFF3478F6),
                    ),
                  ),
                  const SizedBox(height: 21),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F8FB),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        _Detail(icon: Icons.aspect_ratio_outlined, text: ratioLabel),
                        const Spacer(),
                        _Detail(icon: Icons.volume_up_outlined, text: '音频 $audioNumber'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 17),
                  OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475467),
                      side: const BorderSide(color: Color(0xFFD8DEE8)),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('取消'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static String _remainingLabel(Duration? remaining) {
    if (remaining == null) return '正在估算剩余时间';
    if (remaining == Duration.zero) return '正在保存';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds.remainder(60);
    return minutes > 0 ? '预计剩余 $minutes 分 $seconds 秒' : '预计剩余 $seconds 秒';
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF3478F6)),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF475467),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
