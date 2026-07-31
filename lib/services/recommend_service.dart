// services/recommend_service.dart
import '../models/anime.dart';
import '../services/api_client.dart';

class RecommendService {
  final ApiClient api;

  RecommendService(this.api);

  Future<List<RecommendationItem>> fetchSimilarRecommendations() async {
    final json = await api.get('/recommend/similar');
    final recs = (json['recommendations'] as List<dynamic>? ?? []).map((e) => RecommendationItem.fromJson(e)).toList();
    return recs;
  }
}
