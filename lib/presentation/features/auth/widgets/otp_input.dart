import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Segmented OTP entry: [length] single-digit boxes that behave as one field.
///
/// Typing a digit auto-advances to the next box; backspace on an empty box
/// steps back and clears the previous one. The concatenated value is reported
/// via [onChanged] on every edit, and [onCompleted] fires once every box is
/// filled. Set [hasError] to paint the boxes in the danger colour.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    required this.length,
    required this.onChanged,
    this.onCompleted,
    this.hasError = false,
    this.enabled = true,
  });

  final int length;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final bool hasError;
  final bool enabled;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _controllers =
        List.generate(widget.length, (_) => TextEditingController());
    _nodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _value => _controllers.map((c) => c.text).join();

  void _emit() {
    final value = _value;
    widget.onChanged(value);
    if (value.length == widget.length) {
      widget.onCompleted?.call(value);
    }
  }

  void _onChanged(int index, String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');

    // Pasted / autofilled code: spread the digits across the boxes from here.
    if (digits.length > 1) {
      var cursor = index;
      for (final d in digits.split('')) {
        if (cursor >= widget.length) break;
        _controllers[cursor].text = d;
        cursor++;
      }
      final next = (cursor).clamp(0, widget.length - 1);
      _nodes[next].requestFocus();
      if (cursor >= widget.length) _nodes[next].unfocus();
      _emit();
      return;
    }

    _controllers[index].text = digits;
    _controllers[index].selection =
        TextSelection.collapsed(offset: digits.length);

    if (digits.isNotEmpty && index + 1 < widget.length) {
      _nodes[index + 1].requestFocus();
    } else if (digits.isNotEmpty) {
      _nodes[index].unfocus();
    }
    _emit();
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _nodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      _emit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.read<AppPalette>();

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );

    final baseColor = widget.hasError ? palette.danger : palette.border;
    final focusColor = widget.hasError ? palette.danger : palette.primary;

    return Row(
      children: List.generate(widget.length, (i) {
        return Expanded(
          child: Padding(
            // Symmetric padding keeps every box the same width; using only
            // right-padding made the last box wider (and, via AspectRatio,
            // taller) so it sat higher than the others.
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: AspectRatio(
              // < 1 makes the boxes taller than they are wide.
              aspectRatio: 0.8,
              child: Focus(
                onKeyEvent: (_, event) => _onKey(i, event),
                child: TextField(
                  controller: _controllers[i],
                  focusNode: _nodes[i],
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  textInputAction: i == widget.length - 1
                      ? TextInputAction.done
                      : TextInputAction.next,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) => _onChanged(i, v),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: palette.onSurface,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                    filled: true,
                    fillColor: palette.surface,
                    enabledBorder: border(baseColor),
                    focusedBorder: border(focusColor, 1.6),
                    border: border(baseColor),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
