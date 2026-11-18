// Links the game points people to.
export 'open_link_stub.dart' if (dart.library.js_interop) 'open_link_web.dart';

/// The App Store listing. Null until it's live: the "Download the app…"
/// line on iPhone browsers only shows once this is set.
///
/// AT LAUNCH, when setting this: Alex wants that line to also sell never
/// repeating questions - along the lines of "Download the app to never hear
/// the same questions twice and better voice recognition" (his wording to
/// finalise; it sits in guest_screen.dart, _AppNudge).
const String? appStoreUrl = null;
