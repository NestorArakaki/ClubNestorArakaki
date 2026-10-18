import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/formatters.dart';
import '../widgets/async_view.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.auth});
  final AuthService auth;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(),
      _password = TextEditingController(),
      _repeat = TextEditingController();
  bool _register = false, _busy = false, _hidden = true;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit({bool reset = false}) async {
    if (reset
        ? emailValidator(_email.text) != null
        : !_form.currentState!.validate()) {
      if (reset) {
        showMessage(
          context,
          'Ingresá un correo válido para recuperar tu contraseña.',
        );
      }
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (reset) {
        await widget.auth.resetPassword(_email.text);
        if (mounted) {
          showMessage(
            context,
            'Si hay una cuenta con ese correo, recibirás un enlace. Revisá también spam.',
          );
        }
      } else if (_register) {
        await widget.auth.register(_email.text, _password.text);
      } else {
        await widget.auth.login(_email.text, _password.text);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ClubNestorArakaki')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: AutofillGroup(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _register ? 'Crear cuenta' : 'Iniciar sesión',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: emailValidator,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: _hidden,
                    autofillHints: [
                      _register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    validator: passwordValidator,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      suffixIcon: IconButton(
                        tooltip: _hidden
                            ? 'Mostrar contraseña'
                            : 'Ocultar contraseña',
                        onPressed: () => setState(() {
                          _hidden = !_hidden;
                        }),
                        icon: Icon(
                          _hidden ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  if (_register) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _repeat,
                      enabled: !_busy,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Repetir contraseña',
                      ),
                      validator: (value) => value == _password.text
                          ? null
                          : 'Las contraseñas no coinciden.',
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(
                      _busy
                          ? 'Procesando…'
                          : _register
                          ? 'Registrarme'
                          : 'Ingresar',
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _register = !_register;
                            _error = null;
                            _form.currentState?.reset();
                          }),
                    child: Text(
                      _register ? 'Ya tengo cuenta' : 'Crear una cuenta',
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _submit(reset: true),
                    child: const Text('Recuperar contraseña'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
