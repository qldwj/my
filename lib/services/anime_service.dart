// services/anime_service.dart
import '../models/anime.dart';
import '../services/api_client.dart';

class AnimeService {
  final ApiClient api;

  AnimeService(this.api);

  Future<List<ScheduleItem>> fetchCalendar() async {
    final json = await api.get('/anime/calendar');
    final schedule = (json['schedule'] as List<dynamic>? ?? []);
    return schedule.map((e) => ScheduleItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<RandomAnimeResult> fetchRandom() async {
    final json = await api.get('/anime/random');
    return RandomAnimeResult.fromJson(json);
  }

  Future<Map<String, dynamic>> fetchColdList({int page = 1}) async {
    final json = await api.get('/anime/cold', queryParameters: {'page': '$page'});
    final list = (json['list'] as List<dynamic>? ?? []).map((e) => ColdAnime.fromJson(e)).toList();
    return {'total': json['total'] ?? 0, 'list': list};
  }
}
