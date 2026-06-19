import { Router } from '@kit.ArkUI';
import {
  ChatDeeplink,
  PendingDeeplink,
  QuickReplyDeeplink,
  createChatDeeplinkRouteParams,
  createQuickReplyDeeplinkRouteParams
} from './DeeplinkInbox';
import { createProfileRouteParams } from '../models/profile/ProfileRouteParams';
import { TdMeInfo } from '../models/td/TdViewTypes';

export class PostAuthRouter {
  async openProfileRoot(pageRouter: Router, me: TdMeInfo): Promise<boolean> {
    try {
      await pageRouter.replaceUrl({
        url: 'pages/Profile',
        params: createProfileRouteParams(me)
      });
      pageRouter.clear();
      return true;
    } catch (error) {
      return false;
    }
  }

  async openChatDeeplinkStack(pageRouter: Router, me: TdMeInfo, deeplink: ChatDeeplink): Promise<boolean> {
    try {
      await pageRouter.replaceUrl({
        url: 'pages/Profile',
        params: createProfileRouteParams(me)
      });
      pageRouter.clear();
      await pageRouter.pushUrl({
        url: 'pages/Chats'
      });
      await pageRouter.pushUrl({
        url: 'pages/ChatDetails',
        params: createChatDeeplinkRouteParams(deeplink)
      });
      return true;
    } catch (error) {
      return false;
    }
  }

  async openQuickReplyDeeplinkStack(
    pageRouter: Router,
    me: TdMeInfo,
    deeplink: QuickReplyDeeplink
  ): Promise<boolean> {
    try {
      await pageRouter.replaceUrl({
        url: 'pages/Profile',
        params: createProfileRouteParams(me)
      });
      pageRouter.clear();
      await pageRouter.pushUrl({
        url: 'pages/QuickReplyPicker',
        params: createQuickReplyDeeplinkRouteParams(deeplink)
      });
      return true;
    } catch (error) {
      return false;
    }
  }

  async openDeeplinkStack(pageRouter: Router, me: TdMeInfo, deeplink: PendingDeeplink): Promise<boolean> {
    if (deeplink.kind === 'chat') {
      return this.openChatDeeplinkStack(pageRouter, me, deeplink);
    }
    return this.openQuickReplyDeeplinkStack(pageRouter, me, deeplink);
  }
}

export const postAuthRouter: PostAuthRouter = new PostAuthRouter();
