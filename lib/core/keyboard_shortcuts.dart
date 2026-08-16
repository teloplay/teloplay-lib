import 'package:flutter/widgets.dart';

/// Fix-First List #5 — Keyboard Shortcut Scope Conflict.
///
/// Problem: Space bar in the search field was triggering the global
/// Play/Pause shortcut (bound via [CallbackShortcuts] at the shell root),
/// because [CallbackShortcuts] intercepts key events before they reach a
/// focused [TextField]/[EditableText] unless the shortcut callback itself
/// checks focus state.
///
/// Fix: Wrap every global shortcut callback with [ifNotTypingIn] — it
/// checks whether the currently focused widget is an [EditableText] (what
/// [TextField]/[TextFormField] use internally) and, if so, skips the
/// shortcut entirely so the key event falls through to the text field as
/// normal typed input.
///
/// Usage (see desktop_shell.dart):
/// ```dart
/// const SingleActivator(LogicalKeyboardKey.space):
///     ifNotTypingIn(context, () => repo.togglePause()),
/// ```
VoidCallback ifNotTypingIn(BuildContext context, VoidCallback action) {
  return () {
    if (isTextFieldFocused(context)) return;
    action();
  };
}

/// True if the current primary focus is inside an editable text field
/// (search box, any TextField/TextFormField, etc.) anywhere in the app.
bool isTextFieldFocused(BuildContext context) {
  final focused = FocusManager.instance.primaryFocus;
  if (focused == null) return false;

  // EditableText's internal focus node context has an EditableText
  // ancestor immediately above it — checking the widget context itself
  // (not the shell's context) so this works regardless of where
  // ifNotTypingIn() is called from.
  final focusedContext = focused.context;
  if (focusedContext == null) return false;

  bool found = false;
  focusedContext.visitAncestorElements((element) {
    if (element.widget is EditableText) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}