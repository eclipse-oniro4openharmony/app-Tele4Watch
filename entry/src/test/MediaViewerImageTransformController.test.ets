import { describe, it, expect } from '@ohos/hypium';
import {
  MediaViewerImageTransformController,
  MediaViewerImageTransformSnapshot
} from '../main/ets/services/media/MediaViewerImageTransformController';

export default function mediaViewerImageTransformControllerTest() {
  describe('MediaViewerImageTransformControllerTest', () => {
    it('shouldResetTransformWhenMediaIdentityChanges', 0, () => {
      const controller = new MediaViewerImageTransformController();
      let latestSnapshot: MediaViewerImageTransformSnapshot = controller.getSnapshot();
      controller.setListener((snapshot: MediaViewerImageTransformSnapshot): void => {
        latestSnapshot = snapshot;
      });

      controller.syncConfig({
        identity: 'first',
        contentSize: {
          width: 120,
          height: 80
        },
        initialViewportSize: {
          width: 164,
          height: 164
        },
        maximumViewportSize: {
          width: 233,
          height: 233
        }
      });
      controller.startPinch();
      controller.updatePinch(3);
      expect(latestSnapshot.scale).assertEqual(3);
      expect(latestSnapshot.isPanEnabled).assertTrue();

      controller.syncConfig({
        identity: 'second',
        contentSize: {
          width: 120,
          height: 80
        },
        initialViewportSize: {
          width: 164,
          height: 164
        },
        maximumViewportSize: {
          width: 233,
          height: 233
        }
      });

      expect(latestSnapshot.scale).assertEqual(1);
      expect(latestSnapshot.offsetX).assertEqual(0);
      expect(latestSnapshot.offsetY).assertEqual(0);
      expect(latestSnapshot.isPanEnabled).assertFalse();
    });

    it('shouldClampPanToCurrentViewportBounds', 0, () => {
      const controller = new MediaViewerImageTransformController();
      controller.syncConfig({
        identity: 'photo',
        contentSize: {
          width: 121,
          height: 81
        },
        initialViewportSize: {
          width: 164,
          height: 164
        },
        maximumViewportSize: {
          width: 233,
          height: 233
        }
      });

      controller.startPinch();
      controller.updatePinch(3);
      controller.startPan();
      controller.updatePan(500, -500);
      const snapshot = controller.getSnapshot();

      expect(snapshot.offsetX).assertEqual(65);
      expect(snapshot.offsetY).assertEqual(-5);
    });
  });
}
