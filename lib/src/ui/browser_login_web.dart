import 'package:web/web.dart' as web;

bool get canOpenBrowserLogin => true;

void openBrowserLogin() {
  _openServerLogin();
}

void openLoggedOutLogin() {
  final web.HTMLFormElement form =
      web.document.createElement('form') as web.HTMLFormElement;
  form.method = 'post';
  form.action = '/logout';
  web.document.body?.append(form);
  form.submit();
}

void _openServerLogin() {
  web.window.location.replace('/');
}
