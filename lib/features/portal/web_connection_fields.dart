part of 'web_connection_dialog.dart';

extension _WebConnectionFields on _WebConnectionState {
  Widget _fields() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(_s.t('secureWeb.body')),
      if (widget.moveFrom != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(_s.t('secureWeb.moveBody')),
      ],
      const SizedBox(height: AppSpacing.md),
      if (!_generated &&
          widget.conversationId == null &&
          widget.moveFrom == null) ...[
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(_s.t('secureWeb.create'))),
            ButtonSegment(value: true, label: Text(_s.t('secureWeb.join'))),
          ],
          selected: {_join},
          onSelectionChanged: _busy
              ? null
              : (selection) => _update(() {
                  _join = selection.single;
                  _remote.clear();
                  _error = null;
                }),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      if (_generated) ...[
        Text(_s.t(_join ? 'secureWeb.returnAnswer' : 'secureWeb.shareInvite')),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const Key('shared-web-local-code'),
          autofillHints: null,
          controller: _local,
          readOnly: true,
          enableInteractiveSelection: false,
          maxLines: 3,
          decoration: InputDecoration(labelText: _s.t('secureWeb.myCode')),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.copy),
            label: Text(_s.t('secureWeb.copyCode')),
            onPressed: () async {
              await OsPrivacy.copySensitive(_local.text);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_s.t('secureWeb.copied'))),
                );
              }
            },
          ),
        ),
        if (_local.text.length <= 2900)
          OutlinedButton.icon(
            onPressed: _showQr,
            icon: const Icon(Icons.qr_code),
            label: Text(_s.t('secureWeb.showQr')),
          ),
      ],
      if (!_generated && _join || _generated && !_join)
        TextField(
          key: const Key('shared-web-remote-code'),
          enableIMEPersonalizedLearning: false,
          autofillHints: null,
          controller: _remote,
          maxLines: 4,
          maxLength: 49152,
          autocorrect: false,
          enableSuggestions: false,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: _s.t(
              _generated ? 'secureWeb.theirAnswer' : 'secureWeb.theirInvite',
            ),
            hintText: 'IGW1.…',
            counterText: '',
          ),
        ),
      if (!_generated && _join || _generated && !_join)
        TextButton.icon(
          onPressed: _busy ? null : _readQr,
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(_s.t('secureWeb.readQrImage')),
        ),
      if (_busy)
        const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: LinearProgressIndicator(),
        ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
