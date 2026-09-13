import 'dart:async';

import 'package:auravibes_app/domain/entities/agent_list_query.dart';
import 'package:auravibes_app/features/agents/agent_adapters/agent_repository.dart';
import 'package:auravibes_app/features/agents/providers/agent_repository_providers.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_list_notifier.freezed.dart';
part 'agent_list_notifier.g.dart';

@riverpod
class AgentListNotifier extends _$AgentListNotifier {
  static const _searchDelay = Duration(milliseconds: 300);

  AgentRepository? _repository;
  Timer? _searchTimer;
  var _generation = 0;
  var _disposed = false;

  AgentListState? get _current => switch (state) {
    AsyncData(:final value) => value,
    AsyncLoading() || AsyncError() => null,
  };

  AgentRepository get _requiredRepository =>
      _repository ?? (throw StateError('Agent repository is unavailable'));

  @override
  Future<AgentListState> build(String workspaceId) async {
    _repository = ref.watch(agentRepositoryProvider(workspaceId));
    final _ = ref.onDispose(() {
      _disposed = true;
      _generation++;
      _searchTimer?.cancel();
    });
    final page = await _requiredRepository.listAgents(
      .new(workspaceId: workspaceId),
    );

    return AgentListState(agents: page.agents, nextCursor: page.nextCursor);
  }

  void setSearch(String search) {
    final current = _current;
    if (current == null || current.search == search) return;
    _generation++;
    _searchTimer?.cancel();
    state = AsyncData(current.copyWith(search: search, refreshFailed: false));
    _searchTimer = .new(_searchDelay, () {
      if (!_disposed) unawaited(_replace());
    });
  }

  void setType(AgentListType? type) {
    final current = _current;
    if (current == null || current.type == type) return;
    _searchTimer?.cancel();
    _generation++;
    state = AsyncData(current.copyWith(type: type, refreshFailed: false));
    unawaited(_replace());
  }

  void setStatus(AgentListStatus? status) {
    final current = _current;
    if (current == null || current.status == status) return;
    _searchTimer?.cancel();
    _generation++;
    state = AsyncData(current.copyWith(status: status, refreshFailed: false));
    unawaited(_replace());
  }

  Future<void> refresh() {
    _searchTimer?.cancel();
    _generation++;

    return _replace();
  }

  Future<void> retry() {
    final current = _current;
    if (current?.loadMoreFailed == true) return loadMore();

    return refresh();
  }

  Future<void> loadMore() async {
    final current = _current;
    if (current == null ||
        current.nextCursor == null ||
        current.isLoadingMore ||
        current.isRefreshing) {
      return;
    }
    final generation = ++_generation;
    state = AsyncData(
      current.copyWith(isLoadingMore: true, loadMoreFailed: false),
    );
    try {
      final page = await _requiredRepository.listAgents(
        _query(current, cursor: current.nextCursor),
      );
      if (_disposed || generation != _generation) return;
      final agentsById = {for (final agent in current.agents) agent.id: agent};
      for (final agent in page.agents) {
        agentsById[agent.id] = agent;
      }
      state = AsyncData(
        current.copyWith(
          agents: agentsById.values.toList(),
          nextCursor: page.nextCursor,
          isLoadingMore: false,
          loadMoreFailed: false,
        ),
      );
    } on Object {
      if (_disposed || generation != _generation) return;
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreFailed: true),
      );
    }
  }

  Future<void> _replace() async {
    final current = _current;
    if (current == null) return;
    final generation = ++_generation;
    state = AsyncData(
      current.copyWith(
        isRefreshing: true,
        refreshFailed: false,
        loadMoreFailed: false,
      ),
    );
    try {
      final page = await _requiredRepository.listAgents(_query(current));
      if (_disposed || generation != _generation) return;
      state = AsyncData(
        current.copyWith(
          agents: page.agents,
          nextCursor: page.nextCursor,
          isRefreshing: false,
          refreshFailed: false,
        ),
      );
    } on Object {
      if (_disposed || generation != _generation) return;
      state = AsyncData(
        current.copyWith(isRefreshing: false, refreshFailed: true),
      );
    }
  }

  AgentListQuery _query(AgentListState current, {String? cursor}) => .new(
    workspaceId: workspaceId,
    search: current.search,
    type: current.type,
    status: current.status,
    cursor: cursor,
  );
}

@freezed
abstract class AgentListState with _$AgentListState {
  const factory({
    @Default([]) List<AgentListItem> agents,
    @Default('') String search,
    AgentListType? type,
    AgentListStatus? status,
    String? nextCursor,
    @Default(false) bool isRefreshing,
    @Default(false) bool isLoadingMore,
    @Default(false) bool refreshFailed,
    @Default(false) bool loadMoreFailed,
  }) = _AgentListState;
}

extension AgentListStateFilters on AgentListState {
  bool get hasFilters =>
      search.trim().isNotEmpty || type != null || status != null;
}
