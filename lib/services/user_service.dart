// services/user_service.dart
import '../models/user_progress.dart';
import '../models/personality.dart';
import '../services/api_client.dart';

class UserService {
  final ApiClient api;

  UserService(this.api);

  Future<UserProgress> fetchProgress() async {
    final json = await api.get('/user/progress');
    return UserProgress.fromJson(json);
  }

  Future<PersonalityTag> fetchPersonality() async {
    final json = await api.get('/user/personality');
    return PersonalityTag.fromJson(json);
  }
}
