import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'face.dart';

/// Blender-built glTF with articulated lips. Speech progress drives mouth
/// poses at word boundaries; this is approximate word-timed articulation,
/// not audio-derived phoneme alignment.
class BlenderAvatar extends StatefulWidget {
  const BlenderAvatar(
      {super.key,
      required this.mode,
      required this.energy,
      required this.word,
      required this.mood});
  final FaceMode mode;
  final double energy;
  final String word, mood;
  @override
  State<BlenderAvatar> createState() => _BlenderAvatarState();
}

class _BlenderAvatarState extends State<BlenderAvatar> {
  WebViewController? controller;
  @override
  void didUpdateWidget(covariant BlenderAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.word != widget.word ||
        oldWidget.energy != widget.energy) updatePose();
  }

  Future<void> updatePose() async {
    try {
      await controller
          ?.runJavaScript('window.mimoPose && window.mimoPose(${jsonEncode({
            'speaking': widget.mode == FaceMode.speaking,
            'word': widget.word,
            'energy': widget.energy,
            'sleeping': widget.mode == FaceMode.sleeping
          })});');
    } catch (_) {
      /* The model may still be loading; JS retains the last pose. */
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return MimoFace(
          mode: widget.mode, energy: widget.energy, mood: widget.mood);
    }
    return IgnorePointer(
        child: ModelViewer(
      id: 'mimo-avatar',
      src: 'assets/avatar/mimo-head.glb',
      alt: 'MİMO üç boyutlu yüzü',
      cameraControls: false,
      disablePan: true,
      disableZoom: true,
      ar: false,
      autoPlay: false,
      autoRotate: false,
      environmentImage: 'neutral',
      exposure: 1.15,
      cameraOrbit: '0deg 90deg 96%',
      fieldOfView: '30deg',
      backgroundColor: const Color(0xFF060D1A),
      animationName: 'MimoSpeech',
      animationCrossfadeDuration: 0,
      debugLogging: false,
      relatedCss:
          'model-viewer{width:100vw;height:100vh} #ar-button,#ar-prompt{display:none}',
      relatedJs: r'''
        const viewer=document.getElementById('mimo-avatar');
        let state={speaking:false,word:'',sleeping:false}, began=0;
        window.mimoPose=(next)=>{if(next.word!==state.word)began=performance.now();state=next;};
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
          if(viewer.duration>0)viewer.currentTime=viewer.duration*.5*amount;
          viewer.cameraOrbit=`${Math.sin(time*.45)*3}deg ${90+Math.sin(time*.7)*1.2}deg 96%`;
        },90);
      ''',
      onWebViewCreated: (value) {
        controller = value;
        updatePose();
      },
    ));
  }
}
