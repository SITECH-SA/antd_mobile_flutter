import 'package:antd_mobile_flutter/antd_mobile_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// App with a full-screen button underneath, to check that toasts don't
/// swallow taps meant for the page.
Widget _app(
    {required void Function(BuildContext) onReady, VoidCallback? onPageTap}) {
  return AdmTheme(
    data: const AdmThemeData(),
    child: MaterialApp(
      home: Builder(
        builder: (context) {
          onReady(context);
          return Scaffold(
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onPageTap,
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  late BuildContext ctx;

  tearDown(() {
    // Hosts are static; clear messages between tests.
    AdmToast.hide(ctx);
  });

  testWidgets('plain top toast shows, does not block taps, auto-hides',
      (tester) async {
    var pageTaps = 0;
    await tester
        .pumpWidget(_app(onReady: (c) => ctx = c, onPageTap: () => pageTaps++));

    AdmToast.show(ctx, content: 'Saved!', duration: const Duration(seconds: 2));
    // Added in a post-frame callback, so the slide-in starts a frame later.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Saved!'), findsOneWidget);
    expect(tester.getCenter(find.text('Saved!')).dy, greaterThan(0),
        reason: 'fully slid in, on screen');

    await tester.tapAt(tester.getCenter(find.text('Saved!')));
    expect(pageTaps, 1,
        reason: 'taps on a plain toast reach the page underneath');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Saved!'), findsNothing);
  });

  testWidgets('bottom closable toast: tap, persist, close button',
      (tester) async {
    var taps = 0, closes = 0;
    await tester.pumpWidget(_app(onReady: (c) => ctx = c));

    AdmToast.show(
      ctx,
      title: 'Add to Home Screen',
      content: 'Open it with one tap.',
      placement: AdmToastPlacement.bottom,
      offset: 64,
      duration: Duration.zero,
      closable: true,
      onTap: () => taps++,
      onClose: () => closes++,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    final title = find.text('Add to Home Screen');
    expect(title, findsOneWidget);
    // Anchored to the bottom, above the offset.
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getBottomLeft(title).dy, greaterThan(screenHeight / 2));
    expect(tester.getBottomLeft(title).dy, lessThan(screenHeight - 64));

    await tester.tap(title);
    expect(taps, 1);

    // Duration.zero: still there much later.
    await tester.pump(const Duration(seconds: 10));
    expect(title, findsOneWidget);

    await tester.tap(find.byIcon(AdmIcons.x));
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect(title, findsNothing);
  });

  testWidgets('closable toast can be swiped away', (tester) async {
    var closes = 0;
    await tester.pumpWidget(_app(onReady: (c) => ctx = c));

    AdmToast.show(
      ctx,
      title: 'Swipe me',
      content: 'Away',
      placement: AdmToastPlacement.bottom,
      duration: Duration.zero,
      closable: true,
      onClose: () => closes++,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.drag(find.text('Swipe me'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect(find.text('Swipe me'), findsNothing);
  });

  testWidgets('handle.close removes the toast without calling onClose',
      (tester) async {
    var closes = 0;
    await tester.pumpWidget(_app(onReady: (c) => ctx = c));

    final handle = AdmToast.show(
      ctx,
      content: 'Closable from code',
      duration: Duration.zero,
      closable: true,
      onClose: () => closes++,
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Closable from code'), findsOneWidget);

    handle.close();
    await tester.pumpAndSettle();
    expect(find.text('Closable from code'), findsNothing);
    expect(closes, 0);
  });
}
