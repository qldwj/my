// services/marker_service.dart
import '../models/marker.dart';
import '../services/api_client.dart';

class MarkerService {
  final ApiClient api;

  MarkerService(this.api);

  Future<List<Marker>> getMarkersForEpisode(int episodeId) async {
    final json = await api.get('/markers/$episodeId');
    final arr = (json as List<dynamic>);
    return arr.map((e) => Marker.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Marker> createMarker(int episodeId, Marker marker) async {
    final json = await api.post('/markers', {
      'episode_id': episodeId,
      'position': marker.position,
      'text': marker.text,
    });
    return Marker.fromJson(json);
  }

  Future<void> deleteMarker(int id) async {
    await api.delete('/markers/$id');
  }
}
