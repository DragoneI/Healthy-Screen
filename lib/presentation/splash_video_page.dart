import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'app_shell.dart';
import 'ui.dart';

class SplashVideoPage extends StatefulWidget {
  const SplashVideoPage({super.key});

  @override
  State<SplashVideoPage> createState() => _SplashVideoPageState();
}

class _SplashVideoPageState extends State<SplashVideoPage> {
  VideoPlayerController? _controller;
  Timer? _fallbackTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    // Sécurité : passe à AppShell même si la vidéo met un peu plus de temps
    _fallbackTimer = Timer(const Duration(milliseconds: 2600), _goNext);

    try {
      final controller = VideoPlayerController.asset('assets/splash/splash.mp4');
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;

      controller.setVolume(0);
      controller.addListener(() {
        final v = controller.value;
        if (v.isInitialized &&
            !v.isPlaying &&
            v.position >= v.duration &&
            v.duration > Duration.zero) {
          _goNext();
        }
      });

      setState(() {});
      await controller.play();
    } catch (_) {
      _goNext();
    }
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    _fallbackTimer?.cancel();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AppShell(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final ready = ctrl != null && ctrl.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        onTap: _goNext,
        child: Center(
          child: ready
              ? AspectRatio(
                  aspectRatio: ctrl.value.aspectRatio,
                  child: VideoPlayer(ctrl),
                )
              : const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppC.indigo,
                  ),
                ),
        ),
      ),
    );
  }
}