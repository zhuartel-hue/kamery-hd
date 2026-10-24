import 'package:flutter/material.dart';

import '../theme.dart';

/// Logotyp „AriView”: „Ari” w kolorze tekstu, „View” w gradiencie oceanu.
class AriViewWordmark extends StatelessWidget {
  const AriViewWordmark({super.key, this.fontSize});

  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.6, fontSize: fontSize);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('Ari', style: style.copyWith(color: Theme.of(context).colorScheme.onSurface)),
        ShaderMask(
          shaderCallback: (r) => Ocean.gradient.createShader(r),
          child: Text('View', style: style.copyWith(color: Colors.white)),
        ),
      ],
    );
  }
}
