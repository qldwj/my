import 'dart:async';

import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_interest.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/info/rating_review_dialog.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:kazumi/request/apis/custom_comment_api.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/modules/characters/character_item.dart';
import 'package:kazumi/modules/staff/staff_item.dart';

part 'info_controller.g.dart';

class InfoController = _InfoController with _$InfoController;

abstract class _InfoController with Store {
  _InfoController(this.collectController);

  final CollectController collectController;
  late BangumiItem bangumiItem;

  @observable
  bool isLoading = false;

  @observable
  var pluginSearchResponseList = ObservableList<PluginSearchResponse>();

  @observable
  var pluginSearchStatus = ObservableMap<String, PluginSearchStatus>();

  @observable
  var commentsList = ObservableList<CommentItem>();

  @observable
  var characterList = ObservableList<CharacterItem>();

  @observable
  var staffList = ObservableList<StaffFullItem>();

  bool _isFillingInterestUserProfile = false;

  int _commentsOffset = 0;

  void clearComments() {
    commentsList.clear();
    _commentsOffset = 0;
  }

  Future<bool> fillInterestUserProfileIfNeeded() async {
    final interest = bangumiItem.interest;
    if (interest == null || interest.hasUserProfile) {
      return false;
    }
    if (_isFillingInterestUserProfile) {
      return false;
    }
    _isFillingInterestUserProfile = true;
    try {
      final user = await BangumiApi.getCurrentUser();
      if (user == null) {
        return false;
      }
      bangumiItem.interest = interest.copyWithUser(user: user);
      await collectController.updateLocalCollect(bangumiItem);
      return true;
    } catch (e) {
      KazumiLogger()
          .e('InfoController: failed to fill interest user profile', error: e);
      return false;
    } finally {
      _isFillingInterestUserProfile = false;
    }
  }

  void _removeCurrentUserFromPublicComments() {
    final interest = bangumiItem.interest;
    if (interest == null) return;
    final userId = interest.user?.id;
    if (userId == null) return;
    commentsList.removeWhere((item) => item.user.id == userId);
  }

  Future<void> queryBangumiInfoByID(int id, {String type = "init"}) async {
    isLoading = true;
    try {
      await _updateBangumiInfoByID(id, type: type);
    } finally {
      isLoading = false;
    }
  }

  Future<void> refreshBangumiInfoByID(int id) async {
    await _updateBangumiInfoByID(id, type: "update");
  }

  Future<void> _updateBangumiInfoByID(int id, {required String type}) async {
    final value = await BangumiApi.getBangumiInfoByID(id);
    if (value == null) {
      return;
    }
    if (type == "init") {
      bangumiItem = value;
    } else {
      bangumiItem.summary = value.summary;
      bangumiItem.tags = value.tags;
      bangumiItem.rank = value.rank;
      bangumiItem.airDate = value.airDate;
      bangumiItem.airWeekday = value.airWeekday;
      bangumiItem.alias = value.alias;
      bangumiItem.ratingScore = value.ratingScore;
      bangumiItem.votes = value.votes;
      bangumiItem.votesCount = value.votesCount;
      final incomingInterest = value.interest;
      final previousInterest = bangumiItem.interest;
      if (incomingInterest == null) {
        bangumiItem.interest = null;
      } else if (previousInterest == null || !previousInterest.hasUserProfile) {
        bangumiItem.interest = incomingInterest;
      } else {
        bangumiItem.interest =
            incomingInterest.copyWithUser(user: previousInterest.user);
      }
    }
    await collectController.updateLocalCollect(bangumiItem);
  }

  Future<void> queryBangumiCommentsByID(int id, {bool refresh = true}) async {
    await _updateBangumiCommentsByID(
      id,
      refresh: refresh,
      clearBeforeFetch: true,
    );
  }

  Future<void> _updateBangumiCommentsByID(
    int id, {
    required bool refresh,
    required bool clearBeforeFetch,
  }) async {
    if (refresh) {
      if (clearBeforeFetch) {
        clearComments();
      }
    }
    final offset = refresh ? 0 : _commentsOffset;
    await BangumiApi.getBangumiCommentsByID(id, offset: offset).then((value) async {
      if (refresh && !clearBeforeFetch) {
        commentsList = ObservableList<CommentItem>.of(value.commentList);
      } else {
        commentsList.addAll(value.commentList);
      }
      _commentsOffset = refresh
          ? value.commentList.length
          : _commentsOffset + value.commentList.length;
      _removeCurrentUserFromPublicComments();
      // ⭐ 自建评论：我的服务器评论优先显示（排在 Bangumi 评论前面）
      await _mergeCustomComments(id);
    });
    KazumiLogger().i(
        'InfoController: loaded comments list length ${commentsList.length}, offset $_commentsOffset');
  }

  /// 自建评论头像 URL：在自有服务器上，直连加载（不走代理）；
  /// 空则用默认 logo。Bangumi 评论头像的代理逻辑在别处保持不变。
  String _avatarUrl(String avatar) {
    return avatar.isNotEmpty ? avatar : 'https://qlyyz.xyz/logo.webp';
  }

  /// ⭐ 拉取自建评论（我的服务器）并合并到列表最前（优先显示）
  Future<void> _mergeCustomComments(int subjectId) async {
    try {
      // 🔧 先移除已存在的 server 评论，避免加载更多/重复刷新时累积重复
      commentsList.removeWhere((c) => c.source == 'server');
      final res = await CustomCommentApi.fetch(subjectId: subjectId);
      final custom = res.items;
      if (custom.isEmpty) return;
      // 🔧 按内容去重（数据库可能存在历史重复提交），置顶优先、其次保留最新
      final deduped = <CustomCommentItem>[];
      final seen = <String>{};
      final sorted = List<CustomCommentItem>.from(custom)
        ..sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          return b.createdAt.compareTo(a.createdAt);
        });
      for (final c in sorted) {
        final key = '${c.uid}|${c.text}';
        if (seen.contains(key)) continue;
        seen.add(key);
        deduped.add(c);
      }
      final adminNick = res.adminNickname;
      final items = deduped.map((c) => CommentItem(
            user: User(
              id: -c.id,
              username: 'server',
              // 置顶评论且无发送者时显示管理员昵称
              nickname: c.sender.isNotEmpty
                  ? c.sender
                  : (c.pinned && adminNick.isNotEmpty ? adminNick : '樱花用户'),
              // 🆕 使用评论者自己的头像（未上传则用默认 logo）
              avatar: UserAvatar(
                small: _avatarUrl(c.avatar),
                medium: _avatarUrl(c.avatar),
                large: _avatarUrl(c.avatar),
              ),
              sign: '',
              joinedAt: c.createdAt,
            ),
            comment: Comment(
              rate: c.rating.clamp(0, 10),
              comment: c.text,
              updatedAt: c.createdAt,
            ),
            source: 'server',
            pinned: c.pinned,
            uid: c.uid,
            votes: c.votes,
            parentId: c.parentId > 0 ? -c.parentId : 0,
          )).toList();
      commentsList.insertAll(0, items);
      KazumiLogger().i('InfoController: 合并自建评论 ${items.length} 条');
    } catch (e) {
      KazumiLogger().w('InfoController: 自建评论拉取失败', error: e);
    }
  }

  /// ⭐ 发表评论到樱花服务器（rating 0-10，0=不评分），成功后刷新评论列表
  /// 自动携带登录用户资料（uid/昵称/头像）用于评论显示
  Future<String?> addCustomComment(String text, {int rating = 0}) async {
    final id = bangumiItem.id;
    // 登录用户资料（未登录则匿名，匿名用户仍用默认昵称）
    SocialService.restoreLocalProfile();
    final profile = SocialService.myProfile;
    final error = await CustomCommentApi.add(
      subjectId: id,
      text: text,
      sender: profile?.nickname ?? '樱花用户',
      rating: rating,
      uid: profile?.uid ?? '',
      avatar: profile?.avatar ?? '',
    );
    if (error == null) {
      // 重新加载评论（我的服务器评论优先显示）
      unawaited(queryBangumiCommentsByID(id));
    }
    return error;
  }

  Future<void> refreshBangumiCommentsSilently(int id) async {
    if (commentsList.isEmpty) {
      return;
    }
    await _updateBangumiCommentsByID(
      id,
      refresh: true,
      clearBeforeFetch: false,
    );
  }

  Future<void> queryBangumiCharactersByID(int id) async {
    characterList.clear();
    await BangumiApi.getCharatersByBangumiID(id).then((value) {
      characterList.addAll(value.charactersList);
    });
    Map<String, int> relationValue = {
      '主角': 1,
      '配角': 2,
      '客串': 3,
    };

    try {
      characterList.sort((a, b) {
        int valueA = relationValue[a.relation] ?? 4;
        int valueB = relationValue[b.relation] ?? 4;
        return valueA.compareTo(valueB);
      });
    } catch (e) {
      KazumiDialog.showToast(message: '$e');
    }
    KazumiLogger().i(
        'InfoController: loaded character list length ${characterList.length}');
  }

  Future<void> queryBangumiStaffsByID(int id) async {
    staffList.clear();
    await BangumiApi.getBangumiStaffByID(id).then((value) {
      staffList.addAll(value.data);
    });
    KazumiLogger()
        .i('InfoController: loaded staff list length ${staffList.length}');
  }

  Future<bool> rateBangumi(RatingReviewResult data,
      {required int localType}) async {
    final trimmedComment = data.comment.trim();
    if (await BangumiApi.addOrUpdateBangumiEvaluationBySubjectID(
      bangumiItem.id,
      localType,
      comment: trimmedComment.isNotEmpty ? trimmedComment : null,
      rate: data.score > 0 ? data.score : 0,
      tags: data.tags.isNotEmpty ? data.tags : null,
    )) {
      bangumiItem.interest = BangumiInterest.mergeLocalSubmission(
        previous: bangumiItem.interest,
        rate: data.score,
        comment: trimmedComment,
        tags: data.tags,
      );
      await collectController.updateLocalCollect(bangumiItem);
      await fillInterestUserProfileIfNeeded();
      _removeCurrentUserFromPublicComments();
      await refreshBangumiCommentsSilently(bangumiItem.id);
      await refreshBangumiInfoByID(bangumiItem.id);
      return true;
    }
    return false;
  }
}
