import 'package:flutter/material.dart';
import '../../theme/adm_icons.dart';
import '../../theme/adm_theme.dart';

enum AdmToastType { success, fail, error, warning, loading, info }

/// Screen edge an [AdmToast] is anchored to.
enum AdmToastPlacement { top, bottom }

class _AdmMessageData {
  static int _nextId = 0;
  final int id = _nextId++;
  final String content;
  final AdmToastType type;
  final String? title;
  final Widget? icon;
  final VoidCallback? onTap;
  final bool closable;
  final VoidCallback? onClose;

  _AdmMessageData({
    required this.content,
    required this.type,
    this.title,
    this.icon,
    this.onTap,
    this.closable = false,
    this.onClose,
  });

  /// Plain status messages ignore touches, as before; anything the user can
  /// act on (tap or close) receives them.
  bool get interactive => onTap != null || closable;

  /// Rich messages (with a title) span the available width instead of
  /// hugging their text.
  bool get block => title != null;
}

/// Lets the caller close one message shown by [AdmToast.show].
class AdmToastHandle {
  const AdmToastHandle._(this._id, this._placement);

  final int _id;
  final AdmToastPlacement _placement;

  /// Removes this message if it is still visible. Does not call `onClose`.
  void close() => AdmToast._hosts[_placement]?.key.currentState?.remove(_id);
}

/// [AdmToast] — Ant Design-style message notifications.
///
/// By default appears at the top-center of the screen, stacks up to 3
/// messages, and auto-dismisses after [duration].
///
/// ```dart
/// AdmToast.show(context, content: 'Saved!', type: AdmToastType.success);
/// AdmToast.show(context, content: 'Warning!', type: AdmToastType.warning);
/// AdmToast.show(context, content: 'Loading…', type: AdmToastType.loading);
/// AdmToast.hide(context); // clear all
/// ```
///
/// Persistent, actionable messages — e.g. an invitation above a bottom tab
/// bar that opens a page on tap and can be swiped away:
///
/// ```dart
/// final handle = AdmToast.show(
///   context,
///   title: 'Add to Home Screen',
///   content: 'Open the app with one tap.',
///   icon: const Icon(AdmIcons.house),
///   placement: AdmToastPlacement.bottom,
///   offset: 76, // clear the tab bar
///   duration: Duration.zero, // stay until closed
///   closable: true,
///   onTap: () => openGuide(),
///   onClose: () => rememberDismissed(),
/// );
/// handle.close(); // remove it programmatically
/// ```
class AdmToast {
  static final Map<AdmToastPlacement,
      ({GlobalKey<_AdmMessageHostState> key, OverlayEntry entry})> _hosts = {};
  static const _maxCount = 3;

  /// Shows a message and returns a handle to close it early.
  ///
  /// - [placement] / [offset]: screen edge and extra distance from it, on top
  ///   of the safe area (e.g. the height of a bottom navigation bar).
  /// - [duration]: time before it hides itself; [Duration.zero] keeps it until
  ///   it is closed. Loading messages never hide themselves.
  /// - [title]: optional bold line above [content]; the message then spans the
  ///   available width.
  /// - [icon]: replaces the icon implied by [type].
  /// - [onTap]: makes the message tappable.
  /// - [closable]: adds a close button and swipe-to-dismiss; [onClose] runs
  ///   when the user closes it this way (not on auto-hide or [hide]).
  static AdmToastHandle show(
    BuildContext context, {
    required String content,
    AdmToastType type = AdmToastType.info,
    Duration duration = const Duration(milliseconds: 3000),
    bool maskClosable = false, // kept for API compatibility
    AdmToastPlacement placement = AdmToastPlacement.top,
    double offset = 0,
    String? title,
    Widget? icon,
    VoidCallback? onTap,
    bool closable = false,
    VoidCallback? onClose,
  }) {
    // Recreate the host if its overlay went away (e.g. the app's root
    // Navigator/Overlay was rebuilt); a stale host would swallow messages.
    final existing = _hosts[placement];
    final host = existing != null && existing.entry.mounted
        ? existing
        : _hosts[placement] = _createHost(context, placement);
    final msg = _AdmMessageData(
      content: content,
      type: type,
      title: title,
      icon: icon,
      onTap: onTap,
      closable: closable,
      onClose: onClose,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = host.key.currentState;
      if (state == null) return;
      state.offset = offset;
      state.add(msg);
      if (type != AdmToastType.loading && duration > Duration.zero) {
        Future.delayed(duration, () => host.key.currentState?.remove(msg.id));
      }
    });

    return AdmToastHandle._(msg.id, placement);
  }

  /// Removes every visible message, at both placements.
  static void hide(BuildContext context) {
    for (final host in _hosts.values) {
      host.key.currentState?.clear();
    }
  }

  static ({GlobalKey<_AdmMessageHostState> key, OverlayEntry entry})
      _createHost(
    BuildContext context,
    AdmToastPlacement placement,
  ) {
    final key = GlobalKey<_AdmMessageHostState>();
    final entry = OverlayEntry(
        builder: (_) => _AdmMessageHost(key: key, placement: placement));
    Overlay.of(context).insert(entry);
    return (key: key, entry: entry);
  }
}

// ── Host Widget ──────────────────────────────────────────────────────────────

class _AdmMessageHost extends StatefulWidget {
  const _AdmMessageHost({super.key, required this.placement});

  final AdmToastPlacement placement;

  @override
  State<_AdmMessageHost> createState() => _AdmMessageHostState();
}

class _AdmMessageHostState extends State<_AdmMessageHost> {
  final _messages = <_AdmMessageData>[];
  final _listKey = GlobalKey<AnimatedListState>();
  double _offset = 0;

  set offset(double value) {
    if (value != _offset) setState(() => _offset = value);
  }

  bool get _isBottom => widget.placement == AdmToastPlacement.bottom;

  void add(_AdmMessageData msg) {
    while (_messages.length >= AdmToast._maxCount) {
      _removeAt(0);
    }
    setState(() => _messages.add(msg));
    _listKey.currentState?.insertItem(
      _messages.length - 1,
      duration: const Duration(milliseconds: 300),
    );
  }

  void remove(int id) {
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx != -1) _removeAt(idx);
  }

  /// Closed by the user (close button or swipe).
  void _dismiss(_AdmMessageData msg, {bool swiped = false}) {
    final idx = _messages.indexWhere((m) => m.id == msg.id);
    if (idx == -1) return;
    // A swiped message has already animated away; drop it without a second animation.
    _removeAt(idx, animate: !swiped);
    msg.onClose?.call();
  }

  void _removeAt(int idx, {bool animate = true}) {
    late final _AdmMessageData msg;
    setState(() => msg = _messages.removeAt(idx));
    _listKey.currentState?.removeItem(
      idx,
      (ctx, anim) => animate
          ? _MessageItem(msg: msg, animation: anim, fromBottom: _isBottom)
          : const SizedBox.shrink(),
      duration: animate ? const Duration(milliseconds: 200) : Duration.zero,
    );
  }

  void clear() {
    for (int i = _messages.length - 1; i >= 0; i--) {
      _removeAt(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Plain status messages never block the screen underneath. The list is a
    // scroll view, which would otherwise absorb taps across its whole band.
    final hasInteractive = _messages.any((m) => m.interactive);
    return SafeArea(
      child: Padding(
        padding: _isBottom
            ? EdgeInsets.only(bottom: 8 + _offset)
            : EdgeInsets.only(top: 8 + _offset),
        child: Align(
          alignment: _isBottom ? Alignment.bottomCenter : Alignment.topCenter,
          child: IgnorePointer(
            ignoring: !hasInteractive,
            child: AnimatedList(
              key: _listKey,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              initialItemCount: 0,
              itemBuilder: (ctx, idx, anim) {
                // Capture the message itself: indexes shift as others come and go.
                final msg = _messages[idx];
                return _MessageItem(
                  msg: msg,
                  animation: anim,
                  fromBottom: _isBottom,
                  onClose: () => _dismiss(msg),
                  onSwiped: () => _dismiss(msg, swiped: true),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Message Item ─────────────────────────────────────────────────────────────

class _MessageItem extends StatelessWidget {
  final _AdmMessageData msg;
  final Animation<double> animation;
  final bool fromBottom;
  final VoidCallback? onClose;
  final VoidCallback? onSwiped;

  const _MessageItem({
    required this.msg,
    required this.animation,
    this.fromBottom = false,
    this.onClose,
    this.onSwiped,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AdmTheme.tokensOf(context);

    Color iconColor;
    IconData? iconData;
    switch (msg.type) {
      case AdmToastType.success:
        iconColor = tokens.colorSuccess;
        iconData = Icons.check_circle;
        break;
      case AdmToastType.fail:
      case AdmToastType.error:
        iconColor = tokens.colorDanger;
        iconData = Icons.cancel;
        break;
      case AdmToastType.warning:
        iconColor = tokens.colorWarning;
        iconData = Icons.warning_rounded;
        break;
      case AdmToastType.loading:
        iconColor = tokens.colorPrimary;
        iconData = null;
        break;
      case AdmToastType.info:
        iconColor = tokens.colorPrimary;
        iconData = Icons.info;
        break;
    }

    final slideAnim = Tween<Offset>(
      begin: Offset(0, fromBottom ? 1.0 : -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

    final Widget leading;
    if (msg.icon != null) {
      leading = IconTheme.merge(
        data: IconThemeData(color: iconColor, size: msg.block ? 20 : 16),
        child: msg.icon!,
      );
    } else if (msg.type == AdmToastType.loading) {
      leading = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: iconColor,
        ),
      );
    } else {
      leading = Icon(iconData, color: iconColor, size: 16);
    }

    final text = Text(
      msg.content,
      style: TextStyle(
        color: msg.title != null
            ? tokens.colorTextSecondary
            : tokens.colorTextBase,
        fontSize: msg.title != null ? tokens.fontSizeSm : tokens.fontSizeMd,
        fontWeight: tokens.fontWeightNormal,
        decoration: TextDecoration.none,
      ),
    );

    final body = msg.title == null
        ? text
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                msg.title!,
                style: TextStyle(
                  color: tokens.colorTextBase,
                  fontSize: tokens.fontSizeMd,
                  fontWeight: tokens.fontWeightBold,
                  decoration: TextDecoration.none,
                ),
              ),
              SizedBox(height: tokens.spaceXs),
              text,
            ],
          );

    final radius = BorderRadius.circular(tokens.radiusMd);

    Widget card = Container(
      constraints: const BoxConstraints(maxWidth: 480),
      decoration: BoxDecoration(
        color: tokens.colorBackground,
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
          BoxShadow(
            color: Color(0x1E000000),
            blurRadius: 6,
            spreadRadius: -4,
            offset: Offset(0, 3),
          ),
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 28,
            spreadRadius: 8,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: msg.onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 10, msg.closable ? 4 : 16, 10),
            child: Row(
              mainAxisSize: msg.block ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: msg.title != null
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: msg.title != null ? 2 : 0),
                  child: leading,
                ),
                SizedBox(width: msg.block ? 12 : 8),
                if (msg.block) Expanded(child: body) else Flexible(child: body),
                if (msg.closable)
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip:
                          MaterialLocalizations.of(context).closeButtonTooltip,
                      icon: Icon(AdmIcons.x,
                          size: 18, color: tokens.colorTextSecondary),
                      onPressed: onClose,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (msg.block) card = SizedBox(width: double.infinity, child: card);

    if (msg.closable) {
      card = Dismissible(
        key: ValueKey('adm-toast-${msg.id}'),
        direction: DismissDirection.horizontal,
        onDismissed: (_) => onSwiped?.call(),
        child: card,
      );
    }

    return IgnorePointer(
      ignoring: !msg.interactive,
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: slideAnim,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Center(child: card),
          ),
        ),
      ),
    );
  }
}
