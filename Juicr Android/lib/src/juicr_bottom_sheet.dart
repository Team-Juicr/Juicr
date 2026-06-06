import 'package:flutter/material.dart';

import 'visual_style.dart';

Future<T?> showJuicrBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useRootNavigator = false,
  bool? showDragHandle,
  Color? backgroundColor,
  ShapeBorder? shape,
  Color? barrierColor,
}) {
  final floating = JuicrVisual.bottomSheetUsesFloatingLayout(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    showDragHandle: floating ? false : (showDragHandle ?? true),
    backgroundColor: floating
        ? Colors.transparent
        : backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
    shape: floating ? null : shape ?? JuicrVisual.bottomSheetShape,
    barrierColor: barrierColor,
    builder: (sheetContext) {
      final keyboardInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
      final sheetFloating = JuicrVisual.bottomSheetUsesFloatingLayout(
        sheetContext,
      );
      final content = JuicrVisual.bottomSheetFrame(
        sheetContext,
        includeHandle: sheetFloating && (showDragHandle ?? true),
        padding: sheetFloating
            ? const EdgeInsets.fromLTRB(16, 10, 16, 16)
            : EdgeInsets.zero,
        child: builder(sheetContext),
      );
      return AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: SafeArea(top: false, child: content),
      );
    },
  );
}

EdgeInsets juicrBottomSheetPadding(
  BuildContext sheetContext, {
  double left = 18,
  double top = 0,
  double right = 18,
}) {
  return EdgeInsets.fromLTRB(
    left,
    top,
    right,
    JuicrVisual.bottomSheetBottomBreathingRoom,
  );
}
