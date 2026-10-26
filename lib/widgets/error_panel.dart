import 'package:flutter/material.dart';

import '../services/api_client.dart';

String friendlyErrorMessage(Object? error) {
  if (error is ApiException) {
    if (error.network) {
      return 'Revisá tu conexión a Internet y volvé a intentarlo. Si el servicio está iniciando, puede demorar unos instantes.';
    }
    if ((error.status ?? 0) >= 500 || error.code == 'invalid_response') {
      return 'Puede ser un problema temporal. Render Free puede tardar en reactivarse. Esperá un momento y volvé a intentarlo.';
    }
    return error.message;
  }
  return 'Ocurrió un problema inesperado. Volvé a intentarlo.';
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final apiError = error is ApiException ? error as ApiException : null;
    final network = apiError?.network ?? false;
    final server =
        (apiError?.status ?? 0) >= 500 || apiError?.code == 'invalid_response';
    final title = network
        ? 'No pudimos conectarnos'
        : server
        ? 'El servidor no está disponible'
        : 'No pudimos cargar la información';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                network
                    ? Icons.wifi_off_rounded
                    : server
                    ? Icons.cloud_off_rounded
                    : Icons.error_outline,
                size: 56,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(friendlyErrorMessage(error), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FormErrorMessage extends StatelessWidget {
  const FormErrorMessage({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
