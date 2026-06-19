import { describe, it, expect } from '@ohos/hypium';
import { isDigitText, parsePositiveIntegerText } from '../main/ets/utils/NumericTextParser';

export default function numericTextParserTest() {
  describe('NumericTextParserTest', () => {
    it('shouldParseDigitOnlyPositiveIntegers', 0, () => {
      expect(parsePositiveIntegerText('1')).assertEqual(1);
      expect(parsePositiveIntegerText(' 42 ')).assertEqual(42);
      expect(parsePositiveIntegerText('0007')).assertEqual(7);
    });

    it('shouldRejectEmptyZeroNegativeAndMixedText', 0, () => {
      expect(parsePositiveIntegerText('')).assertEqual(0);
      expect(parsePositiveIntegerText('   ')).assertEqual(0);
      expect(parsePositiveIntegerText('0')).assertEqual(0);
      expect(parsePositiveIntegerText('-1')).assertEqual(0);
      expect(parsePositiveIntegerText('12:34')).assertEqual(0);
      expect(parsePositiveIntegerText('12abc')).assertEqual(0);
    });

    it('shouldValidateDigitText', 0, () => {
      expect(isDigitText('12345')).assertTrue();
      expect(isDigitText('12 45')).assertFalse();
      expect(isDigitText('12.45')).assertFalse();
    });
  });
}
