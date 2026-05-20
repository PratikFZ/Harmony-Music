import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ionicons/ionicons.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '/ui/player/components/animated_play_button.dart';
import '/ui/screens/JamSession/jam_session_controller.dart';
import '/ui/screens/JamSession/jam_session_host_screen.dart';
import '/ui/screens/JamSession/jam_session_join_screen.dart';
import '../player_controller.dart';

class PlayerControlWidget extends StatelessWidget {
  const PlayerControlWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: ShaderMask(
                  shaderCallback: (rect) {
                    return const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.transparent
                      ],
                    ).createShader(
                        Rect.fromLTWH(0, 0, rect.width, rect.height));
                  },
                  blendMode: BlendMode.dstIn,
                  child: Obx(() {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Marquee(
                          delay: const Duration(milliseconds: 300),
                          duration: const Duration(seconds: 10),
                          id: "${playerController.currentSong.value}_title",
                          child: Text(
                            playerController.currentSong.value != null
                                ? playerController.currentSong.value!.title
                                : "NA",
                            textAlign: TextAlign.start,
                            style: Theme.of(context).textTheme.labelMedium!,
                          ),
                        ),
                        const SizedBox(
                          height: 5,
                        ),
                        Marquee(
                          delay: const Duration(milliseconds: 300),
                          duration: const Duration(seconds: 10),
                          id: "${playerController.currentSong.value}_subtitle",
                          child: Text(
                            playerController.currentSong.value != null
                                ? playerController.currentSong.value!.artist!
                                : "NA",
                            textAlign: TextAlign.start,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        )
                      ],
                    );
                  }),
                ),
              ),
              SizedBox(
                width: 45,
                child: IconButton(
                    onPressed: playerController.toggleFavourite,
                    icon: Obx(() => Icon(
                          playerController.isCurrentSongFav.isFalse
                              ? Icons.favorite_border
                              : Icons.favorite,
                          color: Theme.of(context).textTheme.titleMedium!.color,
                        ))),
              ),
              SizedBox(
                width: 45,
                child: _jamButton(context),
              ),
            ],
          ),
          const SizedBox(
            height: 20,
          ),
          GetX<PlayerController>(builder: (controller) {
            return ProgressBar(
              thumbRadius: 7,
              barHeight: 4.5,
              baseBarColor: Theme.of(context).sliderTheme.inactiveTrackColor,
              bufferedBarColor:
                  Theme.of(context).sliderTheme.valueIndicatorColor,
              progressBarColor: Theme.of(context).sliderTheme.activeTrackColor,
              thumbColor: Theme.of(context).sliderTheme.thumbColor,
              timeLabelTextStyle: Theme.of(context)
                  .textTheme
                  .titleMedium!
                  .copyWith(fontSize: 14),
              progress: controller.progressBarStatus.value.current,
              total: controller.progressBarStatus.value.total,
              buffered: controller.progressBarStatus.value.buffered,
              onSeek: controller.seek,
            );
          }),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                  onPressed: playerController.toggleShuffleMode,
                  icon: Obx(() => Icon(
                        Ionicons.shuffle,
                        color: playerController.isShuffleModeEnabled.value
                            ? Theme.of(context).textTheme.titleLarge!.color
                            : Theme.of(context)
                                .textTheme
                                .titleLarge!
                                .color!
                                .withOpacity(0.2),
                      ))),
              _previousButton(playerController, context),
              const CircleAvatar(
                  radius: 35,
                  child: AnimatedPlayButton(
                    key: Key("playButton"),
                  )),
              _nextButton(playerController, context),
              Obx(() {
                return IconButton(
                    onPressed: playerController.toggleLoopMode,
                    icon: Icon(
                      Icons.all_inclusive,
                      color: playerController.isLoopModeEnabled.value
                          ? Theme.of(context).textTheme.titleLarge!.color
                          : Theme.of(context)
                              .textTheme
                              .titleLarge!
                              .color!
                              .withOpacity(0.2),
                    ));
              }),
            ],
          ),
        ]);
  }

  Widget _jamButton(BuildContext context) {
    // Only wrap in Obx when the controller exists — otherwise Obx has no
    // reactive value to track and throws "improper use of GetX detected".
    if (!Get.isRegistered<JamSessionController>()) {
      return IconButton(
        icon: Icon(
          Icons.people,
          color: Theme.of(context).textTheme.titleMedium!.color,
        ),
        tooltip: 'Jam Session',
        onPressed: () => _showJamSheet(context),
      );
    }
    final ctrl = Get.find<JamSessionController>();
    return Obx(() {
      final state = ctrl.state.value;
      final isActive =
          state == JamState.connected || state == JamState.waitingForPeer;
      return IconButton(
        icon: Icon(
          Icons.people,
          color: isActive
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).textTheme.titleMedium!.color,
        ),
        tooltip: isActive ? 'Jam Session (active)' : 'Jam Session',
        onPressed: () => _showJamSheet(context),
      );
    });
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
            const SizedBox(height: 24),
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
                leading: const CircleAvatar(
                    child: Icon(Icons.broadcast_on_personal)),
                title: const Text('Start a session'),
                subtitle: const Text('Share a QR code with friends'),
                onTap: () {
                  Get.back();
                  Get.to(() => const JamSessionHostScreen());
                },
              ),
              ListTile(
                leading:
                    const CircleAvatar(child: Icon(Icons.qr_code_scanner)),
                title: const Text('Join a session'),
                subtitle: const Text('Scan the host\'s QR code'),
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

  Widget _previousButton(
      PlayerController playerController, BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.skip_previous,
        color: Theme.of(context).textTheme.titleMedium!.color,
      ),
      iconSize: 30,
      onPressed: playerController.prev,
    );
  }
}

Widget _nextButton(PlayerController playerController, BuildContext context) {
  return Obx(() {
    final isLastSong = playerController.currentQueue.isEmpty ||
        (!(playerController.isShuffleModeEnabled.isTrue ||
                playerController.isQueueLoopModeEnabled.isTrue) &&
            (playerController.currentQueue.last.id ==
                playerController.currentSong.value?.id));
    return IconButton(
        icon: Icon(
          Icons.skip_next,
          color: isLastSong
              ? Theme.of(context).textTheme.titleLarge!.color!.withOpacity(0.2)
              : Theme.of(context).textTheme.titleMedium!.color,
        ),
        iconSize: 30,
        onPressed: isLastSong ? null : playerController.next);
  });
}
