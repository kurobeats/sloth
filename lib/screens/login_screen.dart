import 'package:flutter/material.dart';

import '../state.dart';
import '../todo_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _allowSelfSigned = false;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await AppScope.of(context).signIn(
      server: _server.text,
      username: _user.text.trim(),
      password: _password.text,
      allowBadCert: _allowSelfSigned,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.check_circle_outline, size: 56, color: c.accent),
                    const SizedBox(height: 16),
                    Text(
                      'Sloth',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: TodoText.xxxxl,
                        fontWeight: FontWeight.w600,
                        color: c.primaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tasks from your Vikunja server',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: TodoText.medium,
                        color: c.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Server',
                        hintText: 'https://vikunja.example.com',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _user,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Username Or Email Address',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    CheckboxListTile(
                      value: _allowSelfSigned,
                      onChanged: (v) =>
                          setState(() => _allowSelfSigned = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: Text(
                        'Allow self-signed certificate',
                        style: TextStyle(fontSize: 13, color: c.secondaryText),
                      ),
                      subtitle: Text(
                        'Only needed when the server uses a private CA.',
                        style: TextStyle(fontSize: 11, color: c.secondaryText),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (state.error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        state.error!,
                        style: TextStyle(color: c.overdue, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: state.loading ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: c.accent,
                        foregroundColor: c.onAccent,
                      ),
                      child: state.loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Login'),
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
}
