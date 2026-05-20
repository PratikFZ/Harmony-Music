import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../Search/components/desktop_search_bar.dart';
import '/ui/screens/Search/search_screen_controller.dart';
import '/ui/widgets/animated_screen_transition.dart';
import '../Library/library_combined.dart';
import '../../widgets/side_nav_bar.dart';
import '../Library/library.dart';
import '../Search/search_screen.dart';
import '../Settings/settings_screen_controller.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/create_playlist_dialog.dart';
import '../../navigator.dart';
import '../../widgets/content_list_widget.dart';
import '../../widgets/quickpickswidget.dart';
import '../../widgets/shimmer_widgets/home_shimmer.dart';
import 'home_screen_controller.dart';
import '../Settings/settings_screen.dart';
import '../JamSession/jam_session_controller.dart';
import '../JamSession/jam_session_host_screen.dart';
import '../JamSession/jam_session_join_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    final HomeScreenController homeScreenController =
        Get.find<HomeScreenController>();
    final SettingsScreenController settingsScreenController =
        Get.find<SettingsScreenController>();

    return Scaffold(
        floatingActionButton: Obx(
          () => ((homeScreenController.tabIndex.value == 0 &&
                          !GetPlatform.isDesktop) ||
                      homeScreenController.tabIndex.value == 2) &&
                  settingsScreenController.isBottomNavBarEnabled.isFalse
              ? Obx(
                  () => Padding(
                    padding: EdgeInsets.only(
                        bottom: playerController.playerPanelMinHeight.value >
                                Get.mediaQuery.padding.bottom
                            ? playerController.playerPanelMinHeight.value -
                                Get.mediaQuery.padding.bottom
                            : playerController.playerPanelMinHeight.value),
                    child: homeScreenController.tabIndex.value == 0
                        // Home tab: Jam FAB stacked above Search FAB
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: 50,
                                width: 50,
                                child: FittedBox(
                                  child: FloatingActionButton.small(
                                    heroTag: 'jam_fab',
                                    focusElevation: 0,
                                    elevation: 0,
                                    shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.all(
                                            Radius.circular(12))),
                                    onPressed: () => _showJamSheet(context),
                                    child: const Icon(Icons.people),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 60,
                                width: 60,
                                child: FittedBox(
                                  child: FloatingActionButton(
                                    heroTag: 'search_fab',
                                    focusElevation: 0,
                                    elevation: 0,
                                    shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.all(
                                            Radius.circular(14))),
                                    onPressed: () => Get.toNamed(
                                        ScreenNavigationSetup.searchScreen,
                                        id: ScreenNavigationSetup.id),
                                    child: const Icon(Icons.search),
                                  ),
                                ),
                              ),
                            ],
                          )
                        // Library tab: just the add-playlist FAB
                        : SizedBox(
                            height: 60,
                            width: 60,
                            child: FittedBox(
                              child: FloatingActionButton(
                                  heroTag: 'add_fab',
                                  focusElevation: 0,
                                  shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(
                                          Radius.circular(14))),
                                  elevation: 0,
                                  onPressed: () => showDialog(
                                      context: context,
                                      builder: (context) =>
                                          const CreateNRenamePlaylistPopup()),
                                  child: const Icon(Icons.add)),
                            ),
                          ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        body: Obx(
          () => Row(
            children: <Widget>[
              // create a navigation rail
              settingsScreenController.isBottomNavBarEnabled.isFalse
                  ? const SideNavBar()
                  : const SizedBox(
                      width: 0,
                    ),
              //const VerticalDivider(thickness: 1, width: 2),
              Expanded(
                child: Obx(() => AnimatedScreenTransition(
                    enabled: settingsScreenController
                        .isTransitionAnimationDisabled.isFalse,
                    resverse: homeScreenController.reverseAnimationtransiton,
                    horizontalTransition:
                        settingsScreenController.isBottomNavBarEnabled.isTrue,
                    child: Center(
                      key: ValueKey<int>(homeScreenController.tabIndex.value),
                      child: const Body(),
                    ))),
              ),
            ],
          ),
        ));
  }
}

void _showJamSheet(BuildContext context) {
  final ctrl = Get.isRegistered<JamSessionController>()
      ? Get.find<JamSessionController>()
      : null;
  final hasActive = ctrl != null &&
      (ctrl.state.value == JamState.connected ||
          ctrl.state.value == JamState.waitingForPeer);

  Get.bottomSheet(
    Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Jam Session', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            hasActive
                ? (ctrl.role.value == JamRole.host
                    ? 'You are hosting a Jam.'
                    : 'You are joined to a Jam.')
                : 'Listen in sync over your Wi-Fi or Tailscale.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          if (hasActive) ...[
            ListTile(
              leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: const Icon(Icons.open_in_full, color: Colors.white)),
              title: Text(ctrl.role.value == JamRole.host
                  ? 'Open host screen'
                  : 'Open jam screen'),
              subtitle: const Text('See QR / status'),
              onTap: () {
                Get.back();
                Get.to(() => ctrl.role.value == JamRole.host
                    ? const JamSessionHostScreen()
                    : const JamSessionJoinScreen());
              },
            ),
            ListTile(
              leading:
                  const CircleAvatar(child: Icon(Icons.stop_circle_outlined)),
              title: Text(ctrl.role.value == JamRole.host
                  ? 'End session'
                  : 'Leave session'),
              subtitle: const Text('Stop syncing'),
              onTap: () {
                Get.back();
                ctrl.endSession();
              },
            ),
          ] else ...[
            ListTile(
              leading:
                  const CircleAvatar(child: Icon(Icons.broadcast_on_personal)),
              title: const Text('Start a session'),
              subtitle: const Text('Share a QR with friends'),
              onTap: () {
                Get.back();
                Get.to(() => const JamSessionHostScreen());
              },
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.qr_code_scanner)),
              title: const Text('Join a session'),
              subtitle: const Text("Scan the host's QR code"),
              onTap: () {
                Get.back();
                Get.to(() => const JamSessionJoinScreen());
              },
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class Body extends StatelessWidget {
  const Body({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final homeScreenController = Get.find<HomeScreenController>();
    final settingsScreenController = Get.find<SettingsScreenController>();
    final size = MediaQuery.of(context).size;
    final topPadding = GetPlatform.isDesktop
        ? 85.0
        : context.isLandscape
            ? 50.0
            : size.height < 750
                ? 80.0
                : 85.0;
    final leftPadding =
        settingsScreenController.isBottomNavBarEnabled.isTrue ? 20.0 : 5.0;
    if (homeScreenController.tabIndex.value == 0) {
      return Padding(
        padding: EdgeInsets.only(left: leftPadding),
        child: Stack(
          children: [
            GestureDetector(
              onTap: () {
                // for Desktop search bar
                if (GetPlatform.isDesktop) {
                  final sscontroller = Get.find<SearchScreenController>();
                  if (sscontroller.focusNode.hasFocus) {
                    sscontroller.focusNode.unfocus();
                  }
                }
              },
              child: Obx(
                () => homeScreenController.networkError.isTrue
                    ? SizedBox(
                        height: MediaQuery.of(context).size.height - 180,
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                "home".tr,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        "networkError1".tr,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(
                                        height: 10,
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 15, vertical: 10),
                                        decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .textTheme
                                                .titleLarge!
                                                .color,
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: InkWell(
                                          onTap: () {
                                            homeScreenController
                                                .loadContentFromNetwork();
                                          },
                                          child: Text(
                                            "retry".tr,
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .canvasColor),
                                          ),
                                        ),
                                      ),
                                    ]),
                              ),
                            )
                          ],
                        ),
                      )
                    : Obx(() {
                        // dispose all detachached scroll controllers
                        homeScreenController.disposeDetachedScrollControllers();
                        final items = homeScreenController
                                .isContentFetched.value
                            ? [
                                Obx(() {
                                  final scrollController = ScrollController();
                                  homeScreenController.contentScrollControllers
                                      .add(scrollController);
                                  return QuickPicksWidget(
                                      content:
                                          homeScreenController.quickPicks.value,
                                      scrollController: scrollController);
                                }),
                                ...getWidgetList(
                                    homeScreenController.middleContent,
                                    homeScreenController),
                                ...getWidgetList(
                                    homeScreenController.fixedContent,
                                    homeScreenController)
                              ]
                            : [const HomeShimmer()];
                        return ListView.builder(
                          padding:
                              EdgeInsets.only(bottom: 200, top: topPadding),
                          itemCount: items.length,
                          itemBuilder: (context, index) => items[index],
                        );
                      }),
              ),
            ),
            if (GetPlatform.isDesktop)
              Align(
                alignment: Alignment.topCenter,
                child: LayoutBuilder(builder: (context, constraints) {
                  return SizedBox(
                    width: constraints.maxWidth > 800
                        ? 800
                        : constraints.maxWidth - 40,
                    child: const Padding(
                        padding: EdgeInsets.only(top: 15.0),
                        child: DesktopSearchBar()),
                  );
                }),
              )
          ],
        ),
      );
    } else if (homeScreenController.tabIndex.value == 1) {
      return settingsScreenController.isBottomNavBarEnabled.isTrue
          ? const SearchScreen()
          : const SongsLibraryWidget();
    } else if (homeScreenController.tabIndex.value == 2) {
      return settingsScreenController.isBottomNavBarEnabled.isTrue
          ? const CombinedLibrary()
          : const PlaylistNAlbumLibraryWidget(isAlbumContent: false);
    } else if (homeScreenController.tabIndex.value == 3) {
      return settingsScreenController.isBottomNavBarEnabled.isTrue
          ? const SettingsScreen(isBottomNavActive: true)
          : const PlaylistNAlbumLibraryWidget();
    } else if (homeScreenController.tabIndex.value == 4) {
      return const LibraryArtistWidget();
    } else if (homeScreenController.tabIndex.value == 5) {
      return const SettingsScreen();
    } else {
      return Center(
        child: Text("${homeScreenController.tabIndex.value}"),
      );
    }
  }

  List<Widget> getWidgetList(
      dynamic list, HomeScreenController homeScreenController) {
    return list
        .map((content) {
          final scrollController = ScrollController();
          homeScreenController.contentScrollControllers.add(scrollController);
          return ContentListWidget(
              content: content, scrollController: scrollController);
        })
        .whereType<Widget>()
        .toList();
  }
}
