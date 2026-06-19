import { describe, it, expect } from '@ohos/hypium';
import { createEmptyUiTextValue } from '../main/ets/models/ui/UiTextValue';
import { TdChatMessageItem } from '../main/ets/services/td/TdPayloadTypes';
import { createIdleMediaViewerPlaybackSnapshot } from '../main/ets/services/media/MediaViewerPlaybackController';
import { MediaViewerContentSize } from '../main/ets/models/media/MediaViewerContentTypes';
import {
  calculateMediaViewerImageViewportSizeForScale,
  clampMediaViewerImageTransform
} from '../main/ets/services/media/MediaViewerImageTransformController';
import { MediaViewerPageViewModel } from '../main/ets/viewmodel/MediaViewerPageViewModel';

function buildMessage(overrides?: Partial<TdChatMessageItem>): TdChatMessageItem {
  return {
    id: overrides?.id ?? '1',
    chatId: overrides?.chatId ?? '55',
    senderUserId: overrides?.senderUserId ?? '77',
    senderChatId: overrides?.senderChatId,
    senderAvatarPath: overrides?.senderAvatarPath,
    sendingState: overrides?.sendingState,
    deliveryState: overrides?.deliveryState,
    kind: overrides?.kind ?? 'text',
    text: overrides?.text ?? 'hello',
    textValue: overrides?.textValue ?? createEmptyUiTextValue(),
    caption: overrides?.caption,
    mediaFileId: overrides?.mediaFileId,
    mediaThumbFileId: overrides?.mediaThumbFileId,
    mediaMinithumbnailData: overrides?.mediaMinithumbnailData,
    mediaLocalPath: overrides?.mediaLocalPath,
    mediaThumbPath: overrides?.mediaThumbPath,
    mediaWidth: overrides?.mediaWidth,
    mediaHeight: overrides?.mediaHeight,
    mediaMimeType: overrides?.mediaMimeType,
    mediaIsAnimated: overrides?.mediaIsAnimated,
    mediaDurationSec: overrides?.mediaDurationSec,
    voiceNoteWaveform: overrides?.voiceNoteWaveform,
    voiceNoteIsListened: overrides?.voiceNoteIsListened,
    isOutgoing: overrides?.isOutgoing ?? false,
    date: overrides?.date ?? 1710000000
  };
}

export default function mediaViewerPageViewModelTest() {
  describe('MediaViewerPageViewModelTest', () => {
    it('shouldCreateMediaViewerRouteParamsForVideoNote', 0, () => {
      const viewModel = new MediaViewerPageViewModel();
      const params = viewModel.createMediaViewerRouteParams(
        '55',
        'OSTC Team',
        'ostc',
        buildMessage({
          id: '900',
          kind: 'videoNote',
          mediaFileId: 901,
          mediaThumbFileId: 902,
          mediaMinithumbnailData: 'bWluaQ==',
          mediaLocalPath: '/tmp/video-note.mp4',
          mediaThumbPath: '/tmp/video-note-thumb.jpg',
          mediaMimeType: 'video/mp4',
          mediaIsAnimated: false,
          mediaDurationSec: 9,
          mediaWidth: 240,
          mediaHeight: 240
        })
      );

      expect(params?.messageId).assertEqual('900');
      expect(params?.mediaKind).assertEqual('videoNote');
      expect(params?.mediaFileId).assertEqual(901);
      expect(params?.mediaThumbFileId).assertEqual(902);
      expect(params?.mediaMinithumbnailData).assertEqual('bWluaQ==');
      expect(params?.isRoundVideoNote).assertTrue();
    });

    it('shouldSkipUnsupportedMessageKinds', 0, () => {
      const viewModel = new MediaViewerPageViewModel();
      const params = viewModel.createMediaViewerRouteParams('55', 'OSTC Team', 'ostc', buildMessage({ kind: 'text' }));

      expect(params).assertUndefined();
    });

    it('shouldParseRouteParamsDefensively', 0, () => {
      const viewModel = new MediaViewerPageViewModel();
      const routeParams = viewModel.parseRouteParams({
        chatId: ' 55 ',
        chatTitle: ' OSTC Team ',
        chatUsername: undefined,
        messageId: ' 900 ',
        mediaKind: undefined,
        mediaFileId: 901,
        mediaThumbFileId: undefined,
        mediaFilePath: ' /tmp/video.mp4 ',
        mediaThumbPath: '',
        mediaMinithumbnailData: ' abc ',
        mediaMimeType: ' video/mp4 ',
        mediaIsAnimated: false,
        mediaDurationSec: 9,
        mediaWidth: 240,
        mediaHeight: 240,
        isRoundVideoNote: true
      });

      expect(routeParams.chatId).assertEqual('55');
      expect(routeParams.chatTitle).assertEqual('OSTC Team');
      expect(routeParams.chatUsername).assertEqual('');
      expect(routeParams.messageId).assertEqual('900');
      expect(routeParams.mediaKind).assertEqual('photo');
      expect(routeParams.mediaFileId).assertEqual(901);
      expect(routeParams.mediaThumbFileId).assertEqual(0);
      expect(routeParams.mediaFilePath).assertEqual('/tmp/video.mp4');
      expect(routeParams.mediaMinithumbnailData).assertEqual('abc');
      expect(routeParams.mediaMimeType).assertEqual('video/mp4');
      expect(routeParams.mediaIsAnimated).assertFalse();
      expect(routeParams.isRoundVideoNote).assertTrue();
    });

    it('shouldPlanNavigationToIndexOnlyWhenUnauthorized', 0, () => {
      const viewModel = new MediaViewerPageViewModel();
      const unauthorizedPlan = viewModel.planAuthStateChange('authorizationStateWaitPhoneNumber');
      const readyPlan = viewModel.planAuthStateChange('authorizationStateReady');

      expect(unauthorizedPlan.shouldNavigateToIndex).assertTrue();
      expect(unauthorizedPlan.resetIndexNavigation).assertFalse();
      expect(readyPlan.shouldNavigateToIndex).assertFalse();
      expect(readyPlan.resetIndexNavigation).assertTrue();
    });

    it('shouldCreateDownloadPlanAndPlaybackRequestForPlayableMedia', 0, () => {
      const viewModel = new MediaViewerPageViewModel();
      const initialState = viewModel.applyRoute(viewModel.createInitialState(), {
        chatId: '55',
        chatTitle: 'OSTC Team',
        chatUsername: 'ostc',
        messageId: '901',
        mediaKind: 'video',
        mediaFileId: 901,
        mediaThumbFileId: 902,
        mediaFilePath: '',
        mediaThumbPath: '',
        mediaMinithumbnailData: '',
        mediaMimeType: 'video/mp4',
        mediaIsAnimated: false,
        mediaDurationSec: 5,
        mediaWidth: 320,
        mediaHeight: 180,
        isRoundVideoNote: false
      });
      const downloadPlan = viewModel.createMediaDownloadPlan(initialState);
      const loadedState = viewModel.mergeMessageUpdate(initialState, buildMessage({
        id: '901',
        kind: 'video',
        mediaLocalPath: '/tmp/video.mp4',
        mediaMimeType: 'video/mp4',
        mediaIsAnimated: false,
        mediaDurationSec: 8
      }));
      const playbackRequest = viewModel.createPlaybackRequest(loadedState);

      expect(downloadPlan.shouldDownload).assertTrue();
      expect(downloadPlan.fileId).assertEqual(901);
      expect(playbackRequest?.messageId).assertEqual('901');
      expect(playbackRequest?.filePath).assertEqual('/tmp/video.mp4');
      expect(playbackRequest?.durationMs).assertEqual(8000);
    });

    it('shouldMergeIncomingMessageUpdateWithExistingPageState', 0, () => {
      const viewModel = new MediaViewerPageViewModel();
      const initialState = viewModel.applyRoute(viewModel.createInitialState(), {
        chatId: '55',
        chatTitle: 'OSTC Team',
        chatUsername: 'ostc',
        messageId: '901',
        mediaKind: 'video',
        mediaFileId: 901,
        mediaThumbFileId: 902,
        mediaFilePath: '',
        mediaThumbPath: '',
        mediaMinithumbnailData: '',
        mediaMimeType: 'video/mp4',
        mediaIsAnimated: false,
        mediaDurationSec: 5,
        mediaWidth: 320,
        mediaHeight: 180,
        isRoundVideoNote: false
      });

      const mergedState = viewModel.mergeMessageUpdate(initialState, buildMessage({
        id: '901',
        kind: 'video',
        mediaFileId: 901,
        mediaThumbFileId: 902,
        mediaLocalPath: '/tmp/video.mp4',
        mediaThumbPath: '/tmp/video-thumb.jpg',
        mediaDurationSec: 8
      }));

      expect(mergedState.mediaFilePath).assertEqual('/tmp/video.mp4');
      expect(mergedState.mediaThumbPath).assertEqual('/tmp/video-thumb.jpg');
      expect(mergedState.mediaDurationSec).assertEqual(8);
    });

    it('shouldResolveDisplayValuesFromPageState', 0, () => {
      const viewModel = new MediaViewerPageViewModel();
      const pageState = viewModel.applyRoute(viewModel.createInitialState(), {
        chatId: '55',
        chatTitle: 'OSTC Team',
        chatUsername: 'ostc',
        messageId: '905',
        mediaKind: 'videoNote',
        mediaFileId: 905,
        mediaThumbFileId: 906,
        mediaFilePath: '',
        mediaThumbPath: '/tmp/video-note-thumb.jpg',
        mediaMinithumbnailData: 'mini',
        mediaMimeType: 'video/mp4',
        mediaIsAnimated: false,
        mediaDurationSec: 61,
        mediaWidth: 500,
        mediaHeight: 500,
        isRoundVideoNote: true
      });
      const snapshot = createIdleMediaViewerPlaybackSnapshot();
      snapshot.durationMs = 61000;

      const imageSource = viewModel.resolveImageSource(pageState);
      const videoPreviewSource = viewModel.resolveVideoPreviewSource(pageState);
      const videoSize = viewModel.calculateVideoContentSize(pageState);
      const shouldShowLoading = viewModel.shouldShowLoadingState(pageState, snapshot.phase);

      expect(imageSource).assertEqual('file:///tmp/video-note-thumb.jpg');
      expect(videoPreviewSource).assertEqual('file:///tmp/video-note-thumb.jpg');
      expect(videoSize.width).assertEqual(215);
      expect(videoSize.height).assertEqual(215);
      expect(shouldShowLoading).assertTrue();
    });

    it('shouldFitRectangularMediaIntoRoundScreenSafeViewport', 0, () => {
      const viewModel = new MediaViewerPageViewModel();
      const pageState = viewModel.applyRoute(viewModel.createInitialState(), {
        chatId: '55',
        chatTitle: 'OSTC Team',
        chatUsername: 'ostc',
        messageId: '906',
        mediaKind: 'photo',
        mediaFileId: 906,
        mediaThumbFileId: 907,
        mediaFilePath: '/tmp/photo.jpg',
        mediaThumbPath: '/tmp/photo-thumb.jpg',
        mediaMinithumbnailData: '',
        mediaMimeType: 'image/jpeg',
        mediaIsAnimated: false,
        mediaDurationSec: 0,
        mediaWidth: 1200,
        mediaHeight: 800,
        isRoundVideoNote: false
      });

      const contentSize = viewModel.calculateImageContentSize(pageState);

      expect(contentSize.width).assertEqual(164);
      expect(contentSize.height).assertEqual(109);
    });

    it('shouldRenderAnimationWithVideoSurfaceWhenPayloadIsVideo', 0, () => {
      const viewModel = new MediaViewerPageViewModel();
      const pageState = viewModel.applyRoute(viewModel.createInitialState(), {
        chatId: '55',
        chatTitle: 'OSTC Team',
        chatUsername: 'ostc',
        messageId: '907',
        mediaKind: 'animation',
        mediaFileId: 907,
        mediaThumbFileId: 908,
        mediaFilePath: '/tmp/animation.mp4',
        mediaThumbPath: '/tmp/animation-thumb.jpg',
        mediaMinithumbnailData: '',
        mediaMimeType: 'video/mp4',
        mediaIsAnimated: true,
        mediaDurationSec: 4,
        mediaWidth: 320,
        mediaHeight: 320,
        isRoundVideoNote: false
      });

      expect(viewModel.shouldRenderWithVideoSurface(pageState)).assertTrue();
      expect(viewModel.shouldRenderWithImage(pageState)).assertFalse();
    });

    it('shouldRenderAnimatedGifWithPlayerButStaticGifAsImage', 0, () => {
      const viewModel = new MediaViewerPageViewModel();
      const animatedGifState = viewModel.applyRoute(viewModel.createInitialState(), {
        chatId: '55',
        chatTitle: 'OSTC Team',
        chatUsername: 'ostc',
        messageId: '908',
        mediaKind: 'animation',
        mediaFileId: 908,
        mediaThumbFileId: 909,
        mediaFilePath: '/tmp/animated.gif',
        mediaThumbPath: '/tmp/animated-thumb.jpg',
        mediaMinithumbnailData: '',
        mediaMimeType: 'image/gif',
        mediaIsAnimated: true,
        mediaDurationSec: 3,
        mediaWidth: 320,
        mediaHeight: 320,
        isRoundVideoNote: false
      });
      const staticGifState = viewModel.applyRoute(viewModel.createInitialState(), {
        chatId: '55',
        chatTitle: 'OSTC Team',
        chatUsername: 'ostc',
        messageId: '909',
        mediaKind: 'photo',
        mediaFileId: 910,
        mediaThumbFileId: 911,
        mediaFilePath: '/tmp/static.gif',
        mediaThumbPath: '',
        mediaMinithumbnailData: '',
        mediaMimeType: 'image/gif',
        mediaIsAnimated: false,
        mediaDurationSec: 0,
        mediaWidth: 320,
        mediaHeight: 320,
        isRoundVideoNote: false
      });

      expect(viewModel.shouldRenderWithVideoSurface(animatedGifState)).assertTrue();
      expect(viewModel.shouldRenderWithImage(animatedGifState)).assertFalse();
      expect(viewModel.shouldRenderWithVideoSurface(staticGifState)).assertFalse();
      expect(viewModel.shouldRenderWithImage(staticGifState)).assertTrue();
    });

    it('shouldClampImageTransformToDefaultScale', 0, () => {
      const viewModel = new MediaViewerPageViewModel();
      const initialViewportSize: MediaViewerContentSize = {
        width: 164,
        height: 164
      };
      const maximumViewportSize = viewModel.calculateImageMaximumViewportSize();
      const transform = clampMediaViewerImageTransform(
        {
          scale: 0.5,
          offsetX: 80,
          offsetY: -80
        },
        {
          width: 120,
          height: 80
        },
        initialViewportSize,
        maximumViewportSize
      );

      expect(transform.scale).assertEqual(1);
      expect(transform.offsetX).assertEqual(0);
      expect(transform.offsetY).assertEqual(0);
    });

    it('shouldGrowImageViewportWithScaleUntilFullScreen', 0, () => {
      const viewModel = new MediaViewerPageViewModel();
      const initialViewportSize: MediaViewerContentSize = {
        width: 164,
        height: 164
      };
      const maximumViewportSize = viewModel.calculateImageMaximumViewportSize();

      const partiallyZoomedViewport = calculateMediaViewerImageViewportSizeForScale(
        initialViewportSize,
        maximumViewportSize,
        1.2
      );
      const fullyZoomedViewport = calculateMediaViewerImageViewportSizeForScale(
        initialViewportSize,
        maximumViewportSize,
        2
      );

      expect(partiallyZoomedViewport.width).assertEqual(197);
      expect(partiallyZoomedViewport.height).assertEqual(197);
      expect(fullyZoomedViewport.width).assertEqual(233);
      expect(fullyZoomedViewport.height).assertEqual(233);
    });

    it('shouldClampZoomedImagePanToViewportBounds', 0, () => {
      const viewModel = new MediaViewerPageViewModel();
      const initialViewportSize: MediaViewerContentSize = {
        width: 164,
        height: 164
      };
      const maximumViewportSize = viewModel.calculateImageMaximumViewportSize();
      const transform = clampMediaViewerImageTransform(
        {
          scale: 3,
          offsetX: 500,
          offsetY: -500
        },
        {
          width: 121,
          height: 81
        },
        initialViewportSize,
        maximumViewportSize
      );

      expect(transform.scale).assertEqual(3);
      expect(transform.offsetX).assertEqual(65);
      expect(transform.offsetY).assertEqual(-5);
    });

    it('shouldClampImageTransformToMaximumScale', 0, () => {
      const viewModel = new MediaViewerPageViewModel();
      const initialViewportSize: MediaViewerContentSize = {
        width: 164,
        height: 164
      };
      const maximumViewportSize = viewModel.calculateImageMaximumViewportSize();
      const transform = clampMediaViewerImageTransform(
        {
          scale: 9,
          offsetX: 0,
          offsetY: 0
        },
        {
          width: 120,
          height: 80
        },
        initialViewportSize,
        maximumViewportSize
      );

      expect(transform.scale).assertEqual(4);
    });
  });
}
