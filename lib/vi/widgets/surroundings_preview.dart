import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../surroundings_watch.dart';

/// What the camera sees, once it is seeing anything.
class SurroundingsPreview extends StatelessWidget {
  const SurroundingsPreview({super.key, required this.watch});

  final SurroundingsWatch watch;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: watch,
        builder: (context, _) {
          final camera = watch.camera;
          return camera == null
              ? Container(color: AppColors.navyRaised)
              : CameraPreview(camera);
        },
      );
}
