import 'package:flutter/widgets.dart';

/// Fix-First List #5 — Keyboard Shortcut Scope Conflict (v2).
///
/// Problem (original): Space bar in the search field was triggering the
/// global Play/Pause shortcut, because [CallbackShortcuts] intercepts key
/// events before they reach a focused [TextField]/[EditableText].
///
/// First fix attempt (WRONG — kept for history): wrapping the callback
/// with [ifNotTypingIn] so it no-ops while typing. This stopped playback
/// from toggling, but did NOT fix the real problem — [CallbackShortcuts]
/// marks a key event as *handled* the moment its [SingleActivator]
/// matches, regardless of what the bound callback does. So the space
/// keystroke was still being swallowed before reaching [EditableText];
/// it just silently did nothing instead of toggling playback. Net
/// result: pressing space in the search box typed nothing at all.
///
/// Real fix: don't use [CallbackShortcuts] for keys that can conflict
/// with typing. Instead wrap the shell in a [Focus] widget with
/// [Focus.onKeyEvent], and for the conflicting keys (space, bare
/// arrow-left/right) explicitly return [KeyEventResult.ignored] whenever
/// a text field currently has focus. Returning "ignored" lets Flutter's
/// key-event pipeline continue propagating the event to the focused
/// [EditableText], which is what actually makes space type a space
/// character again — a callback returning early can't do that.
///
/// [isTextFieldFocused] is unchanged and still used by the new
/// [Focus.onKeyEvent] handler in desktop_shell.dart.
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