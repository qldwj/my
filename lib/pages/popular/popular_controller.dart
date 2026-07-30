import 'dart:math';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/nsfw_filter.dart';
import 'package:mobx/mobx.dart';
import 'package:dio/dio.dart';
import 'package:kazumi/models/top_item.dart';

part 'popular_controller.g.dart';

class PopularController = _PopularController with _$PopularController;

abstract class _PopularController with Store {
  static const int _trendPageSize = 24;

  int _trendOffset = 0;

  @observable
  String currentTag = '';

  @observable
  ObservableList<BangumiItem> bangumiList = ObservableList.of([]);

  @observable
  ObservableList<BangumiItem> trendList = ObservableList.of([]);

  double scrollOffset = 0.0;

  @observable
  bool isLoadingMore = false;

  @observable
  bool isTimeOut = false;

  // ===== 热门推荐相关 =====
  @observable
  ObservableList<TopItem> topList = ObservableList.of([]);

  @observable
  bool isLoadingTop = false;

  @observable
  bool isTopLoadingMore = false;

  int _topCurrentPage = 1;
  bool _hasMoreTop = true;

  bool get _bangumiMirrorEnabled =>
      GStorage.getSetting(SettingsKeys.enableBangumiProxy);

  void setCurrentTag(String s) {
    currentTag = s;
  }

  void clearBangumiList() {
    bangumiList.clear();
  }

  @action
  Future<void> queryBangumiByTrend({String type = 'add'}) async {
    if (type == 'init') {
      trendList.clear();
      _trendOffset = 0;
    }
    isLoadingMore = true;
    final result = _bangumiMirrorEnabled
        ? await BangumiApi.getBangumiMirrorPopularSubjects(
            limit: _trendPageSize,
            offset: _trendOffset,
          )
        : await BangumiApi.getBangumiTrendsList(
            limit: _trendPageSize,
            offset: _trendOffset,
          );
    if (result.isNotEmpty) {
      _trendOffset += _trendPageSize;
    }
    final existingIds = trendList.map((item) => item.id).toSet();
    final filtered = NsfwFilter.filter(result);
    trendList.addAll(filtered.where((item) => existingIds.add(item.id)));
    isLoadingMore = false;
    isTimeOut = trendList.isEmpty;
  }

  @action
  Future<void> queryBangumiByTag({String type = 'add'}) async {
    if (type == 'init') {
      bangumiList.clear();
    }
    isLoadingMore = true;
    var tag = currentTag;
    var result = _bangumiMirrorEnabled
        ? await BangumiApi.getBangumiMirrorPopularSubjects(
            tag: tag,
            offset: bangumiList.length,
          )
        : await BangumiApi.getBangumiList(
            rank: Random().nextInt(8000) + 1,
            tag: tag,
          );
    bangumiList.addAll(NsfwFilter.filter(result));
    isLoadingMore = false;
    isTimeOut = bangumiList.isEmpty;
  }

  // ===== 获取热门推荐 =====
  @action
  Future<void> queryTopItems() async {
    if (isLoadingTop) return;
    isLoadingTop = true;
    _topCurrentPage = 1;
    _hasMoreTop = true;

    try {
      final response = await Dio().get(
        'https://qlyyz.xyz/api/top',
        queryParameters: {'page': _topCurrentPage},
      );

      print('热门推荐返回: ${response.data}');

      if (response.data != null && 
          response.data['collect'] != null && 
          response.data['collect'] is List) {
        
        final List<dynamic> data = response.data['collect'];
        if (data.isNotEmpty) {
          final List<TopItem> items = data.map((e) => TopItem.fromJson(e)).toList();
          topList.clear();
          topList.addAll(items);
          print('成功加载 ${items.length} 条热门推荐');
        } else {
          topList.clear();
          print('热门推荐数据为空');
        }

        if (data.length < 20) {
          _hasMoreTop = false;
        }
      } else {
        topList.clear();
        _hasMoreTop = false;
        print('热门推荐数据格式错误');
      }
    } catch (e) {
      print('获取热门推荐失败: $e');
      topList.clear();
      _hasMoreTop = false;
    } finally {
      isLoadingTop = false;
    }
  }

  // ===== 加载更多热门推荐 =====
  @action
  Future<void> loadMoreTopItems() async {
    if (isTopLoadingMore || !_hasMoreTop) return;
    isTopLoadingMore = true;
    _topCurrentPage++;

    try {
      final response = await Dio().get(
        'https://qlyyz.xyz/api/top',
        queryParameters: {'page': _topCurrentPage},
      );

      if (response.data != null && 
          response.data['collect'] != null && 
          response.data['collect'] is List) {
        
        final List<dynamic> data = response.data['collect'];
        if (data.isNotEmpty) {
          final List<TopItem> items = data.map((e) => TopItem.fromJson(e)).toList();
          topList.addAll(items);
          print('成功加载更多 ${items.length} 条热门推荐');
          
          if (items.length < 20) {
            _hasMoreTop = false;
          }
        } else {
          _hasMoreTop = false;
        }
      } else {
        _hasMoreTop = false;
      }
    } catch (e) {
      print('加载更多热门推荐失败: $e');
      _hasMoreTop = false;
    } finally {
      isTopLoadingMore = false;
    }
  }
}