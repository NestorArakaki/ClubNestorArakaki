import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/formatters.dart';
import '../widgets/async_view.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.api});
  final ApiClient api;
  @override
  Widget build(BuildContext context) => AsyncView<Profile>(
    load: api.profile,
    builder: (profile, refresh) => ProfileForm(api: api, profile: profile),
  );
}

class ProfileForm extends StatefulWidget {
  const ProfileForm({super.key, required this.api, required this.profile});
  final ApiClient api;
  final Profile profile;
  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _first, _last, _birth;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _first = TextEditingController(text: widget.profile.firstName);
    _last = TextEditingController(text: widget.profile.lastName);
    _birth = TextEditingController(text: widget.profile.birthDate ?? '');
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _birth.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
    });
    try {
      final saved = await widget.api.updateProfile({
        'first_name': _first.text.trim(),
        'last_name': _last.text.trim(),
        'birth_date': _birth.text.isEmpty ? null : _birth.text,
      });
      if (mounted) {
        _first.text = saved.firstName;
        _last.text = saved.lastName;
        _birth.text = saved.birthDate ?? '';
        showMessage(context, 'Perfil actualizado.');
      }
    } catch (e) {
      if (mounted) showMessage(context, '$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Mi perfil', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.profile.email ?? 'Sin correo en Firebase',
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Correo (solo lectura)',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _first,
            enabled: !_busy,
            validator: requiredName,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _last,
            enabled: !_busy,
            validator: requiredName,
            decoration: const InputDecoration(labelText: 'Apellido'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _birth,
            enabled: !_busy,
            validator: birthValidator,
            keyboardType: TextInputType.datetime,
            decoration: const InputDecoration(
              labelText: 'Nacimiento (AAAA-MM-DD)',
              helperText: 'Opcional. Borrá el campo para quitar la fecha.',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Guardando…' : 'Guardar perfil'),
          ),
        ],
      ),
    ),
  );
}
