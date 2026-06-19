import { describe, it, expect } from '@ohos/hypium';
import {
  formatCallDurationMMSS,
  splitCallDurationParts
} from '../main/ets/utils/CallDurationFormatter';

export default function callDurationFormatterTest() {
  describe('CallDurationFormatterTest', () => {
    it('shouldRenderZeroAsDoubleZero', 0, () => {
      expect(formatCallDurationMMSS(0)).assertEqual('00:00');
    });

    it('shouldClampNegativeValuesToZero', 0, () => {
      expect(formatCallDurationMMSS(-5)).assertEqual('00:00');
    });

    it('shouldClampNonFiniteValuesToZero', 0, () => {
      expect(formatCallDurationMMSS(Number.NaN)).assertEqual('00:00');
      expect(formatCallDurationMMSS(Number.POSITIVE_INFINITY)).assertEqual('00:00');
    });

    it('shouldZeroPadSubMinuteValues', 0, () => {
      expect(formatCallDurationMMSS(1)).assertEqual('00:01');
      expect(formatCallDurationMMSS(9)).assertEqual('00:09');
      expect(formatCallDurationMMSS(59)).assertEqual('00:59');
    });

    it('shouldRollOverAtSixtySeconds', 0, () => {
      expect(formatCallDurationMMSS(60)).assertEqual('01:00');
      expect(formatCallDurationMMSS(61)).assertEqual('01:01');
      expect(formatCallDurationMMSS(125)).assertEqual('02:05');
    });

    it('shouldRenderTenPlusMinutesWithoutLeadingPad', 0, () => {
      expect(formatCallDurationMMSS(600)).assertEqual('10:00');
      expect(formatCallDurationMMSS(3599)).assertEqual('59:59');
    });

    it('shouldKeepMinutesGrowingPastOneHour', 0, () => {
      // The formatter is MM:SS even past 60 minutes — that matches the call
      // screen contract (the duration text replaces the status line, not a
      // dedicated hours column).
      expect(formatCallDurationMMSS(3600)).assertEqual('60:00');
      expect(formatCallDurationMMSS(3661)).assertEqual('61:01');
    });

    it('shouldFloorFractionalSeconds', 0, () => {
      expect(formatCallDurationMMSS(1.9)).assertEqual('00:01');
      expect(formatCallDurationMMSS(59.99)).assertEqual('00:59');
    });

    // splitCallDurationParts — used by the chat-history call bubble to feed
    // the localised `chat_call_event_duration_*` templates.

    it('shouldSplitZeroIntoZeroParts', 0, () => {
      const parts = splitCallDurationParts(0);
      expect(parts.minutes).assertEqual(0);
      expect(parts.seconds).assertEqual(0);
    });

    it('shouldClampNegativeAndNonFiniteSplits', 0, () => {
      const negative = splitCallDurationParts(-5);
      expect(negative.minutes).assertEqual(0);
      expect(negative.seconds).assertEqual(0);

      const nan = splitCallDurationParts(Number.NaN);
      expect(nan.minutes).assertEqual(0);
      expect(nan.seconds).assertEqual(0);

      const inf = splitCallDurationParts(Number.POSITIVE_INFINITY);
      expect(inf.minutes).assertEqual(0);
      expect(inf.seconds).assertEqual(0);
    });

    it('shouldSplitSubMinuteValuesIntoSecondsOnly', 0, () => {
      const one = splitCallDurationParts(1);
      expect(one.minutes).assertEqual(0);
      expect(one.seconds).assertEqual(1);

      const fiftyNine = splitCallDurationParts(59);
      expect(fiftyNine.minutes).assertEqual(0);
      expect(fiftyNine.seconds).assertEqual(59);
    });

    it('shouldSplitOneMinuteCleanly', 0, () => {
      const sixty = splitCallDurationParts(60);
      expect(sixty.minutes).assertEqual(1);
      expect(sixty.seconds).assertEqual(0);
    });

    it('shouldSplitMixedMinuteAndSeconds', 0, () => {
      const oneOhTwo = splitCallDurationParts(125);
      expect(oneOhTwo.minutes).assertEqual(2);
      expect(oneOhTwo.seconds).assertEqual(5);
    });

    it('shouldKeepMinutesGrowingPastOneHour', 0, () => {
      const sixtyOne = splitCallDurationParts(3661);
      expect(sixtyOne.minutes).assertEqual(61);
      expect(sixtyOne.seconds).assertEqual(1);
    });

    it('shouldFloorFractionalSecondsInSplit', 0, () => {
      const fractional = splitCallDurationParts(125.9);
      expect(fractional.minutes).assertEqual(2);
      expect(fractional.seconds).assertEqual(5);
    });
  });
}
