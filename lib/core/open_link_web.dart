import 'package:web/web.dart' as web;

/// Opens [url] in a new tab.
void openLink(String url) => web.window.open(url, '_blank');
