import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FamilyPage extends StatefulWidget {
  final VoidCallback onDone;
  const FamilyPage({super.key, required this.onDone});

  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  final _name = TextEditingController();
  final _familyName = TextEditingController();
  final _code = TextEditingController();
  bool _loading = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_name.text.trim().isEmpty) {
      _show('Enter your display name first.');
      return;
    }
    setState(() => _loading = true);
    try {
      await action();
      widget.onDone();
    } on PostgrestException catch (e) {
      _show(e.message);
    } catch (e) {
      _show('Error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _show(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _create() => _run(() async {
        await Supabase.instance.client.rpc('create_family', params: {
          'p_name': _familyName.text.trim().isEmpty
              ? 'My Family'
              : _familyName.text.trim(),
          'p_display_name': _name.text.trim(),
        });
      });

  Future<void> _join() => _run(() async {
        await Supabase.instance.client.rpc('join_family', params: {
          'p_code': _code.text,
          'p_display_name': _name.text.trim(),
        });
      });

  @override
  void dispose() {
    _name.dispose();
    _familyName.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join your family'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _name,
                    decoration:
                        const InputDecoration(labelText: 'Your display name'),
                  ),
                  const SizedBox(height: 24),
                  const Text('Create a new family',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextField(
                    controller: _familyName,
                    decoration:
                        const InputDecoration(labelText: 'Family name'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _loading ? null : _create,
                    child: const Text('Create family'),
                  ),
                  const SizedBox(height: 24),
                  const Text('Or join with an invite code',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Invite code'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _loading ? null : _join,
                    child: const Text('Join family'),
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}