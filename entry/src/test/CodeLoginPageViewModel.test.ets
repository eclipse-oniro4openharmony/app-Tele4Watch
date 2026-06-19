import { describe, it, expect } from '@ohos/hypium';
import { CodeLoginPageMode, CodeLoginPageState } from '../main/ets/models/auth/CodeLoginPageState';
import { createEmptyUiTextValue } from '../main/ets/models/ui/UiTextValue';
import { CodeLoginPageViewModel } from '../main/ets/viewmodel/CodeLoginPageViewModel';

function buildCodeLoginState(loginCodeInput: string, expectedCodeLength: number = 5): CodeLoginPageState {
  return {
    currentAuthState: 'authorizationStateWaitCode',
    loginCodeInput: loginCodeInput,
    pageMode: CodeLoginPageMode.Result,
    infoText: createEmptyUiTextValue(),
    errorText: createEmptyUiTextValue(),
    expectedCodeLength: expectedCodeLength,
    submitEnabled: false
  };
}

export default function codeLoginPageViewModelTest() {
  describe('CodeLoginPageViewModelTest', () => {
    it('shouldEnableSubmitForExpectedCodeLength', 0, () => {
      const viewModel = new CodeLoginPageViewModel();
      const waitCodeState = buildCodeLoginState('');

      expect(viewModel.hasValidCodeInput('')).assertFalse();
      expect(viewModel.hasValidCodeInput('1234')).assertFalse();
      expect(viewModel.hasValidCodeInput('123456')).assertFalse();
      expect(viewModel.hasValidCodeInput('12a45')).assertFalse();
      expect(viewModel.hasValidCodeInput('12345')).assertTrue();
      expect(viewModel.hasValidCodeInput(' 12345 ')).assertTrue();

      expect(viewModel.updateCodeInput(waitCodeState, '1234').submitEnabled).assertFalse();
      expect(viewModel.updateCodeInput(waitCodeState, '123456').submitEnabled).assertFalse();
      expect(viewModel.updateCodeInput(waitCodeState, '12a45').submitEnabled).assertFalse();
      expect(viewModel.updateCodeInput(waitCodeState, '12345').submitEnabled).assertTrue();

      const sixDigitState = buildCodeLoginState('', 6);
      expect(viewModel.hasValidCodeInput('123456', 6)).assertTrue();
      expect(viewModel.updateCodeInput(sixDigitState, '12345').submitEnabled).assertFalse();
      expect(viewModel.updateCodeInput(sixDigitState, '123456').submitEnabled).assertTrue();
    });

    it('shouldSubmitOnlyExpectedLengthCode', 0, () => {
      const viewModel = new CodeLoginPageViewModel();
      const shortCodePlan = viewModel.planCodeSubmit(buildCodeLoginState('1234'));
      const validCodePlan = viewModel.planCodeSubmit(buildCodeLoginState(' 12345 '));
      const sixDigitPlan = viewModel.planCodeSubmit(buildCodeLoginState(' 123456 ', 6));

      expect(shortCodePlan.shouldSubmit).assertFalse();
      expect(shortCodePlan.nextPageState.submitEnabled).assertFalse();
      expect(validCodePlan.shouldSubmit).assertTrue();
      expect(validCodePlan.loginCodeInput).assertEqual('12345');
      expect(validCodePlan.nextPageState.loginCodeInput).assertEqual('12345');
      expect(validCodePlan.nextPageState.submitEnabled).assertFalse();
      expect(sixDigitPlan.shouldSubmit).assertTrue();
      expect(sixDigitPlan.loginCodeInput).assertEqual('123456');
      expect(sixDigitPlan.nextPageState.loginCodeInput).assertEqual('123456');
    });

    it('shouldNormalizeInvalidExpectedLengthToFallback', 0, () => {
      const viewModel = new CodeLoginPageViewModel();

      expect(viewModel.normalizedExpectedCodeLength(0)).assertEqual(5);
      expect(viewModel.normalizedExpectedCodeLength(0.4)).assertEqual(5);
      expect(viewModel.normalizedExpectedCodeLength(-1)).assertEqual(5);
      expect(viewModel.hasValidCodeInput('12345', 0)).assertTrue();
    });
  });
}
