part of '../link_registry.dart';

mixin _LinkRegistryWeb on _LinkRegistryState {
  bool isWebConversation(String conversationId) =>
      _web.contains(conversationId);
  Future<({String conversationId, String code})> createWebInvitation({
    String? conversationId,
  }) => _web.createInvitation(conversationId: conversationId);
  Future<({String conversationId, String code})> joinWebInvitation(
    String code,
  ) => _web.joinInvitation(code);
  Future<void> acceptWebAnswer(String conversationId, String code) =>
      _web.acceptAnswer(conversationId, code);
  Future<void> cancelWebInvitation(String conversationId) =>
      _web.cancelInvitation(conversationId);

  @visibleForTesting
  set debugWebSessionFactory(
    WebPeerSession Function({
      void Function(String)? onState,
      void Function(Map<String, dynamic>)? onTextFrame,
      void Function(Map<String, dynamic>)? onControl,
      void Function(WebPeerTransfer)? onTransfer,
      void Function(Object)? onError,
    })
    factory,
  ) => _web.sessionFactory = factory;
}
