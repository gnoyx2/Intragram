part of '../home_screen.dart';

// 브라우저의 스캔은 기기 코드가 아니라 초대 코드를 읽음
const _scanLabel = kIsWeb ? 'secureWeb.scanInvite' : 'home.scanDevice';

mixin _HomeScreenAppBar on ConsumerState<HomeScreen> {
  PreferredSizeWidget _appBar(ColorScheme scheme) {
    // 좁은 폰에 큰 글씨면 제목을 줄이지 않고 아이콘 액션을 메뉴로 옮김
    final compact =
        MediaQuery.sizeOf(context).width < 480 &&
        MediaQuery.textScalerOf(context).scale(20) > 28;
    return AppBar(
      titleSpacing: AppSpacing.lg,
      toolbarHeight: AppType.toolbarHeight(context),
      title: Row(
        children: [
          const BrandPigeonIcon(size: 30),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  kAppName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  S.of(context).t('home.slogan'),
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (!compact) ...[
          IconButton(
            icon: Icon(
              Icons.search,
              semanticLabel: macOSAppName(
                S.of(context).t('home.searchMessages'),
              ),
            ),
            tooltip: S.of(context).t('home.searchMessages'),
            onPressed: () => Navigator.of(context).push(SearchScreen.route()),
          ),
          IconButton(
            icon: Icon(
              Icons.add_link,
              semanticLabel: macOSAppName(
                S.of(context).t(kIsWeb ? 'secureWeb.open' : 'home.connectByIp'),
              ),
            ),
            tooltip: S
                .of(context)
                .t(kIsWeb ? 'secureWeb.open' : 'home.connectByIp'),
            onPressed: () => kIsWeb
                ? showWebConnectionDialog(context)
                : manualConnect(context, ref),
          ),
          if (canScanQr)
            IconButton(
              icon: Icon(
                Icons.qr_code_scanner,
                semanticLabel: macOSAppName(S.of(context).t(_scanLabel)),
              ),
              tooltip: S.of(context).t(_scanLabel),
              onPressed: () => scanConnect(context, ref),
            ),
          // 브라우저엔 게스트 포털이 없음: 연결은 바로 앞 버튼 하나로 엶
          if (!kIsWeb)
            IconButton(
              icon: Icon(
                Icons.qr_code_2,
                semanticLabel: macOSAppName(
                  S.of(context).t('home.guestPortal'),
                ),
              ),
              tooltip: S.of(context).t('home.guestPortal'),
              onPressed: () => PortalSheet.show(context),
            ),
        ],
        PopupMenuButton<String>(
          icon: Icon(
            Icons.more_vert,
            semanticLabel: macOSAppName(S.of(context).t('chat.more')),
          ),
          tooltip: S.of(context).t('chat.more'),
          onSelected: (value) {
            switch (value) {
              case 'search':
                Navigator.of(context).push(SearchScreen.route());
              case 'connect':
                if (kIsWeb) {
                  showWebConnectionDialog(context);
                } else {
                  manualConnect(context, ref);
                }
              case 'scan':
                scanConnect(context, ref);
              case 'portal':
                PortalSheet.show(context);
              case 'settings':
                Navigator.of(context).push(SettingsScreen.route());
              case 'wipe':
                panicWipe(context, ref);
            }
          },
          itemBuilder: (menuContext) => [
            if (compact) ...[
              PopupMenuItem(
                value: 'search',
                child: Text(S.of(context).t('home.searchMessages')),
              ),
              PopupMenuItem(
                value: 'connect',
                child: Text(
                  S
                      .of(context)
                      .t(kIsWeb ? 'secureWeb.open' : 'home.connectByIp'),
                ),
              ),
              if (canScanQr)
                PopupMenuItem(
                  value: 'scan',
                  child: Text(S.of(context).t(_scanLabel)),
                ),
              if (!kIsWeb)
                PopupMenuItem(
                  value: 'portal',
                  child: Text(S.of(context).t('home.guestPortal')),
                ),
            ],
            PopupMenuItem(
              value: 'settings',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.settings_outlined),
                title: Text(S.of(context).t('home.settings')),
              ),
            ),
            PopupMenuItem(
              value: 'wipe',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_forever, color: scheme.error),
                title: Text(
                  S.of(context).t('home.panicWipe'),
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
