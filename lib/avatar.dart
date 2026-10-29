import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'face.dart';

/// Textured anatomical glTF with coordinated jaw, teeth, tongue and eyelids.
/// Playback PCM energy drives the jaw; this is amplitude-based articulation,
/// not phoneme alignment.
class BlenderAvatar extends StatefulWidget {
  const BlenderAvatar(
      {super.key,
      required this.mode,
      required this.energy,
      required this.word,
      required this.mood,
      this.wordOffset = 0});
  final FaceMode mode;
  final double energy;
  final String word, mood;
  final int wordOffset;
  @override
  State<BlenderAvatar> createState() => _BlenderAvatarState();
}

class _BlenderAvatarState extends State<BlenderAvatar> {
  WebViewController? controller;
  String? posterData;
  bool posterReady = false;
  Timer? poseTimer;
  bool dirty = true, sending = false;
  @override
  void initState() {
    super.initState();
    rootBundle.load('assets/avatar/mimo-portrait.png').then((data) {
      if (mounted)
        setState(() {
          posterData =
              'data:image/png;base64,${base64Encode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))}';
          posterReady = true;
        });
    }).catchError((Object _) {
      if (mounted) setState(() => posterReady = true);
    });
    poseTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (dirty && !sending) updatePose();
    });
  }

  @override
  void dispose() {
    poseTimer?.cancel();
    controller = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BlenderAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.word != widget.word ||
        oldWidget.wordOffset != widget.wordOffset ||
        (oldWidget.energy - widget.energy).abs() > .08 ||
        oldWidget.mood != widget.mood) dirty = true;
  }

  Future<void> updatePose() async {
    if (sending || controller == null) return;
    sending = true;
    dirty = false;
    try {
      await controller
          ?.runJavaScript('window.mimoPose && window.mimoPose(${jsonEncode({
            'speaking': widget.mode == FaceMode.speaking,
            'word': widget.word,
            'offset': widget.wordOffset,
            'energy': widget.energy,
            'sleeping': widget.mode == FaceMode.sleeping,
            'listening': widget.mode == FaceMode.listening,
            'mood': widget.mood
          })});');
    } catch (_) {
      dirty = true;
    } finally {
      sending = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return MimoFace(
          mode: widget.mode, energy: widget.energy, mood: widget.mood);
    }
    if (!posterReady)
      return Image.asset('assets/avatar/mimo-portrait.png',
          fit: BoxFit.contain);
    return IgnorePointer(
        child: ModelViewer(
      id: 'mimo-avatar',
      src: 'assets/avatar/mimo-head.glb',
      poster: posterData,
      alt: 'MİMO üç boyutlu yüzü',
      cameraControls: false,
      disablePan: true,
      disableZoom: true,
      ar: false,
      autoPlay: false,
      autoRotate: false,
      environmentImage: 'neutral',
      exposure: .95,
      cameraTarget: '0m 0.035m 0m',
      cameraOrbit: '0deg 90deg 90%',
      fieldOfView: '30deg',
      backgroundColor: const Color(0xFF060D1A),
      animationName: 'MimoPerformance',
      animationCrossfadeDuration: 0,
      debugLogging: false,
      relatedCss:
          'model-viewer{width:100vw;height:100vh} #ar-button,#ar-prompt{display:none}',
      relatedJs: r'''
        const viewer=document.getElementById('mimo-avatar');
        let state={speaking:false,word:'',sleeping:false}, began=0;
        window.mimoPose=(next)=>{if(next.word!==state.word || next.offset!==state.offset)began=performance.now();state=next;};
        viewer.addEventListener('load',()=>{viewer.pause();viewer.currentTime=0;});
        const started=performance.now();
        setInterval(()=>{
          if(!viewer.loaded)return;
          const time=(performance.now()-started)/1000;
          const chars=Array.from(state.word.toLocaleLowerCase('tr'));
          const index=Math.min(chars.length-1,Math.floor((performance.now()-began)/105));
          const c=chars[index]||'';
          const pose=/[aeâ]/.test(c)?.95:/[oöuü]/.test(c)?.65:/[iı]/.test(c)?.32:/[mbp]/.test(c)?0:.18;
          const amount=state.speaking?(state.word===''?Math.max(0,Math.min(1,state.energy||0)):(performance.now()-began<Math.max(250,chars.length*140)?pose:0)):0;
          // Seek the Blender morph animation to a deterministic mouth pose.
          if(viewer.duration>0) {
            const blink=time%4.8;
            viewer.currentTime=state.sleeping ? 25/24 : state.speaking ? .5*amount : blink>4.6 ? 1+(blink-4.6)/.2*.125 : 0;
          }
          viewer.cameraOrbit=`${Math.sin(time*.45)*3}deg ${90+Math.sin(time*.7)*1.2}deg 90%`;
        },90);
      ''',
      onWebViewCreated: (value) {
        controller = value;
        dirty = true;
      },
    ));
  }
}
