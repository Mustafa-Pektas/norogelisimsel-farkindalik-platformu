import 'package:shared_preferences/shared_preferences.dart';

import '../models/scenario_workspace_draft.dart';

/// Tek çalışma alanının yerel metin taslağı; model/video/analiz kaydı değildir.
class ScenarioDraftStore {
  const ScenarioDraftStore({this.preferences = SharedPreferences.getInstance});
  static const storageKey = 'scenario_workspace_draft_v1';
  final Future<SharedPreferences> Function() preferences;

  Future<ScenarioWorkspaceDraft?> load() async {
    final prefs = await preferences();
    // Başarısız bir yazmanın yalnız bellek önbelleğine girmiş değerini yükleme.
    await prefs.reload();
    final raw = prefs.getString(storageKey);
    return raw == null ? null : ScenarioWorkspaceDraft.fromJsonString(raw);
  }

  Future<void> save(ScenarioWorkspaceDraft draft) async {
    final prefs = await preferences();
    if (!await prefs.setString(storageKey, draft.toJsonString())) {
      throw StateError('Taslak kaydedilemedi.');
    }
  }

  Future<void> delete() async {
    final prefs = await preferences();
    if (!await prefs.remove(storageKey)) throw StateError('Taslak silinemedi.');
  }
}
