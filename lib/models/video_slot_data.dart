import 'package:video_player/video_player.dart';

class VideoSlotData {
  VideoSlotData({required this.number});

  final int number;
  String? path;
  VideoPlayerController? controller;
  double zoom = 100;
  double offsetX = 0;
  double offsetY = 0;

  bool get isImported => path != null && controller?.value.isInitialized == true;

  Future<void> dispose() async {
    await controller?.dispose();
  }
}
