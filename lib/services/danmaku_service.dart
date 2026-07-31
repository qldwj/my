// services/danmaku_service.dart
import '../models/hotwords.dart';
import '../services/api_client.dart';

class DanmakuService {
  final ApiClient api;

  DanmakuService(this.api);

  Future<HotwordsResponse> fetchHotwords(int episodeId) async {
    final json = await api.get('/danmaku/hotwords/$episodeId');
    return HotwordsResponse.fromJson(json);
  }
}
