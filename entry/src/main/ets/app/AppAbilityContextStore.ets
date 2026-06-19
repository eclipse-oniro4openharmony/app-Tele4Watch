import { common } from '@kit.AbilityKit';

/**
 * Stores the current Stage-model ability context for services that require UIAbilityContext.
 */
class AppAbilityContextStore {
  private currentContext: common.UIAbilityContext | undefined = undefined;

  /**
   * Saves the current UIAbility context.
   *
   * @param context The context owned by EntryAbility.
   */
  put(context: common.UIAbilityContext): void {
    this.currentContext = context;
  }

  /**
   * Reads the current UIAbility context.
   *
   * @returns Stored UIAbility context or `undefined` before ability creation.
   */
  peek(): common.UIAbilityContext | undefined {
    return this.currentContext;
  }

  /**
   * Clears the stored context when EntryAbility is destroyed.
   */
  clear(): void {
    this.currentContext = undefined;
  }
}

export const appAbilityContextStore: AppAbilityContextStore = new AppAbilityContextStore();
