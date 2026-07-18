import 'package:flutter/material.dart';

class ActionControls extends StatelessWidget {
  const ActionControls({
    super.key,
    required this.audioLabel,
    required this.ratioLabel,
    required this.audioEnabled,
    required this.ratioEnabled,
    required this.alignEnabled,
    required this.previewEnabled,
    required this.exportEnabled,
    required this.aligning,
    required this.onAudio,
    required this.onRatio,
    required this.onAlign,
    required this.onPreview,
    required this.onExport,
  });

  final String audioLabel;
  final String ratioLabel;
  final bool audioEnabled;
  final bool ratioEnabled;
  final bool alignEnabled;
  final bool previewEnabled;
  final bool exportEnabled;
  final bool aligning;
  final VoidCallback onAudio;
  final VoidCallback onRatio;
  final VoidCallback onAlign;
  final VoidCallback onPreview;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PillAction(
            icon: Icons.volume_up_outlined,
            label: audioLabel,
            enabled: audioEnabled,
            onTap: onAudio,
          ),
          _PillAction(
            icon: Icons.aspect_ratio_outlined,
            label: ratioLabel,
            enabled: ratioEnabled,
            onTap: onRatio,
          ),
          _RoundAction(
            icon: Icons.sync_rounded,
            label: '对齐',
            enabled: alignEnabled,
            busy: aligning,
            onTap: onAlign,
          ),
          _RoundAction(
            icon: Icons.replay_rounded,
            label: '预览',
            enabled: previewEnabled,
            onTap: onPreview,
          ),
          _RoundAction(
            icon: Icons.file_upload_outlined,
            label: '导出',
            enabled: exportEnabled,
            emphasized: true,
            onTap: onExport,
          ),
        ],
      ),
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.38,
      duration: const Duration(milliseconds: 160),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        shadowColor: const Color(0x17142F54),
        elevation: 2,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            height: 52,
            constraints: const BoxConstraints(minWidth: 72),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFE1E7EF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: const Color(0xFF3478F6)),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF344054),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.busy = false,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final bool busy;
  final bool emphasized;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled || busy ? 1 : 0.38,
      duration: const Duration(milliseconds: 160),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: emphasized && enabled ? const Color(0xFF3478F6) : Colors.white,
            shape: const CircleBorder(),
            shadowColor: const Color(0x17142F54),
            elevation: 2,
            child: InkWell(
              onTap: enabled && !busy ? onTap : null,
              customBorder: const CircleBorder(),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: emphasized && enabled
                        ? const Color(0xFF3478F6)
                        : const Color(0xFFE1E7EF),
                  ),
                ),
                child: Center(
                  child: busy
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : Icon(
                          icon,
                          size: 22,
                          color: emphasized && enabled
                              ? Colors.white
                              : const Color(0xFF3478F6),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
