import 'package:flutter/material.dart';

Widget getFlexibleSpace(BuildContext context) =>
    ColoredBox(color: Theme.of(context).scaffoldBackgroundColor);
Widget getLeadingIcon(BuildContext context) => IconButton(
    tooltip: '返回',
    icon: Icon(Icons.arrow_back_rounded,
        size: 22, color: Theme.of(context).colorScheme.onSurface),
    onPressed: () => Navigator.maybePop(context));
